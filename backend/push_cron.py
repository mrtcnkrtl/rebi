"""
Hatırlatıcı push dağıtıcısı: `POST /push/dispatch` ucunu düzenli aralıkla çağırır.

docker compose'ta `push-cron` servisi olarak çalışır (sunucuda elle crontab gerekmez):

    python push_cron.py

Ortam değişkenleri:
- `PUSH_DISPATCH_SECRET`  zorunlu; boşsa dağıtıcı kapalı kalır (konteyner çökmez, bir kez bildirir).
- `PUSH_DISPATCH_URL`     varsayılan `http://api:8000/push/dispatch?max_users=1000`
- `PUSH_DISPATCH_INTERVAL_SECONDS`  varsayılan 300 (5 dk). Saat başlarına hizalanır
  (:00, :05, :10 …); aynı hatırlatıcı gönderim defteri yüzünden iki kez gitmez.

Bir tur başarısız olursa (ağ, 5xx) bir sonraki turda yeniden denenir; dağıtıcı kendiliğinden durmaz.
Her turun sonunda `ALIVE_FILE` güncellenir: konteyner sağlık denetimi bunu okur.
"""

from __future__ import annotations

import json
import os
import sys
import time
import urllib.error
import urllib.request

DEFAULT_URL = "http://api:8000/push/dispatch?max_users=1000"
DEFAULT_INTERVAL_SECONDS = 300
REQUEST_TIMEOUT_SECONDS = 240
ALIVE_FILE = os.getenv("PUSH_CRON_ALIVE_FILE", "/tmp/push_cron_alive")


def log(message: str) -> None:
    print(f"[push-cron] {time.strftime('%Y-%m-%d %H:%M:%S')} {message}", flush=True)


def seconds_until_next_tick(now: float, interval: int) -> float:
    """Bir sonraki `interval` katına kalan süre; hizalama tam sınırdaysa tam aralık."""
    interval = max(1, int(interval))
    return interval - (now % interval)


def dispatch_once(url: str, secret: str, opener=urllib.request.urlopen) -> dict | None:
    """Tek tur: başarıda yanıt gövdesi, hatada None (hata günlüğe yazılır)."""
    request = urllib.request.Request(
        url, method="POST", data=b"", headers={"X-Push-Dispatch-Token": secret}
    )
    try:
        with opener(request, timeout=REQUEST_TIMEOUT_SECONDS) as response:
            body = json.loads(response.read().decode("utf-8") or "{}")
    except urllib.error.HTTPError as e:
        log(f"dağıtım reddedildi: HTTP {e.code}")
        return None
    except Exception as e:  # ağ, zaman aşımı, bozuk yanıt
        log(f"dağıtım çağrısı başarısız: {type(e).__name__}")
        return None
    return body if isinstance(body, dict) else None


def describe(result: dict, max_users_hint: int = 1000) -> str:
    if not result.get("push_configured", True):
        return "sunucuda FCM yapılandırılmamış (FCM_SERVICE_ACCOUNT_JSON); gönderim yok"
    text = (
        f"kullanıcı={result.get('users_considered', 0)} "
        f"hatırlatıcı={result.get('reminders_sent', 0)} "
        f"bildirim={result.get('notifications_sent', 0)} "
        f"geçersiz_token={result.get('invalid_tokens_removed', 0)} "
        f"başarısız={result.get('deliveries_failed', 0)}"
    )
    if int(result.get("users_considered", 0)) >= max_users_hint:
        text += " — UYARI: kullanıcı sınırına ulaşıldı"
    return text


def touch_alive() -> None:
    try:
        with open(ALIVE_FILE, "a"):
            pass
        os.utime(ALIVE_FILE, None)
    except OSError:
        pass


def main() -> int:
    secret = (os.getenv("PUSH_DISPATCH_SECRET") or "").strip()
    if not secret:
        log("PUSH_DISPATCH_SECRET tanımlı değil; dağıtıcı kapalı. (deploy/.env.api'ye ekleyip yeniden başlatın.)")
        while True:  # konteyner çökme döngüsüne girmesin
            touch_alive()
            time.sleep(600)

    url = os.getenv("PUSH_DISPATCH_URL") or DEFAULT_URL
    interval = int(os.getenv("PUSH_DISPATCH_INTERVAL_SECONDS") or DEFAULT_INTERVAL_SECONDS)
    log(f"başladı: her {interval} sn, {url.split('?')[0]}")

    while True:
        time.sleep(seconds_until_next_tick(time.time(), interval))
        result = dispatch_once(url, secret)
        if result is not None:
            log(describe(result))
        touch_alive()


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(0)
