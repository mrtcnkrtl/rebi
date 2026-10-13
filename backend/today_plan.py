"""
Ana ekran planı: bugünün havasına göre ne kullanılacak ve hangi saat
aralıklarında hatırlatılacak.

Saatler yerel duvar saatidir ("07:30"); bildirimleri istemci kendi saat
diliminde kurar. Sunucu yalnızca planı üretir, bildirim göndermez.

Hatırlatıcı pencereleri kullanıcının gün düzenine (uyanma ve uyku saati) bağlıdır;
varsayılan düzen (07:30 / 23:00) eski sabit pencerelerle birebir aynıdır.
"""

from __future__ import annotations

import re

from flow_engine import SKIN_TYPE_PROFILES, compute_environment_branches

# Günlük su hedefi (ml). Hatırlatıcı bu hedefe ulaşılınca susar.
WATER_TARGET_ML = 2000

# Güneş kremi tazelemesi bu UV değerinden itibaren hatırlatılır.
SPF_REFRESH_UV_THRESHOLD = 5
SPF_REFRESH_MAX_PER_DAY = 2

# Dudak balsamı: soğuk veya kuru havada.
LIP_BALM_MAX_TEMPERATURE = 10
LIP_BALM_MAX_HUMIDITY = 35

# ── Kullanıcı ayarları ──────────────────────────────────────────────────────

# Hatırlatıcı kimliği → kullanıcının açıp kapatabildiği kategori.
REMINDER_CATEGORIES: dict[str, str] = {
    "routine_morning": "routine",
    "routine_evening": "routine",
    "water_intake": "water",
    "makeup_log": "makeup",
    "makeup_removal": "makeup",
    "nutrition_log": "nutrition",
    "spf_refresh": "spf",
    "lip_balm": "lip_balm",
    "daily_checkin": "checkin",
}
CATEGORY_NAMES = tuple(dict.fromkeys(REMINDER_CATEGORIES.values()))

WATER_INTERVAL_CHOICES = (60, 90, 120, 180)

# En erken uyanma ve en geç uyku saati; arası en az bu kadar olmalı (pencereler sığsın).
EARLIEST_WAKE_MINUTES = 4 * 60
LATEST_SLEEP_MINUTES = 23 * 60 + 59
MIN_AWAKE_MINUTES = 9 * 60

DEFAULT_REMINDER_SETTINGS: dict = {
    "wake_time": "07:30",
    "sleep_time": "23:00",
    "water_every_minutes": 120,
    "enabled": {name: True for name in CATEGORY_NAMES},
}

_HHMM = re.compile(r"^(\d{1,2}):(\d{2})$")


def parse_hhmm(value) -> int | None:
    """`"07:30"` → 450; biçim ya da aralık bozuksa None."""
    match = _HHMM.match(str(value or "").strip())
    if not match:
        return None
    hours, minutes = int(match.group(1)), int(match.group(2))
    if hours > 23 or minutes > 59:
        return None
    return hours * 60 + minutes


def format_hhmm(minutes: int) -> str:
    minutes = max(0, min(24 * 60 - 1, int(minutes)))
    return f"{minutes // 60:02d}:{minutes % 60:02d}"


def day_span_is_valid(wake_minutes: int, sleep_minutes: int) -> bool:
    return (
        wake_minutes >= EARLIEST_WAKE_MINUTES
        and sleep_minutes <= LATEST_SLEEP_MINUTES
        and sleep_minutes - wake_minutes >= MIN_AWAKE_MINUTES
    )


def normalize_reminder_settings(raw) -> dict:
    """
    Kayıtlı ya da eksik ayarlardan her zaman geçerli bir ayar sözlüğü üretir.
    Bozuk alan varsayılana döner; uyanma/uyku saati tutarsızsa ikisi birden varsayılan olur.
    """
    source = raw if isinstance(raw, dict) else {}
    defaults = DEFAULT_REMINDER_SETTINGS

    wake = parse_hhmm(source.get("wake_time"))
    sleep = parse_hhmm(source.get("sleep_time"))
    if wake is None or sleep is None or not day_span_is_valid(wake, sleep):
        wake = parse_hhmm(defaults["wake_time"])
        sleep = parse_hhmm(defaults["sleep_time"])

    every = source.get("water_every_minutes")
    if isinstance(every, bool) or every not in WATER_INTERVAL_CHOICES:
        every = defaults["water_every_minutes"]

    stored_enabled = source.get("enabled") if isinstance(source.get("enabled"), dict) else {}
    enabled = {
        name: stored_enabled[name] if isinstance(stored_enabled.get(name), bool) else True
        for name in CATEGORY_NAMES
    }
    return {
        "wake_time": format_hhmm(wake),
        "sleep_time": format_hhmm(sleep),
        "water_every_minutes": every,
        "enabled": enabled,
    }


# Uyanma (wake) ya da uyku (sleep) saatine göre pencere: (çapa, başlangıç, bitiş) dakika farkı.
# 07:30 / 23:00 için sonuç eski sabit pencerelerdir (07:30–09:30, 10:00–11:00, …).
_WINDOW_OFFSETS: dict[str, tuple[str, int, int]] = {
    "routine_morning": ("wake", 0, 120),
    "makeup_log": ("wake", 150, 210),
    "spf_refresh": ("wake", 210, 510),
    "lip_balm": ("wake", 270, 330),
    "routine_evening": ("sleep", -120, 0),
    "makeup_removal": ("sleep", -120, 0),
    "nutrition_log": ("sleep", -180, -150),
    "daily_checkin": ("sleep", -120, -30),
}


def reminder_windows(settings: dict | None = None) -> dict[str, tuple[str, str]]:
    """Hatırlatıcı kimliği → (başlangıç, bitiş) yerel saat penceresi."""
    s = normalize_reminder_settings(settings)
    wake = parse_hhmm(s["wake_time"])
    sleep = parse_hhmm(s["sleep_time"])
    anchors = {"wake": wake, "sleep": sleep}

    windows: dict[str, tuple[str, str]] = {}
    for reminder_id, (anchor, start_offset, end_offset) in _WINDOW_OFFSETS.items():
        base = anchors[anchor]
        start = max(wake, min(sleep, base + start_offset))
        end = max(wake, min(sleep, base + end_offset))
        windows[reminder_id] = (format_hhmm(start), format_hhmm(end))
    windows["water_intake"] = (format_hhmm(wake + 90), format_hhmm(sleep - 120))
    return windows


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


def build_reminders(
    weather: dict,
    aggregated: dict,
    checkin_done: bool = False,
    settings: dict | None = None,
) -> list[dict]:
    """
    Bugün için saat aralıklı hatırlatıcılar; yapılan işler listeden düşer.
    `settings`: kullanıcının gün düzeni ve kapattığı kategoriler (yoksa varsayılan).
    """
    w = weather or {}
    agg = aggregated or {}
    s = normalize_reminder_settings(settings)
    windows = reminder_windows(s)
    enabled = s["enabled"]
    uv = float(w.get("uv_index", 3) or 0)
    humidity = float(w.get("humidity", 50) or 0)
    temperature = float(w.get("temperature", 20) or 0)

    makeup = agg.get("makeup") or {}
    reminders: list[dict] = []

    def add(reminder_id: str, title: str, body: str, log_event: str | None = None, every_minutes: int | None = None):
        if not enabled.get(REMINDER_CATEGORIES[reminder_id], True):
            return
        start, end = windows[reminder_id]
        reminders.append(_reminder(reminder_id, title, body, start, end, log_event, every_minutes))

    if not agg.get("routine_morning_done"):
        add(
            "routine_morning",
            "Sabah rutini",
            "Bugünün sabah adımlarını uygula ve bitince işaretle.",
            log_event="routine_completed_block",
        )

    if not makeup.get("logged"):
        add(
            "makeup_log",
            "Bugün makyaj yaptın mı?",
            "Makyaj yaptıysan akşam temizliği planına eklenir.",
            log_event="makeup",
        )

    if int(agg.get("water_ml_total") or 0) < WATER_TARGET_ML:
        add(
            "water_intake",
            "Su içme zamanı",
            f"Günlük hedef {WATER_TARGET_ML} ml. İçtikçe kaydet.",
            log_event="water_intake",
            every_minutes=s["water_every_minutes"],
        )

    if uv >= SPF_REFRESH_UV_THRESHOLD and int(agg.get("spf_refreshes") or 0) < SPF_REFRESH_MAX_PER_DAY:
        add(
            "spf_refresh",
            "Güneş kremini yenile",
            f"UV {int(uv)}. Dışarıdaysan 2 saatte bir tazele.",
            log_event="spf_refresh",
            every_minutes=120,
        )

    if temperature <= LIP_BALM_MAX_TEMPERATURE or humidity < LIP_BALM_MAX_HUMIDITY:
        add(
            "lip_balm",
            "Dudak balsamı",
            "Soğuk / kuru hava dudak derisini hızlı kurutur.",
        )

    if not agg.get("nutrition_logged"):
        add(
            "nutrition_log",
            "Beslenme kaydı",
            "Bugün abur cubur veya şekerli bir şey yedin mi?",
            log_event="nutrition",
        )

    if makeup.get("used") and not makeup.get("removed"):
        add(
            "makeup_removal",
            "Makyaj temizliği",
            "Makyajlı gün: yağ bazlı temizleyici + ardından jel ile çift temizlik yap.",
            log_event="makeup",
        )

    if not agg.get("routine_evening_done"):
        add(
            "routine_evening",
            "Akşam rutini",
            "Akşam adımlarını uygula ve bitince işaretle.",
            log_event="routine_completed_block",
        )

    if not checkin_done:
        add(
            "daily_checkin",
            "Günlük check-in",
            "Cildin bugün nasıldı? Rutin buna göre uyarlanır.",
        )

    reminders.sort(key=lambda r: r["start"])
    return reminders


def _to_minutes(hhmm: str) -> int:
    hours, _, minutes = str(hhmm).partition(":")
    return int(hours) * 60 + int(minutes)


def _slots(reminder: dict) -> list[int]:
    """Hatırlatıcının pencere içindeki gönderim dakikaları."""
    start = _to_minutes(reminder["start"])
    end = _to_minutes(reminder["end"])
    every = reminder.get("every_minutes")
    if not every:
        return [start]
    return list(range(start, end + 1, int(every)))


def due_reminders(reminders: list[dict], local_time: str, tolerance_minutes: int = 10) -> list[dict]:
    """
    Verilen yerel saatte gönderilmesi gereken hatırlatıcılar.

    `tolerance_minutes` dağıtıcının çalışma aralığıdır: cron 10 dakikada bir
    çalışıyorsa saatini kaçırmış hatırlatıcı da bu pencerede yakalanır.
    `slot` alanı aynı hatırlatıcının aynı pencerede tekrar gönderilmemesi için
    defter anahtarı olarak kullanılır.
    """
    now = _to_minutes(local_time)
    due = []
    for reminder in reminders or []:
        for slot in _slots(reminder):
            if 0 <= now - slot < tolerance_minutes:
                due.append({**reminder, "slot": f"{slot // 60:02d}:{slot % 60:02d}"})
                break
    return due
