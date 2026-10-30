"""
REBI AI - Ana API Sunucusu v3.0
=================================
Mimari: Flow Engine (deterministik) -> Knowledge Router (metadata) -> AI (polish)
Yeni: /daily_checkin endpoint, adaptif rutin sistemi, risk skoru
"""

import asyncio
import httpx
import json
from fastapi import FastAPI, HTTPException, UploadFile, File, Depends, Request, Query
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field, model_validator
from typing import Optional, Literal
import os
import re
import secrets
import time
import uuid
from contextlib import nullcontext
from datetime import date, datetime, timedelta, timezone

from config import SUPABASE_URL, SUPABASE_SERVICE_KEY, CORS_ORIGINS, get_logger
from supabase_client import get_shared_client
from async_bridge import configure_threadpool, run_async, run_sync
from weather_service import FALLBACK as WEATHER_FALLBACK, fetch_weather_live
from today_plan import (
    CATEGORY_NAMES,
    DEFAULT_REMINDER_SETTINGS,
    EARLIEST_WAKE_MINUTES,
    LATEST_SLEEP_MINUTES,
    MIN_AWAKE_MINUTES,
    MIN_WINDOW_MINUTES,
    REMINDER_ACTIONS,
    WATER_INTERVAL_CHOICES,
    WATER_TARGET_CHOICES,
    WINDOW_IDS,
    build_environment_advice,
    build_reminders,
    build_weather_decisions,
    day_span_is_valid,
    due_reminders,
    normalize_reminder_settings,
    format_hhmm,
    parse_hhmm,
    reminder_category,
    reminder_open_path,
    reminder_windows,
    resolve_reminder_action,
)
from push_service import push_configured, send_push
from chat_context import build_today_summary
from shelf import SHELF_EVENT_TYPES, SHELF_LOOKBACK_DAYS, derive_products_out
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
    auth_configuration_valid,
    enforce_supabase_user,
    insecure_auth_allowed,
    jwt_auth_enabled,
    user_is_rebi_plus,
    user_plus_chat_is_monthly_capped,
)
from free_chat_quota import (
    free_chat_limit,
    free_chat_remaining,
)
from plus_chat_quota import (
    plus_chat_monthly_cap,
    plus_chat_remaining,
)
from chat_quota import reserve_chat_turn
from redis_client import redis_status
from db_integrity import get_integrity, refresh_in_background as _refresh_db_integrity, summary_nowait
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
    LIMIT_ROUTINE_ACTIVE,
    LIMIT_TODAY_PLAN,
    LIMIT_CHAT_ASSESSMENT,
    LIMIT_DAILY_CHECKIN,
    LIMIT_DAILY_CHECKIN_STATUS,
    LIMIT_GENERATE_ROUTINE,
    LIMIT_CHAT,
    LIMIT_CHAT_HISTORY,
    LIMIT_CHAT_HISTORY_CLEAR,
    LIMIT_CHAT_HISTORY_IMPORT,
    LIMIT_USER_DATA,
    LIMIT_USER_PROFILE_WRITE,
    LIMIT_DEVICE_REGISTER,
    LIMIT_PUSH_DISPATCH,
    LIMIT_PUSH_RESPOND,
    LIMIT_UPLOAD_PHOTO,
    LIMIT_ACCOUNT_DELETE,
    LIMIT_INTRO_SEEN,
    get_client_ip,
    enforce_ai_user_limit,
    enforce_ingest_user_limit,
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

def docs_enabled() -> bool:
    """Üretimde uç listesi ve şema dışarıya kapalıdır; API_DOCS_ENABLED=1 açar."""
    return (os.getenv("API_DOCS_ENABLED") or "").strip().lower() in {"1", "true", "yes", "on"}


_DOCS_ON = docs_enabled()

app = FastAPI(
    title="Rebi API",
    version="3.0.0",
    description=(
        "Rebi holistik cilt bakım API’si. "
        "Mobil ve web istemcileri `POST` gövdelerinde `user_id` (Supabase `auth.users` UUID) kullanır. "
        "`SUPABASE_JWT_SECRET` tanımlıysa isteklere `Authorization: Bearer <access_token>` ekleyin; "
        "`sub` ile `user_id` eşleşmeli."
    ),
    openapi_tags=_OPENAPI_TAGS,
    docs_url="/docs" if _DOCS_ON else None,
    redoc_url="/redoc" if _DOCS_ON else None,
    openapi_url="/openapi.json" if _DOCS_ON else None,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=CORS_ORIGINS + ["https://rebiovil.com", "https://www.rebiovil.com"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# Açılışta uygulanan şema durumu /health üzerinden görünür: sessiz şema
# kayması deploy sonrası kontrolde yakalanır.
_DB_SCHEMA_STATUS = "unknown"


@app.on_event("startup")
async def _configure_threadpool() -> None:
    await configure_threadpool()


@app.on_event("startup")
def _bootstrap_database_schema() -> None:
    """Supabase Postgres şifresi/URI varsa supabase/migrations/*.sql dosyalarını uygular."""
    global _DB_SCHEMA_STATUS
    try:
        from db_bootstrap import ensure_daily_events_schema

        _DB_SCHEMA_STATUS = ensure_daily_events_schema()
        if _DB_SCHEMA_STATUS == "error":
            log.warning(
                "daily_events şeması uygulanamadı; API çalışmaya devam ediyor."
            )
    except Exception as e:
        _DB_SCHEMA_STATUS = "error"
        log.warning("DB bootstrap çalıştırılamadı (yok sayılıyor): %s", e)
    # Eksik indeks/fonksiyon açılışta günlüğe düşsün; arka planda çalışır, açılışı geciktirmez.
    try:
        _refresh_db_integrity(force=True)
    except Exception as e:
        log.warning("DB öz-denetimi başlatılamadı (yok sayılıyor): %s", e)


def get_supabase():
    """Paylaşılan istemci (bağlantı havuzu yeniden kullanılır); yapılandırılmamışsa None."""
    return get_shared_client()

def _utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _safe_date_from_timestamp(ts: Optional[str]) -> str:
    """
    Basit ve sorunsuz: timestamp parse edilemezse bugüne düş.
    Date key: YYYY-MM-DD. Zaman damgası saat farkı taşıyorsa (mobil: `+03:00`) olayın
    kendi yerel günü kullanılır; böylece 00:00–03:00 arası kayıtlar önceki güne düşmez.
    `Z` ya da farksız damga UTC günüdür.
    """
    if not ts:
        return str(date.today())
    try:
        return datetime.fromisoformat(str(ts).replace("Z", "+00:00")).date().isoformat()
    except Exception:
        return str(date.today())


# `.in_()` filtreleri URL'ye yazılır: yüzlerce UUID ~37 bayt/kimlik tutar ve ağ geçidi sınırını aşabilir.
_BULK_IN_CHUNK = 50


def _chunks(items: list, size: int):
    for i in range(0, len(items), size):
        yield items[i : i + size]


def _postgrest_page_size() -> int:
    """PostgREST bir yanıtta en fazla `db-max-rows` satır döner (Supabase varsayılanı 1000)."""
    try:
        return max(10, int(os.getenv("POSTGREST_MAX_ROWS") or 1000))
    except ValueError:
        return 1000


def _fetch_paged(make_query, max_pages: int = 20) -> list[dict]:
    """
    Sınırın üstündeki sonuçları sayfa sayfa okur (`range`). Yoksa fazla satır sessizce kesilir ve en yeni
    kayıtlar kaybolur. `make_query` her çağrıda aynı sorguyu yeniden kurar ve BENZERSİZ bir anahtarla
    (ör. `id`) bitirir: eşit sıralı satırlar sayfa sınırında kaybolmasın ya da tekrarlanmasın.
    """
    size = _postgrest_page_size()
    rows: list[dict] = []
    for page in range(max_pages):
        batch = make_query().range(page * size, page * size + size - 1).execute().data or []
        rows.extend(batch)
        if len(batch) < size:
            break
    else:
        # Üst sınır, kötü niyetli ya da bozuk bir hesabın (yüz binlerce olay) isteği sonsuza dek şişirmesini önler.
        log.error("Sayfalı okuma %d sayfada bitmedi; sonuç eksik olabilir.", max_pages)
    return rows


def _local_today(utc_offset_minutes: Optional[int] = None) -> date:
    """
    Kullanıcının bugünü. İstemci `utc_offset_minutes` gönderirse onun yerel günü,
    göndermezse sunucu günü (web davranışı).
    """
    if utc_offset_minutes is None:
        return date.today()
    offset = max(-840, min(840, int(utc_offset_minutes)))
    return (datetime.now(timezone.utc) + timedelta(minutes=offset)).date()


# Supabase yokken (veya tablo yoksa) geliştirme için bellek içi depolama
_MEM_DAILY_EVENTS: dict[tuple[str, str], list[dict]] = {}

def _mem_append_event(user_id: str, log_date: str, event: dict) -> None:
    key = (user_id, log_date)
    bucket = _MEM_DAILY_EVENTS.setdefault(key, [])
    cid = event.get("client_event_id")
    if cid and any(e.get("client_event_id") == cid for e in bucket):
        return
    bucket.append(event)


_MAX_PRODUCTS_FINISHED = 20

# Supabase yokken (ya da demo kullanıcıda) hatırlatıcı ayarları bellekte tutulur.
_MEM_REMINDER_SETTINGS: dict[str, dict] = {}


def _load_reminder_settings(supabase, user_id: str) -> dict:
    """Kullanıcının hatırlatıcı ayarları; kayıt yoksa ya da okunamazsa varsayılan."""
    if should_use_supabase_db(supabase, user_id):
        try:
            rows = (
                supabase.table("reminder_settings")
                .select("settings")
                .eq("user_id", user_id)
                .limit(1)
                .execute()
            ).data or []
            return normalize_reminder_settings(rows[0].get("settings") if rows else None)
        except Exception as e:
            log.error("reminder_settings okunamadı (varsayılan kullanılır): %s", type(e).__name__)
            return normalize_reminder_settings(None)
    return normalize_reminder_settings(_MEM_REMINDER_SETTINGS.get(user_id))


def _load_reminder_settings_bulk(supabase, user_ids: list[str]) -> dict[str, dict]:
    """
    Push dağıtımı için birden çok kullanıcının ayarı toplu okunur; kayıtsızlar varsayılan alır.
    Okuma başarısız olursa istisna yükselir: varsayılan ayara düşmek kullanıcının kapattığı kategorileri
    ve sessiz saatlerini yok sayıp onlara istemedikleri bildirimi gönderirdi; çağıran bu kullanıcıları atlar.
    """
    stored: dict[str, dict] = {}
    if supabase and user_ids:
        for chunk in _chunks(list(user_ids), _BULK_IN_CHUNK):
            rows = (
                supabase.table("reminder_settings")
                .select("user_id,settings")
                .in_("user_id", chunk)
                .execute()
            ).data or []
            stored.update({str(r.get("user_id")): r.get("settings") for r in rows})
    return {uid: normalize_reminder_settings(stored.get(uid)) for uid in user_ids}

# Tek bir su kaydının sınırı; negatif değer yanlış girişi düzeltir (ör. -250).
_MAX_WATER_EVENT_ML = 5000

# Rutin blokları: adım işaretleri bu iki gruba ayrı yazılır.
_ROUTINE_BLOCKS = ("morning", "evening")

# Kabul edilen makyaj temizleme yöntemleri; bilinmeyen değer None olur.
_MAKEUP_REMOVAL_METHODS = frozenset({"double", "cleanser", "water", "wipe", "none"})


def _aggregate_daily_events(events: list[dict]) -> dict:
    water_ml_total = 0
    nutrition = {}
    nutrition_logged = False
    stress_vals = []
    sleep_hours = None
    last_location = None
    last_weather = None
    routine_steps_done = 0
    routine_morning_done = False
    routine_evening_done = False
    routine_steps: dict[str, set[int]] = {block: set() for block in _ROUTINE_BLOCKS}
    spf_refreshes = 0
    last_photo_meta = None
    checkin_feedback_events = 0
    makeup_logged = False
    makeup_used = False
    makeup_removed = False
    makeup_removal_method = None
    products_finished: list[dict] = []

    for ev in events or []:
        t = (ev.get("type") or "").lower()
        payload = ev.get("payload") or {}
        if t == "water_intake":
            try:
                ml = int(payload.get("ml", 0) or 0)
            except Exception:
                ml = 0
            ml = max(-_MAX_WATER_EVENT_ML, min(_MAX_WATER_EVENT_ML, ml))
            water_ml_total = max(0, water_ml_total + ml)
        elif t == "nutrition":
            if isinstance(payload, dict):
                nutrition = {**nutrition, **payload}
                nutrition_logged = True
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
            done = bool(payload.get("done"))
            if done:
                routine_steps_done += 1
            # Hangi adım: `block` + `step_order`. Aynı adım için son olay geçerlidir (işaret kaldırılabilir).
            block = str(payload.get("block") or "").strip().lower()
            step = payload.get("step_order")
            if block in routine_steps and isinstance(step, (int, float)) and not isinstance(step, bool):
                if done:
                    routine_steps[block].add(int(step))
                else:
                    routine_steps[block].discard(int(step))
        elif t == "routine_completed_block":
            # Son olay geçerlidir: `{"morning": false}` bloğu yeniden açar (yanlış dokunuşu geri alma).
            if "morning" in payload:
                routine_morning_done = bool(payload.get("morning"))
                if routine_morning_done:
                    routine_steps_done += 1
            if "evening" in payload:
                routine_evening_done = bool(payload.get("evening"))
                if routine_evening_done:
                    routine_steps_done += 1
        elif t == "spf_refresh":
            spf_refreshes += 1
        elif t == "photo_meta":
            if isinstance(payload, dict):
                last_photo_meta = payload
        elif t == "checkin_feedback":
            checkin_feedback_events += 1
        elif t == "makeup":
            makeup_logged = True
            if payload.get("used") is not None:
                makeup_used = bool(payload.get("used"))
            if bool(payload.get("removed")):
                makeup_used = True
                makeup_removed = True
            method = str(payload.get("method") or "").strip().lower()
            if method in _MAKEUP_REMOVAL_METHODS:
                makeup_removal_method = method
                if method != "none":
                    makeup_used = True
                    makeup_removed = True
        elif t == "product_finished":
            if len(products_finished) < _MAX_PRODUCTS_FINISHED:
                products_finished.append({
                    "product": str(payload.get("product") or "").strip()[:120] or None,
                    "step_order": payload.get("step_order"),
                    "at": ev.get("event_time"),
                })

    avg_stress = None
    if stress_vals:
        avg_stress = sum(stress_vals) / max(1, len(stress_vals))

    return {
        "water_ml_total": water_ml_total,
        "nutrition": nutrition,
        "nutrition_logged": nutrition_logged,
        "avg_stress": avg_stress,
        "sleep_hours": sleep_hours,
        "last_location": last_location,
        "weather": last_weather,
        "events_count": len(events or []),
        "routine_steps_done": routine_steps_done,
        "routine_morning_done": routine_morning_done,
        "routine_evening_done": routine_evening_done,
        "routine_steps": {block: sorted(steps) for block, steps in routine_steps.items()},
        "spf_refreshes": spf_refreshes,
        "last_photo_meta": last_photo_meta,
        "checkin_feedback_events": checkin_feedback_events,
        "makeup": {
            "logged": makeup_logged,
            "used": makeup_used,
            "removed": makeup_removed,
            "removal_method": makeup_removal_method,
        },
        "products_finished": products_finished,
    }


def _load_daily_events(supabase, user_id: str, log_date: str) -> list[dict]:
    """Günün olayları: Supabase varsa oradan, yoksa bellekten."""
    if should_use_supabase_db(supabase, user_id):
        try:
            # Sayfalı: tek sorgu yanıt sınırında kesilirse eskiden yeniye sıralı listenin SON (en yeni) olayları kaybolurdu.
            return _fetch_paged(lambda: (
                supabase.table("daily_events")
                .select("event_time,type,payload,source")
                .eq("user_id", user_id)
                .eq("log_date", log_date)
                .order("event_time")
                .order("id")
            ))
        except Exception as e:
            log.error("daily_events okuma hatası (fallback memory): %s", e)
    return _MEM_DAILY_EVENTS.get((user_id, log_date), [])


def _load_shelf_events(supabase, user_id: str, today: date) -> list[dict]:
    """Rafım için kullanıcının son bir yıllık ürün olayları (eskiden yeniye)."""
    since = str(today - timedelta(days=SHELF_LOOKBACK_DAYS))
    if should_use_supabase_db(supabase, user_id):
        try:
            return _fetch_paged(lambda: (
                supabase.table("daily_events")
                .select("event_time,log_date,type,payload")
                .eq("user_id", user_id)
                .in_("type", list(SHELF_EVENT_TYPES))
                .gte("log_date", since)
                .order("event_time")
                .order("id")
            ))
        except Exception as e:
            log.error("Rafım olayları okunamadı (bellek yedeği): %s", type(e).__name__)
    rows = [
        {**event, "log_date": day}
        for (uid, day), events in _MEM_DAILY_EVENTS.items()
        if uid == user_id and day >= since
        for event in events
        if event.get("type") in SHELF_EVENT_TYPES
    ]
    return sorted(rows, key=lambda e: str(e.get("event_time") or ""))


def _products_out(supabase, user_id: str, today: date) -> list[dict]:
    """Bitti işaretlenip henüz yenisi alınmamış ürünler (en son biten üstte)."""
    return derive_products_out(_load_shelf_events(supabase, user_id, today), today)


def _restock_window_open(settings: dict, local_now: datetime) -> bool:
    """Push dağıtımında Rafım sorgusu yalnızca "yenisini aldın mı" penceresi açıkken yapılır."""
    start, end = reminder_windows(settings).get("restock_check", ("", ""))
    now = local_now.hour * 60 + local_now.minute
    a, b = parse_hhmm(start), parse_hhmm(end)
    return a is not None and b is not None and a <= now <= b + _PUSH_DISPATCH_TOLERANCE_MINUTES


def _load_active_routine(supabase, user_id: str) -> dict:
    """Yürürlükteki rutin satırı; yoksa boş sözlük."""
    if not should_use_supabase_db(supabase, user_id):
        return {}
    try:
        r = (
            supabase.table("routines")
            .select("active_routine,assessment_id,created_at")
            .eq("user_id", user_id)
            .eq("is_active", True)
            .order("created_at", desc=True)
            .limit(1)
            .execute()
        )
        rows = r.data or []
        return rows[0] or {} if rows else {}
    except Exception as e:
        log.error("Aktif rutin okuma hatası: %s", e)
        return {}


def _checkin_done_today(supabase, user_id: str, log_date: str) -> bool:
    if is_demo_user_id(user_id):
        return demo_checkin_already_today(user_id, log_date)
    if not supabase:
        return False
    try:
        r = (
            supabase.table("daily_logs")
            .select("id")
            .eq("user_id", user_id)
            .eq("log_date", log_date)
            .limit(1)
            .execute()
        )
        return bool(r.data)
    except Exception as e:
        log.error("Check-in durumu okunamadı: %s", e)
        return False


_PROFILE_FIELDS = "full_name,skin_type,age,gender,city,updated_at"


def _load_profile_row(supabase, user_id: str) -> dict:
    if not should_use_supabase_db(supabase, user_id):
        return {}
    try:
        r = supabase.table("profiles").select(_PROFILE_FIELDS).eq("id", user_id).limit(1).execute()
        return (r.data or [{}])[0] or {}
    except Exception as e:
        log.error("Profil okunamadı: %s", type(e).__name__)
        return {}


def _chat_last_seq(supabase, user_id: str) -> Optional[int]:
    """Sohbet geçmişinin son imleci; mobil bunu artımlı okuma için kullanır."""
    if not should_use_supabase_db(supabase, user_id):
        return None
    try:
        r = (
            supabase.table("chat_history")
            .select("seq")
            .eq("user_id", user_id)
            .order("seq", desc=True)
            .limit(1)
            .execute()
        )
        return int(r.data[0]["seq"]) if r.data else None
    except Exception as e:
        log.error("Sohbet imleci okunamadı: %s", type(e).__name__)
        return None


def _consent_state(supabase, user_id: str) -> dict:
    """
    Rıza ve gizlilik izinleri. Mobil istemci bunu açılışta okur; aksi halde
    yapay zekâ uçları 403 döner ve sebebi istemcide görünmez.
    """
    state = {
        "legal_version": _LEGAL_CONSENT_VERSION,
        "legal_accepted": False,
        "ai_processing_allowed": False,
        "location_processing_allowed": False,
        "photo_processing_allowed": False,
    }
    if not should_use_supabase_db(supabase, user_id):
        return state
    try:
        c = (
            supabase.table("legal_consents")
            .select("accepted_at")
            .eq("user_id", user_id)
            .eq("document_version", _LEGAL_CONSENT_VERSION)
            .limit(1)
            .execute()
        )
        state["legal_accepted"] = bool(c.data)
        p = (
            supabase.table("privacy_preferences")
            .select("ai_processing_allowed,location_processing_allowed,photo_processing_allowed")
            .eq("user_id", user_id)
            .limit(1)
            .execute()
        )
        row = (p.data or [{}])[0] or {}
        state["ai_processing_allowed"] = row.get("ai_processing_allowed") is True
        state["location_processing_allowed"] = row.get("location_processing_allowed") is True
        state["photo_processing_allowed"] = row.get("photo_processing_allowed") is True
    except Exception as e:
        log.error("Rıza durumu okunamadı: %s", type(e).__name__)
    return state


def _privacy_permission_granted(supabase, user_id: str, permission: str) -> bool:
    """
    İzin var mı? `_require_privacy_permission` isteği keser; bu sürüm yalnızca
    sorar ve hata durumunda izin yok sayar (sessizce atlanır).
    """
    field = {
        "ai": "ai_processing_allowed",
        "location": "location_processing_allowed",
        "photo": "photo_processing_allowed",
    }[permission]
    if not should_use_supabase_db(supabase, user_id):
        return False
    try:
        r = (
            supabase.table("privacy_preferences")
            .select(field)
            .eq("user_id", user_id)
            .eq(field, True)
            .limit(1)
            .execute()
        )
        return bool(r.data)
    except Exception as e:
        log.error("İzin sorgusu başarısız: %s", type(e).__name__)
        return False


# Aynı bölge için hava durumu kısa süre saklanır; dağıtıcı ve ana ekran yüzlerce kullanıcı için
# sağlayıcıyı tekrar tekrar çağırmaz. Başarısız çekim çok kısa saklanır ve ASLA varsayılan
# değerle doldurulmaz: kullanıcı sahte değeri "canlı hava" diye görmesin.
_WEATHER_CACHE: dict[tuple, tuple[float, Optional[dict]]] = {}
_WEATHER_CACHE_MAX = 500
_WEATHER_TTL_SECONDS = 30 * 60
_WEATHER_FAILURE_TTL_SECONDS = 2 * 60


async def _weather_for_coords(lat: float, lon: float) -> Optional[dict]:
    """Önbellekli canlı hava; hiçbir kaynak yanıt vermiyorsa None."""
    key = (round(float(lat), 1), round(float(lon), 1))
    now = time.monotonic()
    cached = _WEATHER_CACHE.get(key)
    if cached is not None and cached[0] > now:
        return dict(cached[1]) if cached[1] else None
    data = await fetch_weather_live(lat, lon)
    if len(_WEATHER_CACHE) >= _WEATHER_CACHE_MAX:
        _WEATHER_CACHE.clear()
    ttl = _WEATHER_TTL_SECONDS if data else _WEATHER_FAILURE_TTL_SECONDS
    _WEATHER_CACHE[key] = (now + ttl, data)
    return dict(data) if data else None


async def _weather_cached(lat: float, lon: float) -> dict:
    """
    Rutin üretimi ve check-in için hava: `fetch_weather` ile aynı sözleşme (kaynak yanıt vermezse varsayılan değer),
    ama aynı 0,1° hücre için 30 dk önbellekli; başarısız çekim 2 dk saklanır. Eskiden her rutin/check-in isteği
    sağlayıcıya ayrı çağrı yapardı (ücretli planda ay sonu çağrı sayısı).
    """
    return await _weather_for_coords(lat, lon) or dict(WEATHER_FALLBACK)


async def _weather_from_profile(supabase, user_id: str) -> Optional[dict]:
    """
    İstemci konum göndermediğinde profildeki son bilinen koordinatı kullan.
    Konum izni yoksa hava durumu çekilmez.
    """
    coords = await run_sync(_profile_coords, supabase, user_id)
    if coords is None:
        return None
    return await _weather_for_coords(*coords)


def _profile_coords(supabase, user_id: str) -> Optional[tuple]:
    """Konum izni verilmişse profildeki son bilinen (enlem, boylam); aksi halde None. Senkron DB okuması."""
    if not _privacy_permission_granted(supabase, user_id, "location"):
        return None
    try:
        r = (
            supabase.table("profiles")
            .select("location_lat,location_lon")
            .eq("id", user_id)
            .limit(1)
            .execute()
        )
    except Exception as e:
        log.error("Profil konumu okunamadı: %s", type(e).__name__)
        return None
    row = (r.data or [{}])[0] or {}
    lat, lon = row.get("location_lat"), row.get("location_lon")
    if lat is None or lon is None:
        return None
    return lat, lon


async def _chat_today_summary(supabase, user_id: str, utc_offset_minutes: Optional[int]) -> str:
    """
    Sohbet için bugünün kısa özeti (hava, su, makyaj, beslenme, rutin). Veri ya da veritabanı
    yoksa, ya da herhangi bir hata olursa boş döner; sohbet bunsuz da çalışır.
    """
    if not should_use_supabase_db(supabase, user_id):
        return ""
    try:
        today = str(_local_today(utc_offset_minutes))
        aggregated = await run_sync(
            lambda: _aggregate_daily_events(_load_daily_events(supabase, user_id, today))
        )
        weather = aggregated.get("weather") or await _weather_from_profile(supabase, user_id)

        def _rest():
            settings = _load_reminder_settings(supabase, user_id)
            return build_today_summary(
                aggregated,
                weather,
                _checkin_done_today(supabase, user_id, today),
                settings["water_target_ml"],
                _products_out(supabase, user_id, date.fromisoformat(today)),
            )

        return await run_sync(_rest)
    except Exception as e:
        log.error("Sohbet günlük özeti hazırlanamadı: %s", type(e).__name__)
        return ""


def _profile_skin_type(supabase, user_id: str) -> str:
    if not should_use_supabase_db(supabase, user_id):
        return "normal"
    try:
        r = supabase.table("profiles").select("skin_type").eq("id", user_id).limit(1).execute()
        if r.data:
            return str(r.data[0].get("skin_type") or "normal")
    except Exception as e:
        log.error("Profil cilt tipi okunamadı: %s", e)
    return "normal"


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
    concerns: Optional[list] = None  # [{id, severity_score, zones}] — yoksa concern + severity_score
    actives_experience: str = "occasional"  # none | occasional | regular (retinol/asit vb. geçmiş kullanım)
    actives_unused: Optional[list] = None  # eski istemciler: her id -> never
    actives_tolerance: Optional[dict] = None  # { "bha": "never"|"good"|"mild"|"bad", ... }
    makeup_frequency: int = 0  # 0 yok, 1 seyrek, 3 haftada birkaç, 5 günlük
    makeup_removal: str = "cleanser"  # none | water | cleanser | double
    # UI: karışıklığı azaltan netleştirici işaretler (şimdilik opsiyonel)
    special_flags: Optional[dict] = None
    # Yalnızca erkeğe sorulan tıraş cevabı (mobil). Rutini şimdilik değiştirmez; kaydedilir ve sohbet bağlamına verilir.
    shaving_frequency: int = 0  # 0 hayır, 1 ara sıra, 3 haftada birkaç, 7 her gün
    shaving_after: str = ""  # ok | irritated | ingrown ("" = tıraş olmuyor / sorulmadı)
    triggers: Optional[list] = None
    past_treatments: Optional[list] = None
    expectations: Optional[list] = None
    nutrition: Optional[dict] = None

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
        self.shaving_frequency = max(0, min(7, int(self.shaving_frequency)))
        if self.shaving_after not in ("ok", "irritated", "ingrown"):
            self.shaving_after = ""
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
        from multi_concern import normalize_concern_entries, rank_concerns

        ranked = rank_concerns(
            normalize_concern_entries(
                concern=self.concern,
                severity_score=self.severity_score,
                acne_zones=self.acne_zones,
                concerns=self.concerns,
            )
        )
        self.concerns = ranked
        if ranked:
            self.concern = ranked[0]["id"]
            self.severity_score = int(ranked[0]["score"])
            acne = next((x for x in ranked if x["id"] == "acne" and x.get("zones")), None)
            pores = next((x for x in ranked if x["id"] == "pores" and x.get("zones")), None)
            if acne:
                self.acne_zones = acne["zones"]
            elif pores and not self.acne_zones:
                self.acne_zones = pores["zones"]
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


# Girdi sınırları: istemci ne gönderirse göndersin modele giden token sayısı sınırlıdır. Aşan kısım reddedilmez,
# sessizce kırpılır (meşru kullanım bu sınırların çok altındadır; INCI listesi yapıştırmak ~1-2 bin karakterdir).
# Kırpma olmazsa tek bir istek (nginx sınırı 12 MB) milyonlarca giriş token'ı faturalandırabilir.
CHAT_MESSAGE_MAX_CHARS = 4000
CHAT_HISTORY_MAX_TURNS = 20
# Değerlendirme sohbetinde "bilgi toplandı mı" sezgisi tüm geçmişi tarar (model yalnızca son 16 turu görür);
# erken verilen cevaplar (hamilelik, alerji…) kaybolmasın diye bu uçta sınır daha geniştir. Maliyeti artırmaz.
ASSESSMENT_HISTORY_MAX_TURNS = 40
CHAT_HISTORY_ITEM_MAX_CHARS = 1500
CHAT_PROFILE_MAX_KEYS = 80
CHAT_PROFILE_VALUE_MAX_CHARS = 1000
TRANSLATE_MAX_ITEMS = 40
TRANSLATE_ITEM_FIELD_MAX_CHARS = 1000


def _clip_text(value, limit: int):
    return value[:limit] if isinstance(value, str) and len(value) > limit else value


def _clip_history(history, max_turns: int = CHAT_HISTORY_MAX_TURNS):
    """Son N tur; her turun metni sınırlı. Sözlük olmayan öğeler atılır (sunucu `.get` ile okur)."""
    if not history:
        return history
    clipped = []
    for item in [m for m in history if isinstance(m, dict)][-max_turns:]:
        content = item.get("content")
        if isinstance(content, str) and len(content) > CHAT_HISTORY_ITEM_MAX_CHARS:
            item = {**item, "content": content[:CHAT_HISTORY_ITEM_MAX_CHARS]}
        clipped.append(item)
    return clipped


def _clip_profile(profile):
    """Serbest biçimli profil sözlüğü: anahtar sayısı ve metin değerleri sınırlı."""
    if not isinstance(profile, dict):
        return profile
    return {
        k: _clip_text(v, CHAT_PROFILE_VALUE_MAX_CHARS)
        for k, v in list(profile.items())[:CHAT_PROFILE_MAX_KEYS]
    }


class ChatRequest(BaseModel):
    user_id: str
    message: str
    concern: Optional[str] = "acne"
    history: Optional[list[dict]] = None

    @model_validator(mode="after")
    def _clip_inputs(self):
        self.message = _clip_text(self.message, CHAT_MESSAGE_MAX_CHARS)
        self.history = _clip_history(self.history)
        return self


class ChatResponse(BaseModel):
    reply: str
    sources: list[str]


class AssessmentChatRequest(BaseModel):
    user_id: str
    message: str
    history: Optional[list] = None
    user_profile: Optional[dict] = None

    @model_validator(mode="after")
    def _clip_inputs(self):
        self.message = _clip_text(self.message, CHAT_MESSAGE_MAX_CHARS)
        self.history = _clip_history(self.history, ASSESSMENT_HISTORY_MAX_TURNS)
        self.user_profile = _clip_profile(self.user_profile)
        return self


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
    # İstemcinin UTC farkı (dakika): sohbetin bildiği "bugün" kullanıcının yerel günüdür.
    utc_offset_minutes: Optional[int] = Field(default=None, ge=-840, le=840)

    @model_validator(mode="after")
    def _clip_inputs(self):
        self.message = _clip_text(self.message, CHAT_MESSAGE_MAX_CHARS)
        self.history = _clip_history(self.history)
        return self


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


class ChatHistoryMessage(BaseModel):
    seq: int
    role: Literal["user", "assistant"]
    content: str
    surface: str
    created_at: Optional[str] = None


class ChatHistoryImportMessage(BaseModel):
    role: Literal["user", "assistant"]
    content: str


class ChatHistoryImportRequest(BaseModel):
    user_id: str
    messages: list[ChatHistoryImportMessage]
    surface: Literal["general", "concern"] = "general"

    @model_validator(mode="after")
    def _cap_messages(self):
        self.messages = self.messages[-_CHAT_IMPORT_MAX_MESSAGES:]
        return self


class ChatHistoryImportResponse(BaseModel):
    imported: int
    skipped: bool
    cursor: Optional[int] = None


class ChatHistoryResponse(BaseModel):
    user_id: str
    messages: list[ChatHistoryMessage] = []
    # Mobil istemci bu imleci saklar ve sonraki açılışta yalnızca yenileri çeker.
    cursor: Optional[int] = None
    synced: bool


# Model/ağ hatasında kullanıcıya dönen sabit metinler: bu turlar kullanıcının kota hakkından düşmez.
_ASSESSMENT_ERROR_PREFIXES = (
    "Bir hata oluştu",
    "Bağlantı kurulamadı",
    "Şu an güvenli bir yanıt üretilemedi",
    "Şu an kısa bir yanıt üretilemedi",
    "Üzgünüm, şu anda cevap veremiyorum",
    "Şu an çok yoğunuz",
    "İşlem tamamlanamadı",
)
_GENERAL_ERROR_PREFIXES = (
    "Bir hata oluştu",
    "Bağlantı kurulamadı",
    "Şu an çok yoğunuz",
    "İşlem tamamlanamadı",
)


def _reply_looks_failed(reply: str, prefixes: tuple) -> bool:
    text = (reply or "").strip()
    return not text or text.startswith(prefixes)


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

    @model_validator(mode="after")
    def _clip_inputs(self):
        self.routine_items = [
            {k: _clip_text(v, TRANSLATE_ITEM_FIELD_MAX_CHARS) for k, v in item.items()}
            for item in self.routine_items[:TRANSLATE_MAX_ITEMS]
        ]
        return self


class DailyCheckinRequest(BaseModel):
    user_id: str
    # İstemcinin UTC farkı (dakika); verilirse "bugün" kullanıcının yerel günüdür.
    utc_offset_minutes: Optional[int] = None
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
    "makeup",
    "product_finished",
    "product_restocked",
]


class DailyTrackingIngestRequest(BaseModel):
    user_id: str
    timestamp: Optional[str] = None
    type: DailyTrackingClientEventType
    payload: dict = Field(default_factory=dict)
    source: str = "mobile"
    # Çevrimdışı kuyruk aynı olayı tekrar gönderirse ikinci yazım atlanır.
    client_event_id: Optional[str] = None

    @model_validator(mode="after")
    def _cap_payload(self):
        if self.client_event_id is not None:
            self.client_event_id = self.client_event_id.strip()[:64] or None
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


class RoutineActiveResponse(BaseModel):
    user_id: str
    has_routine: bool
    routine: list[dict] = []
    assessment_id: Optional[str] = None
    created_at: Optional[str] = None


SkinTypeName = Literal["normal", "dry", "oily", "combination", "sensitive"]


class UserProfileResponse(BaseModel):
    user_id: str
    full_name: Optional[str] = None
    skin_type: Optional[str] = None
    age: Optional[int] = None
    gender: Optional[str] = None
    city: Optional[str] = None
    updated_at: Optional[str] = None
    synced: bool


class UserProfileUpdateRequest(BaseModel):
    user_id: str
    full_name: Optional[str] = None
    skin_type: Optional[SkinTypeName] = None
    age: Optional[int] = None
    gender: Optional[Literal["female", "male", "other"]] = None
    city: Optional[str] = None

    @model_validator(mode="after")
    def _normalize_profile(self):
        if self.full_name is not None:
            self.full_name = self.full_name.strip()[:120]
        if self.city is not None:
            self.city = self.city.strip()[:80]
        if self.age is not None:
            self.age = max(13, min(100, int(self.age)))
        return self


class ReminderSettingsUpdateRequest(BaseModel):
    """Yalnızca gönderilen alanlar değişir."""

    user_id: str
    wake_time: Optional[str] = None
    sleep_time: Optional[str] = None
    water_every_minutes: Optional[int] = None
    water_target_ml: Optional[int] = None
    enabled: Optional[dict[str, bool]] = None
    # Pencere düzenlemeleri: kimlik -> {start, end}; kimlik için null o hatırlatıcıyı varsayılana döndürür.
    # `windows: null` hepsini sıfırlar. Alan hiç gönderilmezse dokunulmaz.
    windows: Optional[dict[str, Optional[dict]]] = None
    # Sessiz saatler {start, end}; `quiet: null` kapatır. Alan hiç gönderilmezse dokunulmaz.
    quiet: Optional[dict] = None


class ReminderSettingsResponse(BaseModel):
    user_id: str
    settings: dict
    synced: bool = True


class UserHistoryDay(BaseModel):
    log_date: str
    tracking: dict
    checkin: Optional[dict] = None


class UserHistoryResponse(BaseModel):
    user_id: str
    from_date: str
    to_date: str
    days: list[UserHistoryDay] = []
    assessments: list[dict] = []
    synced: bool
    # Kullanıcının günlük su hedefi (ml): grafik referansı ve "hedefi tutturulan gün" sayısı bununla hesaplanır.
    water_target_ml: int = 2000


class DeviceRegisterRequest(BaseModel):
    user_id: str
    token: str
    platform: Literal["ios", "android", "web"]
    # Hatırlatıcı saatleri yerel olduğundan cihazın UTC farkı gerekir.
    utc_offset_minutes: int = 0
    locale: Optional[str] = None
    app_version: Optional[str] = None
    push_enabled: bool = True
    # Bildirim butonlarını kendisi çizebilen sürümler true gönderir; Android'e
    # bu durumda yalnızca veri taşıyan mesaj gider.
    actions_supported: bool = False

    @model_validator(mode="after")
    def _normalize_device(self):
        self.token = self.token.strip()[:4096]
        if not self.token:
            raise ValueError("Cihaz anahtarı boş olamaz.")
        self.utc_offset_minutes = max(-840, min(840, int(self.utc_offset_minutes)))
        if self.locale:
            self.locale = self.locale.strip()[:10]
        if self.app_version:
            self.app_version = self.app_version.strip()[:30]
        return self


class DeviceRegisterResponse(BaseModel):
    ok: bool = True
    push_configured: bool
    synced: bool
    # Sunucu push dağıtıcısı yakın zamanda çalıştı mı (son tur ≤ 20 dk). Mobil, push'a yalnızca dağıtıcı canlıysa güvenir;
    # aksi hâlde hatırlatmalar yerel bildirimle kurulur (FCM açık ama push-cron çalışmıyorsa hiç hatırlatma gelmemesin).
    dispatch_alive: bool = False


class PushRespondRequest(BaseModel):
    user_id: str
    reminder_id: str = Field(..., min_length=1, max_length=40)
    action_id: str = Field(..., min_length=1, max_length=40)
    # Bildirim verisindeki yerel gün ve pencere; kayıt bu güne yazılır.
    log_date: Optional[str] = None
    slot: Optional[str] = Field(None, pattern=r"^\d{2}:\d{2}$")
    timestamp: Optional[str] = None
    client_event_id: Optional[str] = None


class PushRespondResponse(BaseModel):
    ok: bool = True
    log_date: str
    log_event: str
    aggregated: dict


class PushDispatchResponse(BaseModel):
    users_considered: int
    reminders_sent: int
    notifications_sent: int
    invalid_tokens_removed: int
    push_configured: bool
    # Hiçbir cihaza ulaşmayan ve sonraki turda yeniden denenecek hatırlatıcılar.
    deliveries_failed: int = 0
    # Verisi okunamadığı için bu turda atlanan kullanıcılar (yanlış bildirim göndermektense susulur).
    users_skipped: int = 0
    # Süre bütçesi ya da `max_users` yüzünden tur bitmedi; kalan kullanıcılar sonraki turda devam eder.
    truncated: bool = False


# Son dağıtım turunun özeti (bellekte): /health izleyicisi dağıtımın çalışıp çalışmadığını görsün.
_PUSH_LAST_RUN: dict = {}

# Dağıtıcı 5 dakikada bir çalışır; bu süreden eski son tur "çalışmıyor" sayılır. Özet bellekte tutulur
# (API tek süreç: uvicorn varsayılanı); çok işçili çalıştırılırsa Redis'e taşınmalı.
_PUSH_DISPATCH_ALIVE_MINUTES = 20


def _dispatch_alive() -> bool:
    """Push dağıtıcısı yakın zamanda tur attı mı? (Süreç yeniden başlayınca ilk turdan sonra yeniden doğru olur.)"""
    try:
        at = datetime.fromisoformat(str(_PUSH_LAST_RUN.get("at")))
    except (TypeError, ValueError):
        return False
    if at.tzinfo is None:
        at = at.replace(tzinfo=timezone.utc)
    return datetime.now(timezone.utc) - at <= timedelta(minutes=_PUSH_DISPATCH_ALIVE_MINUTES)


class UserSnapshotResponse(BaseModel):
    """Mobil açılışında tek çağrıyla senkron olunacak durum."""

    user_id: str
    server_time: str
    log_date: str
    profile: dict
    has_routine: bool
    routine: list[dict] = []
    routine_created_at: Optional[str] = None
    progress: dict
    checkin_done: bool
    chat_cursor: Optional[int] = None
    consent: dict
    plus: bool
    synced: bool


class TodayPlanResponse(BaseModel):
    user_id: str
    log_date: str
    has_routine: bool
    routine: list[dict] = []
    weather: dict
    weather_source: Literal["live", "tracking", "profile", "default"]
    environment_advice: list[dict] = []
    # Güneş kremi, nemlendirici ve dudak balsamı kararları (yapılandırılmış, istemci kendi dilinde yazar).
    weather_decisions: dict = {}
    # Rafım: bitti işaretlenip yenisi alınmamış ürünler (gün sınırı yok).
    products_out: list[dict] = []
    reminders: list[dict] = []
    reminder_settings: dict = {}
    progress: dict
    checkin_done: bool


_ACCOUNT_DELETE_CONFIRM = "HESABIMI_SIL"


class AccountDeleteRequest(BaseModel):
    user_id: str
    confirm_text: str


class LegalConsentAcceptRequest(BaseModel):
    user_id: str
    document_version: str
    kvkk_accepted: bool
    explicit_consent_accepted: bool
    ai_processing_accepted: bool
    location_processing_accepted: bool = False
    photo_processing_accepted: bool = False


class PrivacyPreferencesRequest(BaseModel):
    user_id: str
    ai_processing_allowed: bool
    location_processing_allowed: bool = False
    photo_processing_allowed: bool = False


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
            "/routine/active",
            "/today/plan",
            "/chat",
            "/chat_assessment",
            "/chat/history",
            "/daily_tracking/ingest",
            "/daily_tracking/today",
            "/daily_checkin",
            "/daily_checkin/status",
            "/me/snapshot",
            "/me/profile",
            "/me/history",
            "/devices/register",
            "/upload_photo",
            "/account/delete",
            "/health",
        ],
    }


@app.get("/knowledge/entity_search", response_model=KnowledgeEntitySearchResponse, tags=["meta"])
def knowledge_entity_search(
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


@app.get(
    "/intro/seen",
    tags=["meta"],
    dependencies=[Depends(rate_limit_dependency(LIMIT_INTRO_SEEN))],
)
def intro_seen_get(request: Request):
    """Bu istemci IP’si giriş sunumunu daha önce bitirdi mi? Ham IP saklanmaz."""
    from intro_seen import intro_already_seen

    return {"seen": intro_already_seen(get_client_ip(request))}


@app.post(
    "/intro/seen",
    tags=["meta"],
    dependencies=[Depends(rate_limit_dependency(LIMIT_INTRO_SEEN))],
)
def intro_seen_post(request: Request):
    from intro_seen import mark_intro_seen

    mark_intro_seen(get_client_ip(request))
    return {"ok": True, "seen": True}


@app.get("/health", tags=["health"])
async def health():
    supabase = get_supabase()
    auth_valid = auth_configuration_valid()
    body = {
        "status": "ok" if auth_valid else "misconfigured",
        "supabase": "connected" if supabase else "not configured",
        "concerns": list(CONCERN_KNOWLEDGE_MAP.keys()),
        "jwt_auth": "on" if jwt_auth_enabled() else "off",
        "auth_mode": (
            "jwt"
            if jwt_auth_enabled()
            else ("insecure_development" if insecure_auth_allowed() else "blocked")
        ),
        "rate_limit_backend": rate_limit_backend_label(),
        # Redis erişilebilir mi? "down": uygulama çalışır ama kota/hız sınırı süreç içine düşmüştür.
        "redis": await run_sync(redis_status),
        # Canlı DB öz-denetimi (eksik indeks/fonksiyon, retention cron'u). Önbellekten döner, DB'yi beklemez.
        "db_integrity": summary_nowait(),
        "push": "configured" if push_configured() else "off",
        "push_dispatch": _PUSH_LAST_RUN or None,
        "db_schema": _DB_SCHEMA_STATUS,
    }
    if not auth_valid:
        return JSONResponse(status_code=503, content=body)
    return body


@app.post(
    "/daily_tracking/ingest",
    response_model=DailyTrackingIngestResponse,
    tags=["tracking"],
    dependencies=[Depends(rate_limit_dependency(LIMIT_DAILY_TRACKING_INGEST))],
)
def daily_tracking_ingest(request: Request, req: DailyTrackingIngestRequest):
    """
    En basit ama sorunsuz: gün içinde event ingest et.
    Supabase varsa daily_events tablosuna yazar; yoksa bellek içi saklar.
    """
    enforce_supabase_user(request, req.user_id)
    _enforce_ingest_user_limit(req.user_id)
    payload_has_coords = (req.payload or {}).get("lat") is not None
    if req.type == "location" or payload_has_coords:
        # Koordinat hem saklanıyor hem hava durumu sağlayıcısına gidiyor.
        _require_privacy_permission(req.user_id, "location")
    log_date, aggregated = _store_daily_event(
        req.user_id,
        req.type,
        req.payload or {},
        timestamp=req.timestamp,
        source=req.source or "mobile",
        client_event_id=req.client_event_id,
    )
    return DailyTrackingIngestResponse(ok=True, log_date=log_date, aggregated=aggregated)


def _store_daily_event(
    user_id: str,
    event_type: str,
    payload: dict,
    *,
    timestamp: Optional[str] = None,
    source: str = "mobile",
    client_event_id: Optional[str] = None,
    log_date: Optional[str] = None,
) -> tuple[str, dict]:
    """Olayı yazar ve o günün güncel toplamını döner (Supabase yoksa bellek)."""
    ts = timestamp or _utc_now_iso()
    log_date = log_date or _safe_date_from_timestamp(ts)
    event = {
        "user_id": user_id,
        "event_time": ts,
        "log_date": log_date,
        "type": event_type,
        "payload": payload,
        "source": source,
    }
    if client_event_id:
        event["client_event_id"] = client_event_id

    supabase = get_supabase()
    wrote_remote = False
    db_backed = should_use_supabase_db(supabase, user_id)
    if db_backed:
        try:
            table = supabase.table("daily_events")
            if client_event_id:
                table.upsert(
                    event,
                    on_conflict="user_id,client_event_id",
                    ignore_duplicates=True,
                ).execute()
            else:
                table.insert(event).execute()
            wrote_remote = True
        except Exception as e:
            log.error("daily_events insert hatası: %s", e)

    if not wrote_remote:
        if db_backed:
            # Gerçek kullanıcıda olayı süreç belleğine yazıp "tamam" demek sessiz veri kaybıdır: bellek yeniden
            # başlatmada silinir ve gün okumaları hep veritabanından yapılır (bellek hiç okunmaz). 503 dönersek
            # mobil olayı aynı `client_event_id` ile kuyruğa alıp yeniden dener (tekrar yazım olayı iki kez saydırmaz).
            raise HTTPException(status_code=503, detail="Kayıt şu an yazılamadı; bağlantı düzelince yeniden denenecek.")
        _mem_append_event(user_id, log_date, event)

    # Location gelirse anlık weather snapshot ekle (opsiyonel ama değerli)
    if event_type == "location":
        try:
            lat = payload.get("lat")
            lon = payload.get("lon")
            # Hava servisi yanıt vermezse olay yazılmaz: varsayılan değer gerçek hava gibi saklanmasın.
            weather_data = (
                run_async(_weather_for_coords, lat, lon) if lat is not None and lon is not None else None
            )
            if weather_data:
                w_event = {
                    "user_id": user_id,
                    "event_time": _utc_now_iso(),
                    "log_date": log_date,
                    "type": "weather",
                    "payload": weather_data,
                    "source": "server",
                }
                if should_use_supabase_db(supabase, user_id):
                    try:
                        supabase.table("daily_events").insert(w_event).execute()
                    except Exception as e:
                        log.error("weather event insert hatası (ignored): %s", e)
                        _mem_append_event(user_id, log_date, w_event)
                else:
                    _mem_append_event(user_id, log_date, w_event)
        except Exception as e:
            log.error("Location->weather hatası (ignored): %s", e)

    # Return aggregated for immediate UI feedback
    events = []
    if should_use_supabase_db(supabase, user_id):
        try:
            events = _fetch_paged(lambda: (
                supabase.table("daily_events")
                .select("event_time,type,payload,source")
                .eq("user_id", user_id)
                .eq("log_date", log_date)
                .order("event_time")
                .order("id")
            ))
        except Exception as e:
            log.error("daily_events read hatası (fallback memory): %s", e)
            events = _MEM_DAILY_EVENTS.get((user_id, log_date), [])
    else:
        events = _MEM_DAILY_EVENTS.get((user_id, log_date), [])

    return log_date, _aggregate_daily_events(events)


@app.get(
    "/daily_tracking/today",
    response_model=DailyTrackingTodayResponse,
    tags=["tracking"],
    dependencies=[Depends(rate_limit_dependency(LIMIT_DAILY_TRACKING_TODAY))],
)
def daily_tracking_today(
    request: Request,
    user_id: str,
    log_date: Optional[str] = None,
    include_events: bool = False,
    utc_offset_minutes: Optional[int] = Query(None, ge=-840, le=840),
):
    """
    Mobil: bugün ne toplandı? Basit günlük özet.
    """
    enforce_supabase_user(request, user_id)
    d = log_date or str(_local_today(utc_offset_minutes))
    events = _load_daily_events(get_supabase(), user_id, d)

    return DailyTrackingTodayResponse(
        user_id=user_id,
        log_date=d,
        aggregated=_aggregate_daily_events(events),
        events=(events if include_events else []),
    )


@app.get(
    "/routine/active",
    response_model=RoutineActiveResponse,
    tags=["routine"],
    dependencies=[Depends(rate_limit_dependency(LIMIT_ROUTINE_ACTIVE))],
)
def routine_active(request: Request, user_id: str = Query(..., min_length=1)):
    """Mobil ana ekran: yürürlükteki rutin (üretmez, yalnızca okur)."""
    enforce_supabase_user(request, user_id)
    row = _load_active_routine(get_supabase(), user_id)
    routine = row.get("active_routine") or []
    return RoutineActiveResponse(
        user_id=user_id,
        has_routine=bool(routine),
        routine=routine,
        assessment_id=(str(row["assessment_id"]) if row.get("assessment_id") else None),
        created_at=(str(row["created_at"]) if row.get("created_at") else None),
    )


@app.get(
    "/today/plan",
    response_model=TodayPlanResponse,
    tags=["routine"],
    dependencies=[Depends(rate_limit_dependency(LIMIT_TODAY_PLAN))],
)
def today_plan_endpoint(
    request: Request,
    user_id: str = Query(..., min_length=1),
    lat: Optional[float] = None,
    lon: Optional[float] = None,
    utc_offset_minutes: Optional[int] = Query(None, ge=-840, le=840),
):
    """
    Mobil ana ekran paketi: günün rutini, havaya göre ürün önerileri
    (SPF / nemlendirici / balsam), saat aralıklı hatırlatıcılar ve bugün
    ne yapıldığı. Yapay zekâ çağrısı yoktur; hava için konum izni gerekir.
    Hatırlatıcı pencereleri kullanıcının gün düzenine (`reminder_settings`) göre kurulur.
    """
    enforce_supabase_user(request, user_id)
    supabase = get_supabase()
    today = str(_local_today(utc_offset_minutes))
    settings = _load_reminder_settings(supabase, user_id)

    events = _load_daily_events(supabase, user_id, today)
    aggregated = _aggregate_daily_events(events)

    # Sıra: istemcinin konumu (canlı) → bugün kaydedilen hava → profildeki konum → varsayılan.
    # Canlı çekim başarısızsa bir sonraki kaynağa düşülür; varsayılan değer "canlı" diye sunulmaz.
    weather: Optional[dict] = None
    weather_source = "default"
    if lat is not None and lon is not None:
        _require_privacy_permission(user_id, "location")
        weather = run_async(_weather_for_coords, lat, lon)
        if weather:
            weather_source = "live"
    if weather is None and aggregated.get("weather"):
        weather = dict(aggregated["weather"])
        weather_source = "tracking"
    if weather is None:
        weather = run_async(_weather_from_profile, supabase, user_id)
        if weather:
            weather_source = "profile"
    if weather is None:
        weather = dict(WEATHER_FALLBACK)

    row = _load_active_routine(supabase, user_id)
    routine = row.get("active_routine") or []
    checkin_done = _checkin_done_today(supabase, user_id, today)
    products_out = _products_out(supabase, user_id, date.fromisoformat(today))

    return TodayPlanResponse(
        user_id=user_id,
        log_date=today,
        has_routine=bool(routine),
        routine=routine,
        weather=weather,
        weather_source=weather_source,
        environment_advice=build_environment_advice(weather, _profile_skin_type(supabase, user_id)),
        weather_decisions=build_weather_decisions(weather, settings),
        products_out=products_out,
        reminders=build_reminders(weather, aggregated, checkin_done, settings, products_out),
        reminder_settings=settings,
        progress=aggregated,
        checkin_done=checkin_done,
    )


_MAX_HISTORY_DAYS = 90


@app.get(
    "/me/profile",
    response_model=UserProfileResponse,
    tags=["account"],
    dependencies=[Depends(rate_limit_dependency(LIMIT_USER_DATA))],
)
def me_profile_get(request: Request, user_id: str = Query(..., min_length=1)):
    """Kullanıcı profili: web ve mobil aynı kaydı okur."""
    enforce_supabase_user(request, user_id)
    supabase = get_supabase()
    if not should_use_supabase_db(supabase, user_id):
        return UserProfileResponse(user_id=user_id, synced=False)
    row = _load_profile_row(supabase, user_id)
    return UserProfileResponse(
        user_id=user_id,
        full_name=row.get("full_name"),
        skin_type=row.get("skin_type"),
        age=row.get("age"),
        gender=row.get("gender"),
        city=row.get("city"),
        updated_at=(str(row["updated_at"]) if row.get("updated_at") else None),
        synced=True,
    )


@app.patch(
    "/me/profile",
    response_model=UserProfileResponse,
    tags=["account"],
    dependencies=[Depends(rate_limit_dependency(LIMIT_USER_PROFILE_WRITE))],
)
def me_profile_update(request: Request, req: UserProfileUpdateRequest):
    """Profili güncelle; yalnızca gönderilen alanlar değişir."""
    enforce_supabase_user(request, req.user_id)
    fields = {
        k: v for k, v in req.model_dump(exclude={"user_id"}).items() if v is not None
    }
    if not fields:
        raise HTTPException(status_code=400, detail="Güncellenecek alan gönderilmedi.")

    supabase = get_supabase()
    if not should_use_supabase_db(supabase, req.user_id):
        return UserProfileResponse(user_id=req.user_id, synced=False, **fields)

    try:
        supabase.table("profiles").upsert({
            "id": req.user_id,
            **fields,
            "updated_at": datetime.now(timezone.utc).isoformat(),
        }).execute()
    except Exception as e:
        log.error("Profil güncellenemedi: %s", type(e).__name__)
        raise HTTPException(status_code=502, detail="Profil şu an güncellenemedi.")

    row = _load_profile_row(supabase, req.user_id)
    return UserProfileResponse(
        user_id=req.user_id,
        full_name=row.get("full_name"),
        skin_type=row.get("skin_type"),
        age=row.get("age"),
        gender=row.get("gender"),
        city=row.get("city"),
        updated_at=(str(row["updated_at"]) if row.get("updated_at") else None),
        synced=True,
    )


def _water_target_for(supabase, user_id: str) -> int:
    """Kullanıcının günlük su hedefi; ayar okunamazsa varsayılan (geçmiş ekranı yine açılsın)."""
    try:
        return int(_load_reminder_settings(supabase, user_id)["water_target_ml"])
    except Exception:
        return int(DEFAULT_REMINDER_SETTINGS["water_target_ml"])


@app.get(
    "/me/history",
    response_model=UserHistoryResponse,
    tags=["account"],
    dependencies=[Depends(rate_limit_dependency(LIMIT_USER_DATA))],
)
def me_history(
    request: Request,
    user_id: str = Query(..., min_length=1),
    days: int = Query(30, ge=1, le=_MAX_HISTORY_DAYS),
    utc_offset_minutes: Optional[int] = Query(None, ge=-840, le=840),
):
    """Geçmiş günler: her gün için takip özeti ve o günün check-in'i."""
    enforce_supabase_user(request, user_id)
    supabase = get_supabase()
    to_date = _local_today(utc_offset_minutes)
    from_date = to_date - timedelta(days=days - 1)
    date_keys = [str(from_date + timedelta(days=i)) for i in range(days)]

    if not should_use_supabase_db(supabase, user_id):
        days_out = [
            UserHistoryDay(
                log_date=d,
                tracking=_aggregate_daily_events(_MEM_DAILY_EVENTS.get((user_id, d), [])),
            )
            for d in date_keys
            if _MEM_DAILY_EVENTS.get((user_id, d))
        ]
        return UserHistoryResponse(
            user_id=user_id,
            from_date=str(from_date),
            to_date=str(to_date),
            days=days_out,
            synced=False,
            water_target_ml=_water_target_for(supabase, user_id),
        )

    try:
        # 90 günde olay sayısı PostgREST yanıt sınırını (1000) kolayca aşar: sayfalanmazsa en yeni günler sessizce kaybolurdu.
        events = _fetch_paged(lambda: (
            supabase.table("daily_events")
            .select("event_time,type,payload,log_date")
            .eq("user_id", user_id)
            .gte("log_date", str(from_date))
            .lte("log_date", str(to_date))
            .order("event_time")
            .order("id")
        ))
        logs = (
            supabase.table("daily_logs")
            .select("log_date,applied_routine,skin_feeling,sleep_hours,stress_level,risk_score")
            .eq("user_id", user_id)
            .gte("log_date", str(from_date))
            .lte("log_date", str(to_date))
            .order("log_date", desc=False)
            .execute()
        ).data or []
        assessments = (
            supabase.table("assessments")
            .select("id,concern,severity_score,created_at")
            .eq("user_id", user_id)
            .order("created_at", desc=True)
            .limit(10)
            .execute()
        ).data or []
    except Exception as e:
        log.error("Geçmiş okunamadı: %s", type(e).__name__)
        raise HTTPException(status_code=502, detail="Geçmiş veriler şu an okunamadı.")

    by_date: dict[str, list[dict]] = {}
    for ev in events:
        by_date.setdefault(str(ev.get("log_date")), []).append(ev)
    checkin_by_date = {str(row.get("log_date")): row for row in logs}

    days_out = [
        UserHistoryDay(
            log_date=d,
            tracking=_aggregate_daily_events(by_date.get(d, [])),
            checkin=checkin_by_date.get(d),
        )
        for d in date_keys
        if d in by_date or d in checkin_by_date
    ]
    return UserHistoryResponse(
        user_id=user_id,
        from_date=str(from_date),
        to_date=str(to_date),
        days=days_out,
        water_target_ml=_water_target_for(supabase, user_id),
        assessments=assessments,
        synced=True,
    )


@app.get(
    "/me/snapshot",
    response_model=UserSnapshotResponse,
    tags=["account"],
    dependencies=[Depends(rate_limit_dependency(LIMIT_USER_DATA))],
)
def me_snapshot(
    request: Request,
    user_id: str = Query(..., min_length=1),
    utc_offset_minutes: Optional[int] = Query(None, ge=-840, le=840),
):
    """
    Mobil açılış paketi: profil, yürürlükteki rutin, bugünün ilerlemesi,
    rıza durumu ve sohbet imleci tek çağrıda döner.
    """
    enforce_supabase_user(request, user_id)
    supabase = get_supabase()
    today = str(_local_today(utc_offset_minutes))
    row = _load_active_routine(supabase, user_id)
    routine = row.get("active_routine") or []
    synced = should_use_supabase_db(supabase, user_id)

    return UserSnapshotResponse(
        user_id=user_id,
        server_time=_utc_now_iso(),
        log_date=today,
        profile=_load_profile_row(supabase, user_id),
        has_routine=bool(routine),
        routine=routine,
        routine_created_at=(str(row["created_at"]) if row.get("created_at") else None),
        progress=_aggregate_daily_events(_load_daily_events(supabase, user_id, today)),
        checkin_done=_checkin_done_today(supabase, user_id, today),
        chat_cursor=_chat_last_seq(supabase, user_id),
        consent=_consent_state(supabase, user_id),
        plus=user_is_rebi_plus(request, user_id),
        synced=synced,
    )


@app.get(
    "/me/reminder-settings",
    response_model=ReminderSettingsResponse,
    tags=["account"],
    dependencies=[Depends(rate_limit_dependency(LIMIT_USER_DATA))],
)
def me_reminder_settings_get(request: Request, user_id: str = Query(..., min_length=1)):
    """Hatırlatıcı ayarları: gün düzeni, su aralığı ve kapatılan kategoriler."""
    enforce_supabase_user(request, user_id)
    supabase = get_supabase()
    return ReminderSettingsResponse(
        user_id=user_id,
        settings=_load_reminder_settings(supabase, user_id),
        synced=should_use_supabase_db(supabase, user_id),
    )


def _parse_range_or_422(raw, label: str) -> tuple[int, int]:
    parsed = None
    if isinstance(raw, dict):
        start, end = parse_hhmm(raw.get("start")), parse_hhmm(raw.get("end"))
        parsed = (start, end) if start is not None and end is not None else None
    if parsed is None:
        raise HTTPException(status_code=422, detail=f"{label}: başlangıç ve bitiş SS:DD biçiminde olmalı.")
    return parsed


def _merge_windows(current: dict, incoming: Optional[dict], merged: dict) -> dict:
    """Pencere düzenlemelerini birleştirir; geçersiz kimlik/saat/çok kısa ya da gün dışı pencere 422 verir."""
    if incoming is None:  # açıkça null: hepsini varsayılana döndür
        return {}
    wake, sleep = parse_hhmm(merged["wake_time"]), parse_hhmm(merged["sleep_time"])
    result = {k: dict(v) for k, v in current.items()}
    for reminder_id, custom in incoming.items():
        if reminder_id not in WINDOW_IDS:
            raise HTTPException(status_code=422, detail=f"Bilinmeyen hatırlatıcı: {reminder_id}")
        if custom is None:
            result.pop(reminder_id, None)
            continue
        start, end = _parse_range_or_422(custom, reminder_id)
        if end - start < MIN_WINDOW_MINUTES:
            raise HTTPException(
                status_code=422,
                detail=f"{reminder_id}: pencere en az {MIN_WINDOW_MINUTES} dakika olmalı ve bitiş başlangıçtan sonra gelmeli.",
            )
        if start < wake or end > sleep:
            raise HTTPException(
                status_code=422,
                detail=f"{reminder_id}: pencere uyanma ({merged['wake_time']}) ile uyku ({merged['sleep_time']}) saati arasında olmalı.",
            )
        result[reminder_id] = {"start": format_hhmm(start), "end": format_hhmm(end)}
    return result


def _validated_quiet(raw: Optional[dict]) -> Optional[dict]:
    if raw is None:
        return None
    start, end = _parse_range_or_422(raw, "Sessiz saatler")
    if start == end:
        raise HTTPException(status_code=422, detail="Sessiz saatlerin başlangıcı ile bitişi aynı olamaz.")
    return {"start": format_hhmm(start), "end": format_hhmm(end)}


def _merge_reminder_settings(current: dict, req: ReminderSettingsUpdateRequest) -> dict:
    """Gönderilen alanları mevcut ayara işler; geçersiz değerde 422 verir."""
    merged = {**current, "enabled": {**current["enabled"]}}

    if req.wake_time is not None:
        if parse_hhmm(req.wake_time) is None:
            raise HTTPException(status_code=422, detail="Uyanma saati SS:DD biçiminde olmalı.")
        merged["wake_time"] = req.wake_time
    if req.sleep_time is not None:
        if parse_hhmm(req.sleep_time) is None:
            raise HTTPException(status_code=422, detail="Uyku saati SS:DD biçiminde olmalı.")
        merged["sleep_time"] = req.sleep_time
    wake = parse_hhmm(merged["wake_time"])
    sleep = parse_hhmm(merged["sleep_time"])
    if wake is None or sleep is None or not day_span_is_valid(wake, sleep):
        raise HTTPException(
            status_code=422,
            detail=(
                f"Uyanma saati en erken {EARLIEST_WAKE_MINUTES // 60:02d}:00, uyku saati en geç "
                f"{LATEST_SLEEP_MINUTES // 60:02d}:{LATEST_SLEEP_MINUTES % 60:02d} olabilir; "
                f"ikisi arasında en az {MIN_AWAKE_MINUTES // 60} saat bulunmalı."
            ),
        )

    if req.water_every_minutes is not None:
        if req.water_every_minutes not in WATER_INTERVAL_CHOICES:
            raise HTTPException(
                status_code=422,
                detail=f"Su aralığı şunlardan biri olmalı: {', '.join(str(v) for v in WATER_INTERVAL_CHOICES)} dakika.",
            )
        merged["water_every_minutes"] = req.water_every_minutes

    if req.water_target_ml is not None:
        if req.water_target_ml not in WATER_TARGET_CHOICES:
            raise HTTPException(
                status_code=422,
                detail=f"Su hedefi şunlardan biri olmalı: {', '.join(str(v) for v in WATER_TARGET_CHOICES)} ml.",
            )
        merged["water_target_ml"] = req.water_target_ml

    if "windows" in req.model_fields_set:
        merged["windows"] = _merge_windows(current.get("windows") or {}, req.windows, merged)
    if "quiet" in req.model_fields_set:
        merged["quiet"] = _validated_quiet(req.quiet)

    if req.enabled is not None:
        unknown = sorted(set(req.enabled) - set(CATEGORY_NAMES))
        if unknown:
            raise HTTPException(status_code=422, detail=f"Bilinmeyen hatırlatıcı kategorisi: {', '.join(unknown)}")
        merged["enabled"].update(req.enabled)

    return normalize_reminder_settings(merged)


@app.put(
    "/me/reminder-settings",
    response_model=ReminderSettingsResponse,
    tags=["account"],
    dependencies=[Depends(rate_limit_dependency(LIMIT_USER_PROFILE_WRITE))],
)
def me_reminder_settings_update(request: Request, req: ReminderSettingsUpdateRequest):
    """Hatırlatıcı ayarlarını güncelle; yalnızca gönderilen alanlar değişir."""
    enforce_supabase_user(request, req.user_id)
    supabase = get_supabase()
    settings = _merge_reminder_settings(_load_reminder_settings(supabase, req.user_id), req)

    if not should_use_supabase_db(supabase, req.user_id):
        _MEM_REMINDER_SETTINGS[req.user_id] = settings
        return ReminderSettingsResponse(user_id=req.user_id, settings=settings, synced=False)

    try:
        supabase.table("reminder_settings").upsert(
            {
                "user_id": req.user_id,
                "settings": settings,
                "updated_at": datetime.now(timezone.utc).isoformat(),
            },
            on_conflict="user_id",
        ).execute()
    except Exception as e:
        log.error("Hatırlatıcı ayarları kaydedilemedi: %s", type(e).__name__)
        raise HTTPException(status_code=502, detail="Hatırlatıcı ayarları şu an kaydedilemedi.")
    return ReminderSettingsResponse(user_id=req.user_id, settings=settings, synced=True)


_PUSH_DISPATCH_TOLERANCE_MINUTES = 10
_PUSH_MAX_TOKENS_PER_USER = 5
_PUSH_WEATHER_HOURS = (10, 17)


def _require_push_dispatch_secret(request: Request) -> None:
    """Dağıtım yalnızca sunucu cron'una açıktır; anahtar yoksa kapalıdır."""
    secret = (os.getenv("PUSH_DISPATCH_SECRET") or "").strip()
    if not secret:
        raise HTTPException(status_code=503, detail="Push dağıtımı yapılandırılmamış.")
    provided = (request.headers.get("x-push-dispatch-token") or "").strip()
    if not provided or not secrets.compare_digest(provided, secret):
        raise HTTPException(status_code=401, detail="Geçersiz dağıtım anahtarı.")


def _claim_push_slot(supabase, user_id: str, reminder_id: str, log_date: str, slot: str) -> bool:
    """
    Gönderim defterine yaz. Satır zaten varsa bu hatırlatıcı bugün bu pencerede
    gönderilmiş demektir ve tekrar gönderilmez.
    """
    try:
        supabase.table("push_sends").insert({
            "user_id": user_id,
            "reminder_id": reminder_id,
            "log_date": log_date,
            "slot": slot,
        }).execute()
        return True
    except Exception as e:
        if _is_duplicate_error(e):
            log.info("Hatırlatıcı atlandı (zaten gönderilmiş): %s %s", reminder_id, slot)
        else:
            # Defter yazılamıyorsa tekrarı önleyemeyiz; göndermeyiz ama sessiz kalmayız.
            log.error("Gönderim defterine yazılamadı (hatırlatıcı atlandı): %s %s %s", reminder_id, slot, type(e).__name__)
        return False


def _is_duplicate_error(exc: Exception) -> bool:
    """Benzersiz kısıt ihlali mi (Postgres 23505)?"""
    if str(getattr(exc, "code", "") or "") == "23505":
        return True
    text = str(exc).lower()
    return "duplicate key" in text or "unique constraint" in text


def _release_push_slot(supabase, user_id: str, reminder_id: str, log_date: str, slot: str) -> None:
    """Gönderim hiçbir cihaza ulaşmadıysa rezervi geri al; sonraki turda yeniden denenir."""
    try:
        (
            supabase.table("push_sends")
            .delete()
            .eq("user_id", user_id)
            .eq("reminder_id", reminder_id)
            .eq("log_date", log_date)
            .eq("slot", slot)
            .execute()
        )
    except Exception as e:
        log.error("Gönderim rezervi geri alınamadı: %s", type(e).__name__)


def _remove_invalid_device_tokens(supabase, tokens: list[str]) -> int:
    removed = 0
    for chunk in _chunks(list(tokens), _BULK_IN_CHUNK):
        try:
            supabase.table("device_tokens").delete().in_("token", chunk).execute()
            removed += len(chunk)
        except Exception as e:
            log.error("Geçersiz cihaz kayıtları silinemedi: %s", type(e).__name__)
    return removed


@app.post(
    "/devices/register",
    response_model=DeviceRegisterResponse,
    tags=["push"],
    dependencies=[Depends(rate_limit_dependency(LIMIT_DEVICE_REGISTER))],
)
def device_register(request: Request, req: DeviceRegisterRequest):
    """Cihazı bildirimler için kaydeder; her açılışta çağrılabilir."""
    enforce_supabase_user(request, req.user_id)
    supabase = get_supabase()
    if not should_use_supabase_db(supabase, req.user_id):
        return DeviceRegisterResponse(push_configured=push_configured(), synced=False, dispatch_alive=_dispatch_alive())
    try:
        supabase.table("device_tokens").upsert({
            "user_id": req.user_id,
            "token": req.token,
            "platform": req.platform,
            "utc_offset_minutes": req.utc_offset_minutes,
            "locale": req.locale,
            "app_version": req.app_version,
            "push_enabled": req.push_enabled,
            "actions_supported": req.actions_supported,
            "last_seen_at": _utc_now_iso(),
        }, on_conflict="token").execute()
    except Exception as e:
        log.error("Cihaz kaydı yazılamadı: %s", type(e).__name__)
        raise HTTPException(status_code=502, detail="Cihaz kaydı şu an yapılamadı.")
    return DeviceRegisterResponse(push_configured=push_configured(), synced=True, dispatch_alive=_dispatch_alive())


@app.delete(
    "/devices/register",
    tags=["push"],
    dependencies=[Depends(rate_limit_dependency(LIMIT_DEVICE_REGISTER))],
)
def device_unregister(
    request: Request,
    user_id: str = Query(..., min_length=1),
    token: str = Query(..., min_length=1),
):
    """Çıkışta veya bildirim kapatıldığında cihaz kaydını kaldırır."""
    enforce_supabase_user(request, user_id)
    supabase = get_supabase()
    if not should_use_supabase_db(supabase, user_id):
        return {"ok": True, "synced": False}
    try:
        (
            supabase.table("device_tokens")
            .delete()
            .eq("user_id", user_id)
            .eq("token", token.strip()[:4096])
            .execute()
        )
    except Exception as e:
        log.error("Cihaz kaydı silinemedi: %s", type(e).__name__)
        raise HTTPException(status_code=502, detail="Cihaz kaydı şu an silinemedi.")
    return {"ok": True, "synced": True}


# ── Push dağıtımı ────────────────────────────────────────────────────────────────────────────────
# Kullanıcılar sayfa sayfa işlenir. Her sayfa için ayarlar, günün olayları, check-in, konum ve raf verisi
# kullanıcı başına ayrı değil TOPLU sorgularla okunur (sayfa başına ~10 sorgu, kullanıcı başına ~4 yerine).
# Hatırlatıcılar önce hepsi için hesaplanır, sonra gönderimler eşzamanlı yapılır. Süre bütçesi aşılırsa tur
# yarım kalır ve bir sonraki tur kaldığı kullanıcıdan devam eder; sondaki kullanıcılar aç kalmaz.

_PUSH_PAGE_USERS = 100
_PUSH_SEND_CONCURRENCY = 10
_PUSH_WEATHER_CONCURRENCY = 8
# Bütçe aşılmış turun kaldığı yer (bellekte; tek süreç). None: sıradaki tur baştan başlar.
_PUSH_CURSOR: dict = {"after": None}


def _push_clock() -> float:
    """Tur süresi ölçümü (testler sahte saat takar; olay döngüsünün zamanlayıcılarına dokunmaz)."""
    return time.monotonic()


def _push_budget_seconds() -> float:
    """Bir turun en fazla süresi. push-cron isteği 240 sn sonra bırakır; bütçe bunun altında tutulur."""
    try:
        return max(5.0, float(os.getenv("PUSH_DISPATCH_BUDGET_SECONDS") or 200))
    except ValueError:
        return 200.0


def _load_push_page(supabase, after: Optional[str], max_users: int) -> tuple[dict[str, dict], Optional[str], bool]:
    """
    `after`'dan sonraki, push'u açık en fazla `max_users` kullanıcı (kullanıcı kimliğine göre sıralı).
    Döner: ({kullanıcı: {"tokens", "actions", "data_only", "offset": dk}}, son kullanıcı kimliği, liste bitti mi).
    `actions`: bildirim butonlarını işleyebilen cihazlar; `data_only`: başlık/gövdeyi veri içinde alan (Android) cihazlar.
    Her kullanıcının cihazları kimlik sırasında ardışıktır; en son görülen cihaz önce gelir ve saat farkı ondan alınır.
    """
    row_limit = max_users * _PUSH_MAX_TOKENS_PER_USER + 1
    query = (
        supabase.table("device_tokens")
        .select("user_id,token,platform,utc_offset_minutes,actions_supported")
        .eq("push_enabled", True)
    )
    if after:
        query = query.gt("user_id", after)
    rows = query.order("user_id").order("last_seen_at", desc=True).limit(row_limit).execute().data or []

    users: dict[str, dict] = {}
    for row in rows:
        uid, token = str(row.get("user_id") or ""), str(row.get("token") or "")
        if not uid or not token:
            continue
        entry = users.setdefault(
            uid,
            {"tokens": [], "actions": set(), "data_only": set(), "offset": int(row.get("utc_offset_minutes") or 0)},
        )
        if len(entry["tokens"]) < _PUSH_MAX_TOKENS_PER_USER:
            entry["tokens"].append(token)
            if row.get("actions_supported"):
                entry["actions"].add(token)
                if row.get("platform") == "android":
                    entry["data_only"].add(token)

    full = len(rows) >= row_limit
    if full and len(users) > 1:
        # Sayfa dolduysa son kullanıcının cihazları yarım kalmış olabilir: bir sonraki sayfada baştan okunur.
        users.pop(next(reversed(users)))
    more = full
    if len(users) > max_users:
        users = dict(list(users.items())[:max_users])
        more = True
    last_uid = next(reversed(users)) if users else None
    return users, last_uid, not more


def _load_daily_events_bulk(supabase, user_ids: list[str], log_date: str) -> dict[str, list[dict]]:
    """Kullanıcıların `log_date` günündeki olayları (kullanıcı başına eskiden yeniye). Yanıt sınırını aşarsa sayfalanır."""
    out: dict[str, list[dict]] = {uid: [] for uid in user_ids}
    for chunk in _chunks(list(user_ids), _BULK_IN_CHUNK):
        rows = _fetch_paged(lambda c=chunk: (
            supabase.table("daily_events")
            .select("user_id,event_time,type,payload,source")
            .in_("user_id", c)
            .eq("log_date", log_date)
            .order("user_id")
            .order("event_time")
            .order("id")
        ))
        for row in rows:
            out.setdefault(str(row.get("user_id")), []).append(row)
    return out


def _checkins_done_bulk(supabase, user_ids: list[str], log_date: str) -> set[str]:
    """`log_date` gününde check-in yapmış kullanıcılar."""
    done: set[str] = set()
    for chunk in _chunks(list(user_ids), _BULK_IN_CHUNK):
        rows = (
            supabase.table("daily_logs")
            .select("user_id")
            .in_("user_id", chunk)
            .eq("log_date", log_date)
            .execute()
        ).data or []
        done.update(str(r.get("user_id")) for r in rows)
    return done


def _products_out_bulk(supabase, today_by_user: dict[str, date]) -> dict[str, list[dict]]:
    """Rafım: kullanıcıların bitmiş/yenisi alınmamış ürünleri (her biri kendi yerel gününe göre)."""
    user_ids = list(today_by_user)
    since_by_user = {uid: str(today - timedelta(days=SHELF_LOOKBACK_DAYS)) for uid, today in today_by_user.items()}
    since_min = min(since_by_user.values())
    events: dict[str, list[dict]] = {uid: [] for uid in user_ids}
    for chunk in _chunks(user_ids, 25):
        rows = _fetch_paged(lambda c=chunk: (
            supabase.table("daily_events")
            .select("user_id,event_time,log_date,type,payload")
            .in_("user_id", c)
            .in_("type", list(SHELF_EVENT_TYPES))
            .gte("log_date", since_min)
            .order("user_id")
            .order("event_time")
            .order("id")
        ))
        for row in rows:
            uid = str(row.get("user_id"))
            if uid in events and str(row.get("log_date") or "") >= since_by_user[uid]:
                events[uid].append(row)
    return {uid: derive_products_out(evs, today_by_user[uid]) for uid, evs in events.items()}


async def _weather_for_cells(coords: list[tuple[float, float]]) -> dict[tuple, Optional[dict]]:
    """Birkaç koordinat hücresinin havası eşzamanlı alınır (önbellekli); hücre = 0,1° (~11 km)."""
    sem = asyncio.Semaphore(_PUSH_WEATHER_CONCURRENCY)

    async def one(lat: float, lon: float):
        async with sem:
            try:
                return await _weather_for_coords(lat, lon)
            except Exception as e:
                log.error("Push: hava alınamadı: %s", type(e).__name__)
                return None

    results = await asyncio.gather(*(one(lat, lon) for lat, lon in coords))
    return {(round(float(lat), 1), round(float(lon), 1)): w for (lat, lon), w in zip(coords, results)}


def _weather_for_users(supabase, user_ids: list[str]) -> dict[str, dict]:
    """
    Konum izni vermiş kullanıcıların profildeki son koordinatından hava. Aynı hücredeki kullanıcılar tek
    sağlayıcı çağrısını paylaşır. Hata olursa havaya bağlı hatırlatıcılar o tur çıkmaz (varsayılan UV 3).
    """
    try:
        allowed: set[str] = set()
        for chunk in _chunks(list(user_ids), _BULK_IN_CHUNK):
            rows = (
                supabase.table("privacy_preferences")
                .select("user_id")
                .in_("user_id", chunk)
                .eq("location_processing_allowed", True)
                .execute()
            ).data or []
            allowed.update(str(r.get("user_id")) for r in rows)
        coords: dict[str, tuple[float, float]] = {}
        for chunk in _chunks(sorted(allowed), _BULK_IN_CHUNK):
            rows = (
                supabase.table("profiles")
                .select("id,location_lat,location_lon")
                .in_("id", chunk)
                .execute()
            ).data or []
            for row in rows:
                if row.get("location_lat") is not None and row.get("location_lon") is not None:
                    coords[str(row["id"])] = (float(row["location_lat"]), float(row["location_lon"]))
        if not coords:
            return {}
        cells = {(round(lat, 1), round(lon, 1)): (lat, lon) for lat, lon in coords.values()}
        fetched = run_async(_weather_for_cells, list(cells.values()))
    except Exception as e:
        log.error("Push: konum/hava okunamadı (havaya bağlı hatırlatıcılar atlanır): %s", type(e).__name__)
        return {}
    out: dict[str, dict] = {}
    for uid, (lat, lon) in coords.items():
        weather = fetched.get((round(lat, 1), round(lon, 1)))
        if weather:
            out[uid] = dict(weather)
    return out


async def _send_push_jobs(jobs: list[dict]) -> list[dict]:
    """Bir sayfanın bildirimlerini eşzamanlı (sınırlı) gönderir; biri çökse diğerleri etkilenmez."""
    sem = asyncio.Semaphore(_PUSH_SEND_CONCURRENCY)

    async def one(job: dict) -> dict:
        async with sem:
            try:
                return await send_push(
                    job["tokens"],
                    job["title"],
                    job["body"],
                    job["data"],
                    category=job.get("category"),
                    action_tokens=job.get("action_tokens") or frozenset(),
                    data_only_tokens=job.get("data_only_tokens") or frozenset(),
                )
            except Exception as e:
                log.error("Push gönderimi başarısız: %s", type(e).__name__)
                return {"status": "error", "sent": 0, "invalid_tokens": []}

    return list(await asyncio.gather(*(one(j) for j in jobs)))


_PUSH_CLAIM_CHUNK = 200


def _claim_push_slots(supabase, candidates: list[dict]) -> list[dict]:
    """
    Aday hatırlatıcıları gönderim defterine TOPLU yazar ve yalnızca bu çağrıda yeni yazılanları döner.
    `ignore_duplicates` (Prefer: resolution=ignore-duplicates) çakışan satırları atlar ve yalnızca eklenenleri
    geri verir; böylece tek istekte "hangisi daha önce gönderilmiş" öğrenilir (kullanıcı başına bir ekleme yerine).
    Defter yazılamıyorsa tekrarı önleyemeyiz: o grup gönderilmez (susmak, iki kez göndermekten iyidir).
    """
    claimed: set[tuple] = set()
    for chunk in _chunks(candidates, _PUSH_CLAIM_CHUNK):
        rows = [
            {"user_id": c["uid"], "reminder_id": c["reminder_id"], "log_date": c["log_date"], "slot": c["slot"]}
            for c in chunk
        ]
        try:
            written = (
                supabase.table("push_sends")
                .upsert(rows, on_conflict="user_id,reminder_id,log_date,slot", ignore_duplicates=True)
                .execute()
            ).data or []
            claimed.update(
                (str(r.get("user_id")), r.get("reminder_id"), str(r.get("log_date")), r.get("slot")) for r in written
            )
        except Exception as e:
            text = str(e)
            if "42P10" in text or "ON CONFLICT" in text.upper():
                # Veritabanında beklenen benzersiz indeks yok: eski, satır satır yola düşülür (her satır kendi çakışmasını bilir).
                log.warning("push_sends toplu yazımı desteklenmiyor, satır satır yazılacak: %s", type(e).__name__)
                for c in chunk:
                    if _claim_push_slot(supabase, c["uid"], c["reminder_id"], c["log_date"], c["slot"]):
                        claimed.add((c["uid"], c["reminder_id"], c["log_date"], c["slot"]))
            else:
                log.error(
                    "Gönderim defterine yazılamadı (%d hatırlatıcı atlandı): %s", len(chunk), type(e).__name__
                )
    return [c for c in candidates if (c["uid"], c["reminder_id"], c["log_date"], c["slot"]) in claimed]


def _dispatch_page(supabase, users: dict[str, dict], totals: dict) -> None:
    """Bir kullanıcı sayfasının zamanı gelen hatırlatıcılarını hesaplar, deftere yazar ve gönderir."""
    uids = list(users)
    totals["considered"] += len(uids)
    try:
        settings_by_user = _load_reminder_settings_bulk(supabase, uids)
    except Exception as e:
        log.error("Push: ayarlar okunamadı, %d kullanıcı bu turda atlandı: %s", len(uids), type(e).__name__)
        totals["skipped"] += len(uids)
        return

    now_utc = datetime.now(timezone.utc)
    local_now = {uid: now_utc + timedelta(minutes=users[uid]["offset"]) for uid in uids}
    by_date: dict[str, list[str]] = {}
    for uid in uids:
        by_date.setdefault(local_now[uid].date().isoformat(), []).append(uid)

    events_by_user: dict[str, list[dict]] = {}
    checkin_done: set[str] = set()
    skip: set[str] = set()
    for log_date, date_uids in by_date.items():
        try:
            events_by_user.update(_load_daily_events_bulk(supabase, date_uids, log_date))
            checkin_done |= _checkins_done_bulk(supabase, date_uids, log_date)
        except Exception as e:
            # Günün durumunu bilmeden hatırlatmak, yapılmış işi tekrar hatırlatmak demek: bu kullanıcılar atlanır.
            log.error("Push: günün verisi okunamadı, %d kullanıcı atlandı: %s", len(date_uids), type(e).__name__)
            skip.update(date_uids)
    totals["skipped"] += len(skip)
    active = [uid for uid in uids if uid not in skip]
    aggregated = {uid: _aggregate_daily_events(events_by_user.get(uid, [])) for uid in active}

    # Havaya bağlı tek hatırlatıcılar SPF (11–16) ve balsam (12–13): sağlayıcıya yalnızca gün ortasında başvurulur.
    need_weather = [
        uid for uid in active
        if not aggregated[uid].get("weather") and _PUSH_WEATHER_HOURS[0] <= local_now[uid].hour <= _PUSH_WEATHER_HOURS[1]
    ]
    weather_by_user = _weather_for_users(supabase, need_weather) if need_weather else {}

    # Rafım sorgusu yalnızca "yenisini aldın mı" penceresi açıkken yapılır.
    shelf_today = {
        uid: local_now[uid].date()
        for uid in active
        if settings_by_user.get(uid) and _restock_window_open(settings_by_user[uid], local_now[uid])
    }
    products_by_user: dict[str, list[dict]] = {}
    if shelf_today:
        try:
            products_by_user = _products_out_bulk(supabase, shelf_today)
        except Exception as e:
            log.error("Push: Rafım okunamadı (yenisini aldın mı atlanır): %s", type(e).__name__)

    candidates: list[dict] = []
    for uid in active:
        user_settings = settings_by_user.get(uid)
        log_date = local_now[uid].date().isoformat()
        weather = aggregated[uid].get("weather") or weather_by_user.get(uid)
        plan = build_reminders(
            weather or dict(WEATHER_FALLBACK),
            aggregated[uid],
            uid in checkin_done,
            user_settings,
            products_by_user.get(uid),
        )
        for reminder in due_reminders(
            plan,
            local_now[uid].strftime("%H:%M"),
            _PUSH_DISPATCH_TOLERANCE_MINUTES,
            quiet=(user_settings or {}).get("quiet"),
        ):
            candidates.append({
                "uid": uid,
                "reminder_id": reminder["id"],
                "log_date": log_date,
                "slot": reminder["slot"],
                "tokens": users[uid]["tokens"],
                "action_tokens": users[uid]["actions"],
                "data_only_tokens": users[uid]["data_only"],
                "category": reminder.get("category"),
                "title": reminder["title"],
                "body": reminder["body"],
                "data": {
                    "reminder_id": reminder["id"],
                    "log_event": reminder.get("log_event") or "",
                    "log_date": log_date,
                    "slot": reminder["slot"],
                    "open_path": reminder.get("open_path") or reminder_open_path(reminder["id"]),
                    "actions": json.dumps(
                        [{"id": a["id"], "label": a["label"]} for a in reminder.get("actions") or []],
                        ensure_ascii=False,
                    ),
                },
            })

    # Defter toplu yazılır: yalnızca bu turda YENİ yazılanlar gönderilir (başka tur/işçi önceden aldıysa atlanır).
    jobs = _claim_push_slots(supabase, candidates)
    if not jobs:
        return
    invalid: set[str] = set()
    for job, result in zip(jobs, run_async(_send_push_jobs, jobs)):
        sent = int(result.get("sent") or 0)
        totals["notifications"] += sent
        if sent:
            totals["reminders"] += 1
        elif not result.get("invalid_tokens"):
            # FCM'e ulaşılamadı / istek reddedildi: rezervi bırak, pencere bitmeden yeniden denensin.
            _release_push_slot(supabase, job["uid"], job["reminder_id"], job["log_date"], job["slot"])
            totals["failed"] += 1
        invalid.update(result.get("invalid_tokens") or [])
    if invalid:
        totals["invalid"] += _remove_invalid_device_tokens(supabase, sorted(invalid))


@app.post(
    "/push/dispatch",
    response_model=PushDispatchResponse,
    tags=["push"],
    dependencies=[Depends(rate_limit_dependency(LIMIT_PUSH_DISPATCH))],
)
def push_dispatch(request: Request, max_users: int = Query(200, ge=1, le=50000)):
    """
    Zamanı gelen hatırlatıcıları kayıtlı cihazlara gönderir. Sunucu cron'u tarafından 5 dakikada bir
    çağrılmak üzere tasarlandı; her hatırlatıcı gün içinde tek kez gider (`push_sends` defteri).
    `max_users`: bir turda işlenecek en fazla kullanıcı. Tur süre bütçesini (`PUSH_DISPATCH_BUDGET_SECONDS`)
    aşarsa `truncated` döner ve sonraki tur kaldığı kullanıcıdan devam eder.
    """
    _require_push_dispatch_secret(request)
    if not push_configured():
        return PushDispatchResponse(
            users_considered=0,
            reminders_sent=0,
            notifications_sent=0,
            invalid_tokens_removed=0,
            push_configured=False,
        )

    supabase = get_supabase()
    if not supabase:
        raise HTTPException(status_code=503, detail="Supabase bağlantısı yok")

    started = _push_clock()
    budget = _push_budget_seconds()
    totals = {"considered": 0, "skipped": 0, "reminders": 0, "notifications": 0, "invalid": 0, "failed": 0}
    after = _PUSH_CURSOR.get("after")
    truncated = False
    first_page = True
    while True:
        remaining = max_users - totals["considered"]
        if remaining <= 0 or _push_clock() - started > budget:
            truncated = True
            break
        try:
            users, last_uid, exhausted = _load_push_page(supabase, after, min(_PUSH_PAGE_USERS, remaining))
        except Exception as e:
            log.error("Cihaz listesi okunamadı: %s", type(e).__name__)
            if first_page:
                raise HTTPException(status_code=502, detail="Cihaz listesi okunamadı.")
            truncated = True
            break
        first_page = False
        if users:
            _dispatch_page(supabase, users, totals)
        if exhausted:
            after = None
            break
        after = last_uid

    # Tur tamamlandıysa baştan, yarım kaldıysa kaldığı kullanıcıdan devam.
    _PUSH_CURSOR["after"] = after if truncated else None

    summary = PushDispatchResponse(
        users_considered=totals["considered"],
        reminders_sent=totals["reminders"],
        notifications_sent=totals["notifications"],
        invalid_tokens_removed=totals["invalid"],
        push_configured=True,
        deliveries_failed=totals["failed"],
        users_skipped=totals["skipped"],
        truncated=truncated,
    )
    # clear() kullanılmaz: /health başka iş parçacığında okurken sözlük bir an boş görünmesin (anahtarlar her turda aynı).
    _PUSH_LAST_RUN.update(summary.model_dump(), at=_utc_now_iso())
    log.info(
        "Push dağıtımı: kullanıcı=%d hatırlatıcı=%d bildirim=%d geçersiz_token=%d başarısız=%d atlanan=%d süre=%.1fsn",
        summary.users_considered, summary.reminders_sent, summary.notifications_sent,
        summary.invalid_tokens_removed, summary.deliveries_failed, summary.users_skipped,
        _push_clock() - started,
    )
    if truncated:
        log.warning("Push dağıtımı yarım kaldı (süre bütçesi ya da max_users); sonraki tur kaldığı yerden devam eder.")
    return summary


@app.get("/push/actions", tags=["push"])
async def push_actions():
    """
    Bildirim kategorileri ve butonları. iOS kategorileri bildirim gelmeden önce
    kaydedilmelidir; uygulama bu listeyi açılışta çeker.
    """
    return {
        "categories": [
            {
                "id": reminder_id,
                "category": reminder_category(reminder_id),
                "actions": [{"id": a["id"], "label": a["label"]} for a in actions],
                "open_path": reminder_open_path(reminder_id),
            }
            for reminder_id, actions in REMINDER_ACTIONS.items()
        ],
    }


def _push_log_date(value: Optional[str]) -> Optional[str]:
    """Bildirimdeki yerel gün; bugünden en fazla bir gün sapabilir."""
    if not value:
        return None
    try:
        parsed = date.fromisoformat(value)
    except ValueError:
        return None
    today = datetime.now(timezone.utc).date()
    return parsed.isoformat() if abs((parsed - today).days) <= 1 else None


@app.post(
    "/push/respond",
    response_model=PushRespondResponse,
    tags=["push"],
    dependencies=[Depends(rate_limit_dependency(LIMIT_PUSH_RESPOND))],
)
def push_respond(request: Request, req: PushRespondRequest):
    """
    Bildirim butonuna verilen cevabı günlük kayda yazar. Hangi olayın hangi
    yükle yazılacağını sunucu belirler; aynı bildirime ikinci dokunuş sayılmaz.
    """
    enforce_supabase_user(request, req.user_id)
    action = resolve_reminder_action(req.reminder_id, req.action_id)
    if not action:
        raise HTTPException(status_code=422, detail="Bu hatırlatıcı için böyle bir cevap yok.")

    log_date = _push_log_date(req.log_date) or _safe_date_from_timestamp(req.timestamp)
    client_event_id = (req.client_event_id or "").strip()[:64] or None
    if not client_event_id and req.slot:
        client_event_id = f"push:{req.reminder_id}:{log_date}:{req.slot}"[:64]

    log_date, aggregated = _store_daily_event(
        req.user_id,
        action["log_event"],
        action["payload"],
        timestamp=req.timestamp,
        source="push",
        client_event_id=client_event_id,
        log_date=log_date,
    )

    supabase = get_supabase()
    if req.slot and should_use_supabase_db(supabase, req.user_id):
        # Yerel bildirime gelen cevap da deftere girer; sunucu aynı pencereye
        # ayrıca push göndermez.
        try:
            supabase.table("push_sends").upsert({
                "user_id": req.user_id,
                "reminder_id": req.reminder_id,
                "log_date": log_date,
                "slot": req.slot,
                "action_id": req.action_id,
                "responded_at": _utc_now_iso(),
            }, on_conflict="user_id,reminder_id,log_date,slot").execute()
        except Exception as e:
            log.error("Bildirim cevabı deftere yazılamadı: %s", type(e).__name__)

    return PushRespondResponse(
        log_date=log_date,
        log_event=action["log_event"],
        aggregated=aggregated,
    )


@app.post(
    "/maintenance/purge",
    tags=["maintenance"],
    dependencies=[Depends(rate_limit_dependency(LIMIT_PUSH_DISPATCH))],
)
def maintenance_purge(request: Request, only_if_no_cron: bool = Query(True)):
    """
    Süresi dolan verileri siler (`purge_expired_rebi_data()`, süreler docs/DATA_RETENTION.md'de). Normalde Supabase
    pg_cron günde bir çalıştırır; bu uç, pg_cron yoksa push-cron servisinin (RETENTION_PURGE_DAILY=1) çağıracağı güvenlik
    ağıdır. `only_if_no_cron` (varsayılan): pg_cron işi aktifse hiçbir şey yapmaz. Dağıtım anahtarıyla korunur.
    """
    _require_push_dispatch_secret(request)
    supabase = get_supabase()
    if not supabase:
        raise HTTPException(status_code=503, detail="Supabase bağlantısı yok")
    if only_if_no_cron:
        try:
            if get_integrity().get("retention") == "pg_cron":
                return {"ok": True, "skipped": "pg_cron_active"}
        except Exception as e:
            log.warning("pg_cron durumu okunamadı, temizlik yine de çalışacak: %s", type(e).__name__)
    try:
        deleted = supabase.rpc("purge_expired_rebi_data").execute().data
    except Exception as e:
        log.error("Retention temizliği başarısız: %s", type(e).__name__)
        raise HTTPException(status_code=502, detail="Temizlik şu an çalıştırılamadı.")
    log.info("Retention temizliği tamam: %s", deleted)
    return {"ok": True, "deleted": deleted}


@app.post(
    "/generate_routine",
    response_model=RoutineResponse,
    tags=["routine"],
    dependencies=[Depends(rate_limit_dependency(LIMIT_GENERATE_ROUTINE))],
)
def generate_routine(request: Request, req: AssessmentRequest):
    """
    Ana rutin üretme endpoint'i.
    1. Hava durumu (1 HTTP call)
    2. Flow Engine (0 token) — içeride bir kez kesinlik (kırmızı çizgi) uygulanır
    3. Knowledge Router (0 token)
    4. AI Polish (~400 token) — yalnızca metin cilası; kuralları zayıflatamaz
    5. Kesinlik kuralları tekrar (AI sonrası zorunlu) + detay sanitize
    """
    enforce_supabase_user(request, req.user_id)
    _enforce_ai_user_limit(req.user_id)
    _require_privacy_permission(req.user_id, "ai")
    if req.location_lat is not None or req.location_lon is not None:
        _require_privacy_permission(req.user_id, "location")
    log.info("Rutin isteği: concern=%s, age=%d, severity=%d", req.concern, req.age, req.severity_score)

    # ADIM 1: Hava Durumu
    weather_data = {"humidity": 50, "uv_index": 3, "temperature": 20, "description": "N/A"}
    if req.location_lat and req.location_lon:
        weather_data = run_async(_weather_cached, req.location_lat, req.location_lon)

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
        shaving_frequency=req.shaving_frequency,
        shaving_after=req.shaving_after,
        concerns=req.concerns,
        triggers=req.triggers,
        past_treatments=req.past_treatments,
        expectations=req.expectations,
        nutrition=req.nutrition,
    )

    routine_items = flow_result["routine_items"]
    query_plan = flow_result["query_plan"]
    context_summary = flow_result["context_summary"]

    log.info("Flow Engine: %d rutin öğesi, %d sorgu planı", len(routine_items), len(query_plan))

    # ADIM 3: Knowledge Router (0 TOKEN)
    knowledge_result = run_async(execute_query_plan, query_plan)
    knowledge_context = run_async(get_targeted_context, knowledge_result, max_chars=2000)

    # ADIM 3b: Kanonik dolap — şikâyet için kanıta dayalı içerik zinciri + literatür.
    # Rutin adımlarını değiştirmez; polish'in bilimsel bağlamını güçlendirir.
    try:
        from knowledge.cabinet_router import format_routine_expert_block

        expert_block, _expert_meta = format_routine_expert_block(req.concern)
        if expert_block:
            knowledge_context = (expert_block + "\n\n" + (knowledge_context or "")).strip()
            log.info(
                "Rutin uzman bloğu eklendi: concern=%s ing=%d",
                req.concern,
                len(_expert_meta.get("ingredient_ids") or []),
            )
    except Exception as e:
        log.warning("Rutin uzman bloğu atlandı: %s", e)

    # Rutinin altına tek kısa opsiyonel bitkisel satır (varsa PDF verisiyle beslenir)
    routine_items = list(routine_items)
    routine_items.extend(_optional_natural_examples_routine_item(req.concern, knowledge_result=knowledge_result))

    # ADIM 4: AI Polish (~400 TOKEN)
    accept_lang = (request.headers.get("accept-language") or "").strip()
    target_lang = _primary_lang_from_header(accept_lang)
    polished_routine, ai_polish_note = run_async(polish_routine_with_ai,
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
    polished_routine = run_async(translate_routine_items, polished_routine, target_lang=target_lang)

    # Kanonik kimlik: motorun yazdığı action cümlelerinden id bas, sonra yedek etiketle.
    try:
        from knowledge.routine_identity import stamp_canonical_ids, build_cabinet_active_plan
        from knowledge.cabinet_router import tag_items_with_canonical_ids
        from flow_engine import avoided_families_from_tolerance, merge_actives_tolerance

        stamp_canonical_ids(polished_routine)
        _n_tagged = tag_items_with_canonical_ids(polished_routine)
        if _n_tagged:
            log.info("Kanonik id etiketleme: %d rutin öğesi", _n_tagged)
        _avoided = avoided_families_from_tolerance(
            merge_actives_tolerance(req.actives_tolerance, req.actives_unused)
        )
        flow_result["active_plan"] = build_cabinet_active_plan(
            req.concern,
            polished_routine,
            is_pregnant=bool(req.is_pregnant),
            avoided_families=_avoided,
        )
    except Exception as e:
        log.warning("Kanonik id / aktif plan atlandı: %s", e)

    # Faz 3 (gölge): motor seçimini kanonik zincirle karşılaştır. İçeriği
    # DEĞİŞTİRMEZ; sadece hangi önerilen aktiflerin rutinde yer aldığını /
    # eksik kaldığını raporlar (canlıya almadan önceki doğrulama katmanı).
    chain_coverage = None
    try:
        from knowledge.cabinet_router import chain_actives_for_concern

        _chain = [a for a in chain_actives_for_concern(req.concern) if a.get("effect_status") == "supports"]
        if _chain:
            _routine_ids = {
                str(cid)
                for it in polished_routine
                for cid in (it.get("canonical_ingredient_ids") or [])
            }
            _covered = [a["name_tr"] for a in _chain if a["ingredient_id"] in _routine_ids]
            _missing = [a["name_tr"] for a in _chain if a["ingredient_id"] not in _routine_ids]
            chain_coverage = {
                "concern": req.concern,
                "recommended_total": len(_chain),
                "covered": _covered,
                "missing": _missing,
            }
            if _missing:
                log.info(
                    "Rutin zincir kapsaması: %d/%d karşılandı; eksik: %s",
                    len(_covered),
                    len(_chain),
                    ", ".join(_missing[:5]),
                )
    except Exception as e:
        log.warning("Zincir kapsama raporu atlandı: %s", e)

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
                    "shaving_frequency": req.shaving_frequency,
                    "shaving_after": req.shaving_after,
                    "concerns": req.concerns or [],
                    "triggers": req.triggers or [],
                    "past_treatments": req.past_treatments or [],
                    "expectations": req.expectations or [],
                    "nutrition": req.nutrition or {},
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
        log.info("Demo kullanıcı: profil/assessment/rutin DB yazımı atlandı")

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
            "chain_coverage": chain_coverage,
            "cabinet_enrichment": flow_result.get("cabinet_enrichment"),
            "multi_concern": flow_result.get("multi_concern"),
            "token_estimate": "~400 (sadece AI polish)",
        },
    )


_CHAT_CONTENT_MAX_CHARS = 8000
_CHAT_HISTORY_MAX_ROWS = 200
_CHAT_IMPORT_MAX_MESSAGES = 60


def _persist_chat_turn(
    user_id: str,
    surface: str,
    user_message: str,
    reply: str,
    concern: Optional[str] = None,
) -> None:
    """Sohbet turunu sunucuda sakla; web ve mobil aynı geçmişi görür."""
    supabase = get_supabase()
    if not should_use_supabase_db(supabase, user_id):
        return
    rows = []
    for role, content in (("user", user_message), ("assistant", reply)):
        text = str(content or "").strip()
        if text:
            rows.append({
                "user_id": user_id,
                "surface": surface,
                "role": role,
                "content": text[:_CHAT_CONTENT_MAX_CHARS],
                "concern": concern,
            })
    if len(rows) < 2:
        # Yarım tur (boş mesaj veya boş yanıt) geçmişe yazılmaz.
        return
    try:
        supabase.table("chat_history").insert(rows).execute()
    except Exception as e:
        log.error("Sohbet geçmişi yazılamadı: %s", type(e).__name__)


@app.get(
    "/chat/history",
    response_model=ChatHistoryResponse,
    tags=["chat"],
    dependencies=[Depends(rate_limit_dependency(LIMIT_CHAT_HISTORY))],
)
def chat_history_get(
    request: Request,
    user_id: str = Query(..., min_length=1),
    limit: int = Query(50, ge=1, le=_CHAT_HISTORY_MAX_ROWS),
    after_seq: Optional[int] = Query(None, ge=0),
    surface: Optional[Literal["general", "concern", "assessment"]] = None,
):
    """
    Sunucudaki sohbet geçmişi (eskiden yeniye). `after_seq` verilirse yalnızca
    o imleçten sonraki mesajlar döner; mobil açılışta tüm geçmişi tekrar çekmez.
    """
    enforce_supabase_user(request, user_id)
    supabase = get_supabase()
    if not should_use_supabase_db(supabase, user_id):
        return ChatHistoryResponse(user_id=user_id, messages=[], cursor=None, synced=False)

    try:
        q = (
            supabase.table("chat_history")
            .select("seq,role,content,surface,created_at")
            .eq("user_id", user_id)
        )
        if surface:
            q = q.eq("surface", surface)
        if after_seq is not None:
            rows = q.gt("seq", after_seq).order("seq", desc=False).limit(limit).execute().data or []
        else:
            # Son N mesajı al, sonra kronolojik sıraya çevir.
            rows = list(reversed(q.order("seq", desc=True).limit(limit).execute().data or []))
    except Exception as e:
        log.error("Sohbet geçmişi okunamadı: %s", type(e).__name__)
        raise HTTPException(status_code=502, detail="Sohbet geçmişi şu an okunamadı.")

    messages = [
        ChatHistoryMessage(
            seq=int(r.get("seq") or 0),
            role=r.get("role") or "assistant",
            content=r.get("content") or "",
            surface=r.get("surface") or "general",
            created_at=(str(r["created_at"]) if r.get("created_at") else None),
        )
        for r in rows
    ]
    return ChatHistoryResponse(
        user_id=user_id,
        messages=messages,
        cursor=(messages[-1].seq if messages else after_seq),
        synced=True,
    )


@app.post(
    "/chat/history/import",
    response_model=ChatHistoryImportResponse,
    tags=["chat"],
    dependencies=[Depends(rate_limit_dependency(LIMIT_CHAT_HISTORY_IMPORT))],
)
def chat_history_import(request: Request, req: ChatHistoryImportRequest):
    """
    Sunucu öncesi dönemden kalan yerel sohbeti bir kez yukarı taşır. Sunucuda
    bu yüzey için kayıt varsa içe aktarma atlanır; kopya geçmiş oluşmaz.
    """
    enforce_supabase_user(request, req.user_id)
    supabase = get_supabase()
    if not should_use_supabase_db(supabase, req.user_id):
        return ChatHistoryImportResponse(imported=0, skipped=True)

    try:
        existing = (
            supabase.table("chat_history")
            .select("seq")
            .eq("user_id", req.user_id)
            .eq("surface", req.surface)
            .limit(1)
            .execute()
        )
    except Exception as e:
        log.error("Sohbet geçmişi kontrol edilemedi: %s", type(e).__name__)
        raise HTTPException(status_code=502, detail="Sohbet geçmişi şu an okunamadı.")
    if existing.data:
        return ChatHistoryImportResponse(
            imported=0, skipped=True, cursor=_chat_last_seq(supabase, req.user_id)
        )

    rows = [
        {
            "user_id": req.user_id,
            "surface": req.surface,
            "role": m.role,
            "content": m.content.strip()[:_CHAT_CONTENT_MAX_CHARS],
        }
        for m in req.messages
        if m.content.strip()
    ]
    if not rows:
        return ChatHistoryImportResponse(imported=0, skipped=True)
    try:
        supabase.table("chat_history").insert(rows).execute()
    except Exception as e:
        log.error("Sohbet geçmişi aktarılamadı: %s", type(e).__name__)
        raise HTTPException(status_code=502, detail="Sohbet geçmişi şu an aktarılamadı.")
    return ChatHistoryImportResponse(
        imported=len(rows), skipped=False, cursor=_chat_last_seq(supabase, req.user_id)
    )


@app.delete(
    "/chat/history",
    tags=["chat"],
    dependencies=[Depends(rate_limit_dependency(LIMIT_CHAT_HISTORY_CLEAR))],
)
def chat_history_clear(request: Request, user_id: str = Query(..., min_length=1)):
    """Sohbeti temizle: geçmiş her iki platformdan da silinir."""
    enforce_supabase_user(request, user_id)
    supabase = get_supabase()
    if not should_use_supabase_db(supabase, user_id):
        return {"ok": True, "synced": False}
    try:
        supabase.table("chat_history").delete().eq("user_id", user_id).execute()
    except Exception as e:
        log.error("Sohbet geçmişi silinemedi: %s", type(e).__name__)
        raise HTTPException(status_code=502, detail="Sohbet geçmişi şu an silinemedi.")
    return {"ok": True, "synced": True}


@app.post(
    "/chat",
    response_model=ChatResponse,
    tags=["chat"],
    dependencies=[Depends(rate_limit_dependency(LIMIT_CHAT))],
)
def chat(request: Request, req: ChatRequest):
    """
    Interaktif sohbet endpoint'i.
    Kullanıcı sorusu -> Knowledge Base'den bağlam -> Gemini cevap
    Token: ~200-400/mesaj
    """
    enforce_supabase_user(request, req.user_id)
    _enforce_ai_user_limit(req.user_id)
    _require_privacy_permission(req.user_id, "ai")
    log.info("Chat isteği: concern=%s message_chars=%d", req.concern, len(req.message or ""))

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

    knowledge_result = run_async(execute_query_plan, query_plan)
    knowledge_context = run_async(get_targeted_context, knowledge_result, max_chars=2000)

    reply = run_async(chat_with_knowledge,
        user_message=req.message,
        knowledge_context=knowledge_context,
        history=req.history,
        user_id=req.user_id,
        folder_slug="data-pdfs",
        accept_lang=_primary_lang_from_header(request.headers.get("accept-language") or "tr"),
    )

    _persist_chat_turn(req.user_id, "concern", req.message, reply, concern=concern)

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
def chat_assessment(request: Request, req: AssessmentChatRequest):
    """
    AI-driven cilt değerlendirmesi sohbeti.
    Temel bilgiler form ile toplanır, kalan değerlendirmeyi AI konuşarak yapar.
    AI birkaç soru sorar, yeterli bilgi topladığında is_complete=True döndürür.
    """
    enforce_supabase_user(request, req.user_id)
    _enforce_ai_user_limit(req.user_id)
    _require_privacy_permission(req.user_id, "ai")
    log.info("Assessment chat isteği: message_chars=%d", len(req.message or ""))

    profile = req.user_profile or {}
    is_free = profile.get("mode") == "free_chat"
    lim = free_chat_limit()
    plus = user_is_rebi_plus(request, req.user_id)
    plus_chat_capped = plus and user_plus_chat_is_monthly_capped(request, req.user_id)
    plim = plus_chat_monthly_cap()

    # Hak, model çağrısından önce atomik olarak alınır (paralel isteklerle kota aşılamaz); başarısız tur iade edilir.
    hold = None
    if is_free and jwt_auth_enabled():
        reservation = reserve_chat_turn(req.user_id, plus=plus, plus_capped=plus_chat_capped)
        if reservation.exceeded == "free_daily":
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
        if reservation.exceeded == "plus_monthly":
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
        hold = reservation.hold

    from rag_service import assessment_chat
    with hold or nullcontext():  # istisna çıkarsa hak otomatik iade edilir
        result = run_async(assessment_chat,
            user_message=req.message,
            history=req.history,
            user_profile=profile,
            user_id=req.user_id,
        )
        if hold is not None and _reply_looks_failed(result.get("reply"), _ASSESSMENT_ERROR_PREFIXES):
            hold.release()

    remaining: Optional[int] = None
    usage_kind: Optional[str] = None
    usage_remaining: Optional[int] = None
    usage_limit: Optional[int] = None
    if is_free and jwt_auth_enabled():
        if not plus:
            remaining = free_chat_remaining(req.user_id)
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


def _generate_chat_general_reply(request: Request, req: ChatGeneralRequest) -> tuple[str, dict]:
    """
    Profil ipuçlarını toplar ve Rebi Chat yanıtını üretir. Döner: (yanıt, kanıt paketi).
    Kota rezervasyonu çağıranda tutulur: buradan istisna çıkarsa hak iade edilir.
    """
    from rag_service import chat_general as rebi_chat_general

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
                    if ld.get("shaving_after"):
                        profile_hint["shaving_after"] = ld.get("shaving_after")

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

    today_summary = run_async(_chat_today_summary, get_supabase(), req.user_id, req.utc_offset_minutes)
    if today_summary:
        profile_hint["today_summary"] = today_summary

    # chat_general kanıt paketini kendi kurar; metaveriyi yeniden hesaplamak DB + embedding maliyetini ikiye katlardı.
    ev_holder: dict = {}
    reply = run_async(rebi_chat_general,
        user_message=req.message,
        history=req.history,
        user_id=req.user_id,
        profile_hint=profile_hint,
        accept_lang=_primary_lang_from_header(request.headers.get("accept-language") or "tr"),
        evidence_out=ev_holder,
    )
    return reply, ev_holder


@app.post(
    "/chat_general",
    response_model=ChatGeneralResponse,
    tags=["chat"],
    dependencies=[Depends(rate_limit_dependency(LIMIT_CHAT_ASSESSMENT))],
)
def chat_general_endpoint(request: Request, req: ChatGeneralRequest):
    """
    Rebi Chat (genel): rutin motorundan ayrı, serbest soru-cevap.
    Kota/Plus mantığı chat_assessment ile aynıdır.
    """
    enforce_supabase_user(request, req.user_id)
    _enforce_ai_user_limit(req.user_id)
    _require_privacy_permission(req.user_id, "ai")
    lim = free_chat_limit()
    plus = user_is_rebi_plus(request, req.user_id)
    plus_chat_capped = plus and user_plus_chat_is_monthly_capped(request, req.user_id)
    plim = plus_chat_monthly_cap()

    # Hak, model çağrısından önce atomik olarak alınır (paralel isteklerle kota aşılamaz); başarısız tur iade edilir.
    hold = None
    if jwt_auth_enabled():
        reservation = reserve_chat_turn(req.user_id, plus=plus, plus_capped=plus_chat_capped)
        if reservation.exceeded == "free_daily":
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
        if reservation.exceeded == "plus_monthly":
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
        hold = reservation.hold

    from rag_service import _EVIDENCE_OK_THRESHOLD as _EV_OK

    with hold or nullcontext():  # istisna çıkarsa hak otomatik iade edilir
        reply, ev_holder = _generate_chat_general_reply(request, req)
        r = (reply or "").strip()
        err_like = _reply_looks_failed(r, _GENERAL_ERROR_PREFIXES)
        if hold is not None and err_like:
            hold.release()

    # Evidence metadata (best-effort; does not affect the reply). Kanıt aranmadıysa (sınır yanıtı vb.) boş kalır.
    evidence_used = None
    evidence_score = None
    evidence_sources = None
    if ev_holder:
        try:
            evidence_score = float(ev_holder.get("score") or 0.0)
            evidence_sources = ev_holder.get("sources") or []
            evidence_used = bool(evidence_score >= float(_EV_OK))
        except Exception:
            evidence_used, evidence_score, evidence_sources = None, None, None

    if not err_like:
        _persist_chat_turn(req.user_id, "general", req.message, r)

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
def chat_usage(request: Request, user_id: str = Query(..., min_length=1)):
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
def translate_routine_items_endpoint(request: Request, req: TranslateRoutineItemsRequest):
    """
    Frontend can store routines in DB/local snapshot in Turkish.
    This endpoint adds `action_localized` and `detail_localized` for the selected UI language.
    """
    enforce_supabase_user(request, req.user_id)
    _enforce_ai_user_limit(req.user_id)
    _require_privacy_permission(req.user_id, "ai")
    from rag_service import translate_routine_items, _primary_lang_from_header

    target_lang = _primary_lang_from_header(request.headers.get("accept-language", "") or "")
    items = run_async(translate_routine_items, req.routine_items or [], target_lang=target_lang)
    return {"routine_items": items}


@app.get(
    "/daily_checkin/status",
    tags=["checkin"],
    dependencies=[Depends(rate_limit_dependency(LIMIT_DAILY_CHECKIN_STATUS))],
)
def daily_checkin_status(
    request: Request,
    user_id: str,
    utc_offset_minutes: Optional[int] = Query(None, ge=-840, le=840),
):
    """Bugün için check-in yapılmış mı (aynı gün tekrarını önlemek için)."""
    enforce_supabase_user(request, user_id)
    supabase = get_supabase()
    today = str(_local_today(utc_offset_minutes))
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
def daily_checkin(request: Request, req: DailyCheckinRequest):
    """
    Günlük check-in: 3-5 hızlı soru ile cilt durumu takibi.
    Akış: Check-in → daily_logs kaydet → hava durumu → risk skoru → AI adaptasyon → rutin güncelle
    """
    enforce_supabase_user(request, req.user_id)
    _enforce_ai_user_limit(req.user_id)
    _require_privacy_permission(req.user_id, "ai")
    if req.location_lat is not None or req.location_lon is not None:
        _require_privacy_permission(req.user_id, "location")
    log.info("Daily checkin isteği alındı")

    supabase = get_supabase()
    today_str = str(_local_today(req.utc_offset_minutes))

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
        weather_data = run_async(_weather_cached, req.location_lat, req.location_lon)

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
            ai_note = run_async(adapt_routine_with_ai,
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

            log.info("Daily log kaydedildi: changes=%d", len(adaptation["changes"]))
        except Exception as e:
            log.error("Daily log kayıt hatası: %s", e)
    elif is_demo_user_id(req.user_id):
        demo_checkin_mark(req.user_id, today_str)
        log.info("Demo check-in: DB atlandı, bellekte bugün işaretlendi")

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
_LEGAL_CONSENT_VERSION = "v2"


def _photo_content_matches_extension(contents: bytes, ext: str) -> bool:
    """Basit magic-byte kontrolü; istemcinin MIME/uzantı beyanına güvenme."""
    if ext in {"jpg", "jpeg"}:
        return contents.startswith(b"\xff\xd8\xff")
    if ext == "png":
        return contents.startswith(b"\x89PNG\r\n\x1a\n")
    if ext == "webp":
        return (
            len(contents) >= 12
            and contents[:4] == b"RIFF"
            and contents[8:12] == b"WEBP"
        )
    if ext in {"heic", "heif"}:
        return len(contents) >= 12 and contents[4:8] == b"ftyp"
    return False


def _enforce_ingest_user_limit(user_id: str) -> None:
    """Olay yazımında kullanıcı başına sınır. Demo kimlikleri ortaktır: atlanır."""
    if is_demo_user_id(user_id):
        return
    enforce_ingest_user_limit(user_id)


def _enforce_ai_user_limit(user_id: str) -> None:
    """Yapay zekâ uçlarında kullanıcı başına dakikalık/saatlik bütçe (IP'den bağımsız). Demo kimlikleri ortaktır: atlanır."""
    if is_demo_user_id(user_id):
        return
    enforce_ai_user_limit(user_id)


def _require_privacy_permission(user_id: str, permission: str) -> None:
    """Enforce immutable v2 consent before external/sensitive processing."""
    if insecure_auth_allowed() and is_demo_user_id(user_id):
        return
    fields = {
        "ai": "ai_processing_allowed",
        "location": "location_processing_allowed",
        "photo": "photo_processing_allowed",
    }
    field = fields.get(permission)
    if not field:
        raise RuntimeError(f"Unknown privacy permission: {permission}")
    supabase = get_supabase()
    if not supabase:
        raise HTTPException(status_code=503, detail="Rıza doğrulama servisi kullanılamıyor.")
    try:
        result = (
            supabase.table("privacy_preferences")
            .select(field)
            .eq("user_id", user_id)
            .eq(field, True)
            .limit(1)
            .execute()
        )
    except Exception as e:
        log.error("Rıza izni doğrulanamadı: permission=%s error=%s", permission, type(e).__name__)
        raise HTTPException(status_code=503, detail="Rıza izni doğrulanamadı.")
    if not result.data:
        labels = {
            "ai": "AI işleme",
            "location": "konum işleme",
            "photo": "cilt fotoğrafı işleme",
        }
        raise HTTPException(
            status_code=403,
            detail=f"{labels[permission]} izni gerekli.",
        )


def _delete_skin_photos_for_user(supabase, user_id: str) -> None:
    """skin-photos bucket içinde {user_id}/ altındaki dosyaları siler (CASCADE storage’da yok)."""
    prefix = (user_id or "").strip()
    if not prefix or ".." in prefix or any(c in prefix for c in "/\\"):
        raise HTTPException(status_code=400, detail="Geçersiz kullanıcı kimliği")
    try:
        items = supabase.storage.from_("skin-photos").list(prefix)
    except Exception as e:
        log.error("skin-photos list başarısız: %s", type(e).__name__)
        raise HTTPException(
            status_code=502,
            detail="Cilt fotoğrafları doğrulanamadığı için hesap silme durduruldu.",
        )
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
        log.info("skin-photos silindi: count=%d", len(paths))
    except Exception as e:
        log.error("skin-photos remove başarısız: %s", type(e).__name__)
        raise HTTPException(
            status_code=502,
            detail="Cilt fotoğrafları silinemediği için hesap silme durduruldu.",
        )


# PostgREST "tablo yok" (şema önbelleğinde bulunamadı) ve Postgres "undefined_table" kodları.
_MISSING_TABLE_CODES = frozenset({"PGRST205", "42P01"})


def _is_missing_table_error(exc: Exception) -> bool:
    """Tablo henüz oluşturulmamış mı (migration uygulanmadan yayına çıkıldı)?"""
    if str(getattr(exc, "code", "") or "") in _MISSING_TABLE_CODES:
        return True
    text = str(exc).lower()
    return "could not find the table" in text or ("relation" in text and "does not exist" in text)


def _delete_user_application_data(supabase, user_id: str) -> None:
    """
    Cascade yapılandırmasından bağımsız olarak kişisel veri satırlarını sil.
    Tablo hiç yoksa silinecek veri de yoktur: bu hesap silmeyi durdurmaz (yeni bir tablo
    migration'ından önce yayına çıkan sürüm hesap silmeyi bozmasın). Diğer her hata durdurur.
    """
    targets = (
        ("privacy_preferences", "user_id"),
        ("legal_consents", "user_id"),
        ("device_tokens", "user_id"),
        ("push_sends", "user_id"),
        ("reminder_settings", "user_id"),
        ("chat_history", "user_id"),
        ("daily_events", "user_id"),
        ("daily_logs", "user_id"),
        ("routines", "user_id"),
        ("assessments", "user_id"),
        ("profiles", "id"),
    )
    for table, column in targets:
        try:
            supabase.table(table).delete().eq(column, user_id).execute()
        except Exception as e:
            if _is_missing_table_error(e):
                log.warning("Hesap veri silme: tablo yok, atlandı: table=%s", table)
                continue
            log.error("Hesap veri silme başarısız: table=%s error=%s", table, type(e).__name__)
            raise HTTPException(
                status_code=502,
                detail="Uygulama verilerinin tamamı silinemedi; hesap silme durduruldu.",
            )


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
        log.error("GoTrue admin delete_user başarısız: status=%s", r.status_code)
        raise HTTPException(
            status_code=502,
            detail="Kimlik sağlayıcı hesabı silinemedi. Daha sonra tekrar deneyin veya destek ile iletişime geçin.",
        )


@app.get("/legal-consent/status", tags=["account"])
def legal_consent_status(
    request: Request,
    user_id: str,
    document_version: str = _LEGAL_CONSENT_VERSION,
):
    enforce_supabase_user(request, user_id)
    if document_version != _LEGAL_CONSENT_VERSION:
        return {"accepted": False, "document_version": _LEGAL_CONSENT_VERSION}
    supabase = get_supabase()
    if not supabase:
        raise HTTPException(status_code=500, detail="Supabase bağlantısı yok")
    try:
        result = (
            supabase.table("legal_consents")
            .select(
                "accepted_at,ai_processing_accepted,"
                "location_processing_accepted,photo_processing_accepted"
            )
            .eq("user_id", user_id)
            .eq("document_version", document_version)
            .limit(1)
            .execute()
        )
    except Exception as e:
        log.error("Rıza durumu okunamadı: error=%s", type(e).__name__)
        raise HTTPException(status_code=502, detail="Rıza kaydı doğrulanamadı.")
    row = result.data[0] if result.data else None
    return {
        "accepted": bool(row),
        "document_version": document_version,
        "accepted_at": row.get("accepted_at") if row else None,
        "ai_processing_accepted": bool(row and row.get("ai_processing_accepted")),
        "location_processing_accepted": bool(row and row.get("location_processing_accepted")),
        "photo_processing_accepted": bool(row and row.get("photo_processing_accepted")),
    }


@app.post("/legal-consent/accept", tags=["account"])
def accept_legal_consent(request: Request, req: LegalConsentAcceptRequest):
    enforce_supabase_user(request, req.user_id)
    if (
        req.document_version != _LEGAL_CONSENT_VERSION
        or not req.kvkk_accepted
        or not req.explicit_consent_accepted
        or not req.ai_processing_accepted
    ):
        raise HTTPException(status_code=400, detail="Geçerli KVKK ve açık rıza onayı gerekli.")
    supabase = get_supabase()
    if not supabase:
        raise HTTPException(status_code=500, detail="Supabase bağlantısı yok")
    try:
        existing = (
            supabase.table("legal_consents")
            .select("accepted_at")
            .eq("user_id", req.user_id)
            .eq("document_version", req.document_version)
            .limit(1)
            .execute()
        )
        already_recorded = bool(existing.data)
        if already_recorded:
            accepted_at = existing.data[0].get("accepted_at")
        else:
            inserted = supabase.table("legal_consents").insert({
                "user_id": req.user_id,
                "document_version": req.document_version,
                "kvkk_accepted": True,
                "explicit_consent_accepted": True,
                "ai_processing_accepted": True,
                "location_processing_accepted": bool(req.location_processing_accepted),
                "photo_processing_accepted": bool(req.photo_processing_accepted),
            }).execute()
            row = inserted.data[0] if inserted.data else {}
            accepted_at = row.get("accepted_at")
        supabase.table("privacy_preferences").upsert({
            "user_id": req.user_id,
            "ai_processing_allowed": True,
            "location_processing_allowed": bool(req.location_processing_accepted),
            "photo_processing_allowed": bool(req.photo_processing_accepted),
            "updated_at": datetime.now(timezone.utc).isoformat(),
        }).execute()
    except Exception as e:
        log.error("Rıza kaydı yazılamadı: error=%s", type(e).__name__)
        raise HTTPException(status_code=502, detail="Rıza kaydı güvenli biçimde oluşturulamadı.")
    return {
        "ok": True,
        "document_version": req.document_version,
        "accepted_at": accepted_at,
        "already_recorded": already_recorded,
    }


@app.get("/privacy-preferences", tags=["account"])
def privacy_preferences_get(request: Request, user_id: str):
    enforce_supabase_user(request, user_id)
    supabase = get_supabase()
    if not supabase:
        raise HTTPException(status_code=500, detail="Supabase bağlantısı yok")
    try:
        result = (
            supabase.table("privacy_preferences")
            .select(
                "ai_processing_allowed,location_processing_allowed,"
                "photo_processing_allowed,updated_at"
            )
            .eq("user_id", user_id)
            .limit(1)
            .execute()
        )
    except Exception as e:
        log.error("Gizlilik tercihleri okunamadı: %s", type(e).__name__)
        raise HTTPException(status_code=502, detail="Gizlilik tercihleri okunamadı.")
    row = result.data[0] if result.data else {}
    return {
        "ai_processing_allowed": row.get("ai_processing_allowed") is True,
        "location_processing_allowed": row.get("location_processing_allowed") is True,
        "photo_processing_allowed": row.get("photo_processing_allowed") is True,
        "updated_at": row.get("updated_at"),
    }


@app.post("/privacy-preferences", tags=["account"])
def privacy_preferences_update(request: Request, req: PrivacyPreferencesRequest):
    enforce_supabase_user(request, req.user_id)
    if not req.ai_processing_allowed:
        raise HTTPException(
            status_code=400,
            detail="AI izni bu hizmet modeli için zorunludur; geri çekmek için hesabınızı silebilirsiniz.",
        )
    supabase = get_supabase()
    if not supabase:
        raise HTTPException(status_code=500, detail="Supabase bağlantısı yok")
    payload = {
        "user_id": req.user_id,
        "ai_processing_allowed": True,
        "location_processing_allowed": bool(req.location_processing_allowed),
        "photo_processing_allowed": bool(req.photo_processing_allowed),
        "updated_at": datetime.now(timezone.utc).isoformat(),
    }
    try:
        result = supabase.table("privacy_preferences").upsert(payload).execute()
    except Exception as e:
        log.error("Gizlilik tercihleri kaydedilemedi: %s", type(e).__name__)
        raise HTTPException(status_code=502, detail="Gizlilik tercihleri kaydedilemedi.")
    return {"ok": True, **(result.data[0] if result.data else payload)}


@app.post(
    "/account/delete",
    tags=["account"],
    dependencies=[Depends(rate_limit_dependency(LIMIT_ACCOUNT_DELETE))],
)
def account_delete(request: Request, req: AccountDeleteRequest):
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
    _delete_user_application_data(supabase, uid)
    run_async(_auth_admin_delete_user, uid)
    log.info("Hesap ve ilişkili kişisel veriler kalıcı silindi")
    return {"ok": True}


@app.post(
    "/upload_photo",
    tags=["media"],
    dependencies=[Depends(rate_limit_dependency(LIMIT_UPLOAD_PHOTO))],
)
def upload_photo(request: Request, user_id: str, file: UploadFile = File(...)):
    """Fotoğraf yükleme endpoint'i."""
    enforce_supabase_user(request, user_id)
    _require_privacy_permission(user_id, "photo")
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
        # Sınırdan bir bayt fazla okunur: büyük dosya tamamen belleğe alınmadan reddedilir.
        contents = file.file.read(_MAX_PHOTO_BYTES + 1)
        if len(contents) > _MAX_PHOTO_BYTES:
            raise HTTPException(
                status_code=400,
                detail="Dosya çok büyük (en fazla 8 MB)",
            )
        if not contents or not _photo_content_matches_extension(contents, file_ext):
            raise HTTPException(
                status_code=400,
                detail="Dosya içeriği izin verilen görsel formatıyla eşleşmiyor.",
            )
        file_path = f"{user_id}/{uuid.uuid4()}.{file_ext}"
        mime = {
            "jpg": "image/jpeg",
            "jpeg": "image/jpeg",
            "png": "image/png",
            "webp": "image/webp",
            "heic": "image/heic",
            "heif": "image/heif",
        }[file_ext]
        bucket = supabase.storage.from_("skin-photos")
        bucket.upload(file_path, contents, file_options={"content-type": mime})
        signed = bucket.create_signed_url(file_path, 3600)
        signed_url = (
            (signed or {}).get("signedURL")
            or (signed or {}).get("signedUrl")
            or (signed or {}).get("signed_url")
        )
        if not signed_url:
            bucket.remove([file_path])
            raise HTTPException(status_code=502, detail="Fotoğraf erişim bağlantısı oluşturulamadı.")
        log.info("Fotoğraf yüklendi: %s", file_path)
        return {"url": signed_url, "path": file_path, "expires_in": 3600}
    except HTTPException:
        raise
    except Exception as e:
        log.error("Fotoğraf yükleme hatası: %s", e)
        raise HTTPException(status_code=500, detail="Fotoğraf yüklenemedi.")


if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
