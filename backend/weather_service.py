import threading
import time

import httpx
from config import OPENWEATHER_API_KEY, get_logger

log = get_logger("weather")

# Sağlayıcıya yapılan her çağrı sayılır ve günlüğe `weather_call ...` satırı olarak yazılır. Open-Meteo ücretli
# planı ayda çağrı sayısıyla ölçülür (Standard 1 milyon); gerçek hacim bu satırlardan okunur:
#   docker compose logs api | grep -c weather_call
_totals: dict[str, dict[str, int]] = {}
_totals_lock = threading.Lock()


def _record_call(provider: str, ok: bool, started: float) -> None:
    with _totals_lock:
        t = _totals.setdefault(provider, {"calls": 0, "failures": 0})
        t["calls"] += 1
        if not ok:
            t["failures"] += 1
    log.info("weather_call provider=%s ok=%d ms=%d", provider, 1 if ok else 0, int((time.perf_counter() - started) * 1000))


def usage_snapshot() -> dict[str, dict[str, int]]:
    """Süreç başlangıcından beri sağlayıcı başına çağrı ve hata sayısı."""
    with _totals_lock:
        return {k: dict(v) for k, v in _totals.items()}


def reset_usage() -> None:
    with _totals_lock:
        _totals.clear()

FALLBACK = {
    "humidity": 50,
    "uv_index": 3,
    "temperature": 20,
    "description": "Varsayılan değerler",
}


async def fetch_weather(lat: float, lon: float) -> dict:
    """Hava durumu; hiçbir kaynak yanıt vermezse varsayılan değerler (her zaman dict)."""
    return await fetch_weather_live(lat, lon) or dict(FALLBACK)


async def fetch_weather_live(lat: float, lon: float) -> dict | None:
    """Fetch current weather from Open-Meteo (free, no key needed) with
    OpenWeatherMap as optional upgrade. Hiçbir kaynak yanıt vermezse None:
    çağıran, varsayılan değeri gerçek hava gibi saklamamalı."""

    # Try Open-Meteo first (completely free, no API key)
    started = time.perf_counter()
    try:
        url = "https://api.open-meteo.com/v1/forecast"
        params = {
            "latitude": lat,
            "longitude": lon,
            "current": "temperature_2m,relative_humidity_2m,weather_code",
            "daily": "uv_index_max",
            "hourly": "uv_index",
            "timezone": "auto",
            "forecast_days": 1,
        }
        async with httpx.AsyncClient(timeout=8.0) as client:
            resp = await client.get(url, params=params)
            resp.raise_for_status()
            data = resp.json()

        current = data.get("current", {})
        daily = data.get("daily", {})

        result = {
            "humidity": current.get("relative_humidity_2m", 50),
            "uv_index": round(daily.get("uv_index_max", [3])[0]),
            "temperature": round(current.get("temperature_2m", 20)),
            "description": _weather_code_to_text(current.get("weather_code", 0)),
        }
        # Saatlik UV (günün yüksek UV aralığı ve şu anki değer): kaynak vermezse alanlar hiç eklenmez.
        try:
            hourly = data.get("hourly", {})
            window = uv_window(hourly.get("time"), hourly.get("uv_index"))
            now_uv = uv_at(current.get("time"), hourly.get("time"), hourly.get("uv_index"))
        except Exception as e:  # bozuk saatlik veri anlık hava bilgisini düşürmesin
            log.warning("Saatlik UV okunamadı: %s", type(e).__name__)
            window, now_uv = None, None
        if window:
            result["uv_window"] = window
        if now_uv is not None:
            result["uv_now"] = now_uv
        _record_call("open-meteo", True, started)
        log.info("Open-Meteo OK: %s°C, UV %s, nem %%%s", result["temperature"], result["uv_index"], result["humidity"])
        return result

    except Exception as e:
        _record_call("open-meteo", False, started)
        log.warning("Open-Meteo hatası: %s — fallback deneniyor", e)

    # Fallback: OpenWeatherMap (if key is available)
    if OPENWEATHER_API_KEY:
        started = time.perf_counter()
        try:
            base_url = "https://api.openweathermap.org/data/3.0/onecall"
            params = {
                "lat": lat, "lon": lon,
                "appid": OPENWEATHER_API_KEY,
                "units": "metric",
                "exclude": "minutely,hourly,daily,alerts",
            }
            async with httpx.AsyncClient(timeout=10.0) as client:
                resp = await client.get(base_url, params=params)
                resp.raise_for_status()
                data = resp.json()

            c = data.get("current", {})
            result = {
                "humidity": c.get("humidity", 50),
                "uv_index": round(c.get("uvi", 3)),
                "temperature": round(c.get("temp", 20)),
                "description": c.get("weather", [{}])[0].get("description", "bilinmiyor"),
            }
            _record_call("openweather", True, started)
            log.info("OpenWeatherMap OK: %s°C, UV %s", result["temperature"], result["uv_index"])
            return result
        except Exception as e:
            _record_call("openweather", False, started)
            log.warning("OpenWeatherMap hatası: %s", e)

    log.warning("Tüm hava servisleri başarısız")
    return None


# Güneş kremi tazelemesinin gerektiği UV eşiği (`today_plan.SPF_REFRESH_UV_THRESHOLD` ile aynı).
UV_WINDOW_THRESHOLD = 5


def _hhmm(iso: str) -> str:
    """`"2026-10-16T11:00"` → `"11:00"`."""
    return str(iso).split("T", 1)[1][:5]


def uv_window(times, values, threshold: float = UV_WINDOW_THRESHOLD) -> dict | None:
    """
    Günün yüksek UV aralığı: UV'nin eşiğe ulaştığı, en yüksek saati içeren kesintisiz saatler.
    `{"start": "11:00", "end": "16:00", "peak": "13:00", "max": 6}`; gün boyu eşiğin altındaysa None.
    Saatler konumun yerel duvar saatidir (hatırlatıcı saatleriyle aynı biçim); `end` son yüksek saatin sonudur.
    """
    if not times or not values or len(times) != len(values):
        return None
    uv = [float(v or 0) for v in values]
    peak = max(range(len(uv)), key=lambda i: uv[i])
    if uv[peak] < threshold:
        return None
    first = last = peak
    while first > 0 and uv[first - 1] >= threshold:
        first -= 1
    while last < len(uv) - 1 and uv[last + 1] >= threshold:
        last += 1
    end_hour = (int(_hhmm(times[last])[:2]) + 1) % 24
    return {
        "start": _hhmm(times[first]),
        "end": f"{end_hour:02d}:00" if end_hour else "23:59",
        "peak": _hhmm(times[peak]),
        "max": round(uv[peak]),
    }


def uv_at(current_time, times, values):
    """`current_time` saatindeki UV (yuvarlak); veri yoksa None."""
    if not current_time or not times or not values:
        return None
    hour = str(current_time).split("T", 1)[1][:2]
    for t, v in zip(times, values):
        if _hhmm(t)[:2] == hour:
            return round(float(v or 0))
    return None


def _weather_code_to_text(code: int) -> str:
    """WMO weather code to Turkish description."""
    mapping = {
        0: "Açık", 1: "Çoğunlukla açık", 2: "Parçalı bulutlu", 3: "Bulutlu",
        45: "Sisli", 48: "Kırağılı sis",
        51: "Hafif çisenti", 53: "Orta çisenti", 55: "Yoğun çisenti",
        61: "Hafif yağmur", 63: "Orta yağmur", 65: "Şiddetli yağmur",
        71: "Hafif kar", 73: "Orta kar", 75: "Şiddetli kar",
        80: "Hafif sağanak", 81: "Orta sağanak", 82: "Şiddetli sağanak",
        95: "Gök gürültülü fırtına",
    }
    return mapping.get(code, "Bilinmiyor")
