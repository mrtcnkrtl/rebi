"""
Birden fazla cilt sorunu: şiddeti yüksek olanla başla, diğerlerini
kötüleştirmeden ekle. Ürün değil etken; doz ve sıklık skora göre değişir.
"""

from __future__ import annotations

from typing import Any, Optional

ALLOWED_CONCERNS = (
    "acne",
    "pigmentation",
    "dryness",
    "aging",
    "pores",
    "oiliness",
    "sensitivity",
    "general",
)

# Eşit şiddette: inflamatuvar / leke / bariyer, yağ-gözenekten önce.
_TIE_BREAK = {cid: i for i, cid in enumerate(ALLOWED_CONCERNS)}

_MAX_SECONDARY_ADDS = 2


def score_band(score: int) -> str:
    if score <= 3:
        return "hafif"
    if score <= 6:
        return "orta"
    return "şiddetli"


def normalize_concern_entries(
    *,
    concern: str,
    severity_score: int,
    acne_zones: Optional[list] = None,
    concerns: Optional[list] = None,
) -> list[dict]:
    """İstemci listesi veya eski tek `concern` alanından tek biçim."""
    out: list[dict] = []
    seen: set[str] = set()
    raw = concerns if concerns else None
    if raw:
        for item in raw:
            if not isinstance(item, dict):
                continue
            cid = str(item.get("id") or "").strip().lower()
            if cid not in ALLOWED_CONCERNS or cid in seen:
                continue
            try:
                raw_sc = item.get("severity_score")
                if raw_sc is None:
                    raw_sc = item.get("score")
                sc = int(raw_sc if raw_sc is not None else 5)
            except (TypeError, ValueError):
                sc = 5
            zones = item.get("zones") or []
            if not isinstance(zones, list):
                zones = []
            zones = [str(z).strip() for z in zones if str(z).strip()][:12]
            rec = {"id": cid, "score": max(0, min(10, sc)), "zones": zones}
            from concern_history import attach_timeline_fields

            attach_timeline_fields(rec, item)
            out.append(rec)
            seen.add(cid)
    if not out:
        cid = str(concern or "general").strip().lower()
        if cid not in ALLOWED_CONCERNS:
            cid = "general"
        zones = [str(z).strip() for z in (acne_zones or []) if str(z).strip()][:12]
        rec = {"id": cid, "score": max(0, min(10, int(severity_score or 5))), "zones": zones}
        from concern_history import attach_timeline_fields

        attach_timeline_fields(rec)
        out.append(rec)
    return out


def rank_concerns(entries: list[dict]) -> list[dict]:
    """En yüksek şiddet önce. Eşitlikte klinik tie-break."""
    return sorted(
        entries,
        key=lambda e: (-int(e.get("score") or 0), _TIE_BREAK.get(e.get("id"), 99)),
    )


def build_guards(
    ranked: list[dict],
    *,
    stings_with_products: bool = False,
    skin_type_key: str = "normal",
) -> dict[str, Any]:
    """Seçilen TÜM sorunlar birbirini kötüleştirmesin diye tavan/yasak."""
    by_id = {e["id"]: int(e["score"]) for e in ranked}
    ids = set(by_id)

    avoid_aha = False
    avoid_bpo = False
    avoid_retinol = False
    max_bha_pct = 2.0
    max_bha_nights = 4
    max_retinol = "0.5"
    avoid_heavy_occlusive = False
    force_starter = False
    prefer_azelaic = False
    min_spf = 30
    notes: list[str] = []

    if "sensitivity" in ids:
        s = by_id["sensitivity"]
        avoid_aha = True
        prefer_azelaic = True
        force_starter = True
        max_bha_pct = min(max_bha_pct, 1.0)
        max_bha_nights = min(max_bha_nights, 2)
        max_retinol = "0.1-0.3"
        notes.append("hassasiyet: asit/BPO tavanı düşürüldü")
        if s >= 5 or stings_with_products:
            avoid_bpo = True
            notes.append("hassasiyet: tam yüz BPO yok")
        if s >= 7 or stings_with_products:
            avoid_retinol = True
            notes.append("hassasiyet: retinol bu planda yok")

    if "dryness" in ids:
        d = by_id["dryness"]
        if d >= 5:
            max_bha_pct = min(max_bha_pct, 1.0)
            max_bha_nights = min(max_bha_nights, 2)
            notes.append("kuruluk: BHA seyreltildi")
        if d >= 6:
            avoid_bpo = True
            notes.append("kuruluk: BPO yok (kurutmasın)")

    if ("acne" in ids or "oiliness" in ids or "pores" in ids) and by_id.get("dryness", 0) < 7:
        avoid_heavy_occlusive = True

    if "pigmentation" in ids:
        min_spf = 50
        notes.append("leke: SPF 50 taban")

    if skin_type_key == "sensitive":
        force_starter = True
        max_bha_pct = min(max_bha_pct, 1.0)
        avoid_aha = True

    if stings_with_products:
        force_starter = True
        avoid_bpo = True
        avoid_aha = True

    return {
        "avoid_aha": avoid_aha,
        "avoid_bpo": avoid_bpo,
        "avoid_retinol": avoid_retinol,
        "max_bha_pct": max_bha_pct,
        "max_bha_nights": max_bha_nights,
        "max_retinol": max_retinol,
        "avoid_heavy_occlusive": avoid_heavy_occlusive,
        "force_starter": force_starter,
        "prefer_azelaic": prefer_azelaic,
        "min_spf": min_spf,
        "notes": notes,
        "by_id": by_id,
    }


def cap_bha(pct: float, nights: int, guards: dict) -> tuple[float, int]:
    pct = min(float(pct), float(guards.get("max_bha_pct") or 2))
    nights = min(int(nights), int(guards.get("max_bha_nights") or 7))
    nights = max(1, nights)
    if pct < 0.5:
        pct = 0.5
    return pct, nights


def bha_for_acne(score: int, guards: dict) -> tuple[float, int]:
    if score <= 3:
        pct, n = 1.0, 2
    elif score <= 6:
        pct, n = 2.0, 3
    else:
        pct, n = 2.0, 4
    return cap_bha(pct, n, guards)


def bha_for_pores(score: int, guards: dict) -> tuple[float, int]:
    """Komedon tıkacı: hafifte bile BHA çekirdek, akne BPO'suz."""
    if score <= 3:
        pct, n = 0.5, 2
    elif score <= 6:
        pct, n = 1.0, 3
    else:
        pct, n = 2.0, 3
    return cap_bha(pct, n, guards)


def bha_for_oiliness(score: int, guards: dict) -> tuple[Optional[float], int]:
    """Sebum: düşük şiddette BHA yok; yalnızca parlama yüksekse düşük doz."""
    if score < 5:
        return None, 0
    if score <= 7:
        pct, n = 0.5, 2
    else:
        pct, n = 1.0, 2
    return cap_bha(pct, n, guards)


def _blob(items: list[dict]) -> str:
    return " ".join(str(i.get("action") or "") for i in items).lower()


def add_secondary_actives(
    items: list[dict],
    secondaries: list[dict],
    guards: dict,
    age_group: dict,
) -> list[dict]:
    """
    İkincil sorunlar: birincinin iskeletine 1-2 destek katmanı.
    Aynı etken ailesini tekrar ekleme; tavanları guards belirler.
    """
    added = 0
    for entry in secondaries:
        if added >= _MAX_SECONDARY_ADDS:
            break
        cid = entry["id"]
        score = int(entry["score"])
        if cid in ("general", "sensitivity"):
            continue
        blob = _blob(items)
        extra = _secondary_item(cid, score, blob, guards, age_group)
        if extra:
            extra.setdefault("concern_role", f"support_{cid}")
            extra.setdefault("priority", 3)
            items.append(extra)
            added += 1
    return items


def _secondary_item(
    cid: str,
    score: int,
    blob: str,
    guards: dict,
    age_group: dict,
) -> Optional[dict]:
    from flow_engine import (
        _skin_arbutin,
        _skin_azelaic,
        _skin_bakuchiol,
        _skin_niacin_tranexamic,
        _skin_niacin_zinc,
        _skin_peptide_light,
        _skin_retinol,
        _skin_salicylic_toner,
    )

    if cid == "pigmentation":
        if "arbutin" in blob or "traneksamik" in blob:
            return None
        ab = "(%2)" if score <= 4 else "(%2-3)"
        return {
            "time": "Akşam",
            "category": "Bakım",
            "icon": "💎",
            "action": _skin_arbutin(ab) if score <= 6 else _skin_niacin_tranexamic(),
            "detail": (
                f"İkincil leke (şiddet {score}/10): birincil tedaviyi bozmadan akşam leke katmanı. "
                "Güçlü gece aktiflerinin olduğu akşamlarda onlar önce. Haftada 3-4 gece."
            ),
            "step_order": 22,
        }

    if cid == "dryness":
        if "seramid" in blob or "squalane" in blob or "skualan" in blob:
            return None
        return {
            "time": "Akşam",
            "category": "Bakım",
            "icon": "🧴",
            "action": "Seramid NP/AP/EOP + squalane onarım serumu (INCI: Ceramide NP vb. + skualan)",
            "detail": (
                f"İkincil kuruluk (şiddet {score}/10): aktiflerden sonra bariyer; "
                "asiti artırmadan nem kaybını kes."
            ),
            "step_order": 28,
        }

    if cid == "aging":
        if "retinol" in blob or "bakuchiol" in blob or "peptid" in blob:
            return None
        if guards.get("avoid_retinol") or not age_group.get("retinol_ok"):
            return {
                "time": "Akşam",
                "category": "Bakım",
                "icon": "🌿",
                "action": _skin_peptide_light() if score < 7 else _skin_bakuchiol(),
                "detail": (
                    f"İkincil yaşlanma (şiddet {score}/10): retinol bu planda diğer sorunu "
                    "kötüleştireceği için peptid/bakuchiol. Haftada 3 gece."
                ),
                "step_order": 22,
            }
        cap = guards.get("max_retinol") or "0.3"
        return {
            "time": "Akşam",
            "category": "Bakım",
            "icon": "🔬",
            "action": _skin_retinol(f"%{cap}" if not str(cap).startswith("%") else cap),
            "detail": (
                f"İkincil yaşlanma (şiddet {score}/10): düşük retinol, BHA/AHA ile aynı gece yok. "
                "Haftada 2 gece; günler sistem atar."
            ),
            "step_order": 22,
        }

    if cid == "acne":
        if "azelaik" in blob or "benzoil" in blob:
            return None
        return {
            "time": "Akşam",
            "category": "Bakım",
            "icon": "🎯",
            "action": _skin_azelaic("%10-15"),
            "detail": (
                f"İkincil akne (şiddet {score}/10): BHA yığmadan azelaik (akne+leke dostu). "
                "Haftada 2-3 gece."
            ),
            "step_order": 22,
        }

    if cid == "oiliness":
        if "çinko" in blob or "cinko" in blob or "zinc" in blob:
            return None
        return {
            "time": "Akşam",
            "category": "Bakım",
            "icon": "💧",
            "action": _skin_niacin_zinc(),
            "detail": (
                f"İkincil yağlılık (şiddet {score}/10): sebum için çinko/niasinamid; "
                "ekstra asit yok."
            ),
            "step_order": 25,
        }

    if cid == "pores":
        if "salisilik" in blob:
            return None
        pct, n = bha_for_pores(score, guards)
        return {
            "time": "Akşam",
            "category": "Bakım",
            "icon": "🕳️",
            "action": _skin_salicylic_toner(pct),
            "detail": (
                f"İkincil gözenek (şiddet {score}/10): komedon için BHA %{pct:g}, haftada {n} gece. "
                "İnflamatuvar akne protokolü eklenmedi."
            ),
            "step_order": 20,
        }

    return None
