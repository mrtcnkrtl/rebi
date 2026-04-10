"""
REBI AI - AI Servisi v2.0
==============================
AI görevleri (token tasarruflu):
1. Deterministik rutin öğelerini sıcak, kişisel dile çevirir
2. Bilgi tabanından gelen kuru veriyi 1-2 cümlelik açıklamaya çevirir
3. Günlük check-in sonrası adaptasyon notu üretir (adapt_routine_with_ai)

AI şu işleri YAPMAZ:
- Rutin oluşturma (Flow Engine yapar)
- Veri arama (Knowledge Router yapar)
- Risk skoru hesaplama (ingredient_db yapar)
"""

import json
import re
from typing import Optional, Literal
from google import genai
from google.genai import types
from config import GEMINI_API_KEY, KNOWLEDGE_CATALOG_USER_ID, get_logger
from flow_engine import sanitize_routine_items_details

log = get_logger("rag_service")

def _polish_user_message(err: Exception) -> str:
    """
    Convert common upstream errors (quota, timeouts) into a user-safe message.
    Must never raise — used inside exception handlers.
    """
    try:
        s = str(err or "")
        sl = s.lower()
        if "429" in sl or "quota" in sl or "resource_exhausted" in sl or "rate limit" in sl:
            return "İşlem tamamlanamadı. Bir süre sonra tekrar dene."
        if "timeout" in sl or "timed out" in sl:
            return "Şu an yanıt gecikti. Biraz sonra tekrar dener misin?"
        return "Bir hata oluştu, tekrar dener misin?"
    except Exception:
        return "Bir hata oluştu, tekrar dener misin?"


def knowledge_entity_fallback_text(
    *,
    user_id: str,
    user_message: str,
    folder_slug: str = "data-pdfs",
    accept_lang: str = "tr",
) -> Optional[str]:
    """
    AI (Gemini) yokken veya kota varken: entity index üzerinden döküman parçaları döndürür.
    - Madde/özüt benzeri soruda chunk yoksa: veri yok mesajı
    - Genel sohbette eşleşme yoksa: None (çağıran varsayılan hata/kota mesajını kullanır)
    """
    uid = (user_id or "").strip()
    if not uid:
        return None
    try:
        from knowledge.entity_search import find_chunks_by_entity, list_entities
    except Exception as e:
        log.warning("knowledge_entity_fallback_text import atlandı: %s", e)
        return None

    msg = (user_message or "").strip()
    if len(msg) < 2:
        return None
    msg_l = msg.lower()

    raw_tokens: list[str] = []
    for t in (
        msg_l.replace("/", " ")
        .replace(",", " ")
        .replace(".", " ")
        .replace("(", " ")
        .replace(")", " ")
        .replace(":", " ")
        .replace(";", " ")
    ).split():
        tt = "".join(ch for ch in t if ch.isalnum() or ch in ("+", "%", "-"))
        if 3 <= len(tt) <= 32:
            raw_tokens.append(tt)

    seen: set[str] = set()
    tokens: list[str] = []
    for t in sorted(raw_tokens, key=lambda x: (-len(x), x))[:12]:
        if t not in seen:
            tokens.append(t)
            seen.add(t)
    if not tokens:
        return None

    candidate_entities: list[str] = []
    try:
        for t in tokens[:6]:
            ents = list_entities(user_id=uid, folder_slug=folder_slug, q=t, k=5) or []
            for e in ents[:3]:
                name = (e.get("name") or "").strip()
                if not name:
                    continue
                name_l = name.lower()
                if name_l == t or t in name_l:
                    candidate_entities.append(name)
            if len(candidate_entities) >= 4:
                break

        chunks_texts: list[str] = []
        used_entity_names: list[str] = []
        for ename in candidate_entities[:2]:
            chunks = find_chunks_by_entity(
                user_id=uid,
                folder_slug=folder_slug,
                q=ename,
                k=6,
            )
            if chunks:
                used_entity_names.append(ename)
            for c in chunks[:4]:
                txt = (c.chunk_text or "").strip()
                if txt:
                    chunks_texts.append(txt)
            if len(chunks_texts) >= 6:
                break

        if chunks_texts:
            hdr = ""
            if used_entity_names:
                hdr = "İlgili maddeler: " + ", ".join(used_entity_names[:4]) + "\n\n"
            body = "\n\n---\n\n".join(chunks_texts)
            return (hdr + body)[:2400]

        ingredient_intent = any(
            w in msg_l
            for w in [
                "nedir",
                "ne işe yarar",
                "nasıl kullan",
                "kullanılır",
                "yüzde",
                "%",
                "konsantr",
                "oran",
                "doz",
                "percent",
                "concentration",
                "ingredient",
                "active",
            ]
        )
        if ingredient_intent and any(len(t) >= 4 for t in tokens[:6]):
            if (accept_lang or "tr").lower().startswith("en"):
                return "I couldn't find this in the current dataset yet."
            return "Bunu şu anki veri setimde bulamadım."
    except Exception as e:
        log.warning("knowledge_entity_fallback_text hatası: %s", e)
        return None

    return None


def _knowledge_fallback_for_any_user(user_id: Optional[str], user_message: str) -> Optional[str]:
    """Önce oturum user_id, sonra ortak katalog user_id (ingest ile aynı) ile entity araması."""
    seen: set[str] = set()
    for uid in ((user_id or "").strip(), (KNOWLEDGE_CATALOG_USER_ID or "").strip()):
        if not uid or uid in seen:
            continue
        seen.add(uid)
        fb = knowledge_entity_fallback_text(user_id=uid, user_message=user_message)
        if fb:
            return fb
    return None


_GREETING_ONLY = re.compile(
    r"^(merhaba|selam|hey|hi|hello|sa|günaydın|iyi akşamlar|iyi günler)\s*!?\s*$",
    re.I,
)


def _free_chat_is_personal_or_lifestyle(msg: str) -> bool:
    """Kişisel belirti, hormonal, yaşam tarzı, rutin planı — uygulama alanı; chat değil."""
    t = (msg or "").strip().lower()
    if len(t) < 2:
        return False
    needles = (
        "yüzüm",
        "cildim",
        "tenim",
        "şişti",
        "şişme",
        "ödem",
        "kızardı",
        "kızarıklığım",
        "kızarıklık",
        "kaşınt",
        "yanıyor",
        "acıyor",
        "adet",
        "regl",
        "hamile",
        "gecikme",
        "stresliyim",
        "çok stres",
        "uykum",
        "uyuyamadım",
        "su içmedim",
        "içemedim",
        "yorgunum",
        "yapılacak",
        "ne yapayım",
        "rutin öner",
        "rutinim",
        "kişisel öner",
        "bana rutin",
        "check-in",
        "check in",
        "dashboard",
    )
    return any(n in t for n in needles)


def _gemini_response_text(response) -> str:
    """
    google-genai bazen güvenlik/aday yokken .text ile patlar.
    Önce .text, olmazsa candidates[].content.parts[].text toplanır.
    """
    if response is None:
        return ""
    try:
        t = response.text
        if isinstance(t, str) and t.strip():
            return t.strip()
    except Exception:
        pass
    try:
        chunks = []
        for c in getattr(response, "candidates", None) or []:
            content = getattr(c, "content", None)
            if not content:
                continue
            for p in getattr(content, "parts", None) or []:
                pt = getattr(p, "text", None)
                if pt:
                    chunks.append(pt)
        return "\n".join(chunks).strip()
    except Exception:
        return ""


gemini_client = None
if GEMINI_API_KEY:
    try:
        gemini_client = genai.Client(api_key=GEMINI_API_KEY)
        log.info("Gemini client hazır")
    except Exception as e:
        log.error("Gemini client hatası: %s", e)


async def polish_routine_with_ai(
    routine_items: list[dict],
    context_summary: str,
    knowledge_context: str,
    lang: str = "tr",
) -> tuple[list[dict], Optional[str]]:
    """
    Flow Engine'den gelen rutin öğelerini alır,
    AI ile sadece detay cümlelerini kişiselleştirir.
    Token kullanımı: ~300-500 token
    """
    if not gemini_client:
        log.warning("Gemini client yok, orijinal rutin döndürülüyor")
        if not GEMINI_API_KEY:
            log.info("GEMINI_API_KEY yok; polish atlandı")
        else:
            log.warning("Gemini istemcisi başlatılamadı; polish atlandı")
        return routine_items, None

    def _norm_lang(v: str) -> Literal["tr", "en"]:
        s = (v or "").strip().lower()
        if not s:
            return "tr"
        # Accept-Language like: "en-US,en;q=0.9,tr;q=0.8"
        primary = s.split(",")[0].split(";")[0].strip()
        primary = primary.split("-")[0]
        return "en" if primary == "en" else "tr"

    lng = _norm_lang(lang)

    items_text = ""
    for i, item in enumerate(routine_items):
        items_text += f"{i+1}. [{item['time']}] {item['action']}: {item['detail']}\n"

    if lng == "en":
        prompt = f"""Context: {context_summary}

Scientific notes (reference):
{knowledge_context[:1500] if knowledge_context else 'None'}

Improve the routine items below, keeping the plan deterministic:
- Do NOT change action/time/category/icon; ONLY update the \"detail\" field
- Detail: max 2 short sentences, user-facing and clear (avoid system/third-person tone)
- Do NOT add: \"if needed\", \"optional\", \"when tolerated\", \"start slowly\"; frequency is already handled by the engine
- Do NOT give commands; explain in an informative tone

FORBIDDEN: Any brand or product names. Use only active ingredients and concentrations (e.g., Adapalene 0.1%, Retinol 0.3%).

Current items:
{items_text}

Return ONLY a JSON array (detail can change; action/time/category/icon must not change):
[{{"time":"...","category":"...","icon":"...","action":"...","detail":"new detail"}}]"""

        system_instruction = (
            "You are Rebi. Write in English, short and clear. The routine decisions are made by the engine; "
            "you only polish the detail text. NEVER write brand/product names; only actives + concentrations. "
            "Do not defer frequency to the user; avoid 'if needed', 'optional', 'when tolerated', 'start slowly'. "
            "Return ONLY JSON."
        )
    else:
        prompt = f"""Bağlam: {context_summary}

Bilimsel Veri (referans):
{knowledge_context[:1500] if knowledge_context else 'Yok'}

Aşağıdaki rutin öğelerini değerlendir ve EN OPTİMAL olanları seç/geliştir:
- Tüm önerileri verme, kişiye EN UYGUN ve EN ETKİLİ olanları seç
- Birbirine benzeyen/çakışan adımları birleştir
- SADECE "detail" alanını güncelle; "action" aynen kalacak, dokunma
- Detay: en fazla 2 kısa cümle; üçüncü şahıs / sistem dili ("planda", "belirlendi", "atanır")
- Haftalık sıklık ve günler zaten motorda; detayda "kendin ayarla", "gerekirse", "tolere edince", "ilk haftalar seyrek" YAZMA
- Kullanıcıya emir verme ("yap", "ekleme", "kullan"); açıklayıcı bildir

YASAK: Marka veya ürün adı ASLA yazma (Adalen, Differin, La Roche, CeraVe, The Ordinary vb. tüm markalar yasak). Sadece ETKEN MADDE adı ve konsantrasyon kullan (örn. Adapalen %0.1, Retinol %0.3, Niasinamid %10).

Mevcut öğeler:
{items_text}

SADECE JSON array döndür (sadece detail güncellenebilir, action/time/category/icon değiştirme):
[{{"time":"...","category":"...","icon":"...","action":"...","detail":"yeni detay"}}]"""

        system_instruction = (
            "Sen Rebi. Türkçe, kısa ve net. Rutin kararları motorda; sen sadece detail metnini cilala. "
            "ASLA marka veya ürün adı yazma; sadece etken madde ve konsantrasyon. "
            "Kullanıcıya sıklığı bırakma; 'gerekirse', 'isteğe bağlı', 'tolere edince', 'ilk haftalar' kullanma. "
            "SADECE JSON döndür."
        )

    try:
        response = gemini_client.models.generate_content(
            model="gemini-2.0-flash",
            contents=prompt,
            config=types.GenerateContentConfig(
                system_instruction=system_instruction,
                temperature=0.6,
                max_output_tokens=1200,
                response_mime_type="application/json",
            ),
        )

        parsed = json.loads(_gemini_response_text(response) or "{}")

        if isinstance(parsed, list) and len(parsed) > 0:
            for i, item in enumerate(routine_items):
                if i < len(parsed):
                    ai_item = parsed[i]
                    if "detail" in ai_item:
                        item["detail"] = ai_item["detail"]
            sanitize_routine_items_details(routine_items)
            log.info("AI polish tamamlandı: %d öğe güncellendi", min(len(parsed), len(routine_items)))
            return routine_items, None

        log.warning("AI geçersiz format döndürdü, orijinal kullanılıyor")
        return routine_items, None

    except Exception as e:
        log.error("AI polish hatası: %s — orijinal rutin kullanılıyor", e)
        return routine_items, None


def _primary_lang_from_header(accept_language: str) -> str:
    s = (accept_language or "").strip().lower()
    if not s:
        return "tr"
    primary = s.split(",")[0].split(";")[0].strip()
    return primary.split("-")[0] or "tr"


async def translate_routine_items(
    routine_items: list[dict],
    target_lang: str,
) -> list[dict]:
    """
    Motor Türkçe üretir. Bu fonksiyon response'a çeviri alanları ekler:
      - action_localized
      - detail_localized
    Orijinal action/detail korunur (parsing/kurallar bozulmasın diye).
    """
    if not gemini_client:
        return routine_items

    tl = (target_lang or "").strip().lower().split("-")[0]
    if not tl or tl == "tr":
        return routine_items

    payload = []
    for idx, it in enumerate(routine_items):
        payload.append(
            {
                "i": idx,
                "action": (it.get("action") or ""),
                "detail": (it.get("detail") or ""),
            }
        )

    prompt = (
        "Translate the following routine item texts from Turkish to the target language.\n"
        f"Target language: {tl}\n\n"
        "Rules:\n"
        "- Keep active ingredient names and concentrations unchanged (e.g., Retinol %0.3 stays the same).\n"
        "- Do not add new advice; translate only.\n"
        "- Output ONLY JSON array with objects: {i, action_localized, detail_localized}\n\n"
        f"Input JSON:\n{json.dumps(payload, ensure_ascii=False)}"
    )

    try:
        response = gemini_client.models.generate_content(
            model="gemini-2.0-flash",
            contents=prompt,
            config=types.GenerateContentConfig(
                system_instruction=(
                    "You are a careful medical-adjacent translator. Do NOT add content. "
                    "Preserve ingredient names and concentrations verbatim. Return ONLY JSON."
                ),
                temperature=0.2,
                max_output_tokens=1400,
                response_mime_type="application/json",
            ),
        )
        parsed = json.loads(_gemini_response_text(response) or "[]")
        if not isinstance(parsed, list):
            return routine_items
        by_i = {x.get("i"): x for x in parsed if isinstance(x, dict) and x.get("i") is not None}
        out = []
        for idx, it in enumerate(routine_items):
            tr = by_i.get(idx) or {}
            it2 = dict(it)
            al = tr.get("action_localized")
            dl = tr.get("detail_localized")
            if isinstance(al, str) and al.strip():
                it2["action_localized"] = al.strip()
            if isinstance(dl, str) and dl.strip():
                it2["detail_localized"] = dl.strip()
            out.append(it2)
        return out
    except Exception as e:
        log.error("translate_routine_items hatası: %s", e)
        return routine_items


async def assessment_chat(
    user_message: str,
    history: list = None,
    user_profile: dict = None,
    user_id: Optional[str] = None,
) -> dict:
    """
    Gemini multi-turn sohbet formatında cilt değerlendirmesi.
    Konuşma geçmişi Gemini'ye doğal user/model rolleriyle gönderilir.
    """
    is_free_chat = user_profile and user_profile.get("mode") == "free_chat"
    if not gemini_client:
        if is_free_chat:
            fb = _knowledge_fallback_for_any_user(user_id, user_message)
            if fb:
                return {
                    "reply": (
                        "Şu an yapay zekâ kotası veya API kapalı; yüklü dökümanlardan derlenen notlar:\n\n"
                        + fb
                    ),
                    "is_complete": False,
                }
        return {"reply": "Bağlantı kurulamadı, lütfen tekrar dene.", "is_complete": False}

    if is_free_chat:
        return await _free_chat(user_message, history, user_profile, user_id=user_id)

    profile_text = ""
    if user_profile:
        profile_text = (
            f"Profil: {user_profile.get('name','?')}, {user_profile.get('age','?')} yaş, "
            f"{user_profile.get('gender','?')}, {user_profile.get('skin_type','?')} cilt, "
            f"Sorunlar: {', '.join(user_profile.get('concerns', []))}, "
            f"Bölgeler: {', '.join(user_profile.get('zones', []))}, "
            f"Stres: {user_profile.get('stress_score','?')}/16 ({user_profile.get('stress_level','?')}), "
            f"Sigara: {user_profile.get('smoking','Yok')}, Alkol: {user_profile.get('alcohol','Yok')}, "
            f"Beslenme: {user_profile.get('nutrition','?')}, Makyaj: {user_profile.get('makeup','?')}, "
            f"Su: {user_profile.get('water_intake','?')}L, Uyku: {user_profile.get('sleep_hours','?')}s"
        )
        if user_profile.get("severity_duration"):
            profile_text += f" Şiddet/süre (kullanıcı): {user_profile.get('severity_duration')}."
        if user_profile.get("triggers"):
            profile_text += f" Tetikleyiciler (kullanıcı): {user_profile.get('triggers')}."
        if user_profile.get("past_treatments"):
            profile_text += f" Geçmiş tedaviler (kullanıcı): {user_profile.get('past_treatments')}."
        if user_profile.get("expectations"):
            profile_text += f" Beklentiler (kullanıcı): {user_profile.get('expectations')}."

    all_text = " ".join(m.get("content", "") for m in (history or [])).lower() + " " + user_message.lower()
    profile_lower = (profile_text or "").lower()

    up = user_profile or {}
    got_severity = any(w in profile_lower for w in ["şiddet", "süre", "yıldır", "aydır"]) or up.get("severity_duration") or any(w in all_text for w in [
        "süredir", "yıldır", "aydır", "haftadır", "şiddet", "yoğun", "hafif",
        "kötü", "rahatsız", "ağrı", "kaşın", "ne kadar", "çok fazla", "biraz",
    ])
    got_triggers = bool(up.get("triggers")) or any(w in all_text for w in [
        "stres", "yemek", "mevsim", "güneş", "tetik", "neden", "sebep", "adet",
        "dönem", "çikolata", "yağlı", "tatlı", "soğuk", "sıcak", "ürün",
    ])
    got_treatments = bool(up.get("past_treatments")) or any(w in all_text for w in [
        "dene", "kullan", "krem", "ilaç", "tedavi", "doktor", "dermato", "serum",
        "eczane", "reçete", "yaramadı", "denemedim", "hiçbir", "bir şey kullanmad",
    ])
    got_expectations = bool(up.get("expectations")) or any(w in all_text for w in [
        "istiyor", "hedef", "beklenti", "düzel", "azal", "temiz", "kurtul",
        "kavuş", "istiyorum", "olsun", "geçsin", "iyileş",
    ])

    collected = {"severity": got_severity, "triggers": got_triggers,
                 "past_treatments": got_treatments, "expectations": got_expectations}
    collected_count = sum(collected.values())
    missing_names = []
    if not got_severity: missing_names.append("şiddet/süre")
    if not got_triggers: missing_names.append("tetikleyiciler")
    if not got_treatments: missing_names.append("geçmiş tedaviler")
    if not got_expectations: missing_names.append("beklentiler")

    system_prompt = f"""Sen Rebi, profesyonel cilt bakım uzmanısın. Türkçe konuş.

{profile_text}

TEMEL KURALLAR:
1. KISA yanıtlar ver — en fazla 2-3 cümle.
2. Her mesajda EN FAZLA 1 soru sor.
3. Zaten cevapladığı bir şeyi ASLA tekrar sorma.
4. Önceki mesajlarda konuşulmuş konuları tekrarlamak YASAK.
5. Kullanıcı bir soru sorarsa (ürün, madde hakkında) → kısa yanıtla, sonra eksik konuya geç.
6. Kapsam: SADECE cilt, yüz, el bakımı.

BİLGİ DURUMU ({collected_count}/4 toplandı):
- Şiddet/süre: {"ALINDI" if got_severity else "EKSİK — bunu sor"}
- Tetikleyiciler: {"ALINDI" if got_triggers else "EKSİK — bunu sor"}
- Geçmiş tedaviler: {"ALINDI" if got_treatments else "EKSİK — bunu sor"}
- Beklentiler: {"ALINDI" if got_expectations else "EKSİK — bunu sor"}

{"SADECE şu eksik konuda soru sor: " + missing_names[0] if len(missing_names) > 0 else "TÜM BİLGİLER TOPLANDI."}

{f"4/4 bilgi toplandı. DEĞERLENDİRMEYİ TAMAMLA. Yeni soru SORMA. Kısa özet yaz ve JSON ekle." if collected_count >= 4 else ""}

Değerlendirme tamamlama (sadece 4/4 olunca):
Cevabının sonuna ekle:
```json
{{"assessment_complete": true, "severity_score": <1-10>, "stress_impact": "<düşük/orta/yüksek>", "primary_triggers": ["neden1"], "root_causes": ["kök neden"], "optimal_focus": "odak", "notes": "not"}}
```"""

    contents = []
    if history:
        for msg in history[-16:]:
            role = "model" if msg.get("role") == "assistant" else "user"
            contents.append(types.Content(role=role, parts=[types.Part.from_text(text=msg.get("content", ""))]))

    contents.append(types.Content(role="user", parts=[types.Part.from_text(text=user_message)]))

    try:
        response = gemini_client.models.generate_content(
            model="gemini-2.0-flash",
            contents=contents,
            config=types.GenerateContentConfig(
                system_instruction=system_prompt,
                temperature=0.5,
                max_output_tokens=300,
            ),
        )

        reply_text = (_gemini_response_text(response) or "").strip()
        if not reply_text:
            log.warning("Assessment: boş model yanıtı")
            return {"reply": "Şu an güvenli bir yanıt üretilemedi. Kısaca tekrar yazar mısın?", "is_complete": False}

        is_complete = False
        extracted = None
        if "assessment_complete" in reply_text and "true" in reply_text.lower():
            is_complete = True
            try:
                json_start = reply_text.rfind("```json")
                json_end = reply_text.rfind("```", json_start + 7)
                if json_start >= 0 and json_end > json_start:
                    json_str = reply_text[json_start + 7:json_end].strip()
                    extracted = json.loads(json_str)
                    reply_text = reply_text[:json_start].strip()
                else:
                    brace_start = reply_text.rfind("{")
                    brace_end = reply_text.rfind("}") + 1
                    if brace_start >= 0 and brace_end > brace_start:
                        json_str = reply_text[brace_start:brace_end]
                        extracted = json.loads(json_str)
                        reply_text = reply_text[:brace_start].strip()
            except Exception:
                pass

        log.info("Assessment: msgs=%d, collected=%d/4, complete=%s, missing=%s",
                 len(contents), collected_count, is_complete, missing_names)
        return {"reply": reply_text, "is_complete": is_complete, "extracted_data": extracted}

    except Exception as e:
        log.error("Assessment chat hatası: %s", e)
        et = str(e).lower()
        if "429" in et or "quota" in et or "resource_exhausted" in et:
            return {
                "reply": "Şu an çok yoğunuz; bir süre sonra tekrar dener misin? (Kota/limit)",
                "is_complete": False,
            }
        return {"reply": "Bir hata oluştu, tekrar dener misin?", "is_complete": False}


async def _free_chat(
    user_message: str,
    history: list = None,
    user_profile: dict = None,
    user_id: Optional[str] = None,
) -> dict:
    """
    Uygulama içi Rebi sohbeti: yalnızca ürün / içerik maddesi bilgisi.
    Kişisel belirti, yaşam tarzı, rutin ve yapılacaklar uygulamanın akışında kalır.
    Mümkünse yüklü dökümanlardan gelen REFERANS ile zemini bağlar.
    """
    hist = list(history or [])
    um = (user_message or "").strip()
    if (
        hist
        and hist[-1].get("role") == "user"
        and (hist[-1].get("content") or "").strip() == um
    ):
        hist = hist[:-1]

    redirect_app = {
        "reply": (
            "Kişisel belirtiler, stres, uyku, su, hormonal döngü ve sana özel yapılacaklar bu sohbette değil; "
            "bunlar uygulamadaki Analiz ve günlük takipte değerlendirilir. "
            "Burada yalnızca kozmetik ürünleri ve içerik maddeleri (ör. niacinamide, temizleyici türleri) hakkında soru sorabilirsin."
        ),
        "is_complete": False,
        "extracted_data": None,
    }

    if _GREETING_ONLY.match(um):
        return {
            "reply": (
                "Merhaba! Burada yalnızca ürün ve içerik maddeleri hakkında kısa bilgi verebilirim. "
                "Kişisel rutin ve öneriler için uygulamadaki Analiz / takip bölümünü kullan."
            ),
            "is_complete": False,
            "extracted_data": None,
        }

    if _free_chat_is_personal_or_lifestyle(um):
        return redirect_app

    kb = _knowledge_fallback_for_any_user(user_id, um)

    # Son kullanıcı mesajı: varsa REFERANS ile (Gemini özeti yalnızca buna dayansın)
    if kb:
        final_user = (
            "REFERANS (Rebi yüklü bilimsel notları — yanıtı YALNIZCA buna dayandır; "
            "referansta olmayan bilgi uydurma; yapılacak listesi veya kişisel rutin önerme):\n\n"
            f"{kb}\n\n---\n\nKullanıcı sorusu: {um}"
        )
    else:
        final_user = um

    contents: list = []
    for msg in hist[-12:]:
        role = "model" if msg.get("role") == "assistant" else "user"
        contents.append(
            types.Content(role=role, parts=[types.Part.from_text(text=msg.get("content", "") or "")])
        )
    contents.append(types.Content(role="user", parts=[types.Part.from_text(text=final_user)]))

    name = (user_profile or {}).get("name", "Kullanıcı")
    if kb:
        system_instruction = (
            f"Kullanıcının görünen adı: {name}.\n"
            "Sen Rebi bilgi asistanısın. Türkçe konuş.\n"
            "Bu kanal SADECE kozmetik ürünleri ve içerik maddeleri hakkında kısa açıklama içindir.\n"
            "REFERANS metnini özetle; madde/ürün dışına çıkma. Yapılacaklar listesi, sabah-akşam rutin adımları, "
            "kişiselleştirilmiş öneri VERME.\n"
            "Tıbbi teşhis koyma; ciddi reaksiyon şüphesinde dermatoloğa yönlendir.\n"
            "En fazla 3–4 kısa cümle."
        )
    else:
        system_instruction = (
            f"Kullanıcının görünen adı: {name}.\n"
            "Sen Rebi bilgi asistanısın. Türkçe konuş.\n"
            "REFERANS yok: bu kanalda yalnızca genel düzeyde bir içerik maddesi veya ürün türü tanımı ver "
            "(en fazla 2–3 cümle). Kişisel öneri, yapılacaklar, rutin adımları VERME.\n"
            "Kullanıcı kişisel belirti veya yaşam tarzı anlatıyorsa kısaca uygulamadaki Analiz/takibe yönlendir.\n"
            "Tıbbi teşhis yok."
        )

    if not gemini_client:
        if kb:
            return {
                "reply": "Şu an özet üretilemiyor; yüklü notlar:\n\n" + kb[:2400],
                "is_complete": False,
                "extracted_data": None,
            }
        return {
            "reply": (
                "Bu konuda yüklü notlarımızda eşleşen pasaj bulamadım. "
                "Bir içerik maddesi veya ürün türü adıyla tekrar dene."
            ),
            "is_complete": False,
            "extracted_data": None,
        }

    try:
        response = gemini_client.models.generate_content(
            model="gemini-2.0-flash",
            contents=contents,
            config=types.GenerateContentConfig(
                system_instruction=system_instruction,
                temperature=0.35 if kb else 0.45,
                max_output_tokens=320,
            ),
        )
        reply = _gemini_response_text(response)
        if not reply:
            log.warning("Free chat: boş veya engellenmiş model yanıtı")
            return {
                "reply": "Şu an güvenli bir yanıt üretilemedi. Sorunu biraz kısaltıp tekrar dener misin?",
                "is_complete": False,
                "extracted_data": None,
            }
        log.info("Free chat yanıtı (%d karakter)", len(reply))
        return {"reply": reply, "is_complete": False, "extracted_data": None}
    except Exception as e:
        log.error("Free chat hatası: %s", e)
        hint = _polish_user_message(e)
        et = str(e).lower()
        if "429" in et or "quota" in et or "resource_exhausted" in et:
            fb = _knowledge_fallback_for_any_user(user_id, um)
            if fb:
                return {
                    "reply": (
                        "Şu an yapay zekâ kotası doldu; yüklü dökümanlardan derlenen notlar:\n\n" + fb
                    ),
                    "is_complete": False,
                    "extracted_data": None,
                }
            return {
                "reply": hint,
                "is_complete": False,
                "extracted_data": None,
            }
        fb2 = _knowledge_fallback_for_any_user(user_id, um)
        if fb2:
            return {
                "reply": (
                    "Şu an yapay zekâ yanıtı alınamadı; yüklü dökümanlardan derlenen notlar:\n\n" + fb2
                ),
                "is_complete": False,
                "extracted_data": None,
            }
        return {"reply": "Bir hata oluştu, tekrar dener misin?", "is_complete": False, "extracted_data": None}


async def chat_with_knowledge(
    user_message: str,
    knowledge_context: str,
    history: Optional[list] = None,
    *,
    user_id: Optional[str] = None,
    folder_slug: Optional[str] = None,
    accept_lang: str = "tr",
) -> str:
    """
    Kullanıcıyla interaktif sohbet. Bilgi tabanından gelen bağlamı kullanır.
    Token kullanımı: ~200-400 token/mesaj
    """
    if not gemini_client:
        return "Üzgünüm, şu anda cevap veremiyorum. Lütfen daha sonra tekrar dene."

    history_text = ""
    if history:
        for msg in history[-6:]:
            role = "Kullanıcı" if msg.get("role") == "user" else "Rebi"
            history_text += f"{role}: {msg.get('content', '')}\n"

    # Entity-first retrieval: if user asks about a specific ingredient/oil/extract,
    # prefer the entity index (knowledge_entities) to avoid scanning the whole dataset.
    entity_context = ""
    used_entity_names: list[str] = []
    try:
        if user_id and folder_slug:
            from knowledge.entity_search import find_chunks_by_entity, list_entities

            msg = (user_message or "").strip()
            msg_l = msg.lower()

            # Very small, cheap candidate mining (avoid token blow-up).
            raw_tokens = []
            for t in (
                msg_l.replace("/", " ")
                .replace(",", " ")
                .replace(".", " ")
                .replace("(", " ")
                .replace(")", " ")
                .replace(":", " ")
                .replace(";", " ")
            ).split():
                tt = "".join(ch for ch in t if ch.isalnum() or ch in ("+", "%", "-"))
                if 3 <= len(tt) <= 32:
                    raw_tokens.append(tt)

            # Keep unique tokens, prioritize longer ones first.
            seen = set()
            tokens = []
            for t in sorted(raw_tokens, key=lambda x: (-len(x), x))[:12]:
                if t not in seen:
                    tokens.append(t)
                    seen.add(t)

            # Query entity list for a few tokens; pick the best matched entity names.
            candidate_entities: list[str] = []
            for t in tokens[:6]:
                ents = list_entities(user_id=user_id, folder_slug=folder_slug, q=t, k=5) or []
                for e in ents[:3]:
                    name = (e.get("name") or "").strip()
                    if not name:
                        continue
                    name_l = name.lower()
                    if name_l == t or t in name_l:
                        candidate_entities.append(name)
                if len(candidate_entities) >= 4:
                    break

            # Fetch chunks for top entities.
            chunks_texts: list[str] = []
            for ename in candidate_entities[:2]:
                chunks = find_chunks_by_entity(
                    user_id=user_id,
                    folder_slug=folder_slug,
                    q=ename,
                    k=6,
                )
                if chunks:
                    used_entity_names.append(ename)
                for c in chunks[:4]:
                    txt = (c.chunk_text or "").strip()
                    if txt:
                        chunks_texts.append(txt)
                if len(chunks_texts) >= 6:
                    break

            if chunks_texts:
                joined = "\n\n---\n\n".join(chunks_texts)
                entity_context = joined[:2200]
            else:
                # If user seems to be asking specifically "about an ingredient" and we have no data, say so.
                ingredient_intent = any(
                    w in msg_l
                    for w in [
                        "nedir",
                        "ne işe yarar",
                        "nasıl kullan",
                        "kullanılır",
                        "yüzde",
                        "%",
                        "konsantr",
                        "oran",
                        "doz",
                        "percent",
                        "concentration",
                        "ingredient",
                        "active",
                    ]
                )
                if ingredient_intent and any(len(t) >= 4 for t in tokens[:6]):
                    if (accept_lang or "tr").lower().startswith("en"):
                        return "I couldn’t find this in the current dataset yet."
                    return "Bunu şu anki data setimde bulamadım."
    except Exception as e:
        log.warning("Entity-first retrieval atlandı: %s", e)

    merged_context = ""
    if entity_context:
        hdr = ""
        if used_entity_names:
            hdr = f"Bulunan maddeler: {', '.join(used_entity_names[:4])}\n\n"
        merged_context = (hdr + entity_context).strip()
    else:
        merged_context = (knowledge_context or "").strip()

    prompt = f"""Önceki konuşma:
{history_text if history_text else 'İlk mesaj.'}

Bilgi tabanından referans:
{merged_context[:2000] if merged_context else 'İlgili veri bulunamadı.'}

Kullanıcı sorusu: {user_message}

Bu soruyu bilgi tabanındaki verilere dayanarak yanıtla. Emin olmadığın konularda bunu belirt. Türkçe yanıt ver."""

    try:
        response = gemini_client.models.generate_content(
            model="gemini-2.0-flash",
            contents=prompt,
            config=types.GenerateContentConfig(
                system_instruction=(
                    "Sen Rebi, bütüncül cilt bakım asistanısın. Türkçe konuş. "
                    "Bilimsel verilere dayalı, kısa ve anlaşılır cevaplar ver. "
                    "Tıbbi teşhis koyma, gerekirse dermatolog öner."
                ),
                temperature=0.5,
                max_output_tokens=600,
            ),
        )
        out = _gemini_response_text(response)
        log.info("Chat yanıtı oluşturuldu (%d karakter)", len(out))
        return out or "Şu an kısa bir yanıt üretilemedi; sorunu tekrar yazar mısın?"

    except Exception as e:
        log.error("Chat hatası: %s", e)
        return "Bir hata oluştu, lütfen tekrar dene."


async def adapt_routine_with_ai(
    current_routine: list,
    daily_data: dict,
    risk_score: int,
    changes: list,
) -> str:
    """
    Günlük check-in verisiyle AI adaptasyon notu üretir.
    Deterministik değişiklikler zaten flow_engine'de yapıldı;
    AI sadece kullanıcıya yönelik açıklama/not üretir.
    Token: ~200-300
    """
    if not gemini_client:
        return "Rutinin güncellendi. Detaylar dashboard'da."

    changes_text = ""
    for c in changes[:5]:
        changes_text += f"- {c['item']}: {c['old']} → {c['new']} (sebep: {c['reason']})\n"

    routine_summary = ""
    for item in current_routine[:8]:
        routine_summary += f"- [{item.get('time','')}] {item.get('action','')}\n"

    prompt = f"""Kullanıcının günlük check-in verisi:
- Uyku: {daily_data.get('sleep_hours', '?')} saat
- Stres: {daily_data.get('stress_today', '?')}/5
- Cilt hissi: {daily_data.get('skin_feeling', '?')}
- Dünkü rutini uyguladı mı: {'Evet' if daily_data.get('applied_routine') else 'Hayır'}
- Notları: {daily_data.get('notes', 'Yok')}

Risk skoru: {risk_score}

Yapılan değişiklikler:
{changes_text if changes_text else 'Değişiklik yok, rutin aynı devam ediyor.'}

Mevcut rutin özeti:
{routine_summary}

Kullanıcıya KISA (2-3 cümle max) bir not yaz:
- Bugün cildi için ne önemli
- Yapılan değişikliklerin sebebi (varsa)
- Motivasyon
Türkçe, sıcak, samimi ol. Bilgi yığını yapma."""

    try:
        response = gemini_client.models.generate_content(
            model="gemini-2.0-flash",
            contents=prompt,
            config=types.GenerateContentConfig(
                system_instruction="Sen Rebi. Türkçe, kısa, sıcak notlar yaz. Max 3 cümle.",
                temperature=0.6,
                max_output_tokens=200,
            ),
        )
        note = (_gemini_response_text(response) or "").strip()
        log.info("AI adaptasyon notu oluşturuldu (%d karakter)", len(note))
        return note
    except Exception as e:
        log.error("AI adaptasyon notu hatası: %s", e)
        return "Rutinin güncellendi. Dashboard'dan detayları görebilirsin."
