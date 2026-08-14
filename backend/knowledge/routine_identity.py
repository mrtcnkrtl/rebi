"""
Single join key between the routine engine, check-in, and the canonical cabinet.

Routine steps are written as Turkish sentences. This module stamps
`canonical_ingredient_ids` from phrases the engine itself generates, then
check-in and the active plan read those ids — not a second dictionary.
"""

from __future__ import annotations

from typing import Any, Optional

from knowledge.entity_resolver import normalize

# Phrases that appear in engine-written `action` lines (longest first).
# This is the write-time identity: we authored these strings.
_OWNED_PHRASES: tuple[tuple[str, str], ...] = (
    ("palmitoyl pentapeptide", "palmitoyl_pentapeptide_4"),
    ("traneksamik asit", "traneksamik_asit"),
    ("tranexamic acid", "traneksamik_asit"),
    ("l-askorbik asit", "vitamin_c"),
    ("ascorbic acid", "vitamin_c"),
    ("hyaluronik asit", "hyaluronik_asit"),
    ("sodyum hyalüronat", "hyaluronik_asit"),
    ("sodium hyaluronate", "hyaluronik_asit"),
    ("kolloidal yulaf", "colloidal_oatmeal"),
    ("demir oksit", "iron_oxides"),
    ("iron oxide", "iron_oxides"),
    ("cinko oksit", "zinc_oxide"),
    ("zinc oxide", "zinc_oxide"),
    ("benzoil peroksit", "benzoil_peroksit"),
    ("benzoyl peroxide", "benzoil_peroksit"),
    ("salisilik asit", "salisilik_asit"),
    ("salicylic acid", "salisilik_asit"),
    ("glikolik asit", "glycolic_acid"),
    ("glycolic acid", "glycolic_acid"),
    ("azelaik asit", "azelaik_asit"),
    ("azelaic acid", "azelaik_asit"),
    ("alfa-arbutin", "alfa_arbutin"),
    ("alpha-arbutin", "alfa_arbutin"),
    ("niasinamid", "niacinamid"),
    ("niacinamide", "niacinamid"),
    ("bakuchiol", "bakuchiol"),
    ("seramid", "seramidler"),
    ("ceramide", "seramidler"),
    ("skualan", "squalane"),
    ("squalane", "squalane"),
    ("kolesterol", "cholesterol"),
    ("gliserin", "glycerin"),
    ("glycerin", "glycerin"),
    ("panthenol", "centella_panthenol"),
    ("pantenol", "centella_panthenol"),
    ("centella", "centella_panthenol"),
    ("tokoferol", "vitamin_e"),
    ("ferulik", "ferulic_acid"),
    ("retinol", "retinol"),
    ("c vitamini", "vitamin_c"),
    ("petrolatum", "petrolatum"),
    ("vazelin", "petrolatum"),
    ("spf", "mineral_spf"),
    ("urea", "urea"),
    ("üre", "urea"),
)

OWNED_PHRASES: tuple[tuple[str, str], ...] = tuple(
    sorted(
        ((normalize(p), iid) for p, iid in _OWNED_PHRASES),
        key=lambda x: len(x[0]),
        reverse=True,
    )
)

# Check-in behaviour per canonical id.
# pause = stop on irritasyon/kirik; reduce = lower frequency; barrier = increase.
BEHAVIOR: dict[str, str] = {
    "retinol": "pause",
    "salisilik_asit": "pause",
    "benzoil_peroksit": "pause",
    "glycolic_acid": "pause",
    "lactic_acid": "pause",
    "malic_acid": "pause",
    "pha": "pause",
    "hidrokinon": "pause",
    "urea": "pause",
    "bakuchiol": "reduce",
    "azelaik_asit": "reduce",
    "alfa_arbutin": "reduce",
    "traneksamik_asit": "reduce",
    "kojik_asit": "reduce",
    "vitamin_c": "reduce",
    "seramidler": "barrier",
    "petrolatum": "barrier",
    "cholesterol": "barrier",
    "glycerin": "barrier",
    "hyaluronik_asit": "barrier",
    "squalane": "barrier",
    "colloidal_oatmeal": "barrier",
    "centella_panthenol": "barrier",
    "aloe_vera": "barrier",
    "allantoin": "barrier",
    "shea_butter": "barrier",
    "beeswax": "barrier",
    "niacinamid": "maintain",
    "mineral_spf": "maintain",
    "chemical_spf": "maintain",
    "zinc_oxide": "maintain",
    "iron_oxides": "maintain",
    "vitamin_e": "maintain",
    "palmitoyl_pentapeptide_4": "maintain",
}

# Tolerance family keys used by flow_engine / active_rules.
TOLERANCE_FAMILY: dict[str, str] = {
    "retinol": "retinol",
    "salisilik_asit": "bha",
    "benzoil_peroksit": "benzoyl",
    "glycolic_acid": "aha",
    "lactic_acid": "aha",
    "malic_acid": "aha",
    "pha": "aha",
    "azelaik_asit": "azelaic",
    "vitamin_c": "vitamin_c",
    "urea": "urea",
    "alfa_arbutin": "pigment",
    "traneksamik_asit": "pigment",
    "kojik_asit": "pigment",
    "hidrokinon": "pigment",
}

PREGNANCY_UNSAFE_IDS = frozenset(
    {
        "retinol",
        "salisilik_asit",
        "benzoil_peroksit",
        "glycolic_acid",
        "hidrokinon",
        "traneksamik_asit",
    }
)

SPF_IDS = frozenset({"mineral_spf", "chemical_spf", "zinc_oxide", "titanium_dioxide", "iron_oxides"})

_TRIGGERS = {
    "pause": {
        "irritasyon": {"action": "pause", "days": 3, "note": "Tahrişte bu aktifi 3 gün duraklat; bariyer öne alınır."},
        "kirik": {"action": "pause", "days": 2, "note": "Bariyer hasarında aktif durur."},
        "kuru": {"action": "reduce", "freq_multiplier": 0.5, "note": "Kurulukta sıklık yarıya iner."},
    },
    "reduce": {
        "irritasyon": {"action": "reduce", "freq_multiplier": 0.5, "note": "Tahrişte sıklık düşürülür."},
        "kirik": {"action": "pause", "days": 2, "note": "Bariyer hasarında ara ver."},
        "kuru": {"action": "reduce", "freq_multiplier": 0.5, "note": "Kurulukta sıklık düşürülür."},
    },
    "barrier": {
        "irritasyon": {"action": "increase", "note": "Tahrişte bariyer katmanı öne alınır."},
        "kirik": {"action": "increase", "note": "Hasarda nem ve oklüzyon artırılır."},
        "kuru": {"action": "increase", "note": "Kurulukta nem katmanı artırılır."},
    },
}


def _is_moisturizer_row(item: dict) -> bool:
    if item.get("category") not in ("Bakım", "Koruma"):
        return False
    so = item.get("step_order")
    if so in (30, 35):
        return True
    a = normalize(item.get("action") or "")
    return any(k in a for k in ("nemlendirici", "bariyer", "seramid")) and "spf" not in a


def stamp_canonical_ids(items: list[dict]) -> int:
    """Merge engine-owned action phrases into canonical_ingredient_ids. Returns stamped rows."""
    n = 0
    for it in items or []:
        if not isinstance(it, dict):
            continue
        if it.get("category") not in ("Bakım", "Koruma"):
            continue
        text = normalize(it.get("action") or "")
        if len(text) < 3:
            continue
        found: list[str] = []
        for phrase, iid in OWNED_PHRASES:
            if phrase and phrase in text and iid not in found:
                found.append(iid)
        if not found:
            continue
        existing = [str(x) for x in (it.get("canonical_ingredient_ids") or [])]
        merged = list(dict.fromkeys([*existing, *found]))
        if merged != existing:
            n += 1
        it["canonical_ingredient_ids"] = merged
        it["identity_stamped"] = True
    return n


def trigger_for_item(item: dict, skin_feeling: str) -> Optional[dict]:
    """
    Check-in action from stamped ids. Combined moisturizer+keratolytic rows
    follow barrier behaviour so a night cream with urea is not paused as an acid.
    """
    ids = [str(x) for x in (item.get("canonical_ingredient_ids") or [])]
    if not ids:
        return None
    feeling = (skin_feeling or "").strip().lower()
    behaviors = [BEHAVIOR.get(i, "maintain") for i in ids]
    if _is_moisturizer_row(item) and "barrier" in behaviors:
        table = _TRIGGERS["barrier"]
        return table.get(feeling) or {"action": "maintain", "note": "Değişiklik gerekmiyor"}
    if "pause" in behaviors:
        table = _TRIGGERS["pause"]
        return table.get(feeling) or {"action": "maintain", "note": "Değişiklik gerekmiyor"}
    if "reduce" in behaviors:
        table = _TRIGGERS["reduce"]
        return table.get(feeling) or {"action": "maintain", "note": "Değişiklik gerekmiyor"}
    if "barrier" in behaviors:
        table = _TRIGGERS["barrier"]
        return table.get(feeling) or {"action": "maintain", "note": "Değişiklik gerekmiyor"}
    return {"action": "maintain", "note": "Değişiklik gerekmiyor"}


def _when_from_tod(tod: str, iid: str) -> str:
    t = (tod or "").upper()
    if iid in SPF_IDS:
        return "morning"
    if "AM" in t and "PM" in t:
        return "morning_or_evening"
    if "AM" in t or "SABAH" in t:
        return "morning"
    if "PM" in t or "AKŞAM" in t or "AKSAM" in t:
        return "evening"
    return "evening" if BEHAVIOR.get(iid) in ("pause", "reduce") else "morning_or_evening"


def build_cabinet_active_plan(
    concern_slug: str,
    items: list[dict],
    *,
    is_pregnant: bool = False,
    avoided_families: Optional[set] = None,
) -> list[dict]:
    """
    Active plan = canonical supports (priority 1–2) that are actually in the
    routine, minus pregnancy and tolerance bans. SPF is kept whenever a SPF step exists.
    """
    from knowledge.cabinet_router import chain_actives_for_concern, tag_items_with_canonical_ids

    stamp_canonical_ids(items)
    tag_items_with_canonical_ids(items)
    present: set[str] = set()
    has_spf = False
    for it in items or []:
        for cid in it.get("canonical_ingredient_ids") or []:
            present.add(str(cid))
        a = normalize(it.get("action") or "")
        if "spf" in a or "gunes koruyucu" in a:
            has_spf = True
            present.update(SPF_IDS & present)
            present.add("mineral_spf")

    avoided = {str(x).lower() for x in (avoided_families or set())}
    out: list[dict] = []
    seen: set[str] = set()
    for link in chain_actives_for_concern(concern_slug, limit=12):
        if (link.get("effect_status") or "supports") != "supports":
            continue
        iid = str(link.get("ingredient_id") or "").strip()
        if not iid or iid in seen:
            continue
        try:
            pr = int(link.get("priority") or 4)
        except (TypeError, ValueError):
            pr = 4
        if pr > 2:
            continue
        if is_pregnant and iid in PREGNANCY_UNSAFE_IDS:
            continue
        fam = TOLERANCE_FAMILY.get(iid)
        if fam and fam in avoided:
            continue
        in_routine = iid in present or (iid in SPF_IDS and has_spf)
        if not in_routine:
            continue
        seen.add(iid)
        out.append(
            {
                "active": iid,
                "name_tr": link.get("name_tr") or iid,
                "family": fam,
                "role": "spf" if iid in SPF_IDS else "active",
                "recommended": True,
                "when": _when_from_tod(str(link.get("time_of_day") or ""), iid),
                "priority": pr,
                "why_tr": (link.get("notes_tr") or "").strip()
                or f"{link.get('name_tr') or iid} bu şikâyetin kanonik zincirinde.",
                "why_en": "",
                "notes_tr": "",
                "notes_en": "",
                "in_routine": True,
            }
        )
    if has_spf and not any(r["active"] in SPF_IDS for r in out):
        out.insert(
            0,
            {
                "active": "mineral_spf",
                "name_tr": "Güneş filtresi",
                "family": None,
                "role": "spf",
                "recommended": True,
                "when": "morning",
                "priority": 1,
                "why_tr": "Her sabah rutininin son adımı; leke ve yaşlanma yönetiminin temeli.",
                "why_en": "",
                "notes_tr": "",
                "notes_en": "",
                "in_routine": True,
            },
        )
    return out
