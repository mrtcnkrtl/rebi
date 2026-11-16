"""
Mağaza kataloğu: sistemin önerdiği maddeler × konsantrasyon bantları → store_products satırları.

Kaynaklar:
  - flow_engine.NEW_ACTIVE_DOSES (onaylı kademeler; bant metni değiştirilmez)
  - ingredient_db.INGREDIENT_DB klasik aktifler (ürün olmayan / reçeteli satırlar elenir)

Satırlar `coming_soon`, fiyatsızdır. `python -m seed_store_catalog` ile Supabase'e upsert edilir;
API boş tabloda da aynı üreticiyi yedek katalog olarak kullanır.
"""

from __future__ import annotations

import re
import sys
from typing import Iterable, Optional

from flow_engine import NEW_ACTIVE_DOSES
from ingredient_db import INGREDIENT_DB
from store import is_valid_slug

# Rutinde yazılan klasik aktifler. Protokol / senaryo anahtarları yok.
CLASSIC_KEYS = (
    "retinol",
    "vitamin_c",
    "niacinamid",
    "salisilik_asit",
    "benzoil_peroksit",
    "hyaluronik_asit",
    "seramidler",
    "azelaik_asit",
    "traneksamik_asit",
    "kojik_asit",
    "alfa_arbutin",
    "centella_panthenol",
    "mineral_spf",
    "cay_agaci",
)

# Ürün SKU'su olmayan konsantrasyon / formül talimatı (klasik DB için).
_NON_PRODUCT_PCT = re.compile(
    r"(?i)(oklüzif|ince tabaka|^\+HA$|^serum$|reçeteli|Tretinoin|Adapalen|"
    r"Bakuchiol|FIRST LINE|alternans|nokta tedavi|oral|mg/gün|"
    r"Gece gündüz|Çoklu mol|veya BP|\+|Bisabolol|ZORUNLU|"
    r"jel$|tonik$|kısa temas)"
)

_TR_SLUG = str.maketrans(
    {
        "ç": "c",
        "ğ": "g",
        "ı": "i",
        "ö": "o",
        "ş": "s",
        "ü": "u",
        "Ç": "c",
        "Ğ": "g",
        "İ": "i",
        "Ö": "o",
        "Ş": "s",
        "Ü": "u",
        "α": "a",
    }
)

_DISPLAY = {
    "retinol": ("Retinol", "Retinol"),
    "vitamin_c": ("C vitamini", "Vitamin C"),
    "niacinamid": ("Niasinamid", "Niacinamide"),
    "salisilik_asit": ("Salisilik asit", "Salicylic acid"),
    "benzoil_peroksit": ("Benzoil peroksit", "Benzoyl peroxide"),
    "hyaluronik_asit": ("Hyaluronik asit", "Hyaluronic acid"),
    "seramidler": ("Seramidler", "Ceramides"),
    "azelaik_asit": ("Azelaik asit", "Azelaic acid"),
    "traneksamik_asit": ("Traneksamik asit", "Tranexamic acid"),
    "kojik_asit": ("Kojik asit", "Kojic acid"),
    "alfa_arbutin": ("Alfa arbutin", "Alpha-arbutin"),
    "centella_panthenol": ("Panthenol / Centella", "Panthenol / Centella"),
    "mineral_spf": ("Güneş kremi", "Sunscreen"),
    "cay_agaci": ("Çay ağacı yağı", "Tea tree oil"),
    "licorice": ("Meyan (glabridin)", "Licorice (glabridin)"),
    "green_tea": ("Yeşil çay / EGCG", "Green tea / EGCG"),
    "hexylresorcinol": ("Heksilresorsinol", "Hexylresorcinol"),
    "mandelic": ("Mandelik asit", "Mandelic acid"),
    "pha": ("PHA (glukonolakton)", "PHA (gluconolactone)"),
    "sulfur": ("Sülfür", "Sulfur"),
    "nag": ("N-asetil glukozamin", "N-acetyl glucosamine"),
    "caffeine_eye": ("Kafein (göz altı)", "Caffeine (undereye)"),
    "dimethicone": ("Dimetikon", "Dimethicone"),
    "gla": ("GLA (hodan)", "GLA (borage)"),
    "linoleic": ("Linoleik asit", "Linoleic acid"),
    "undereye_vitc": ("C vitamini (göz altı)", "Vitamin C (undereye)"),
    "undereye_niacinamide": ("Niasinamid (göz altı)", "Niacinamide (undereye)"),
    "spf_mineral": ("Güneş kremi", "Sunscreen"),
    "spf_chemical": ("Güneş kremi", "Sunscreen"),
    "spf_hybrid": ("Güneş kremi", "Sunscreen"),
    "spf_tinted": ("Güneş kremi", "Sunscreen"),
}

_STEP = {
    "retinol": 20,
    "vitamin_c": 25,
    "niacinamid": 20,
    "salisilik_asit": 20,
    "benzoil_peroksit": 20,
    "hyaluronik_asit": 25,
    "seramidler": 30,
    "azelaik_asit": 20,
    "traneksamik_asit": 20,
    "kojik_asit": 20,
    "alfa_arbutin": 20,
    "centella_panthenol": 25,
    "mineral_spf": 40,
    "cay_agaci": 20,
    "licorice": 20,
    "green_tea": 20,
    "hexylresorcinol": 20,
    "mandelic": 20,
    "pha": 20,
    "sulfur": 20,
    "nag": 20,
    "caffeine_eye": 22,
    "dimethicone": 30,
    "gla": 30,
    "linoleic": 30,
    "undereye_vitc": 22,
    "undereye_niacinamide": 22,
    "spf_mineral": 40,
    "spf_chemical": 40,
    "spf_hybrid": 40,
    "spf_tinted": 40,
}

_TYPE = {
    "mineral_spf": "sunscreen",
    "spf_mineral": "sunscreen",
    "spf_chemical": "sunscreen",
    "spf_hybrid": "sunscreen",
    "spf_tinted": "sunscreen",
    "seramidler": "moisturizer",
    "dimethicone": "moisturizer",
    "gla": "moisturizer",
    "linoleic": "moisturizer",
    "centella_panthenol": "moisturizer",
    "hyaluronik_asit": "serum",
}

# Görsel aileleri (frontend/public/store/*.svg) ve sorun etiketleri.
_VISUAL = {
    "retinol": "serum",
    "vitamin_c": "brightening",
    "niacinamid": "serum",
    "salisilik_asit": "acid",
    "benzoil_peroksit": "acid",
    "hyaluronik_asit": "serum",
    "seramidler": "barrier",
    "azelaik_asit": "acid",
    "traneksamik_asit": "brightening",
    "kojik_asit": "brightening",
    "alfa_arbutin": "brightening",
    "centella_panthenol": "barrier",
    "mineral_spf": "sunscreen",
    "cay_agaci": "acid",
    "licorice": "brightening",
    "green_tea": "serum",
    "hexylresorcinol": "brightening",
    "mandelic": "acid",
    "pha": "acid",
    "sulfur": "acid",
    "nag": "brightening",
    "caffeine_eye": "eye",
    "dimethicone": "barrier",
    "gla": "barrier",
    "linoleic": "barrier",
    "undereye_vitc": "eye",
    "undereye_niacinamide": "eye",
    "spf_mineral": "sunscreen",
    "spf_chemical": "sunscreen",
    "spf_hybrid": "sunscreen",
    "spf_tinted": "sunscreen",
}

_CONCERNS = {
    "retinol": ("aging",),
    "vitamin_c": ("aging", "pigmentation"),
    "niacinamid": ("acne", "aging", "sensitivity"),
    "salisilik_asit": ("acne",),
    "benzoil_peroksit": ("acne",),
    "hyaluronik_asit": ("dryness",),
    "seramidler": ("dryness", "sensitivity"),
    "azelaik_asit": ("acne", "pigmentation"),
    "traneksamik_asit": ("pigmentation",),
    "kojik_asit": ("pigmentation",),
    "alfa_arbutin": ("pigmentation",),
    "centella_panthenol": ("sensitivity", "dryness"),
    "mineral_spf": ("aging", "pigmentation"),
    "cay_agaci": ("acne",),
    "licorice": ("pigmentation",),
    "green_tea": ("acne", "sensitivity"),
    "hexylresorcinol": ("pigmentation",),
    "mandelic": ("pigmentation", "aging"),
    "pha": ("aging", "sensitivity"),
    "sulfur": ("acne",),
    "nag": ("pigmentation",),
    "caffeine_eye": ("undereye",),
    "dimethicone": ("dryness", "sensitivity"),
    "gla": ("dryness",),
    "linoleic": ("dryness", "acne"),
    "undereye_vitc": ("undereye", "pigmentation"),
    "undereye_niacinamide": ("undereye",),
    "spf_mineral": ("aging", "pigmentation", "sensitivity"),
    "spf_chemical": ("aging", "pigmentation"),
    "spf_hybrid": ("aging", "pigmentation"),
    "spf_tinted": ("pigmentation", "aging"),
}


def visual_for(dose_key: str, product_type: str | None = None) -> str:
    if dose_key in _VISUAL:
        return _VISUAL[dose_key]
    if product_type == "sunscreen":
        return "sunscreen"
    if product_type == "moisturizer":
        return "barrier"
    return "serum"


def concerns_for(dose_key: str) -> list[str]:
    return list(_CONCERNS.get(dose_key) or ())


def image_for(dose_key: str, product_type: str | None, name_tr: str) -> list[dict]:
    visual = visual_for(dose_key, product_type)
    return [{
        "url": f"/store/{visual}.svg",
        "alt_tr": name_tr,
        "alt_en": name_tr,
        "visual": visual,
    }]



def slugify_pct(pct: str) -> str:
    """Konsantrasyon etiketini slug parçasına çevirir."""
    s = pct.strip().lower().translate(_TR_SLUG)
    s = s.replace("%", "").replace("–", "-").replace("—", "-")
    s = re.sub(r"[^a-z0-9]+", "-", s)
    s = re.sub(r"-+", "-", s).strip("-")
    return (s or "band")[:48]


def make_slug(dose_key: str, pct: str) -> str:
    key = dose_key.replace("_", "-")
    slug = f"{key}-{slugify_pct(pct)}"
    return slug[:80]


def _names(dose_key: str) -> tuple[str, str]:
    return _DISPLAY.get(dose_key, (dose_key.replace("_", " ").title(), dose_key.replace("_", " ").title()))


def _row(
    *,
    dose_key: str,
    pct: str,
    usage_tr: Optional[str] = None,
    usage_en: Optional[str] = None,
    sort_order: int = 100,
    product_type: Optional[str] = None,
    step_order: Optional[int] = None,
) -> Optional[dict]:
    name_tr, name_en = _names(dose_key)
    slug = make_slug(dose_key, pct)
    if not is_valid_slug(slug):
        return None
    ptype = product_type or _TYPE.get(dose_key, "serum")
    step = step_order if step_order is not None else _STEP.get(dose_key)
    full_tr = f"{name_tr} · {pct}"
    full_en = f"{name_en} · {pct}"
    concerns = concerns_for(dose_key)
    visual = visual_for(dose_key, ptype)
    return {
        "slug": slug,
        "name_tr": full_tr,
        "name_en": full_en,
        "summary_tr": f"{name_tr} · {pct}. Yakında.",
        "summary_en": f"{name_en} · {pct}. Coming soon.",
        "description_tr": (
            f"{name_tr} konsantrasyon bandı: {pct}. "
            "Dermokozmetik ürün; satış açıldığında fiyat burada görünür."
        ),
        "description_en": (
            f"{name_en} concentration band: {pct}. "
            "Dermocosmetic product; price appears here when sales open."
        ),
        "usage_tr": usage_tr,
        "usage_en": usage_en,
        "inci": None,
        "size_label": pct,
        "product_type": ptype,
        "step_order": step,
        "ingredient_ids": [],
        "price_minor": None,
        "currency": "TRY",
        "vat_rate": None,
        "images": image_for(dose_key, ptype, full_tr),
        "status": "coming_soon",
        "in_stock": True,
        "sort_order": sort_order,
        "external_ref": {"dose_key": dose_key, "pct": pct, "concerns": concerns, "visual": visual},
    }


def _uniq_pcts(items: Iterable[tuple[str, Optional[str], Optional[str]]]) -> list[tuple[str, Optional[str], Optional[str]]]:
    seen: set[str] = set()
    out: list[tuple[str, Optional[str], Optional[str]]] = []
    for pct, utr, uen in items:
        p = (pct or "").strip()
        if not p or p in seen:
            continue
        seen.add(p)
        out.append((p, utr, uen))
    return out


def _from_new_actives() -> list[dict]:
    rows: list[dict] = []
    order = 10
    for key, meta in NEW_ACTIVE_DOSES.items():
        if not isinstance(meta, dict):
            continue
        if key == "spf_filter":
            options = meta.get("options") or {}
            labels = {
                "mineral": ("Mineral filtre", "Mineral filter"),
                "chemical": ("Kimyasal filtre", "Chemical filter"),
                "hybrid": ("Hibrit filtre", "Hybrid filter"),
                "tinted": ("Renkli mineral filtre", "Tinted mineral filter"),
            }
            for opt_key, opt in options.items():
                if not isinstance(opt, dict):
                    continue
                tr_lbl, en_lbl = labels.get(opt_key, (opt_key, opt_key))
                info = str(opt.get("info") or "").strip() or None
                detail = str(opt.get("text") or "").strip()
                dose_key = f"spf_{opt_key}"
                row = _row(
                    dose_key=dose_key,
                    pct=tr_lbl,
                    usage_tr=info,
                    usage_en=info,
                    sort_order=order,
                    product_type="sunscreen",
                    step_order=40,
                )
                if row:
                    row["name_en"] = f"Sunscreen · {en_lbl}"
                    if detail:
                        row["description_tr"] = detail + (f" {info}" if info else "")
                        row["description_en"] = detail + (f" {info}" if info else "")
                    rows.append(row)
                    order += 1
            continue
        if key == "barrier":
            for component in ("dimethicone", "gla", "linoleic"):
                bands = meta.get(component) or {}
                if not isinstance(bands, dict):
                    continue
                for pct, _, _ in _uniq_pcts((str(v), None, None) for v in bands.values()):
                    row = _row(dose_key=component, pct=pct, sort_order=order, product_type="moisturizer", step_order=30)
                    if row:
                        rows.append(row)
                        order += 1
            continue
        tiers = meta.get("tiers") or {}
        if not isinstance(tiers, dict):
            continue
        bands = []
        for tier_meta in tiers.values():
            if not isinstance(tier_meta, dict):
                continue
            pct = tier_meta.get("pct")
            freq = tier_meta.get("freq")
            warning = tier_meta.get("warning")
            usage_parts = [str(freq).strip()] if freq else []
            if warning:
                usage_parts.append(str(warning).strip())
            usage = " ".join(usage_parts) if usage_parts else None
            bands.append((str(pct) if pct else "", usage, usage))
        for pct, utr, uen in _uniq_pcts(bands):
            row = _row(dose_key=key, pct=pct, usage_tr=utr, usage_en=uen, sort_order=order)
            if row:
                rows.append(row)
                order += 1
    return rows


def _from_classic() -> list[dict]:
    rows: list[dict] = []
    order = 500
    for key in CLASSIC_KEYS:
        ing = INGREDIENT_DB.get(key) or {}
        concs = ing.get("concentrations") or {}
        if not isinstance(concs, dict):
            continue
        bands = []
        for ctx, meta in concs.items():
            if not isinstance(meta, dict):
                continue
            pct = str(meta.get("pct") or "").strip()
            if not pct or _NON_PRODUCT_PCT.search(pct):
                continue
            freq = meta.get("freq")
            time = meta.get("time")
            usage = " · ".join(p for p in (freq, time) if p) or None
            bands.append((pct, usage, usage))
        for pct, utr, uen in _uniq_pcts(bands):
            row = _row(dose_key=key, pct=pct, usage_tr=utr, usage_en=uen, sort_order=order)
            if row:
                rows.append(row)
                order += 1
    return rows


def build_catalog_rows() -> list[dict]:
    """Vitrin için tüm coming_soon satırlar; slug tekildir."""
    by_slug: dict[str, dict] = {}
    for row in _from_new_actives() + _from_classic():
        by_slug[row["slug"]] = row
    return sorted(by_slug.values(), key=lambda r: (r.get("sort_order", 100), r.get("name_tr") or ""))


def catalog_pcts_for(dose_key: str) -> list[str]:
    """Test: bir maddenin katalogdaki konsantrasyon etiketleri."""
    return [
        (r.get("external_ref") or {}).get("pct")
        for r in build_catalog_rows()
        if (r.get("external_ref") or {}).get("dose_key") == dose_key
    ]


def upsert_catalog(supabase) -> int:
    """Supabase'e slug üzerinden upsert. Dönüş: yazılan satır sayısı."""
    rows = build_catalog_rows()
    if not rows or supabase is None:
        return 0
    # Yönetim alanları dahil; istemciye açılmaz.
    payload = [{k: v for k, v in row.items()} for row in rows]
    supabase.table("store_products").upsert(payload, on_conflict="slug").execute()
    return len(payload)


def main(argv: list[str] | None = None) -> int:
    argv = list(sys.argv[1:] if argv is None else argv)
    if "--print" in argv:
        rows = build_catalog_rows()
        print(f"{len(rows)} ürün")
        for r in rows:
            print(f"  {r['slug']}: {r['name_tr']}")
        return 0
    from supabase_client import get_shared_client

    sb = get_shared_client()
    if not sb:
        print("Supabase yapılandırılmamış", file=sys.stderr)
        return 1
    n = upsert_catalog(sb)
    print(f"{n} ürün yazıldı")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
