import httpx
from config import OPENWEATHER_API_KEY, get_logger

log = get_logger("weather")

FALLBACK = {
    "humidity": 50,
    "uv_index": 3,
    "temperature": 20,
    "description": "Varsayılan değerler",
}


async def fetch_weather(lat: float, lon: float) -> dict:
    """Fetch current weather from Open-Meteo (free, no key needed) with
    OpenWeatherMap as optional upgrade."""

    # Try Open-Meteo first (completely free, no API key)
    try:
        url = "https://api.open-meteo.com/v1/forecast"
        params = {
            "latitude": lat,
            "longitude": lon,
            "current": "temperature_2m,relative_humidity_2m,weather_code",
            "daily": "uv_index_max",
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
        log.info("Open-Meteo OK: %s°C, UV %s, nem %%%s", result["temperature"], result["uv_index"], result["humidity"])
        return result

    except Exception as e:
        log.warning("Open-Meteo hatası: %s — fallback deneniyor", e)

    # Fallback: OpenWeatherMap (if key is available)
    if OPENWEATHER_API_KEY:
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
            log.info("OpenWeatherMap OK: %s°C, UV %s", result["temperature"], result["uv_index"])
            return result
        except Exception as e:
            log.warning("OpenWeatherMap hatası: %s", e)

    log.warning("Tüm hava servisleri başarısız, varsayılan değerler kullanılıyor")
    return FALLBACK


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
