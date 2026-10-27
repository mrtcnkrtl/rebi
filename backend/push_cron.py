"""
Hatırlatıcı push dağıtıcısı: `POST /push/dispatch` ucunu düzenli aralıkla çağırır.

docker compose'ta `push-cron` servisi olarak çalışır (sunucuda elle crontab gerekmez):

    python push_cron.py

Ortam değişkenleri:
- `PUSH_DISPATCH_SECRET`  zorunlu; boşsa dağıtıcı kapalı kalır (konteyner çökmez, bir kez bildirir).
- `PUSH_DISPATCH_URL`     varsayılan `http://api:8000/push/dispatch?max_users=20000`
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
import urllib.parse
import urllib.request

DEFAULT_URL = "http://api:8000/push/dispatch?max_users=20000"
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


def describe(result: dict, max_users_hint: int = 20000) -> str:
    if not result.get("push_configured", True):
        return "sunucuda FCM yapılandırılmamış (FCM_SERVICE_ACCOUNT_JSON); gönderim yok"
    text = (
        f"kullanıcı={result.get('users_considered', 0)} "
        f"hatırlatıcı={result.get('reminders_sent', 0)} "
        f"bildirim={result.get('notifications_sent', 0)} "
        f"geçersiz_token={result.get('invalid_tokens_removed', 0)} "
        f"başarısız={result.get('deliveries_failed', 0)}"
    )
    if int(result.get("users_skipped", 0)):
        text += f" atlanan={result['users_skipped']}"
    if result.get("truncated"):
        # Sunucu süre bütçesini aştı ya da max_users'a ulaştı; sonraki tur kaldığı kullanıcıdan devam eder.
        text += " — UYARI: tur yarım kaldı, sonraki tur devam edecek"
    elif int(result.get("users_considered", 0)) >= max_users_hint:
        text += " — UYARI: kullanıcı sınırına ulaşıldı"
    return text


# ── Günlük retention temizliği (güvenlik ağı) ─────────────────────────────────────────────────────
# Süresi dolan verinin silinmesi (docs/DATA_RETENTION.md) normalde Supabase pg_cron ile yapılır. pg_cron kapalıysa
# hiçbir şey silinmez ve fark edilmez. RETENTION_PURGE_DAILY=1 verilirse bu servis günde bir kez API'nin
# /maintenance/purge ucunu çağırır; uç pg_cron aktifse kendiliğinden atlar (çift temizlik olmaz). Varsayılan KAPALI:
# silme işlemi açıkça istenmeden başlamaz.

PURGE_AFTER_UTC_MINUTE = 3 * 60 + 20  # pg_cron'un varsayılan saati (03:20 UTC) ile aynı
PURGE_RETRY_SECONDS = 1800  # başarısız denemeden sonra 30 dk bekle (her 5 dk'da API'yi dövme)


def purge_enabled() -> bool:
    return (os.getenv("RETENTION_PURGE_DAILY") or "").strip().lower() in {"1", "true", "yes", "on"}


def purge_url(dispatch_url: str) -> str:
    """Dağıtım adresinden aynı sunucudaki temizlik ucunun adresini türetir (RETENTION_PURGE_URL ile ezilebilir)."""
    override = (os.getenv("RETENTION_PURGE_URL") or "").strip()
    if override:
        return override
    parts = urllib.parse.urlsplit(dispatch_url)
    return urllib.parse.urlunsplit((parts.scheme, parts.netloc, "/maintenance/purge", "only_if_no_cron=1", ""))


def maybe_purge(now: float, url: str, secret: str, state: dict, opener=urllib.request.urlopen) -> bool:
    """
    Bugünkü temizlik zamanı geldiyse ve henüz başarıyla yapılmadıysa uca bir kez istek atar.
    `state`: {"done_day": "YYYY-MM-DD", "last_attempt": epoch}. Dönüş: istek denendi mi.
    """
    if not purge_enabled():
        return False
    utc = time.gmtime(now)
    today = time.strftime("%Y-%m-%d", utc)
    if state.get("done_day") == today:
        return False
    if utc.tm_hour * 60 + utc.tm_min < PURGE_AFTER_UTC_MINUTE:
        return False
    if now - float(state.get("last_attempt") or 0) < PURGE_RETRY_SECONDS:
        return False
    state["last_attempt"] = now
    result = dispatch_once(purge_url(url), secret, opener)
    if result is not None and result.get("ok"):
        state["done_day"] = today
        log(f"retention temizliği: {result.get('skipped') or result.get('deleted')}")
    else:
        log("retention temizliği başarısız; 30 dk sonra yeniden denenecek")
    return True


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

    purge_state: dict = {}
    if purge_enabled():
        log("retention temizliği açık: günde bir kez (pg_cron aktif değilse) /maintenance/purge çağrılır")

    while True:
        time.sleep(seconds_until_next_tick(time.time(), interval))
        result = dispatch_once(url, secret)
        if result is not None:
            log(describe(result))
        try:
            maybe_purge(time.time(), url, secret, purge_state)
        except Exception as e:  # temizlik hatası bildirim döngüsünü asla durdurmaz
            log(f"retention temizliği hatası: {type(e).__name__}")
        touch_alive()


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(0)
