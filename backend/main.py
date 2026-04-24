"""
REBI AI - Ana API Sunucusu v3.0
=================================
Mimari: Flow Engine (deterministik) -> Knowledge Router (metadata) -> AI (polish)
Yeni: /daily_checkin endpoint, adaptif rutin sistemi, risk skoru
"""

import httpx
from fastapi import FastAPI, HTTPException, UploadFile, File, Depends, Request, Query
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field, model_validator
from typing import Optional, Literal
import re
import uuid
from datetime import date, datetime, timezone

from config import SUPABASE_URL, SUPABASE_SERVICE_KEY, CORS_ORIGINS, get_logger
from weather_service import fetch_weather
from flow_engine import (
    run_flow,
    adapt_existing_routine,
    CONCERN_KNOWLEDGE_MAP,
    get_routine_care_guide,
    sanitize_routine_items_details,
)
from skincare_absolute_rules import enforce_absolute_rules_on_routine, get_absolute_rules_catalog
from knowledge_router import execute_query_plan, get_targeted_context
from rag_service import polish_routine_with_ai, chat_with_knowledge, translate_routine_items, _primary_lang_from_header
from ingredient_db import compute_risk_score, build_ingredient_context_for_ai
from hydration_window import compute_effective_water_liters, load_water_series_7d
from checkin_carryover import (
    blend_sleep_hours,
    blend_stress_mapped,
    build_carryover_notes,
    effective_makeup_with_history,
    fetch_past_daily_logs,
)
from concern_checkin_extras import apply_concern_extra_risk
from symptom_risk import (
    apply_symptom_tags_risk,
    apply_tracking_risk_bonus,
    normalize_symptom_tags,
)
from auth_deps import (
    enforce_supabase_user,
    jwt_auth_enabled,
    user_is_rebi_plus,
    user_plus_chat_is_monthly_capped,
)
from free_chat_quota import (
    free_chat_limit,
    free_chat_remaining,
    free_chat_quota_exceeded,
    free_chat_record_successful_turn,
)
from plus_chat_quota import (
    plus_chat_monthly_cap,
    plus_chat_quota_exceeded,
    plus_chat_record_successful_turn,
    plus_chat_remaining,
)
from demo_users import (
    demo_checkin_already_today,
    demo_checkin_mark,
    is_demo_user_id,
    should_use_supabase_db,
)
from rate_limit import (
    rate_limit_dependency,
    rate_limit_backend_label,
    LIMIT_DAILY_TRACKING_INGEST,
    LIMIT_DAILY_TRACKING_TODAY,
    LIMIT_CHAT_ASSESSMENT,
    LIMIT_DAILY_CHECKIN,
    LIMIT_DAILY_CHECKIN_STATUS,
    LIMIT_GENERATE_ROUTINE,
    LIMIT_CHAT,
    LIMIT_UPLOAD_PHOTO,
    LIMIT_ACCOUNT_DELETE,
)

log = get_logger("api")


class KnowledgeEntitySearchResponse(BaseModel):
    entities: list[dict] = Field(default_factory=list)
    chunks: list[dict] = Field(default_factory=list)

_OPENAPI_TAGS = [
    {
        "name": "meta",
        "description": "Kök bilgi ve sürüm.",
    },
    {
        "name": "health",
        "description": "Sağlık ve yapılandırma özeti (JWT / rate limit arka ucu).",
    },
    {
        "name": "routine",
        "description": "Analiz sonrası kişiselleştirilmiş rutin üretimi.",
    },
    {
        "name": "chat",
        "description": "Bilgi tabanlı sohbet ve değerlendirme diyaloğu.",
    },
    {
        "name": "checkin",
        "description": "Günlük cilt check-in ve adaptasyon.",
    },
    {
        "name": "tracking",
        "description": "Mobil günlük olaylar (su, uyku, stres, konum vb.).",
    },
    {
        "name": "media",
        "description": "Cilt fotoğrafı yükleme (Supabase Storage).",
    },
    {
        "name": "account",
        "description": "Hesap yönetimi (kalıcı silme).",
    },
]

app = FastAPI(
    title="Rebi API",
    version="3.0.0",
    description=(
        "Rebi holistik cilt bakım API’si. "
        "Mobil ve web istemcileri `POST` gövdelerinde `user_id` (Supabase `auth.users` UUID) kullanır. "
        "`SUPABASE_JWT_SECRET` tanımlıysa isteklere `Authorization: Bearer <access_token>` ekleyin; "
        "`sub` ile `user_id` eşleşmeli. "
        "Şema: [/openapi.json](/openapi.json), interaktif: [/docs](/docs)."
    ),
    openapi_tags=_OPENAPI_TAGS,
    docs_url="/docs",
    redoc_url="/redoc",
    openapi_url="/openapi.json",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=CORS_ORIGINS + ["https://rebiovil.com", "https://www.rebiovil.com"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.on_event("startup")
def _bootstrap_database_schema() -> None:
    """Supabase Postgres şifresi/URI varsa supabase/migrations/*.sql dosyalarını uygular."""
    try:
        from db_bootstrap import ensure_daily_events_schema

        if ensure_daily_events_schema() == "error":
            log.warning(
                "daily_events şeması uygulanamadı; API çalışmaya devam ediyor."
            )
    except Exception as e:
        log.warning("DB bootstrap çalıştırılamadı (yok sayılıyor): %s", e)


def get_supabase():
    if not SUPABASE_URL:
        return None
    from supabase import create_client
    return create_client(SUPABASE_URL, SUPABASE_SERVICE_KEY)

def _utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _safe_date_from_timestamp(ts: Optional[str]) -> str:
    """
    Basit ve sorunsuz: timestamp parse edilemezse bugüne düş.
    Date key: YYYY-MM-DD (UTC).
    """
    if not ts:
        return str(date.today())
    try:
        dt = datetime.fromisoformat(str(ts).replace("Z", "+00:00"))
        if not dt.tzinfo:
            dt = dt.replace(tzinfo=timezone.utc)
        return dt.astimezone(timezone.utc).date().isoformat()
    except Exception:
        return str(date.today())


# Supabase yokken (veya tablo yoksa) geliştirme için bellek içi depolama
_MEM_DAILY_EVENTS: dict[tuple[str, str], list[dict]] = {}

def _mem_append_event(user_id: str, log_date: str, event: dict) -> None:
    key = (user_id, log_date)
    _MEM_DAILY_EVENTS.setdefault(key, []).append(event)


def _aggregate_daily_events(events: list[dict]) -> dict:
    water_ml_total = 0
    nutrition = {}
    stress_vals = []
    sleep_hours = None
    last_location = None
    last_weather = None
    routine_steps_done = 0
    spf_refreshes = 0
    last_photo_meta = None
    checkin_feedback_events = 0

    for ev in events or []:
        t = (ev.get("type") or "").lower()
        payload = ev.get("payload") or {}
        if t == "water_intake":
            try:
                water_ml_total += int(payload.get("ml", 0) or 0)
            except Exception:
                pass
        elif t == "nutrition":
            if isinstance(payload, dict):
                nutrition = {**nutrition, **payload}
        elif t == "stress":
            try:
                stress_vals.append(int(payload.get("value")))
            except Exception:
                pass
        elif t == "sleep":
            try:
                sleep_hours = float(payload.get("hours"))
            except Exception:
                pass
        elif t == "location":
            if isinstance(payload, dict) and payload.get("lat") is not None and payload.get("lon") is not None:
                last_location = {"lat": payload.get("lat"), "lon": payload.get("lon")}
        elif t == "weather":
            if isinstance(payload, dict):
                last_weather = payload
        elif t == "routine_step":
            if bool(payload.get("done")):
                routine_steps_done += 1
        elif t == "routine_completed_block":
            if bool(payload.get("morning")):
                routine_steps_done += 1
            if bool(payload.get("evening")):
                routine_steps_done += 1
        elif t == "spf_refresh":
            spf_refreshes += 1
        elif t == "photo_meta":
            if isinstance(payload, dict):
                last_photo_meta = payload
        elif t == "checkin_feedback":
            checkin_feedback_events += 1

    avg_stress = None
    if stress_vals:
        avg_stress = sum(stress_vals) / max(1, len(stress_vals))

    return {
        "water_ml_total": water_ml_total,
        "nutrition": nutrition,
        "avg_stress": avg_stress,
        "sleep_hours": sleep_hours,
        "last_location": last_location,
        "weather": last_weather,
        "events_count": len(events or []),
        "routine_steps_done": routine_steps_done,
        "spf_refreshes": spf_refreshes,
        "last_photo_meta": last_photo_meta,
        "checkin_feedback_events": checkin_feedback_events,
    }


# Marka/ürün adı veya belirsiz ifade → etken madde + konsantrasyon (ürün önerisi yasak)
BRAND_TO_INGREDIENT = {
    "adalen": "Adapalen (%0.1)",
    "differin": "Adapalen",
    "retin a": "Tretinoin",
    "retina": "Tretinoin",
    "la roche": "etken madde", "cerave": "etken madde", "the ordinary": "etken madde",
    "cetaphil": "temizleyici", "eucerin": "etken madde",
    "zengin onarım kremi": "Seramid %2-5 + Kolesterol + Yağ asidi (bariyer onarım)",
    "zengin krem": "Seramid %2-5 + Squalane (bariyer kremi)",
    "onarım kremi": "Seramid %2-5 + Kolesterol (onarım)",
}


def _sanitize_routine_no_products(routine_items: list) -> None:
    """action ve detail içinde marka/ürün adı geçiyorsa etken madde adıyla değiştir. Ürün önerisi yasak."""
    for item in routine_items:
        for key in ("action", "detail"):
            if key not in item or not item[key]:
                continue
            text = item[key]
            lower = text.lower()
            for brand, replacement in BRAND_TO_INGREDIENT.items():
                if brand in lower:
                    text = re.sub(re.escape(brand), replacement, text, flags=re.IGNORECASE)
            item[key] = text


def _optional_natural_examples_routine_item(concern: str, *, knowledge_result: Optional[dict] = None) -> list:
    """
    Rutinin sonuna tek kısa satır: takviye / bitkisel isteğe bağlı örnekler (lavanta uçucu yağı vb.).
    Uzun PDF özeti yok; bilgi tabanı içeriği yalnızca polish bağlamında kalır.
    """
    c = (concern or "acne").lower().strip()
    if c == "acne":
        examples = (
            "Bitkisel/topikal örnekler (isteğe bağlı): çay ağacı yağı yalnızca noktasal ve çok seyreltik (taşıyıcı yağ ile). "
            "Lavanta gibi uçucu yağlar bazı kişilerde irrite edebilir; kullanacaksan yine çok seyreltik ve önce küçük alanda dene. "
            "Oral destek örnekleri (isteğe bağlı): çinko, omega-3 gibi takviyeler bazı kişilerde destekleyici olabilir; doz/uygunluk için eczacı veya hekim."
        )
    elif c in ("aging", "pigmentation"):
        examples = (
            "Bitkisel/topikal örnekler (isteğe bağlı): yeşil çay türevleri, resveratrol kaynakları gibi antioksidan içerikler. "
            "Oral destek örnekleri (isteğe bağlı): C vitamini, omega-3 gibi takviyeler yalnızca uygunluk varsa hekim/eczacı önerisiyle."
        )
    elif c == "dryness":
        examples = (
            "Bitkisel/topikal örnekler (isteğe bağlı): shea veya jojoba gibi bitkisel yağlar, nem kilidine ek okslüzif katman olarak; "
            "papatya gibi yatıştırıcı bitki özleri içeren formlar. "
            "Oral destek örnekleri (isteğe bağlı): omega-3 gibi destekler bazı kişilerde bariyer konforuna yardımcı olabilir; uygunluk için eczacı/hekim."
        )
    elif c == "sensitivity":
        examples = (
            "Bitkisel/topikal örnekler (isteğe bağlı): aloe, papatya gibi yatıştırıcı bitki özleri içeren ürünler. "
            "Uçucu yağ varsa (lavanta vb.) çok seyreltik olmalı ve önce 24–48 saat yama testi yapılmalı. "
            "Oral destek örnekleri (isteğe bağlı): bazı destekler (omega-3 vb.) uygun kişide yardımcı olabilir; doz/uygunluk için eczacı/hekim."
        )
    else:
        examples = (
            "Bitkisel/topikal örnekler (isteğe bağlı): aloe/papatya gibi yatıştırıcı bitki özleri; yeşil çay gibi antioksidan bitkisel içerikler. "
            "Uçucu yağ kullanacaksan çok seyreltik ve önce küçük alanda dene. "
            "Oral destek örnekleri (isteğe bağlı): vitamin/mineral veya omega-3 gibi takviyeler için doz ve uygunluk hekim veya eczacı ile."
        )

    closing = (
        " Bu satır ana rutin adımlarının yerine geçmez. Uçucu yağlar hassas cildi irrite edebilir. "
        "Hamilelik, emzirme, kronik hastalık veya ilaç kullanımında oral takviyeleri mutlaka hekim/eczacı ile değerlendir."
    )

    usage_text = (examples + closing).strip()

    # Knowledge Router'dan gelen doğal ürün PDF parçaları varsa, bu satırda 1-3 kısa not olarak göster.
    try:
        if isinstance(knowledge_result, dict):
            by_cat = knowledge_result.get("by_category") or {}
            nat_chunks = by_cat.get("Doğal alternatifler (bilgi tabanı)") or []
            if nat_chunks:
                picks = []
                for ch in nat_chunks[:3]:
                    t = str(ch or "").replace("\x00", " ").replace("\n", " ").strip()
                    t = " ".join(t.split())
                    if len(t) > 220:
                        t = t[:220].rstrip() + "…"
                    if t:
                        picks.append(f"- {t}")
                if picks:
                    usage_text = usage_text + "\n\nBitkisel notlar (opsiyonel):\n" + "\n".join(picks[:3])
    except Exception:
        pass

    return [
        {
            "time": "Günlük",
            "category": "Bitkisel",
            "icon": "🌿",
            "action": "Opsiyonel — bitkisel alternatif (istersen)",
            "detail": (
                "Bu madde tamamen opsiyonel: rutinini kurmak için şart değil. "
                "İstersen 'bitkisel' içeriklerden örnek fikirler aşağıda; etkinlik kişiden kişiye değişebilir."
            ),
            "usage": usage_text,
            "step_order": 95,
            "natural_alternative": True,
            "natural_examples_only": True,
        }
    ]


# ═══════════════════════════════════════════════════════
# Request / Response Models
# ═══════════════════════════════════════════════════════

class AssessmentRequest(BaseModel):
    user_id: str
    full_name: str
    age: int
    gender: str
    concern: str
    skin_type: str = "normal"
    severity_score: int = 5
    water_intake: float = 2.0
    sleep_hours: float = 7.0
    stress_score: int = 0
    smoking: bool = False
    smoking_per_day: int = 0
    smoking_years: int = 0
    alcohol: bool = False
    alcohol_frequency: int = 0
    alcohol_amount: int = 1
    location_lat: Optional[float] = None
    location_lon: Optional[float] = None
    photo_url: Optional[str] = None
    is_pregnant: bool = False
    cycle_phase: str = ""
    acne_zones: Optional[list] = None
    actives_experience: str = "occasional"  # none | occasional | regular (retinol/asit vb. geçmiş kullanım)
    actives_unused: Optional[list] = None  # eski istemciler: her id -> never
    actives_tolerance: Optional[dict] = None  # { "bha": "never"|"good"|"mild"|"bad", ... }
    makeup_frequency: int = 0  # 0 yok, 1 seyrek, 3 haftada birkaç, 5 günlük
    makeup_removal: str = "cleanser"  # none | water | cleanser | double
    # UI: karışıklığı azaltan netleştirici işaretler (şimdilik opsiyonel)
    special_flags: Optional[dict] = None

    @model_validator(mode="after")
    def _normalize_assessment(self):
        self.age = max(13, min(100, int(self.age)))
        self.severity_score = max(0, min(10, int(self.severity_score)))
        self.water_intake = max(0.0, min(8.0, float(self.water_intake)))
        self.sleep_hours = max(0.0, min(14.0, float(self.sleep_hours)))
        self.stress_score = max(0, min(40, int(self.stress_score)))
        self.smoking_per_day = max(0, min(60, int(self.smoking_per_day)))
        self.smoking_years = max(0, min(80, int(self.smoking_years)))
        self.alcohol_frequency = max(0, min(7, int(self.alcohol_frequency)))
        self.alcohol_amount = max(0, min(30, int(self.alcohol_amount)))
        self.makeup_frequency = max(0, min(7, int(self.makeup_frequency)))
        if self.location_lat is not None and self.location_lon is not None:
            try:
                la, lo = float(self.location_lat), float(self.location_lon)
                if la < -90 or la > 90 or lo < -180 or lo > 180:
                    self.location_lat = None
                    self.location_lon = None
                else:
                    self.location_lat = la
                    self.location_lon = lo
            except Exception:
                self.location_lat = None
                self.location_lon = None
        return self


class RoutineResponse(BaseModel):
    routine: list[dict]
    weather: dict
    assessment_id: str
    holistic_insights: list[dict]
    active_plan: Optional[list[dict]] = None
    flow_debug: Optional[dict] = None
    care_guide: Optional[dict] = None
    safety_absolute_rules: Optional[dict] = None
    rule_enforcement_report: Optional[dict] = None
    ai_polish_note: Optional[str] = None


class ChatRequest(BaseModel):
    user_id: str
    message: str
    concern: Optional[str] = "acne"
    history: Optional[list[dict]] = None


class ChatResponse(BaseModel):
    reply: str
    sources: list[str]


class AssessmentChatRequest(BaseModel):
    user_id: str
    message: str
    history: Optional[list] = None
    user_profile: Optional[dict] = None


class AssessmentChatResponse(BaseModel):
    reply: str
    is_complete: bool = False
    extracted_data: Optional[dict] = None
    free_chat_remaining: Optional[int] = None
    free_chat_limit: Optional[int] = None
    chat_quota_exceeded: bool = False
    # Birleşik kullanım (UI): free_daily | plus_monthly | plus_unlimited
    usage_kind: Optional[str] = None
    usage_remaining: Optional[int] = None
    usage_limit: Optional[int] = None


class ChatGeneralRequest(BaseModel):
    user_id: str
    message: str
    history: Optional[list] = None


class ChatGeneralResponse(BaseModel):
    reply: str
    usage_kind: Optional[str] = None
    usage_remaining: Optional[int] = None
    usage_limit: Optional[int] = None
    chat_quota_exceeded: bool = False
    # Evidence-first RAG (optional, UI can ignore)
    evidence_used: Optional[bool] = None
    evidence_score: Optional[float] = None
    evidence_sources: Optional[list[dict]] = None


class ChatUsageResponse(BaseModel):
    """Rebi AI sohbet kotası özeti (üst sayaç)."""

    kind: str
    remaining: Optional[int] = None
    limit: Optional[int] = None
    period: Optional[str] = None  # "day" | "month"


def _chat_usage_row(request: Request, user_id: str) -> tuple[Optional[str], Optional[int], Optional[int], Optional[str]]:
    """(kind, remaining, limit, period)."""
    if not jwt_auth_enabled():
        return "plus_unlimited", None, None, None
    uid = (user_id or "").strip()
    if not uid:
        return None, None, None, None
    plus = user_is_rebi_plus(request, user_id)
    if not plus:
        return "free_daily", free_chat_remaining(uid), free_chat_limit(), "day"
    if user_plus_chat_is_monthly_capped(request, user_id):
        return "plus_monthly", plus_chat_remaining(uid), plus_chat_monthly_cap(), "month"
    return "plus_unlimited", None, None, None


class TranslateRoutineItemsRequest(BaseModel):
    user_id: str
    routine_items: list[dict] = Field(default_factory=list)


class DailyCheckinRequest(BaseModel):
    user_id: str
    sleep_hours: float
    stress_today: int          # 1-5
    skin_feeling: str          # "iyi" / "kuru" / "yagli" / "kirik" / "irritasyon"
    applied_routine: bool
    notes: Optional[str] = None
    location_lat: Optional[float] = None
    location_lon: Optional[float] = None
    # Koşullu check-in: riskte kullanılır; None ise profil/takip aynen
    water_ml_today: Optional[int] = None
    makeup_used_today: Optional[bool] = None
    makeup_removal_today: Optional[str] = None
    tried_new_active_today: Optional[bool] = None
    # Endişe tipine göre ek sorular (hepsi opsiyonel; None = atlandı)
    picked_skin_today: Optional[bool] = None
    high_glycemic_intake_today: Optional[bool] = None
    heavy_dairy_today: Optional[bool] = None
    long_sun_exposure_today: Optional[bool] = None
    spf_applied_today: Optional[bool] = None
    very_dry_environment_today: Optional[bool] = None
    long_hot_shower_today: Optional[bool] = None
    fragrance_new_product_today: Optional[bool] = None
    # Semptom etiketleri (UI çoklu seçim)
    symptom_tags: Optional[list[str]] = None
    # Aktif reaksiyon şiddeti (irritasyon/kırık + rutin değişimi olduysa tolerans öğrenimi)
    active_reaction_severity: Optional[int] = None  # 1=hafif, 3=şiddetli
    # Önceki gün önerisi / bugünkü deneyim (analitik + ince ayar)
    recommendation_helpful: Optional[Literal["helpful", "not_helpful", "skip"]] = None
    recommendation_feedback_note: Optional[str] = None

    @model_validator(mode="after")
    def _normalize_daily_checkin(self):
        self.sleep_hours = max(0.0, min(14.0, float(self.sleep_hours)))
        self.stress_today = int(max(1, min(5, int(self.stress_today))))
        allowed_skin = {"iyi", "kuru", "yagli", "kirik", "irritasyon"}
        sf = (self.skin_feeling or "iyi").strip().lower()
        self.skin_feeling = sf if sf in allowed_skin else "iyi"
        if self.water_ml_today is not None:
            self.water_ml_today = int(max(0, min(8000, int(self.water_ml_today))))
        if self.notes:
            self.notes = str(self.notes).strip()[:2000] or None
        if self.recommendation_feedback_note:
            n = str(self.recommendation_feedback_note).strip()[:500]
            self.recommendation_feedback_note = n or None
        self.symptom_tags = normalize_symptom_tags(self.symptom_tags)
        if self.active_reaction_severity is not None:
            self.active_reaction_severity = int(max(1, min(3, int(self.active_reaction_severity))))
        return self


class DailyCheckinResponse(BaseModel):
    today_routine: list[dict]
    changes: list[dict]
    risk_level: str
    risk_detail: str
    ai_note: str
    adaptation_type: str
    care_guide: Optional[dict] = None
    water_effective_liters: Optional[float] = None
    hydration_summary: Optional[str] = None
    lifestyle_carryover_detail: Optional[str] = None


DailyTrackingClientEventType = Literal[
    "water_intake",
    "nutrition",
    "stress",
    "sleep",
    "location",
    "routine_step",
    "spf_refresh",
    "photo_meta",
    "routine_completed_block",
    "checkin_feedback",
]


class DailyTrackingIngestRequest(BaseModel):
    user_id: str
    timestamp: Optional[str] = None
    type: DailyTrackingClientEventType
    payload: dict = Field(default_factory=dict)
    source: str = "mobile"

    @model_validator(mode="after")
    def _cap_payload(self):
        if self.payload is None:
            self.payload = {}
        if not isinstance(self.payload, dict):
            self.payload = {}
        # Aşırı büyük payload’ları kes (güvenlik + DB)
        if len(str(self.payload)) > 8000:
            self.payload = {"truncated": True}
        return self


class DailyTrackingIngestResponse(BaseModel):
    ok: bool = True
    log_date: str
    aggregated: dict


class DailyTrackingTodayResponse(BaseModel):
    user_id: str
    log_date: str
    aggregated: dict
    events: list[dict] = []


_ACCOUNT_DELETE_CONFIRM = "HESABIMI_SIL"


class AccountDeleteRequest(BaseModel):
    user_id: str
    confirm_text: str


# ═══════════════════════════════════════════════════════
# Endpoints
# ═══════════════════════════════════════════════════════

@app.get("/", tags=["meta"])
async def root():
    return {
        "message": "Rebi API v3.0 - Flow Engine + Chat + Adaptive Routine",
        "version": "3.0.0",
        "endpoints": [
            "/generate_routine",
            "/chat",
            "/chat_assessment",
            "/daily_tracking/ingest",
            "/daily_tracking/today",
            "/daily_checkin",
            "/daily_checkin/status",
            "/upload_photo",
            "/account/delete",
            "/health",
        ],
    }


@app.get("/knowledge/entity_search", response_model=KnowledgeEntitySearchResponse, tags=["meta"])
async def knowledge_entity_search(
    request: Request,
    user_id: str,
    folder: str = "data-pdfs",
    q: str = "",
    k: int = 10,
):
    """
    Fast lookup by extracted entities (ingredient/oil/extract) without scanning all chunks.
    Uses knowledge_entities + knowledge_chunk_entities index.
    """
    enforce_supabase_user(request, user_id)
    from knowledge.entity_search import list_entities, find_chunks_by_entity

    entities = list_entities(user_id=user_id, folder_slug=folder, q=q, k=50)
    chunks = [
        {
            "entity": c.entity_name,
            "kind": c.entity_kind,
            "chunk_id": c.chunk_id,
            "document_id": c.document_id,
            "chunk_text": c.chunk_text,
        }
        for c in find_chunks_by_entity(user_id=user_id, folder_slug=folder, q=q, k=k)
    ]
    return KnowledgeEntitySearchResponse(entities=entities, chunks=chunks)


@app.get("/health", tags=["health"])
async def health():
    supabase = get_supabase()
    return {
        "status": "ok",
        "supabase": "connected" if supabase else "not configured",
        "concerns": list(CONCERN_KNOWLEDGE_MAP.keys()),
        "jwt_auth": "on" if jwt_auth_enabled() else "off",
        "rate_limit_backend": rate_limit_backend_label(),
    }


@app.post(
    "/daily_tracking/ingest",
    response_model=DailyTrackingIngestResponse,
    tags=["tracking"],
    dependencies=[Depends(rate_limit_dependency(LIMIT_DAILY_TRACKING_INGEST))],
)
async def daily_tracking_ingest(request: Request, req: DailyTrackingIngestRequest):
    """
    En basit ama sorunsuz: gün içinde event ingest et.
    Supabase varsa daily_events tablosuna yazar; yoksa bellek içi saklar.
    """
    enforce_supabase_user(request, req.user_id)
    ts = req.timestamp or _utc_now_iso()
    log_date = _safe_date_from_timestamp(ts)
    event = {
        "user_id": req.user_id,
        "event_time": ts,
        "log_date": log_date,
        "type": req.type,
        "payload": req.payload or {},
        "source": req.source or "mobile",
    }

    supabase = get_supabase()
    wrote_remote = False
    if should_use_supabase_db(supabase, req.user_id):
        try:
            supabase.table("daily_events").insert(event).execute()
            wrote_remote = True
        except Exception as e:
            log.error("daily_events insert hatası (fallback to memory): %s", e)

    if not wrote_remote:
        _mem_append_event(req.user_id, log_date, event)

    # Location gelirse anlık weather snapshot ekle (opsiyonel ama değerli)
    if req.type == "location":
        try:
            lat = (req.payload or {}).get("lat")
            lon = (req.payload or {}).get("lon")
            if lat is not None and lon is not None:
                weather_data = await fetch_weather(lat, lon)
                w_event = {
                    "user_id": req.user_id,
                    "event_time": _utc_now_iso(),
                    "log_date": log_date,
                    "type": "weather",
                    "payload": weather_data,
                    "source": "server",
                }
                if should_use_supabase_db(supabase, req.user_id):
                    try:
                        supabase.table("daily_events").insert(w_event).execute()
                    except Exception as e:
                        log.error("weather event insert hatası (ignored): %s", e)
                        _mem_append_event(req.user_id, log_date, w_event)
                else:
                    _mem_append_event(req.user_id, log_date, w_event)
        except Exception as e:
            log.error("Location->weather hatası (ignored): %s", e)

    # Return aggregated for immediate UI feedback
    events = []
    if should_use_supabase_db(supabase, req.user_id):
        try:
            r = (
                supabase.table("daily_events")
                .select("event_time,type,payload,source")
                .eq("user_id", req.user_id)
                .eq("log_date", log_date)
                .order("event_time", desc=False)
                .execute()
            )
            events = r.data or []
        except Exception as e:
            log.error("daily_events read hatası (fallback memory): %s", e)
            events = _MEM_DAILY_EVENTS.get((req.user_id, log_date), [])
    else:
        events = _MEM_DAILY_EVENTS.get((req.user_id, log_date), [])

    return DailyTrackingIngestResponse(ok=True, log_date=log_date, aggregated=_aggregate_daily_events(events))


@app.get(
    "/daily_tracking/today",
    response_model=DailyTrackingTodayResponse,
    tags=["tracking"],
    dependencies=[Depends(rate_limit_dependency(LIMIT_DAILY_TRACKING_TODAY))],
)
async def daily_tracking_today(
    request: Request,
    user_id: str,
    log_date: Optional[str] = None,
    include_events: bool = False,
):
    """
    Mobil: bugün ne toplandı? Basit günlük özet.
    """
    enforce_supabase_user(request, user_id)
    d = log_date or str(date.today())
    supabase = get_supabase()
    events = []
    if should_use_supabase_db(supabase, user_id):
        try:
            r = (
                supabase.table("daily_events")
                .select("event_time,type,payload,source")
                .eq("user_id", user_id)
                .eq("log_date", d)
                .order("event_time", desc=False)
                .execute()
            )
            events = r.data or []
        except Exception as e:
            log.error("daily_tracking/today read hatası (fallback memory): %s", e)
            events = _MEM_DAILY_EVENTS.get((user_id, d), [])
    else:
        events = _MEM_DAILY_EVENTS.get((user_id, d), [])

    return DailyTrackingTodayResponse(
        user_id=user_id,
        log_date=d,
        aggregated=_aggregate_daily_events(events),
        events=(events if include_events else []),
    )


@app.post(
    "/generate_routine",
    response_model=RoutineResponse,
    tags=["routine"],
    dependencies=[Depends(rate_limit_dependency(LIMIT_GENERATE_ROUTINE))],
)
async def generate_routine(request: Request, req: AssessmentRequest):
    """
    Ana rutin üretme endpoint'i.
    1. Hava durumu (1 HTTP call)
    2. Flow Engine (0 token) — içeride bir kez kesinlik (kırmızı çizgi) uygulanır
    3. Knowledge Router (0 token)
    4. AI Polish (~400 token) — yalnızca metin cilası; kuralları zayıflatamaz
    5. Kesinlik kuralları tekrar (AI sonrası zorunlu) + detay sanitize
    """
    enforce_supabase_user(request, req.user_id)
    log.info("Rutin isteği: concern=%s, age=%d, severity=%d", req.concern, req.age, req.severity_score)

    # ADIM 1: Hava Durumu
    weather_data = {"humidity": 50, "uv_index": 3, "temperature": 20, "description": "N/A"}
    if req.location_lat and req.location_lon:
        weather_data = await fetch_weather(req.location_lat, req.location_lon)

    # ADIM 2: Flow Engine (0 TOKEN)
    flow_result = run_flow(
        concern=req.concern,
        severity_score=req.severity_score,
        age=req.age,
        gender=req.gender,
        skin_type_key=req.skin_type,
        stress_score=req.stress_score,
        sleep_hours=req.sleep_hours,
        water_intake=req.water_intake,
        smoking=req.smoking,
        alcohol=req.alcohol,
        uv_index=weather_data.get("uv_index", 3),
        humidity=weather_data.get("humidity", 50),
        temperature=weather_data.get("temperature", 20),
        smoking_per_day=req.smoking_per_day,
        smoking_years=req.smoking_years,
        alcohol_frequency=req.alcohol_frequency,
        alcohol_amount=req.alcohol_amount,
        is_pregnant=req.is_pregnant,
        cycle_phase=req.cycle_phase,
        acne_zones=req.acne_zones or [],
        actives_experience=req.actives_experience or "occasional",
        actives_unused=req.actives_unused or [],
        actives_tolerance=req.actives_tolerance,
        makeup_frequency=req.makeup_frequency,
        makeup_removal=req.makeup_removal or "cleanser",
        special_flags=req.special_flags,
    )

    routine_items = flow_result["routine_items"]
    query_plan = flow_result["query_plan"]
    context_summary = flow_result["context_summary"]

    log.info("Flow Engine: %d rutin öğesi, %d sorgu planı", len(routine_items), len(query_plan))

    # ADIM 3: Knowledge Router (0 TOKEN)
    knowledge_result = await execute_query_plan(query_plan)
    knowledge_context = await get_targeted_context(knowledge_result, max_chars=2000)

    # Rutinin altına tek kısa opsiyonel bitkisel satır (varsa PDF verisiyle beslenir)
    routine_items = list(routine_items)
    routine_items.extend(_optional_natural_examples_routine_item(req.concern, knowledge_result=knowledge_result))

    # ADIM 4: AI Polish (~400 TOKEN)
    accept_lang = (request.headers.get("accept-language") or "").strip()
    target_lang = _primary_lang_from_header(accept_lang)
    polished_routine, ai_polish_note = await polish_routine_with_ai(
        routine_items=routine_items,
        context_summary=context_summary,
        knowledge_context=knowledge_context,
        lang=accept_lang or "tr",
    )

    for item in polished_routine:
        item.pop("priority", None)

    _sanitize_routine_no_products(polished_routine)

    polished_routine, rule_enforcement_final = enforce_absolute_rules_on_routine(polished_routine)
    sanitize_routine_items_details(polished_routine)
    polished_routine = await translate_routine_items(polished_routine, target_lang=target_lang)

    # ADIM 5: Veritabanına Kaydet (demo kullanıcı: auth.users FK yok, atla)
    assessment_id = str(uuid.uuid4())
    supabase = get_supabase()
    if should_use_supabase_db(supabase, req.user_id):
        try:
            supabase.table("profiles").upsert({
                "id": req.user_id,
                "full_name": req.full_name,
                "age": req.age,
                "gender": req.gender,
                "location_lat": req.location_lat,
                "location_lon": req.location_lon,
            }).execute()

            assessment_result = supabase.table("assessments").insert({
                "user_id": req.user_id,
                "concern": req.concern,
                "severity_score": req.severity_score,
                "lifestyle_data": {
                    "skin_type": req.skin_type,
                    "water_intake": req.water_intake,
                    "sleep_hours": req.sleep_hours,
                    "stress_score": req.stress_score,
                    "smoking": req.smoking,
                    "smoking_per_day": req.smoking_per_day,
                    "smoking_years": req.smoking_years,
                    "alcohol": req.alcohol,
                    "alcohol_frequency": req.alcohol_frequency,
                    "alcohol_amount": req.alcohol_amount,
                    "is_pregnant": req.is_pregnant,
                    "cycle_phase": req.cycle_phase,
                    "acne_zones": req.acne_zones,
                    "actives_experience": req.actives_experience,
                    "actives_unused": req.actives_unused or [],
                    "actives_tolerance": req.actives_tolerance or {},
                    "makeup_frequency": req.makeup_frequency,
                    "makeup_removal": req.makeup_removal or "cleanser",
                    "special_flags": req.special_flags or {},
                },
                "photo_url": req.photo_url,
                "weather_data": weather_data,
            }).execute()

            if assessment_result.data:
                assessment_id = assessment_result.data[0]["id"]

            supabase.table("routines").insert({
                "user_id": req.user_id,
                "assessment_id": assessment_id,
                "active_routine": polished_routine,
                "is_active": True,
            }).execute()

            supabase.table("routines").update({"is_active": False}).neq(
                "assessment_id", assessment_id
            ).eq("user_id", req.user_id).execute()

            log.info("Veritabanına kaydedildi: assessment_id=%s", assessment_id)

        except Exception as e:
            log.error("DB kayıt hatası: %s", e)
    elif supabase and is_demo_user_id(req.user_id):
        log.info("Demo kullanıcı: profil/assessment/rutin DB yazımı atlandı (user_id=%s)", req.user_id)

    holistic_insights = [
        item for item in polished_routine
        if item.get("category") in ("Zihin", "Yaşam", "Beslenme")
    ]

    log.info("Rutin tamamlandı: %d öğe, %d insight", len(polished_routine), len(holistic_insights))

    # Active plan localization (TR/EN) based on Accept-Language
    try:
        from active_plan import localize_active_plan

        active_plan_localized = localize_active_plan(flow_result.get("active_plan") or [], accept_lang or "tr")
    except Exception:
        active_plan_localized = flow_result.get("active_plan") or []

    return RoutineResponse(
        routine=polished_routine,
        weather=weather_data,
        assessment_id=assessment_id,
        holistic_insights=holistic_insights,
        active_plan=active_plan_localized,
        care_guide=flow_result.get("care_guide"),
        safety_absolute_rules=get_absolute_rules_catalog(),
        rule_enforcement_report=rule_enforcement_final,
        ai_polish_note=ai_polish_note,
        flow_debug={
            "severity": flow_result["severity"]["label_tr"],
            "age_group": flow_result["age_group"]["label_tr"],
            "skin_type": flow_result["skin_type"]["label_tr"],
            "hormonal_info": flow_result.get("hormonal_info", {}),
            "acne_zones": flow_result.get("acne_zone_info", []),
            "risk_info": flow_result.get("risk_info", {}),
            "is_pregnant": req.is_pregnant,
            "actives_experience": req.actives_experience or "occasional",
            "actives_unused": req.actives_unused or [],
            "actives_tolerance": req.actives_tolerance or {},
            "personalization": flow_result.get("personalization"),
            "special_flags": flow_result.get("special_flags_normalized") or {},
            "absolute_enforcement_prefinal": flow_result.get("absolute_enforcement_report"),
            "knowledge_retrieved": knowledge_result.get("total_retrieved", 0),
            "sources": knowledge_result.get("sources", []),
            "token_estimate": "~400 (sadece AI polish)",
        },
    )


@app.post(
    "/chat",
    response_model=ChatResponse,
    tags=["chat"],
    dependencies=[Depends(rate_limit_dependency(LIMIT_CHAT))],
)
async def chat(request: Request, req: ChatRequest):
    """
    Interaktif sohbet endpoint'i.
    Kullanıcı sorusu -> Knowledge Base'den bağlam -> Gemini cevap
    Token: ~200-400/mesaj
    """
    enforce_supabase_user(request, req.user_id)
    log.info("Chat isteği: concern=%s, mesaj='%s'", req.concern, req.message[:60])

    concern = req.concern or "acne"
    knowledge_map = CONCERN_KNOWLEDGE_MAP.get(concern, CONCERN_KNOWLEDGE_MAP["acne"])

    query_plan = [
        {"kategori": knowledge_map["primary_kategori"], "alt_kategori": ak, "limit": 5, "purpose": ak}
        for ak in knowledge_map["primary_alt_kategoriler"][:2]
    ]
    query_plan.append({
        "kategori": knowledge_map["treatment_kategori"],
        "alt_kategori": knowledge_map["treatment_alt_kategoriler"][0],
        "limit": 5,
        "purpose": "Tedavi",
    })

    knowledge_result = await execute_query_plan(query_plan)
    knowledge_context = await get_targeted_context(knowledge_result, max_chars=2000)

    reply = await chat_with_knowledge(
        user_message=req.message,
        knowledge_context=knowledge_context,
        history=req.history,
        user_id=req.user_id,
        folder_slug="data-pdfs",
        accept_lang=_primary_lang_from_header(request.headers.get("accept-language") or "tr"),
    )

    return ChatResponse(
        reply=reply,
        sources=knowledge_result.get("sources", []),
    )


@app.post(
    "/chat_assessment",
    response_model=AssessmentChatResponse,
    tags=["chat"],
    dependencies=[Depends(rate_limit_dependency(LIMIT_CHAT_ASSESSMENT))],
)
async def chat_assessment(request: Request, req: AssessmentChatRequest):
    """
    AI-driven cilt değerlendirmesi sohbeti.
    Temel bilgiler form ile toplanır, kalan değerlendirmeyi AI konuşarak yapar.
    AI birkaç soru sorar, yeterli bilgi topladığında is_complete=True döndürür.
    """
    enforce_supabase_user(request, req.user_id)
    log.info("Assessment chat: user=%s, msg='%s'", req.user_id, req.message[:80])

    profile = req.user_profile or {}
    is_free = profile.get("mode") == "free_chat"
    lim = free_chat_limit()
    plus = user_is_rebi_plus(request, req.user_id)
    plus_chat_capped = plus and user_plus_chat_is_monthly_capped(request, req.user_id)
    plim = plus_chat_monthly_cap()

    if is_free and jwt_auth_enabled():
        if not plus:
            if free_chat_quota_exceeded(req.user_id):
                uk, ur, ul, _ = _chat_usage_row(request, req.user_id)
                return AssessmentChatResponse(
                    reply=(
                        "Bugünkü ücretsiz Rebi AI mesaj hakkın doldu. "
                        "Sınırsız sohbet için Rebi Plus’a geçebilirsin; uygulamadaki "
                        "«Abonelik / Rebi Plus» bölümünden devam et."
                    ),
                    is_complete=False,
                    extracted_data=None,
                    free_chat_remaining=0,
                    free_chat_limit=lim,
                    chat_quota_exceeded=True,
                    usage_kind=uk,
                    usage_remaining=ur,
                    usage_limit=ul,
                )
        if plus_chat_capped:
            if plus_chat_quota_exceeded(req.user_id):
                return AssessmentChatResponse(
                    reply=(
                        "Bu ayki Plus sohbet kotan doldu (paket sınırı). "
                        "Sınırsız sohbet içeren üst pakete geçebilirsin; uygulamada «Abonelik / Rebi Plus» bölümüne bak."
                    ),
                    is_complete=False,
                    extracted_data=None,
                    free_chat_remaining=0,
                    free_chat_limit=None,
                    chat_quota_exceeded=True,
                    usage_kind="plus_monthly",
                    usage_remaining=0,
                    usage_limit=plim,
                )

    from rag_service import assessment_chat
    result = await assessment_chat(
        user_message=req.message,
        history=req.history,
        user_profile=profile,
        user_id=req.user_id,
    )

    remaining: Optional[int] = None
    usage_kind: Optional[str] = None
    usage_remaining: Optional[int] = None
    usage_limit: Optional[int] = None
    if is_free and jwt_auth_enabled():
        reply = (result.get("reply") or "").strip()
        err_like = (
            not reply
            or reply.startswith("Bir hata oluştu")
            or reply.startswith("Bağlantı kurulamadı")
            or reply.startswith("Şu an güvenli bir yanıt üretilemedi")
            or reply.startswith("Şu an kısa bir yanıt üretilemedi")
            or reply.startswith("Üzgünüm, şu anda cevap veremiyorum")
            or reply.startswith("Şu an çok yoğunuz")
            or reply.startswith("İşlem tamamlanamadı")
        )
        if not plus:
            if not err_like:
                free_chat_record_successful_turn(req.user_id)
            remaining = free_chat_remaining(req.user_id)
        elif plus_chat_capped:
            if not err_like:
                plus_chat_record_successful_turn(req.user_id)
        usage_kind, usage_remaining, usage_limit, _ = _chat_usage_row(request, req.user_id)

    return AssessmentChatResponse(
        reply=result.get("reply", ""),
        is_complete=result.get("is_complete", False),
        extracted_data=result.get("extracted_data"),
        free_chat_remaining=remaining,
        free_chat_limit=lim if is_free and jwt_auth_enabled() and not plus else None,
        chat_quota_exceeded=False,
        usage_kind=usage_kind,
        usage_remaining=usage_remaining,
        usage_limit=usage_limit,
    )


@app.post(
    "/chat_general",
    response_model=ChatGeneralResponse,
    tags=["chat"],
    dependencies=[Depends(rate_limit_dependency(LIMIT_CHAT_ASSESSMENT))],
)
async def chat_general_endpoint(request: Request, req: ChatGeneralRequest):
    """
    Rebi Chat (genel): rutin motorundan ayrı, serbest soru-cevap.
    Kota/Plus mantığı chat_assessment ile aynıdır.
    """
    enforce_supabase_user(request, req.user_id)
    lim = free_chat_limit()
    plus = user_is_rebi_plus(request, req.user_id)
    plus_chat_capped = plus and user_plus_chat_is_monthly_capped(request, req.user_id)
    plim = plus_chat_monthly_cap()

    if jwt_auth_enabled():
        if not plus:
            if free_chat_quota_exceeded(req.user_id):
                uk, ur, ul, _ = _chat_usage_row(request, req.user_id)
                return ChatGeneralResponse(
                    reply=(
                        "Bugünkü ücretsiz Rebi AI mesaj hakkın doldu. "
                        "Sınırsız sohbet için Rebi Plus’a geçebilirsin."
                    ),
                    chat_quota_exceeded=True,
                    usage_kind=uk,
                    usage_remaining=ur,
                    usage_limit=ul,
                )
        if plus_chat_capped and plus_chat_quota_exceeded(req.user_id):
            return ChatGeneralResponse(
                reply=(
                    "Bu ayki Plus sohbet kotan doldu (paket sınırı). "
                    "Sınırsız sohbet içeren üst pakete geçebilirsin."
                ),
                chat_quota_exceeded=True,
                usage_kind="plus_monthly",
                usage_remaining=0,
                usage_limit=plim,
            )

    from rag_service import chat_general as rebi_chat_general
    from rag_service import _build_free_chat_evidence_bundle as _build_ev_bundle
    from rag_service import _EVIDENCE_OK_THRESHOLD as _EV_OK

    # Hafif profil hafızası: profiles + en son assessment concern (varsa) + (varsa) aktif rutin özeti
    profile_hint = {}
    try:
        supabase = get_supabase()
        if supabase and not is_demo_user_id(req.user_id):
            p = supabase.table("profiles").select("skin_type,age,city").eq("id", req.user_id).limit(1).execute()
            if p.data:
                row = p.data[0] or {}
                if row.get("skin_type"):
                    profile_hint["skin_type"] = row.get("skin_type")
                if row.get("age"):
                    profile_hint["age"] = row.get("age")
                if row.get("city"):
                    profile_hint["city"] = row.get("city")
            a = (
                supabase.table("assessments")
                .select("concern,created_at,lifestyle_data")
                .eq("user_id", req.user_id)
                .order("created_at", desc=True)
                .limit(1)
                .execute()
            )
            if a.data:
                ar0 = a.data[0] or {}
                if ar0.get("concern"):
                    profile_hint["concern"] = ar0.get("concern")
                # Kişisel tolerans/flag'ler: chat'te tonu ve sıklık önerilerini yumuşatmak için
                ld = ar0.get("lifestyle_data") or {}
                if isinstance(ld, dict):
                    if ld.get("actives_tolerance") is not None:
                        profile_hint["actives_tolerance"] = ld.get("actives_tolerance")
                    if ld.get("special_flags") is not None:
                        profile_hint["special_flags"] = ld.get("special_flags")

            # Aktif rutin: kullanıcı sorularını "mevcut plana göre" yanıtlamak için kısa özet
            try:
                r = (
                    supabase.table("routines")
                    .select("active_routine,created_at")
                    .eq("user_id", req.user_id)
                    .eq("is_active", True)
                    .order("created_at", desc=True)
                    .limit(1)
                    .execute()
                )
                if r.data and r.data[0].get("active_routine"):
                    routine = list(r.data[0].get("active_routine") or [])
                    # Marka/ürün adı temizliği (etken düzeyi)
                    try:
                        _sanitize_routine_no_products(routine)
                    except Exception:
                        pass
                    lines = []
                    for it in routine:
                        if not isinstance(it, dict):
                            continue
                        time = (it.get("time") or "").strip()
                        action = (it.get("action") or "").strip()
                        detail = (it.get("detail") or "").strip()
                        wd = it.get("weekly_days")
                        wd_txt = ""
                        if isinstance(wd, list) and wd:
                            wd_txt = f" [haftalık_günler={','.join(str(x) for x in wd[:7])}]"
                        s = f"{time}: {action}"
                        if detail:
                            s = s + f" — {detail}"
                        s = (s + wd_txt).strip()
                        if s:
                            lines.append(s)
                        if len(lines) >= 8:
                            break
                    if lines:
                        profile_hint["routine_summary"] = "\n".join(lines)[:1200]
            except Exception:
                pass
    except Exception:
        profile_hint = {}

    reply = await rebi_chat_general(
        user_message=req.message,
        history=req.history,
        user_id=req.user_id,
        profile_hint=profile_hint,
        accept_lang=_primary_lang_from_header(request.headers.get("accept-language") or "tr"),
    )

    # Evidence metadata (best-effort; does not affect the reply)
    evidence_used = None
    evidence_score = None
    evidence_sources = None
    try:
        ev = _build_ev_bundle(req.user_id, req.message, req.history)
        evidence_score = float((ev or {}).get("score") or 0.0)
        evidence_sources = (ev or {}).get("sources") or []
        evidence_used = bool(evidence_score >= float(_EV_OK))
    except Exception:
        evidence_used, evidence_score, evidence_sources = None, None, None

    if jwt_auth_enabled():
        # Başarılı tur sayımı (free / plus capped)
        r = (reply or "").strip()
        err_like = (
            not r
            or r.startswith("Bir hata oluştu")
            or r.startswith("Bağlantı kurulamadı")
            or r.startswith("Şu an çok yoğunuz")
            or r.startswith("İşlem tamamlanamadı")
        )
        if not plus:
            if not err_like:
                free_chat_record_successful_turn(req.user_id)
        elif plus_chat_capped:
            if not err_like:
                plus_chat_record_successful_turn(req.user_id)

    uk, ur, ul, _ = _chat_usage_row(request, req.user_id) if jwt_auth_enabled() else ("plus_unlimited", None, None, None)
    return ChatGeneralResponse(
        reply=reply or "",
        usage_kind=uk,
        usage_remaining=ur,
        usage_limit=ul,
        chat_quota_exceeded=False,
        evidence_used=evidence_used,
        evidence_score=evidence_score,
        evidence_sources=evidence_sources,
    )


@app.get(
    "/chat_usage",
    response_model=ChatUsageResponse,
    tags=["chat"],
    dependencies=[Depends(rate_limit_dependency(LIMIT_CHAT_ASSESSMENT))],
)
async def chat_usage(request: Request, user_id: str = Query(..., min_length=1)):
    """Rebi AI sohbet kotası — açılışta üst sayaç için."""
    enforce_supabase_user(request, user_id)
    kind, rem, lim, period = _chat_usage_row(request, user_id)
    if not kind:
        return ChatUsageResponse(kind="none", remaining=None, limit=None, period=None)
    return ChatUsageResponse(kind=kind, remaining=rem, limit=lim, period=period)


@app.post(
    "/routine/translate_items",
    tags=["routine"],
    dependencies=[Depends(rate_limit_dependency(LIMIT_CHAT_ASSESSMENT))],
)
async def translate_routine_items_endpoint(request: Request, req: TranslateRoutineItemsRequest):
    """
    Frontend can store routines in DB/local snapshot in Turkish.
    This endpoint adds `action_localized` and `detail_localized` for the selected UI language.
    """
    enforce_supabase_user(request, req.user_id)
    from rag_service import translate_routine_items, _primary_lang_from_header

    target_lang = _primary_lang_from_header(request.headers.get("accept-language", "") or "")
    items = await translate_routine_items(req.routine_items or [], target_lang=target_lang)
    return {"routine_items": items}


@app.get(
    "/daily_checkin/status",
    tags=["checkin"],
    dependencies=[Depends(rate_limit_dependency(LIMIT_DAILY_CHECKIN_STATUS))],
)
async def daily_checkin_status(request: Request, user_id: str):
    """Bugün için check-in yapılmış mı (aynı gün tekrarını önlemek için)."""
    enforce_supabase_user(request, user_id)
    supabase = get_supabase()
    today = str(date.today())
    if is_demo_user_id(user_id):
        return {
            "already_checked_in": demo_checkin_already_today(user_id, today),
            "log_date": today,
        }
    if not supabase:
        return {"already_checked_in": False, "log_date": today}
    try:
        r = (
            supabase.table("daily_logs")
            .select("id")
            .eq("user_id", user_id)
            .eq("log_date", today)
            .limit(1)
            .execute()
        )
        return {"already_checked_in": bool(r.data), "log_date": today}
    except Exception as e:
        log.error("daily_checkin/status hatası: %s", e)
        return {"already_checked_in": False, "log_date": today}


@app.post(
    "/daily_checkin",
    response_model=DailyCheckinResponse,
    tags=["checkin"],
    dependencies=[Depends(rate_limit_dependency(LIMIT_DAILY_CHECKIN))],
)
async def daily_checkin(request: Request, req: DailyCheckinRequest):
    """
    Günlük check-in: 3-5 hızlı soru ile cilt durumu takibi.
    Akış: Check-in → daily_logs kaydet → hava durumu → risk skoru → AI adaptasyon → rutin güncelle
    """
    enforce_supabase_user(request, req.user_id)
    log.info("Daily checkin: user=%s, feeling=%s, stress=%d", req.user_id, req.skin_feeling, req.stress_today)

    supabase = get_supabase()
    today_str = str(date.today())

    if is_demo_user_id(req.user_id):
        if demo_checkin_already_today(req.user_id, today_str):
            raise HTTPException(
                status_code=409,
                detail="Bugün için check-in zaten kaydedildi. Yarın tekrar deneyebilirsin.",
            )
    elif supabase:
        try:
            dup = (
                supabase.table("daily_logs")
                .select("id")
                .eq("user_id", req.user_id)
                .eq("log_date", today_str)
                .limit(1)
                .execute()
            )
            if dup.data:
                raise HTTPException(
                    status_code=409,
                    detail="Bugün için check-in zaten kaydedildi. Yarın tekrar deneyebilirsin.",
                )
        except HTTPException:
            raise
        except Exception as e:
            log.error("Check-in mükerrer kontrolü hatası: %s", e)

    # 1. Hava durumu
    weather_data = {"humidity": 50, "uv_index": 3, "temperature": 20}
    if req.location_lat and req.location_lon:
        weather_data = await fetch_weather(req.location_lat, req.location_lon)

    # 2. Mevcut aktif rutini Supabase'den çek
    current_routine = []
    user_profile = {}
    if should_use_supabase_db(supabase, req.user_id):
        try:
            routine_res = supabase.table("routines").select("active_routine, assessment_id").eq(
                "user_id", req.user_id
            ).eq("is_active", True).limit(1).execute()

            if routine_res.data and routine_res.data[0].get("active_routine"):
                current_routine = routine_res.data[0]["active_routine"]

            profile_res = supabase.table("profiles").select("*").eq("id", req.user_id).limit(1).execute()
            if profile_res.data:
                user_profile = profile_res.data[0]

            assessment_res = (
                supabase.table("assessments")
                .select("lifestyle_data, concern")
                .eq("user_id", req.user_id)
                .order("created_at", desc=True)
                .limit(1)
                .execute()
            )
            if assessment_res.data:
                ar0 = assessment_res.data[0]
                if ar0.get("lifestyle_data"):
                    user_profile.update(ar0["lifestyle_data"])
                if ar0.get("concern"):
                    user_profile["concern"] = ar0["concern"]

        except Exception as e:
            log.error("Mevcut rutin çekme hatası: %s", e)

    # 3. Mobil günlük takip (varsa): bugün toplanan verilerden özet çıkar
    tracking_today = None
    if should_use_supabase_db(supabase, req.user_id):
        try:
            ev_res = (
                supabase.table("daily_events")
                .select("event_time,type,payload,source")
                .eq("user_id", req.user_id)
                .eq("log_date", today_str)
                .order("event_time", desc=False)
                .execute()
            )
            tracking_today = _aggregate_daily_events(ev_res.data or [])
        except Exception as e:
            # tablo yoksa veya erişim hatası: sessizce yok say
            log.error("daily_events okuma hatası (ignored): %s", e)
    else:
        ev_local = _MEM_DAILY_EVENTS.get((req.user_id, today_str), [])
        tracking_today = _aggregate_daily_events(ev_local)

    # 4. Risk skoru: su (7 gün) + uyku/stres/makyaj (daily_logs carryover) + sorun tipi
    concern_for_carry = str(user_profile.get("concern", "") or "").lower().strip()
    past_logs: list[dict] = []
    if should_use_supabase_db(supabase, req.user_id):
        try:
            past_logs = fetch_past_daily_logs(supabase, req.user_id, today_str, limit=14)
        except Exception as e:
            log.error("daily_logs carryover okuma (ignored): %s", e)

    try:
        effective_sleep, sleep_carry_note = blend_sleep_hours(req.sleep_hours, past_logs)
    except Exception:
        effective_sleep, sleep_carry_note = float(req.sleep_hours), "uyku: carryover atlandı"

    try:
        stress_mapped, stress_carry_note = blend_stress_mapped(req.stress_today, past_logs)
    except Exception:
        stress_mapped, stress_carry_note = req.stress_today * 2, "stres: carryover atlandı"

    if concern_for_carry == "sensitivity" and req.tried_new_active_today is True:
        stress_mapped = min(10, stress_mapped + 2)

    try:
        profile_water = float(user_profile.get("water_intake", 2.0) or 2.0)
    except (TypeError, ValueError):
        profile_water = 2.0
    today_d = date.fromisoformat(today_str)
    use_db = should_use_supabase_db(supabase, req.user_id)
    try:
        water_series = load_water_series_7d(
            req.user_id,
            today_d,
            supabase,
            _MEM_DAILY_EVENTS,
            use_db,
        )
        series_list = list(water_series)
        if req.water_ml_today is not None and req.water_ml_today >= 0:
            lit = max(0.0, float(req.water_ml_today) / 1000.0)
            if series_list:
                d0, _ = series_list[0]
                series_list[0] = (d0, lit)
            else:
                series_list = [(today_str, lit)]
        water_intake, hydration_summary = compute_effective_water_liters(profile_water, series_list)
    except Exception as e:
        log.error("hydration_window hatası (profil suya düşülüyor): %s", e)
        water_intake = profile_water
        hydration_summary = None

    profile_mf = int(user_profile.get("makeup_frequency", 0) or 0)
    profile_mr = str(user_profile.get("makeup_removal", "cleanser") or "cleanser")
    try:
        makeup_frequency, makeup_removal, makeup_carry_note = effective_makeup_with_history(
            concern_for_carry,
            profile_mf,
            profile_mr,
            req.makeup_used_today,
            req.makeup_removal_today,
            past_logs,
        )
    except Exception:
        makeup_frequency, makeup_removal, makeup_carry_note = profile_mf, profile_mr, None
        if req.makeup_used_today is not None:
            if not req.makeup_used_today:
                makeup_frequency, makeup_removal = 0, "cleanser"
            elif req.makeup_removal_today:
                mr = (req.makeup_removal_today or "").lower().strip()
                if mr in ("none", "water", "cleanser", "double"):
                    makeup_removal = mr

    cycle_for_risk = str(user_profile.get("cycle_phase", "") or "")
    gender_for_risk = str(user_profile.get("gender", "") or "")

    risk_info = compute_risk_score(
        stress=stress_mapped,
        water_intake=water_intake,
        humidity=weather_data.get("humidity", 50),
        sleep_hours=effective_sleep,
        makeup_frequency=makeup_frequency,
        makeup_removal=makeup_removal,
        cycle_phase=cycle_for_risk,
        gender=gender_for_risk,
    )
    try:
        risk_info = apply_concern_extra_risk(concern_for_carry, req, past_logs, risk_info)
    except Exception as e:
        log.error("concern_checkin_extras hatası (ignored): %s", e)
    try:
        risk_info = apply_symptom_tags_risk(risk_info, req.symptom_tags)
    except Exception as e:
        log.error("symptom_tags risk hatası (ignored): %s", e)
    try:
        risk_info = apply_tracking_risk_bonus(risk_info, tracking_today)
    except Exception as e:
        log.error("tracking risk bonus hatası (ignored): %s", e)
    risk_detail_out = risk_info.get("detail", "")
    carryover_blob = build_carryover_notes(
        sleep_carry_note,
        stress_carry_note,
        makeup_carry_note,
        hydration_summary,
    )
    risk_detail_out = f"{risk_detail_out} | Carryover: {carryover_blob}"

    # 5. Deterministik adaptasyon
    daily_data = {
        "sleep_hours": req.sleep_hours,
        "stress_today": req.stress_today,
        "skin_feeling": req.skin_feeling,
        "applied_routine": req.applied_routine,
        "notes": req.notes or "",
        "tracking_today": tracking_today or {},
    }

    adaptation = adapt_existing_routine(
        current_routine=current_routine,
        daily_data=daily_data,
        risk_info=risk_info,
    )

    # 4.5 Tolerans öğrenimi (en basit kalıcı yol):
    # check-in'de irritasyon/kırık sinyali → o gün pause/reduce olan aktif ailelerini 'mild' olarak işaretle.
    learned_tol: dict = {}
    if (
        should_use_supabase_db(supabase, req.user_id)
        and req.skin_feeling in ("irritasyon", "kirik")
        and adaptation.get("changes")
    ):
        def _family_from_action(a: str) -> Optional[str]:
            t = (a or "").lower()
            if "retinol" in t or "retinal" in t:
                return "retinol"
            if "salisilik" in t or "salicylic" in t or "bha" in t:
                return "bha"
            if "glikolik" in t or "glycolic" in t or "laktik asit" in t or "lactic acid" in t or " aha" in t:
                return "aha"
            if "benzoil" in t or "benzoyl" in t:
                return "benzoyl"
            if "azelaik" in t or "azelaic" in t:
                return "azelaic"
            if "askorbik" in t or "ascorbic" in t or "c vitamini" in t or "vitamin c" in t:
                return "vitamin_c"
            if "niasinamid" in t or "niacinamide" in t:
                return "niacinamide"
            return None

        try:
            sev_raw = getattr(req, "active_reaction_severity", None)
            sev_i = int(sev_raw) if sev_raw is not None else 1
        except Exception:
            sev_i = 1
        sev_i = max(1, min(3, sev_i))

        for c in adaptation["changes"]:
            fam = _family_from_action(c.get("item", ""))
            if fam:
                if sev_i >= 3:
                    learned_tol[fam] = "bad"
                else:
                    learned_tol[fam] = "mild"

        # En son assessment'ın lifestyle_data.actives_tolerance alanına merge et (varsa).
        try:
            assessment_res = (
                supabase.table("assessments")
                .select("id,lifestyle_data")
                .eq("user_id", req.user_id)
                .order("created_at", desc=True)
                .limit(1)
                .execute()
            )
            if assessment_res.data:
                row = assessment_res.data[0]
                lifestyle = row.get("lifestyle_data") or {}
                tol = lifestyle.get("actives_tolerance") or {}
                if isinstance(tol, dict):
                    tol = {**tol, **learned_tol}
                else:
                    tol = dict(learned_tol)
                lifestyle["actives_tolerance"] = tol
                supabase.table("assessments").update({"lifestyle_data": lifestyle}).eq("id", row["id"]).execute()
        except Exception as e:
            log.error("Tolerans öğrenimi update hatası (ignored): %s", e)

    # Kırmızı çizgiler: check-in sonrası rutin de kesinlik kurallarından geçer (AI/uyarlama metninden bağımsız).
    enforced_items, _checkin_absolute_report = enforce_absolute_rules_on_routine(
        adaptation["adapted_items"]
    )
    sanitize_routine_items_details(enforced_items)
    adaptation["adapted_items"] = enforced_items

    # 5. AI adaptasyon notu (büyük değişikliklerde veya belirsiz durumlarda)
    ai_note = ""
    if adaptation["adaptation_type"] == "major" or req.skin_feeling in ("irritasyon", "kirik"):
        try:
            from rag_service import adapt_routine_with_ai
            ai_note = await adapt_routine_with_ai(
                current_routine=current_routine,
                daily_data=daily_data,
                risk_score=risk_info["score"],
                changes=adaptation["changes"],
            )
        except Exception as e:
            log.error("AI adaptasyon hatası: %s", e)
            ai_note = _generate_fallback_note(risk_info["level"], req.skin_feeling)
    else:
        ai_note = _generate_fallback_note(risk_info["level"], req.skin_feeling)

    # 6. Supabase: daily_logs'a kaydet + routine güncelle
    if should_use_supabase_db(supabase, req.user_id):
        try:
            supabase.table("daily_logs").upsert({
                "user_id": req.user_id,
                "log_date": today_str,
                "sleep_hours": req.sleep_hours,
                "stress_level": req.stress_today,
                "skin_feeling": req.skin_feeling,
                "applied_routine": req.applied_routine,
                "notes": req.notes,
                "weather_data": weather_data,
                "risk_score": risk_info["score"],
                "adaptation": {
                    "type": adaptation["adaptation_type"],
                    "changes": adaptation["changes"],
                    "ai_note": ai_note,
                    "learned_tolerance": learned_tol,
                    "checkin_extras": {
                        "water_ml_today": req.water_ml_today,
                        "makeup_used_today": req.makeup_used_today,
                        "makeup_removal_today": req.makeup_removal_today,
                        "tried_new_active_today": req.tried_new_active_today,
                        "picked_skin_today": req.picked_skin_today,
                        "high_glycemic_intake_today": req.high_glycemic_intake_today,
                        "heavy_dairy_today": req.heavy_dairy_today,
                        "long_sun_exposure_today": req.long_sun_exposure_today,
                        "spf_applied_today": req.spf_applied_today,
                        "very_dry_environment_today": req.very_dry_environment_today,
                        "long_hot_shower_today": req.long_hot_shower_today,
                        "fragrance_new_product_today": req.fragrance_new_product_today,
                        "symptom_tags": req.symptom_tags or [],
                        "active_reaction_severity": req.active_reaction_severity,
                        "recommendation_helpful": req.recommendation_helpful,
                        "recommendation_feedback_note": req.recommendation_feedback_note,
                    },
                },
            }).execute()

            if req.recommendation_helpful and req.recommendation_helpful != "skip":
                try:
                    supabase.table("daily_events").insert({
                        "user_id": req.user_id,
                        "event_time": _utc_now_iso(),
                        "log_date": today_str,
                        "type": "checkin_feedback",
                        "payload": {
                            "helpful": req.recommendation_helpful,
                            "note": (req.recommendation_feedback_note or "")[:500],
                        },
                        "source": "checkin",
                    }).execute()
                except Exception as e:
                    log.error("checkin_feedback daily_events (ignored): %s", e)

            if adaptation["changes"]:
                supabase.table("routines").update({
                    "active_routine": adaptation["adapted_items"],
                }).eq("user_id", req.user_id).eq("is_active", True).execute()

            log.info("Daily log kaydedildi: user=%s, risk=%s, changes=%d",
                     req.user_id, risk_info["level"], len(adaptation["changes"]))
        except Exception as e:
            log.error("Daily log kayıt hatası: %s", e)
    elif is_demo_user_id(req.user_id):
        demo_checkin_mark(req.user_id, today_str)
        log.info("Demo check-in: DB atlandı, bellekte bugün işaretlendi (user_id=%s)", req.user_id)

    is_pregnant = bool(user_profile.get("is_pregnant"))

    return DailyCheckinResponse(
        today_routine=adaptation["adapted_items"],
        changes=adaptation["changes"],
        risk_level=risk_info["level"],
        risk_detail=risk_detail_out,
        ai_note=ai_note,
        adaptation_type=adaptation["adaptation_type"],
        care_guide=get_routine_care_guide(is_pregnant=is_pregnant),
        water_effective_liters=round(float(water_intake), 3),
        hydration_summary=hydration_summary,
        lifestyle_carryover_detail=carryover_blob,
    )


def _generate_fallback_note(risk_level: str, skin_feeling: str) -> str:
    """AI çağrısı olmadan basit adaptasyon notu üret."""
    notes = {
        ("crisis", "irritasyon"): "Cildin şu an çok hassas. Tüm aktif maddeler durduruldu. Sadece bariyer onarım ve nemlendirme yap.",
        ("crisis", "kirik"): "Cilt bariyerin hasar görmüş. Petrolatum + Seramid ile onarım öncelikli.",
        ("crisis", "kuru"): "Yoğun kuruluk ve yüksek risk. Bol nemlendirici + oklüzif kilitleme.",
        ("high", "irritasyon"): "Hassasiyet yüksek. Bazı aktif maddeler sıklığı azaltıldı. Bariyer bakımına odaklan.",
        ("high", "kuru"): "Risk seviyesi yüksek, kuruluk mevcut. Nemlendirme artırıldı.",
        ("high", "kirik"): "Bariyer zayıf. Aktifler azaltıldı, onarım protokolü aktif.",
        ("moderate", "iyi"): "Cilt durumun iyi görünüyor. Mevcut rutin devam ediyor.",
        ("normal", "iyi"): "Her şey yolunda! Rutinine devam et.",
    }
    return notes.get((risk_level, skin_feeling),
                     f"Risk: {risk_level}. Cilt hissi: {skin_feeling}. Rutinin buna göre ayarlandı.")


_MAX_PHOTO_BYTES = 8 * 1024 * 1024
_ALLOWED_PHOTO_EXT = frozenset({"jpg", "jpeg", "png", "webp", "heic", "heif"})


def _delete_skin_photos_for_user(supabase, user_id: str) -> None:
    """skin-photos bucket içinde {user_id}/ altındaki dosyaları siler (CASCADE storage’da yok)."""
    prefix = (user_id or "").strip()
    if not prefix or ".." in prefix or any(c in prefix for c in "/\\"):
        return
    try:
        items = supabase.storage.from_("skin-photos").list(prefix)
    except Exception as e:
        log.warning("skin-photos list atlanıyor (%s): %s", prefix, e)
        return
    if not items:
        return
    paths: list[str] = []
    for item in items:
        if not isinstance(item, dict):
            continue
        name = item.get("name")
        if name and str(name).strip():
            paths.append(f"{prefix}/{name}")
    if not paths:
        return
    try:
        supabase.storage.from_("skin-photos").remove(paths)
        log.info("skin-photos silindi: user=%s count=%d", prefix, len(paths))
    except Exception as e:
        log.warning("skin-photos remove kısmen başarısız (%s): %s", prefix, e)


async def _auth_admin_delete_user(user_id: str) -> None:
    base = (SUPABASE_URL or "").rstrip("/")
    key = (SUPABASE_SERVICE_KEY or "").strip()
    if not base or not key:
        raise HTTPException(status_code=500, detail="Supabase yapılandırması eksik")
    url = f"{base}/auth/v1/admin/users/{user_id}"
    headers = {
        "apikey": key,
        "Authorization": f"Bearer {key}",
    }
    async with httpx.AsyncClient(timeout=45.0) as client:
        r = await client.delete(url, headers=headers)
    if r.status_code not in (200, 204):
        log.error("GoTrue admin delete_user: %s %s", r.status_code, r.text[:500])
        raise HTTPException(
            status_code=502,
            detail="Kimlik sağlayıcı hesabı silinemedi. Daha sonra tekrar deneyin veya destek ile iletişime geçin.",
        )


@app.post(
    "/account/delete",
    tags=["account"],
    dependencies=[Depends(rate_limit_dependency(LIMIT_ACCOUNT_DELETE))],
)
async def account_delete(request: Request, req: AccountDeleteRequest):
    """
    Oturum sahibinin Supabase auth kullanıcısını ve ilişkili uygulama verisini kaldırır
    (şema ON DELETE CASCADE). Storage’daki cilt fotoğrafları ayrıca temizlenir.
    İstemci `confirm_text` olarak tam metin `HESABIMI_SIL` göndermelidir.
    """
    if (req.confirm_text or "").strip() != _ACCOUNT_DELETE_CONFIRM:
        raise HTTPException(
            status_code=400,
            detail=f'Onay metni tam olarak "{_ACCOUNT_DELETE_CONFIRM}" olmalıdır.',
        )
    uid = (req.user_id or "").strip()
    if not uid or ".." in uid or any(c in uid for c in "/\\"):
        raise HTTPException(status_code=400, detail="Geçersiz kullanıcı kimliği")
    try:
        uuid.UUID(uid)
    except ValueError:
        raise HTTPException(status_code=400, detail="Geçersiz kullanıcı kimliği")
    enforce_supabase_user(request, uid)
    if is_demo_user_id(uid):
        raise HTTPException(status_code=400, detail="Demo hesap uygulama üzerinden silinemez.")

    supabase = get_supabase()
    if not supabase:
        raise HTTPException(status_code=500, detail="Supabase bağlantısı yok")

    _delete_skin_photos_for_user(supabase, uid)
    await _auth_admin_delete_user(uid)
    log.info("Hesap kalıcı silindi: user_id=%s", uid)
    return {"ok": True}


@app.post(
    "/upload_photo",
    tags=["media"],
    dependencies=[Depends(rate_limit_dependency(LIMIT_UPLOAD_PHOTO))],
)
async def upload_photo(request: Request, user_id: str, file: UploadFile = File(...)):
    """Fotoğraf yükleme endpoint'i."""
    enforce_supabase_user(request, user_id)
    if not user_id or ".." in user_id or any(c in user_id for c in "/\\"):
        raise HTTPException(status_code=400, detail="Geçersiz kullanıcı kimliği")
    supabase = get_supabase()
    if not supabase:
        raise HTTPException(status_code=500, detail="Supabase bağlantısı yok")
    try:
        name = file.filename or ""
        file_ext = name.rsplit(".", 1)[-1].lower() if "." in name else ""
        if file_ext not in _ALLOWED_PHOTO_EXT:
            raise HTTPException(
                status_code=400,
                detail="İzin verilen formatlar: jpeg, png, webp, heic",
            )
        contents = await file.read()
        if len(contents) > _MAX_PHOTO_BYTES:
            raise HTTPException(
                status_code=400,
                detail="Dosya çok büyük (en fazla 8 MB)",
            )
        file_path = f"{user_id}/{uuid.uuid4()}.{file_ext}"
        supabase.storage.from_("skin-photos").upload(file_path, contents)
        public_url = supabase.storage.from_("skin-photos").get_public_url(file_path)
        log.info("Fotoğraf yüklendi: %s", file_path)
        return {"url": public_url, "path": file_path}
    except HTTPException:
        raise
    except Exception as e:
        log.error("Fotoğraf yükleme hatası: %s", e)
        raise HTTPException(status_code=500, detail=str(e))


if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
