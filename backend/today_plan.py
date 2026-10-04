"""
Ana ekran planı: bugünün havasına göre ne kullanılacak ve hangi saat
aralıklarında hatırlatılacak.

Saatler yerel duvar saatidir ("07:30"); bildirimleri istemci kendi saat
diliminde kurar. Sunucu yalnızca planı üretir, bildirim göndermez.
"""

from __future__ import annotations

from flow_engine import SKIN_TYPE_PROFILES, compute_environment_branches

# Günlük su hedefi (ml). Hatırlatıcı bu hedefe ulaşılınca susar.
WATER_TARGET_ML = 2000

# Güneş kremi tazelemesi bu UV değerinden itibaren hatırlatılır.
SPF_REFRESH_UV_THRESHOLD = 5
SPF_REFRESH_MAX_PER_DAY = 2

# Dudak balsamı: soğuk veya kuru havada.
LIP_BALM_MAX_TEMPERATURE = 10
LIP_BALM_MAX_HUMIDITY = 35


def _reminder(
    reminder_id: str,
    title: str,
    body: str,
    start: str,
    end: str,
    log_event: str | None = None,
    every_minutes: int | None = None,
) -> dict:
    return {
        "id": reminder_id,
        "title": title,
        "body": body,
        "start": start,
        "end": end,
        "every_minutes": every_minutes,
        "log_event": log_event,
    }


def build_environment_advice(weather: dict, skin_type: str = "normal") -> list[dict]:
    """Hava durumuna göre bugün kullanılacak ürün adımları (SPF, nemlendirici, balsam)."""
    w = weather or {}
    uv = float(w.get("uv_index", 3) or 0)
    humidity = float(w.get("humidity", 50) or 0)
    temperature = float(w.get("temperature", 20) or 0)
    key = str(skin_type or "normal").strip().lower()
    profile = SKIN_TYPE_PROFILES.get(key, SKIN_TYPE_PROFILES["normal"])

    items = list(compute_environment_branches(uv, humidity, temperature, profile))

    if temperature <= LIP_BALM_MAX_TEMPERATURE or humidity < LIP_BALM_MAX_HUMIDITY:
        items.append({
            "time": "Sabah",
            "category": "Bakım",
            "icon": "💋",
            "action": "Dudak balsamı (seramid / vazelin bazlı)",
            "detail": (
                f"Hava {int(temperature)}°C ve nem %{int(humidity)}. "
                "Dudak derisi ince olduğu için gün içinde tekrar uygula."
            ),
            "priority": 3,
        })

    return items


def build_reminders(weather: dict, aggregated: dict, checkin_done: bool = False) -> list[dict]:
    """Bugün için saat aralıklı hatırlatıcılar; yapılan işler listeden düşer."""
    w = weather or {}
    agg = aggregated or {}
    uv = float(w.get("uv_index", 3) or 0)
    humidity = float(w.get("humidity", 50) or 0)
    temperature = float(w.get("temperature", 20) or 0)

    makeup = agg.get("makeup") or {}
    reminders: list[dict] = []

    if not agg.get("routine_morning_done"):
        reminders.append(_reminder(
            "routine_morning",
            "Sabah rutini",
            "Bugünün sabah adımlarını uygula ve bitince işaretle.",
            "07:30",
            "09:30",
            log_event="routine_completed_block",
        ))

    if not makeup.get("logged"):
        reminders.append(_reminder(
            "makeup_log",
            "Bugün makyaj yaptın mı?",
            "Makyaj yaptıysan akşam temizliği planına eklenir.",
            "10:00",
            "11:00",
            log_event="makeup",
        ))

    if int(agg.get("water_ml_total") or 0) < WATER_TARGET_ML:
        reminders.append(_reminder(
            "water_intake",
            "Su içme zamanı",
            f"Günlük hedef {WATER_TARGET_ML} ml. İçtikçe kaydet.",
            "09:00",
            "21:00",
            log_event="water_intake",
            every_minutes=120,
        ))

    if uv >= SPF_REFRESH_UV_THRESHOLD and int(agg.get("spf_refreshes") or 0) < SPF_REFRESH_MAX_PER_DAY:
        reminders.append(_reminder(
            "spf_refresh",
            "Güneş kremini yenile",
            f"UV {int(uv)}. Dışarıdaysan 2 saatte bir tazele.",
            "11:00",
            "16:00",
            log_event="spf_refresh",
            every_minutes=120,
        ))

    if temperature <= LIP_BALM_MAX_TEMPERATURE or humidity < LIP_BALM_MAX_HUMIDITY:
        reminders.append(_reminder(
            "lip_balm",
            "Dudak balsamı",
            "Soğuk / kuru hava dudak derisini hızlı kurutur.",
            "12:00",
            "13:00",
        ))

    if not agg.get("nutrition_logged"):
        reminders.append(_reminder(
            "nutrition_log",
            "Beslenme kaydı",
            "Bugün abur cubur veya şekerli bir şey yedin mi?",
            "20:00",
            "20:30",
            log_event="nutrition",
        ))

    if makeup.get("used") and not makeup.get("removed"):
        reminders.append(_reminder(
            "makeup_removal",
            "Makyaj temizliği",
            "Makyajlı gün: yağ bazlı temizleyici + ardından jel ile çift temizlik yap.",
            "21:00",
            "23:00",
            log_event="makeup",
        ))

    if not agg.get("routine_evening_done"):
        reminders.append(_reminder(
            "routine_evening",
            "Akşam rutini",
            "Akşam adımlarını uygula ve bitince işaretle.",
            "21:00",
            "23:00",
            log_event="routine_completed_block",
        ))

    if not checkin_done:
        reminders.append(_reminder(
            "daily_checkin",
            "Günlük check-in",
            "Cildin bugün nasıldı? Rutin buna göre uyarlanır.",
            "21:00",
            "22:30",
        ))

    reminders.sort(key=lambda r: r["start"])
    return reminders
