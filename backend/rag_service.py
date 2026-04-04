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
from typing import Optional
from google import genai
from google.genai import types
from config import GEMINI_API_KEY, get_logger
from flow_engine import sanitize_routine_items_details

log = get_logger("rag_service")


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


def _polish_user_message(exc: Exception) -> str:
    """Kullanıcıya gösterilecek kısa açıklama (log ayrıntılı kalır)."""
    text = str(exc).lower()
    if "429" in text or "quota" in text or "resource_exhausted" in text:
        return (
            "Yapay zeka metin düzenlemesi şu an kullanılamıyor (servis kotası doldu veya geçici limit). "
            "Rutinin bilimsel içeriği aynen korundu; sadece cümle cilası atlandı."
        )
    if not GEMINI_API_KEY:
        return "Yapay zeka anahtarı tanımlı değil; rutin motor çıktısı olduğu gibi sunuldu."
    return (
        "Metin düzenleme adımı tamamlanamadı (bağlantı veya servis hatası). "
        "Rutin önerileri yine de geçerlidir."
    )


async def polish_routine_with_ai(
    routine_items: list[dict],
    context_summary: str,
    knowledge_context: str,
) -> tuple[list[dict], Optional[str]]:
    """
    Flow Engine'den gelen rutin öğelerini alır,
    AI ile sadece detay cümlelerini kişiselleştirir.
    Token kullanımı: ~300-500 token
    """
    if not gemini_client:
        log.warning("Gemini client yok, orijinal rutin döndürülüyor")
        if not GEMINI_API_KEY:
            return routine_items, _polish_user_message(Exception("no key"))
        return routine_items, "Gemini istemcisi başlatılamadı; rutin motor çıktısı kullanıldı."

    items_text = ""
    for i, item in enumerate(routine_items):
        items_text += f"{i+1}. [{item['time']}] {item['action']}: {item['detail']}\n"

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

    try:
        response = gemini_client.models.generate_content(
            model="gemini-2.0-flash",
            contents=prompt,
            config=types.GenerateContentConfig(
                system_instruction=(
                    "Sen Rebi. Türkçe, kısa ve net. Rutin kararları motorda; sen sadece detail metnini cilala. "
                    "ASLA marka veya ürün adı yazma; sadece etken madde ve konsantrasyon. "
                    "Kullanıcıya sıklığı bırakma; 'gerekirse', 'isteğe bağlı', 'tolere edince', 'ilk haftalar' kullanma. "
                    "SADECE JSON döndür."
                ),
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
        return routine_items, "Yapay zeka beklenmeyen formatta yanıt verdi; rutin metinleri değiştirilmedi."

    except Exception as e:
        log.error("AI polish hatası: %s — orijinal rutin kullanılıyor", e)
        return routine_items, _polish_user_message(e)


async def assessment_chat(
    user_message: str,
    history: list = None,
    user_profile: dict = None,
) -> dict:
    """
    Gemini multi-turn sohbet formatında cilt değerlendirmesi.
    Konuşma geçmişi Gemini'ye doğal user/model rolleriyle gönderilir.
    """
    if not gemini_client:
        return {"reply": "Bağlantı kurulamadı, lütfen tekrar dene.", "is_complete": False}

    is_free_chat = user_profile and user_profile.get("mode") == "free_chat"
    if is_free_chat:
        return await _free_chat(user_message, history, user_profile)

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


async def _free_chat(user_message: str, history: list = None, user_profile: dict = None) -> dict:
    """Serbest sohbet modu - cilt/yüz/el bakımı hakkında her şey sorulabilir."""
    hist = list(history or [])
    um = (user_message or "").strip()
    if (
        hist
        and hist[-1].get("role") == "user"
        and (hist[-1].get("content") or "").strip() == um
    ):
        hist = hist[:-1]

    contents: list = []
    for msg in hist[-12:]:
        role = "model" if msg.get("role") == "assistant" else "user"
        contents.append(
            types.Content(role=role, parts=[types.Part.from_text(text=msg.get("content", "") or "")])
        )
    contents.append(types.Content(role="user", parts=[types.Part.from_text(text=user_message)]))

    name = (user_profile or {}).get("name", "Kullanıcı")
    system_instruction = (
        f"Kullanıcının görünen adı: {name}.\n"
        "Sen Rebi, profesyonel cilt bakım asistanısın. Türkçe konuş.\n"
        "KAPSAM: SADECE cilt, yüz ve el bakımı. Ürünler, maddeler (niacinamide, retinol, AHA, BHA vb.), "
        "cilt sorunları, bakım rutinleri, dermakozmetik bilgisi.\n"
        "Kapsam dışı konulara: 'Bu konuda yardımcı olamam, cilt bakımıyla ilgili sorularını yanıtlayabilirim.' de.\n"
        "KISA ve NET yanıtlar ver — en fazla 3–4 cümle. Bilgi yığını yapma.\n"
        "Sıcak, samimi, profesyonel ol. Tıbbi teşhis koyma, gerekirse dermatoloğa yönlendir."
    )

    try:
        response = gemini_client.models.generate_content(
            model="gemini-2.0-flash",
            contents=contents,
            config=types.GenerateContentConfig(
                system_instruction=system_instruction,
                temperature=0.6,
                max_output_tokens=350,
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
        if "429" in str(e).lower() or "quota" in str(e).lower() or "resource_exhausted" in str(e).lower():
            return {
                "reply": hint,
                "is_complete": False,
                "extracted_data": None,
            }
        return {"reply": "Bir hata oluştu, tekrar dener misin?", "is_complete": False, "extracted_data": None}


async def chat_with_knowledge(
    user_message: str,
    knowledge_context: str,
    history: Optional[list] = None,
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

    prompt = f"""Önceki konuşma:
{history_text if history_text else 'İlk mesaj.'}

Bilgi tabanından referans:
{knowledge_context[:2000] if knowledge_context else 'İlgili veri bulunamadı.'}

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
