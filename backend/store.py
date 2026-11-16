"""
Ürün mağazası: katalog görünümü, sepet doğrulama ve ödeme bağdaştırıcısı.

Ürünler `store_products` tablosunda durur. Sepet istemcide tutulur ve yalnız ürün kodu + adet taşır; fiyat her
zaman buradan, sunucudaki katalogdan okunur. Ödeme ve sipariş, seçilecek ticaret altyapısına bırakılmıştır:
`CommerceProvider` sözleşmesini uygulayan bir bağdaştırıcı kaydedilip `STORE_COMMERCE_PROVIDER` ile seçilene
kadar mağaza "satışa kapalı" çalışır; vitrin ve sepet görünür, sipariş başlatılamaz.
"""

from __future__ import annotations

import os
import re
from dataclasses import dataclass
from typing import Callable, Optional, Protocol

VISIBLE_STATUSES = ("coming_soon", "active")
MAX_CART_LINES = 20
MAX_QUANTITY = 10

_SLUG_RE = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
# Site içerik güvenlik politikası yalnız kendi alan adından ve Supabase depolamadan görsel yükler.
_IMAGE_URL_RE = re.compile(r"^(/[A-Za-z0-9_\-./%]+|https://[a-z0-9-]+\.supabase\.co/[^\s\"'<>]+)$")

_TEXT_FIELDS = (
    "name_tr",
    "name_en",
    "summary_tr",
    "summary_en",
    "description_tr",
    "description_en",
    "usage_tr",
    "usage_en",
    "inci",
    "size_label",
)


def is_valid_slug(value: object) -> bool:
    return isinstance(value, str) and len(value) <= 80 and bool(_SLUG_RE.match(value))


def _price_minor(row: dict) -> Optional[int]:
    value = row.get("price_minor")
    if isinstance(value, bool) or not isinstance(value, int) or value <= 0:
        return None
    return value


def is_purchasable(row: dict) -> bool:
    """Satışta, fiyatı açıklanmış ve stokta olan ürün sepete eklenebilir."""
    return row.get("status") == "active" and _price_minor(row) is not None and row.get("in_stock") is not False


def _images(row: dict) -> list[dict]:
    out: list[dict] = []
    for item in row.get("images") or []:
        if not isinstance(item, dict):
            continue
        url = str(item.get("url") or "").strip()
        if not _IMAGE_URL_RE.match(url):
            continue
        out.append({
            "url": url,
            "alt_tr": str(item.get("alt_tr") or "").strip()[:200],
            "alt_en": str(item.get("alt_en") or "").strip()[:200],
        })
    return out[:8]


def public_product(row: dict) -> dict:
    """İstemciye giden ürün kaydı. Yönetim alanları (`external_ref`, `id`) dışarı çıkmaz."""
    step = row.get("step_order")
    ingredients = row.get("ingredient_ids")
    ref = row.get("external_ref") if isinstance(row.get("external_ref"), dict) else {}
    dose_key = str(ref.get("dose_key") or "").strip() or None
    concerns = [str(c) for c in (ref.get("concerns") or []) if c]
    visual = str(ref.get("visual") or "").strip() or None
    images = _images(row)
    if dose_key and (not concerns or not visual or not images):
        try:
            from seed_store_catalog import concerns_for, image_for, visual_for

            if not concerns:
                concerns = concerns_for(dose_key)
            if not visual:
                visual = visual_for(dose_key, row.get("product_type"))
            if not images:
                images = image_for(dose_key, row.get("product_type"), str(row.get("name_tr") or dose_key))
        except Exception:
            pass
    if not visual and images:
        url = str(images[0].get("url") or "")
        if "/store/" in url and url.endswith(".svg"):
            visual = url.rsplit("/", 1)[-1][:-4] if url.endswith(".svg") else None
    out = {field: (str(row.get(field)).strip() if row.get(field) else None) for field in _TEXT_FIELDS}
    out.update({
        "slug": row.get("slug"),
        "product_type": row.get("product_type") or "other",
        "step_order": step if isinstance(step, int) and not isinstance(step, bool) else None,
        "ingredient_ids": [str(i) for i in ingredients if i] if isinstance(ingredients, list) else [],
        "dose_key": dose_key,
        "concerns": concerns,
        "visual": visual,
        "price_minor": _price_minor(row),
        "currency": row.get("currency") or "TRY",
        "images": images,
        "status": row.get("status"),
        "in_stock": row.get("in_stock") is not False,
        "purchasable": is_purchasable(row),
    })
    return out


def visible_products(rows: list[dict]) -> list[dict]:
    """Vitrinde görünen ürünler, sıralı. Taslak ve arşiv kayıtları dışarı çıkmaz."""
    shown = [r for r in rows or [] if r.get("status") in VISIBLE_STATUSES and is_valid_slug(r.get("slug"))]
    shown.sort(key=lambda r: (r.get("sort_order") if isinstance(r.get("sort_order"), int) else 100, str(r.get("name_tr") or "")))
    return [public_product(r) for r in shown]


def normalize_cart(items: object) -> list[tuple[str, int]]:
    """
    İstemciden gelen sepet: `[{"slug", "quantity"}]`. Aynı ürün tek satırda toplanır, adet 1..MAX_QUANTITY
    aralığına çekilir; bozuk satırlar atılır. Satır sayısı MAX_CART_LINES ile sınırlıdır.
    """
    merged: dict[str, int] = {}
    for item in items if isinstance(items, list) else []:
        if not isinstance(item, dict):
            continue
        slug = item.get("slug")
        quantity = item.get("quantity")
        if not is_valid_slug(slug) or isinstance(quantity, bool) or not isinstance(quantity, int) or quantity < 1:
            continue
        if slug not in merged and len(merged) >= MAX_CART_LINES:
            continue
        merged[slug] = min(MAX_QUANTITY, merged.get(slug, 0) + quantity)
    return list(merged.items())


def quote_cart(items: object, rows: list[dict]) -> dict:
    """
    Sepeti katalogla karşılaştırır. Satın alınabilen satırlar güncel fiyatla `lines` içinde, katalogda
    bulunmayan ya da şu an satın alınamayan ürünler `unavailable` içinde döner.
    """
    by_slug = {r.get("slug"): r for r in rows or [] if r.get("status") in VISIBLE_STATUSES}
    lines: list[dict] = []
    unavailable: list[str] = []
    currency = "TRY"
    for slug, quantity in normalize_cart(items):
        row = by_slug.get(slug)
        if not row or not is_purchasable(row):
            unavailable.append(slug)
            continue
        unit = _price_minor(row) or 0
        currency = row.get("currency") or currency
        images = _images(row)
        lines.append({
            "slug": slug,
            "name_tr": row.get("name_tr"),
            "name_en": row.get("name_en"),
            "size_label": row.get("size_label"),
            "image": images[0] if images else None,
            "quantity": quantity,
            "unit_price_minor": unit,
            "line_total_minor": unit * quantity,
        })
    return {
        "lines": lines,
        "unavailable": unavailable,
        "subtotal_minor": sum(line["line_total_minor"] for line in lines),
        "currency": currency,
    }


# ── Ödeme bağdaştırıcısı ────────────────────────────────────────────────────────────────────────────────────


@dataclass(frozen=True)
class CheckoutLine:
    slug: str
    name: str
    quantity: int
    unit_price_minor: int
    external_ref: dict


class CommerceProvider(Protocol):
    """Ticaret altyapısı bağdaştırıcısı: sepetten bir ödeme oturumu açar ve yönlendirme adresini döndürür."""

    name: str

    def create_checkout(
        self, lines: list[CheckoutLine], *, currency: str, user_id: Optional[str], return_url: str
    ) -> str: ...


_PROVIDERS: dict[str, Callable[[], CommerceProvider]] = {}


def register_provider(name: str, factory: Callable[[], CommerceProvider]) -> None:
    _PROVIDERS[name.strip().lower()] = factory


def get_provider() -> Optional[CommerceProvider]:
    """`STORE_COMMERCE_PROVIDER` kayıtlı bir bağdaştırıcıyı gösteriyorsa onu, aksi halde None döndürür."""
    factory = _PROVIDERS.get((os.getenv("STORE_COMMERCE_PROVIDER") or "").strip().lower())
    return factory() if factory else None


def store_open() -> bool:
    return get_provider() is not None


def checkout_lines(quote: dict, rows: list[dict]) -> list[CheckoutLine]:
    by_slug = {r.get("slug"): r for r in rows or []}
    out: list[CheckoutLine] = []
    for line in quote.get("lines") or []:
        row = by_slug.get(line["slug"]) or {}
        ref = row.get("external_ref")
        out.append(
            CheckoutLine(
                slug=line["slug"],
                name=str(line.get("name_tr") or line["slug"]),
                quantity=int(line["quantity"]),
                unit_price_minor=int(line["unit_price_minor"]),
                external_ref=ref if isinstance(ref, dict) else {},
            )
        )
    return out


def is_safe_redirect(url: object) -> bool:
    """Ödeme sayfası yalnız https adresine açılır."""
    return isinstance(url, str) and url.startswith("https://") and len(url) <= 2000 and not re.search(r"\s", url)


def filter_products(
    products: list[dict],
    *,
    step_order: Optional[int] = None,
    product_type: Optional[str] = None,
    concern: Optional[str] = None,
    step_band: Optional[str] = None,
    q: Optional[str] = None,
) -> list[dict]:
    """Vitrin listesini sorun, rutin bandı, tür ve metin aramasıyla daraltır."""
    out = list(products)
    if isinstance(step_order, int) and not isinstance(step_order, bool):
        out = [p for p in out if p.get("step_order") == step_order]
    if product_type:
        want = str(product_type).strip().lower()
        out = [p for p in out if str(p.get("product_type") or "").lower() == want]
    if concern:
        want_c = str(concern).strip().lower()
        out = [p for p in out if want_c in [str(c).lower() for c in (p.get("concerns") or [])]]
    if step_band:
        band = str(step_band).strip().lower()
        # 10 temizlik, 20–28 serum/aktif, 30 nem, 40 SPF
        def in_band(step: object) -> bool:
            if not isinstance(step, int) or isinstance(step, bool):
                return False
            if band == "cleanse":
                return step <= 15
            if band == "treat":
                return 16 <= step <= 28
            if band == "moisturize":
                return 29 <= step <= 35
            if band == "spf":
                return step >= 36
            return True

        out = [p for p in out if in_band(p.get("step_order"))]
    needle = (q or "").strip().casefold()
    if needle:
        out = [
            p
            for p in out
            if needle in " ".join(
                str(p.get(k) or "") for k in ("name_tr", "name_en", "summary_tr", "summary_en", "size_label", "slug", "dose_key")
            ).casefold()
        ]
    return out


def _norm_match(text: object) -> str:
    return re.sub(r"\s+", " ", str(text or "").casefold()).strip()


def match_shelf_product(shelf_name: object, step_order: object, products: list[dict]) -> Optional[dict]:
    """
    Rafım serbest metin ürününü vitrin SKU'suna yaklaştırır.
    Önce aynı step_order adayları; isimde size_label veya madde adı geçiyorsa eşleşir.
    """
    name = _norm_match(shelf_name)
    if not name or not products:
        return None
    step = step_order if isinstance(step_order, int) and not isinstance(step_order, bool) else None
    pool = [p for p in products if step is None or p.get("step_order") == step] or list(products)
    scored: list[tuple[int, dict]] = []
    for p in pool:
        label = _norm_match(p.get("size_label"))
        name_tr = _norm_match(p.get("name_tr"))
        # "Niasinamid · %5" → madde kısmı
        base = name_tr.split("·", 1)[0].strip() if "·" in name_tr else name_tr
        score = 0
        if label and label in name:
            score += 3
        if base and (base in name or any(tok and tok in name for tok in base.replace("/", " ").split() if len(tok) > 3)):
            score += 2
        if step is not None and p.get("step_order") == step:
            score += 1
        if score >= 3:
            scored.append((score, p))
    if not scored:
        return None
    scored.sort(key=lambda t: (-t[0], t[1].get("sort_order") if isinstance(t[1].get("sort_order"), int) else 100))
    return scored[0][1]
