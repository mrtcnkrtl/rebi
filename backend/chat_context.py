"""
Sohbet için kullanıcının bugünkü durumunun kısa özeti.

Rebi sohbeti "bugün UV 7, SPF'im yeter mi?" gibi sorulara günün verisiyle (hava, su, makyaj,
beslenme, rutin) yanıt verebilsin diye prompt'a eklenir. Özet kısa tutulur, ürün adı ya da
kişisel tanımlayıcı içermez ve yalnızca soruyla ilgiliyse kullanılması söylenir.
"""

from __future__ import annotations

from today_plan import WATER_TARGET_ML

_NUTRITION_LABELS = {
    "snacks": "abur cubur",
    "sweets": "şekerli / tatlı",
    "fried_food": "kızartma / fast food",
    "dairy": "süt ürünü",
    "balanced": "dengeli beslenme",
}

_REMOVAL_LABELS = {
    "double": "çift temizlik",
    "cleanser": "temizleyiciyle",
    "water": "sadece suyla",
    "wipe": "misel su / mendille",
    "none": "temizlenmedi",
}


def _number(value) -> int | None:
    try:
        return int(round(float(value)))
    except (TypeError, ValueError):
        return None


def _weather_part(weather: dict | None) -> str | None:
    if not weather:
        return None
    bits = []
    temperature = _number(weather.get("temperature"))
    uv = _number(weather.get("uv_index"))
    humidity = _number(weather.get("humidity"))
    if temperature is not None:
        bits.append(f"{temperature}°C")
    if uv is not None:
        bits.append(f"UV {uv}")
    if humidity is not None:
        bits.append(f"nem %{humidity}")
    return ("Hava: " + ", ".join(bits)) if bits else None


def _nutrition_part(nutrition: dict | None) -> str | None:
    if not isinstance(nutrition, dict) or not nutrition:
        return None
    picked = [label for key, label in _NUTRITION_LABELS.items() if nutrition.get(key) is True]
    # Eski kayıtlar yalnızca junk_food taşır.
    if not picked and nutrition.get("junk_food") is True:
        picked = [_NUTRITION_LABELS["snacks"]]
    if picked:
        return "Yediği: " + ", ".join(picked)
    if nutrition.get("junk_food") is False:
        return "Abur cubur yemedi"
    return None


def _makeup_part(makeup: dict | None) -> str | None:
    if not isinstance(makeup, dict) or not makeup.get("logged"):
        return None
    if not makeup.get("used"):
        return "Makyaj: yapmadı"
    method = _REMOVAL_LABELS.get(str(makeup.get("removal_method") or ""))
    if makeup.get("removed") and method:
        return f"Makyaj: yaptı, {method}"
    if makeup.get("removal_method") == "none":
        return "Makyaj: yaptı, temizlenmedi"
    return "Makyaj: yaptı, henüz temizlemedi"


def build_today_summary(
    aggregated: dict | None,
    weather: dict | None = None,
    checkin_done: bool = False,
    water_target: int = WATER_TARGET_ML,
) -> str:
    """Bugünün verisinden tek paragraflık özet. Veri yoksa boş metin."""
    agg = aggregated or {}
    parts: list[str | None] = [_weather_part(weather)]

    water = _number(agg.get("water_ml_total")) or 0
    if water > 0:
        parts.append(f"Su: {water}/{water_target} ml")

    spf = _number(agg.get("spf_refreshes")) or 0
    if spf > 0:
        parts.append(f"Güneş kremini {spf} kez yeniledi")

    parts.append(_makeup_part(agg.get("makeup")))
    parts.append(_nutrition_part(agg.get("nutrition")))

    blocks = []
    if agg.get("routine_morning_done"):
        blocks.append("sabah")
    if agg.get("routine_evening_done"):
        blocks.append("akşam")
    if blocks:
        parts.append("Rutin yapıldı: " + " ve ".join(blocks))

    finished = [p.get("product") for p in (agg.get("products_finished") or []) if isinstance(p, dict) and p.get("product")]
    if finished:
        parts.append(f"Bitirdiği ürün sayısı: {len(finished)}")

    if checkin_done:
        parts.append("Bugünkü check-in yapıldı")

    return ". ".join(p for p in parts if p)[:700]
