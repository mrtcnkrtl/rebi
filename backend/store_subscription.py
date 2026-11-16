"""
Mağaza abonelikleri (App Store / Google Play, RevenueCat üzerinden).

Akış:
  1. Mobil uygulama RevenueCat'e Supabase kullanıcı kimliğiyle (`app_user_id` = auth.users.id) giriş yapar.
  2. Satın alma, yenileme, iptal, iade… olunca RevenueCat `/webhooks/revenuecat`'e haber verir; satın alma
     sonrası uygulama da `/subscription/sync`'i çağırır.
  3. İkisinde de olayın içeriğine güvenilmez: RevenueCat REST API'den abonenin GÜNCEL hakları çekilir, en üst
     etkin kademe bulunur ve Supabase `app_metadata.rebi_store`'a yazılır. Olaylar sırasız/yinelenmiş gelse
     de sonuç aynıdır.

`app_metadata.rebi_store` = {"tier": "plus"|"pro"|"max", "expires_at_ms": int|None, "product_id": str, "store": str}
Kademe JWT'ye gömülü olduğu için, süre dolduğunda token yenilenene kadar beklenmez: `expires_at_ms` her
istekte kontrol edilir.
"""

from __future__ import annotations

import hmac
import os
import time
from dataclasses import dataclass
from typing import Any, Optional
from urllib.parse import quote

import httpx

from config import get_logger

log = get_logger("store_subscription")

# Küçükten büyüğe. RevenueCat'teki entitlement kimlikleri bunlarla aynıdır.
STORE_TIERS: tuple[str, ...] = ("plus", "pro", "max")

_DEFAULT_DAILY_LIMITS = {"plus": 50, "pro": 80, "max": 120}

# Mağazanın yenilemeyi işlemesi birkaç dakika sürebilir; o arada kullanıcı kilitlenmesin.
_EXPIRY_GRACE_MS = 10 * 60 * 1000


def tier_daily_limits() -> dict[str, int]:
    """`REBI_TIER_DAILY_LIMITS="plus:50,pro:80,max:120"`; eksik/bozuk kademe varsayılana düşer."""
    limits = dict(_DEFAULT_DAILY_LIMITS)
    raw = os.getenv("REBI_TIER_DAILY_LIMITS", "").strip()
    for part in raw.split(","):
        name, _, value = part.partition(":")
        name = name.strip().lower()
        if name not in limits:
            continue
        try:
            limits[name] = max(1, int(value.strip()))
        except ValueError:
            continue
    return limits


def tier_daily_limit(tier: str) -> Optional[int]:
    return tier_daily_limits().get((tier or "").strip().lower())


def _now_ms() -> int:
    return int(time.time() * 1000)


def active_store_tier(app_metadata: dict | None, now_ms: Optional[int] = None) -> Optional[str]:
    """JWT app_metadata'daki mağaza kademesi hâlâ geçerliyse adı; değilse None."""
    info = (app_metadata or {}).get("rebi_store")
    if not isinstance(info, dict):
        return None
    tier = str(info.get("tier") or "").strip().lower()
    if tier not in STORE_TIERS:
        return None
    expires = info.get("expires_at_ms")
    if expires is None:
        return tier  # süresiz (ör. ömür boyu ürün)
    try:
        expires = int(expires)
    except (TypeError, ValueError):
        return None
    now = _now_ms() if now_ms is None else now_ms
    return tier if now < expires + _EXPIRY_GRACE_MS else None


# --- RevenueCat ------------------------------------------------------------------------------------------


@dataclass(frozen=True)
class StoreEntitlement:
    tier: str
    expires_at_ms: Optional[int]
    product_id: str
    store: str

    def as_metadata(self) -> dict[str, Any]:
        return {
            "tier": self.tier,
            "expires_at_ms": self.expires_at_ms,
            "product_id": self.product_id,
            "store": self.store,
        }


def _parse_iso_ms(value: Any) -> Optional[int]:
    if not value:
        return None
    from datetime import datetime

    try:
        return int(datetime.fromisoformat(str(value).replace("Z", "+00:00")).timestamp() * 1000)
    except ValueError:
        return None


def best_entitlement(subscriber: dict, now_ms: Optional[int] = None) -> Optional[StoreEntitlement]:
    """RevenueCat `GET /v1/subscribers/{id}` yanıtındaki `subscriber` nesnesinden en üst etkin kademe."""
    now = _now_ms() if now_ms is None else now_ms
    entitlements = (subscriber or {}).get("entitlements") or {}
    subscriptions = (subscriber or {}).get("subscriptions") or {}
    best: Optional[StoreEntitlement] = None
    for name, ent in entitlements.items():
        tier = str(name).strip().lower()
        if tier not in STORE_TIERS or not isinstance(ent, dict):
            continue
        expires = _parse_iso_ms(ent.get("expires_date"))
        if ent.get("expires_date") and expires is None:
            continue
        if expires is not None and expires + _EXPIRY_GRACE_MS <= now:
            continue
        product_id = str(ent.get("product_identifier") or "")
        store = str((subscriptions.get(product_id) or {}).get("store") or "")
        cand = StoreEntitlement(tier=tier, expires_at_ms=expires, product_id=product_id, store=store)
        if best is None or STORE_TIERS.index(cand.tier) > STORE_TIERS.index(best.tier):
            best = cand
    return best


def revenuecat_secret_key() -> str:
    return os.getenv("REVENUECAT_SECRET_API_KEY", "").strip()


def revenuecat_configured() -> bool:
    return bool(revenuecat_secret_key())


async def fetch_revenuecat_subscriber(app_user_id: str) -> dict:
    key = revenuecat_secret_key()
    if not key:
        raise RuntimeError("REVENUECAT_SECRET_API_KEY tanımlı değil")
    url = f"https://api.revenuecat.com/v1/subscribers/{quote(app_user_id, safe='')}"
    async with httpx.AsyncClient(timeout=15.0) as client:
        r = await client.get(url, headers={"Authorization": f"Bearer {key}", "Accept": "application/json"})
    r.raise_for_status()
    return (r.json() or {}).get("subscriber") or {}


def webhook_authorized(header_value: Optional[str]) -> bool:
    """RevenueCat panelinde webhook için girilen Authorization başlığı (`REVENUECAT_WEBHOOK_AUTH`)."""
    expected = os.getenv("REVENUECAT_WEBHOOK_AUTH", "").strip()
    if not expected:
        return False
    got = (header_value or "").strip()
    if got.lower().startswith("bearer ") and not expected.lower().startswith("bearer "):
        got = got[7:].strip()
    return hmac.compare_digest(got.encode(), expected.encode())


# --- Supabase app_metadata ---------------------------------------------------------------------------


async def write_store_metadata(user_id: str, ent: Optional[StoreEntitlement]) -> None:
    """`app_metadata.rebi_store`'u yazar (GoTrue app_metadata'yı birleştirir; diğer anahtarlar korunur)."""
    from config import SUPABASE_SERVICE_KEY, SUPABASE_URL

    base = (SUPABASE_URL or "").rstrip("/")
    key = (SUPABASE_SERVICE_KEY or "").strip()
    if not base or not key:
        raise RuntimeError("Supabase yapılandırması eksik")
    body = {"app_metadata": {"rebi_store": ent.as_metadata() if ent else None}}
    async with httpx.AsyncClient(timeout=15.0) as client:
        r = await client.put(
            f"{base}/auth/v1/admin/users/{user_id}",
            headers={"apikey": key, "Authorization": f"Bearer {key}"},
            json=body,
        )
    if r.status_code not in (200, 204):
        log.error("app_metadata yazılamadı: status=%s", r.status_code)
        r.raise_for_status()


async def sync_user_from_revenuecat(user_id: str) -> Optional[StoreEntitlement]:
    """RevenueCat'teki güncel durumu Supabase'e yansıtır; yazılan kademeyi döndürür (yoksa None)."""
    subscriber = await fetch_revenuecat_subscriber(user_id)
    ent = best_entitlement(subscriber)
    await write_store_metadata(user_id, ent)
    log.info("Mağaza aboneliği eşitlendi: tier=%s", ent.tier if ent else "none")
    return ent
