"""
Rafım: "ürün bitti" olarak işaretlenen ve henüz yenisi alınmayan ürünler.

Durum ayrı bir tabloda tutulmaz; gün içi olaylardan (`product_finished`, `product_restocked`) türetilir:
bir ürünün son olayı "bitti" ise rafta bitmiş sayılır, "aldım" ise değildir. Böylece web/mobil, çevrimdışı
kuyruk ve geri alma aynı kuralla çalışır ve eski olaylar da (daha önce yazılmış `product_finished`) doğrudan
Rafım'a yansır.
"""

from __future__ import annotations

from datetime import date

FINISHED = "product_finished"
RESTOCKED = "product_restocked"
SHELF_EVENT_TYPES = (FINISHED, RESTOCKED)

# Kullanıcının günlük olay saklama süresi (400 gün) içinde, makul bir geriye bakış.
SHELF_LOOKBACK_DAYS = 365
MAX_PRODUCTS_OUT = 50

# Ürün bittikten kaç gün sonra tek seferlik "yenisini aldın mı?" hatırlatılır.
RESTOCK_REMINDER_DAYS = 3

_MAX_NAME_LEN = 120


def product_name(payload: dict | None) -> str:
    """Olay yükündeki ürün adı (kırpılmış); yoksa boş metin."""
    return str((payload or {}).get("product") or "").strip()[:_MAX_NAME_LEN]


def product_key(name: str) -> str:
    """Aynı ürünü eşleştirmek için: büyük/küçük harf ve fazla boşluk fark yaratmaz."""
    return " ".join(str(name or "").split()).casefold()


def _step_order(payload: dict | None):
    value = (payload or {}).get("step_order")
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    return int(value)


def _days_since(log_date, today: date) -> int:
    try:
        return max(0, (today - date.fromisoformat(str(log_date)[:10])).days)
    except ValueError:
        return 0


def derive_products_out(events: list[dict], today: date) -> list[dict]:
    """
    Olaylar zaman sırasıyla verilir (eskiden yeniye). Dönen liste en son biten üstte olacak şekilde
    `{"product", "step_order", "finished_at", "log_date", "days_out"}` kayıtlarıdır.
    """
    out: dict[str, dict] = {}
    for event in events or []:
        kind = event.get("type")
        payload = event.get("payload") or {}
        name = product_name(payload)
        key = product_key(name)
        if not key:
            continue
        if kind == FINISHED:
            # Zaten bitmişse ilk bitiş tarihi korunur (aynı ürün iki kez işaretlenmiş olabilir).
            out.setdefault(
                key,
                {
                    "product": name,
                    "step_order": _step_order(payload),
                    "finished_at": str(event.get("event_time") or ""),
                    "log_date": str(event.get("log_date") or "")[:10],
                },
            )
        elif kind == RESTOCKED:
            out.pop(key, None)

    items = sorted(out.values(), key=lambda item: item["finished_at"], reverse=True)[:MAX_PRODUCTS_OUT]
    return [{**item, "days_out": _days_since(item["log_date"], today)} for item in items]


def restock_due(products_out: list[dict] | None) -> list[dict]:
    """Tam olarak [`RESTOCK_REMINDER_DAYS`] gün önce bitenler: hatırlatma yalnızca o gün çıkar (her gün tekrarlamaz)."""
    return [p for p in products_out or [] if int(p.get("days_out") or 0) == RESTOCK_REMINDER_DAYS]
