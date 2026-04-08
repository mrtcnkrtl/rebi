from __future__ import annotations

from typing import Optional, Literal

from config import get_logger

log = get_logger("active_plan")


def _pct_range_str(low: float, high: float) -> str:
    if low == high:
        # avoid trailing .0
        v = int(low) if float(low).is_integer() else low
        return f"%{v}"
    a = int(low) if float(low).is_integer() else low
    b = int(high) if float(high).is_integer() else high
    return f"%{a}-{b}"


def _norm_lang(lang: str) -> Literal["tr", "en"]:
    s = (lang or "").strip().lower()
    if not s:
        return "tr"
    primary = s.split(",")[0].split(";")[0].strip()
    primary = primary.split("-")[0]
    return "en" if primary == "en" else "tr"


def localize_active_plan(plan: list[dict], lang: str) -> list[dict]:
    """
    Converts {why_tr/why_en, notes_tr/notes_en} into {why, notes} for requested language.
    Keeps the original *_tr/*_en fields too (debugging / future UI), but ensures `why`/`notes` exist.
    """
    lng = _norm_lang(lang)
    out: list[dict] = []
    for it in plan or []:
        d = dict(it)
        if lng == "en":
            d["why"] = d.get("why_en") or d.get("why_tr") or ""
            d["notes"] = d.get("notes_en") or d.get("notes_tr") or ""
        else:
            d["why"] = d.get("why_tr") or d.get("why_en") or ""
            d["notes"] = d.get("notes_tr") or d.get("notes_en") or ""
        out.append(d)
    return out


def build_active_plan(
    *,
    concern: str,
    skin_type_key: str,
    age_group: dict,
    severity: dict,
    risk_info: dict,
    strength_stage: str,
    niacinamide_start_pct: str,
    merged_actives_tol: dict,
    is_pregnant: bool = False,
    stings_with_products: bool = False,
) -> list[dict]:
    """
    Product recommendation is intentionally NOT included.
    Output is an ingredient-level plan: active + concentration range + when/how often + constraints.
    """
    concern = (concern or "general").strip().lower()
    skin_type_key = (skin_type_key or "normal").strip().lower()
    sev = (severity or {}).get("level") or ""
    risk_level = (risk_info or {}).get("level") or "normal"

    def tol_level(family: str) -> str:
        v = (merged_actives_tol or {}).get(family)
        return v if v in ("never", "good", "mild", "bad") else "good"

    # Prefer data-driven rules if present in DB.
    try:
        from active_rules import build_active_plan_from_rules

        # numeric percent to feed data-driven rules (e.g., niacinamide)
        try:
            _na_base = float(str(niacinamide_start_pct).replace("%", "").strip())
        except Exception:
            _na_base = None

        ctx = {
            "concern": concern,
            "skin_type": skin_type_key,
            "risk_level": risk_level,
            "severity": sev,
            "severity_level": sev,
            "strength_stage": strength_stage,
            "age_group": age_group.get("group") if isinstance(age_group, dict) else None,
            "is_pregnant": bool(is_pregnant),
            "stings_with_products": bool(stings_with_products),
            "niacinamide_start_pct": _na_base,
            "tol_bha": tol_level("bha"),
            "tol_aha": tol_level("aha"),
            "tol_retinol": tol_level("retinol"),
            "tol_benzoyl": tol_level("benzoyl"),
            "tol_azelaic": tol_level("azelaic"),
            "tol_vitamin_c": tol_level("vitamin_c"),
            "tol_vitamin_c_derivatives": tol_level("vitamin_c_derivatives"),
            "tol_adapalene": tol_level("adapalene"),
            "tol_urea": tol_level("urea"),
            "tol_sulfur": tol_level("sulfur"),
            "tol_zinc_pca": tol_level("zinc_pca"),
            "tol_pigment": tol_level("pigment"),
            "tol_niacinamide": tol_level("niacinamide"),
        }
        from_db = build_active_plan_from_rules(ctx)
        if from_db:
            # still ensure `why/notes` exist for requested language later (main.py does localization)
            return from_db
    except Exception as e:
        log.debug("active_rules not used (fallback to heuristics): %s", e)

    return _legacy_build_active_plan(
        concern=concern,
        skin_type_key=skin_type_key,
        age_group=age_group,
        severity=severity,
        risk_info=risk_info,
        strength_stage=strength_stage,
        niacinamide_start_pct=niacinamide_start_pct,
        merged_actives_tol=merged_actives_tol,
    )

def _legacy_build_active_plan(
    *,
    concern: str,
    skin_type_key: str,
    age_group: dict,
    severity: dict,
    risk_info: dict,
    strength_stage: str,
    niacinamide_start_pct: str,
    merged_actives_tol: dict,
) -> list[dict]:
    """
    Legacy heuristic implementation kept as fallback when DB rules are unavailable.
    """
    sev = (severity or {}).get("level") or ""
    risk_level = (risk_info or {}).get("level") or "normal"

    def tol_level(family: str) -> str:
        v = (merged_actives_tol or {}).get(family)
        return v if v in ("never", "good", "mild", "bad") else "good"

    plan: list[dict] = []

    # ── Universal basics (always relevant as "structure") ──
    plan.append(
        {
            "active": "sunscreen",
            "role": "protection",
            "recommended": True,
            "when": "morning",
            "concentration": None,
            "why_tr": "UV; leke, bariyer ve yaşlanmada en büyük dış tetikleyici.",
            "why_en": "UV is the biggest external driver for pigmentation, barrier stress, and photoaging.",
            "notes_tr": "Geniş spektrum SPF: her sabah. Ürün değil, prensip.",
            "notes_en": "Broad-spectrum SPF every morning. Principle, not a product suggestion.",
            "constraints": {"avoid_in_pregnancy": False, "avoid_if_sensitive": False},
        }
    )

    # ── Barrier support (ceramides/panthenol) ──
    plan.append(
        {
            "active": "ceramides_cholesterol_fatty_acids",
            "role": "barrier_repair",
            "recommended": concern in ("dryness", "sensitivity", "general") or skin_type_key in ("dry", "sensitive"),
            "when": "evening",
            "concentration": {"note": "Etiket % şart değil; hedef: bariyer lipitleri 3:1:1 mantığı"},
            "why_tr": "Kuruluk/hassasiyette bariyeri stabilize eder; aktif toleransını iyileştirir.",
            "why_en": "Stabilizes the barrier in dryness/sensitivity and improves overall active tolerance over time.",
            "notes_tr": "Seramid NP/AP/EOP + kolesterol + yağ asitleri hedefi. Uygulama: gece nem katmanı.",
            "notes_en": "Aim for ceramides + cholesterol + fatty acids (3:1:1 logic). Use as the evening barrier layer.",
            "constraints": {"avoid_in_pregnancy": False, "avoid_if_sensitive": False},
        }
    )
    plan.append(
        {
            "active": "panthenol",
            "role": "soothing_barrier",
            "recommended": concern in ("sensitivity", "dryness") or risk_level in ("high", "crisis"),
            "when": "evening",
            "concentration": {"range": _pct_range_str(2.0, 5.0)},
            "why_tr": "Yanma/batma veya yüksek riskte yatıştırma + bariyer desteği.",
            "why_en": "Soothing + barrier support when stinging/irritation signals are present or risk is high.",
            "notes_tr": "Panthenol %2-5 aralığı genelde iyi tolere edilir; iritasyonda önceliklidir.",
            "notes_en": "Panthenol 2–5% is usually well tolerated and is a good priority in irritation phases.",
            "constraints": {"avoid_in_pregnancy": False, "avoid_if_sensitive": False},
        }
    )

    # ── Niacinamide (skin-type dependent) ──
    # Already computed by engine (experience+tolerance+risk)
    try:
        na_pct = float(str(niacinamide_start_pct).replace("%", "").strip())
    except Exception:
        na_pct = 5.0
    na_low = max(2.0, min(na_pct, 10.0))
    na_high = max(na_low, min(10.0, na_low + 3.0))
    if tol_level("niacinamide") != "bad":
        plan.append(
            {
                "active": "niacinamide",
                "role": "sebum_balance_barrier",
                "recommended": skin_type_key in ("oily", "combination")
                or concern in ("acne", "oiliness", "pores", "pigmentation"),
                "when": "morning_or_evening",
                "concentration": {
                    "start": _pct_range_str(na_low, na_low),
                    "range": _pct_range_str(na_low, na_high),
                },
                "constraints": {
                    "avoid_if": ["severe_reaction"] if tol_level("niacinamide") == "bad" else [],
                    "stage": strength_stage,
                    "risk_level": risk_level,
                    "avoid_in_pregnancy": False,
                    "avoid_if_sensitive": False,
                },
                "why_tr": "Sebum dengesi + bariyer desteği (özellikle yağlı/karma, gözenek ve leke ekseninde).",
                "why_en": "Supports sebum balance and barrier function—especially useful in oily/combination skin, pores, and pigmentation routines.",
                "notes_tr": "Sebum dengesi ve bariyer desteği. Tahriş sinyalinde daha düşük yüzdeyle kal.",
                "notes_en": "Supports sebum balance and barrier. If irritation appears, stay in the lower end of the range.",
            }
        )

    # ── Salicylic acid / BHA (pores/oiliness/acne) ──
    if concern in ("acne", "oiliness", "pores") and tol_level("bha") != "bad":
        # conservative ranges
        bha_low, bha_high = (0.5, 2.0)
        # higher risk -> lower range
        if risk_level in ("high", "crisis") or tol_level("bha") in ("mild", "never"):
            bha_low, bha_high = (0.5, 1.0)
        plan.append(
            {
                "active": "salicylic_acid",
                "family": "bha",
                "role": "comedones_sebum",
                "recommended": True,
                "when": "evening",
                "concentration": {"range": _pct_range_str(bha_low, bha_high)},
                "frequency": {"per_week": "2-4", "note_tr": "Toleransa ve risk skoruna göre."},
                "why_tr": "Siyah nokta/komedon tıkacını çözmede en direkt aktiflerden.",
                "why_en": "One of the most direct actives for blackheads/clogged pores and sebum buildup.",
                "notes_tr": "Siyah nokta/tıkanıklık ve sebum için. Aynı seansta çoklu güçlü asit/retinoid biriktirme.",
                "notes_en": "For blackheads/clogging and sebum. Avoid stacking multiple strong acids/retinoids in the same session.",
                "constraints": {"avoid_in_pregnancy": False, "avoid_if_sensitive": True},
            }
        )

    # ── Benzoyl Peroxide (acne) ──
    if concern == "acne" and tol_level("benzoyl") != "bad":
        bp_low, bp_high = (2.5, 5.0)
        if risk_level in ("high", "crisis") or tol_level("benzoyl") in ("never", "mild"):
            bp_low, bp_high = (2.5, 2.5)
        plan.append(
            {
                "active": "benzoyl_peroxide",
                "family": "benzoyl",
                "role": "antibacterial_inflammatory_acne",
                "recommended": sev in ("orta", "şiddetli"),
                "when": "evening",
                "concentration": {"range": _pct_range_str(bp_low, bp_high)},
                "frequency": {"per_week": "1-3"},
                "why_tr": "İnflamatuvar aknede hızlı etkili bir seçenek; tolerans ve riskte düşük % ile.",
                "why_en": "A fast, effective option for inflammatory acne; keep the % conservative when risk/tolerance is limited.",
                "notes_tr": "Kısa temas yaklaşımı (5-10 dk) bazı ciltlerde toleransı artırır.",
                "notes_en": "Short-contact therapy (5–10 minutes) can improve tolerability for some skin types.",
                "constraints": {"avoid_in_pregnancy": False, "avoid_if_sensitive": True},
            }
        )

    # ── AHA (glycolic/lactic) (texture/pigment, not for very sensitive) ──
    if concern in ("pigmentation", "aging") and skin_type_key != "sensitive" and tol_level("aha") != "bad":
        # engine already caps aha_max_pct by age; use it when provided
        try:
            aha_cap = float(age_group.get("aha_max_pct", 10))
        except Exception:
            aha_cap = 10.0
        aha_low, aha_high = (5.0, min(aha_cap, 10.0))
        if risk_level in ("high", "crisis") or tol_level("aha") in ("never", "mild"):
            aha_low, aha_high = (5.0, 5.0)
        plan.append(
            {
                "active": "glycolic_or_lactic_acid",
                "family": "aha",
                "role": "texture_turnover_pigment_support",
                "recommended": sev != "hafif",
                "when": "evening",
                "concentration": {"range": _pct_range_str(aha_low, aha_high)},
                "frequency": {"per_week": "1-3"},
                "why_tr": "Yüzey yenileme ile doku/ton desteği; yaş ve risk durumuna göre % sınır.",
                "why_en": "Supports texture/ton via surface renewal; % is capped by age and tightened under higher risk.",
                "notes_tr": "Aynı gece retinol ile bindirme. Hassas ciltte genelde tercih etmeyiz.",
                "notes_en": "Do not stack with retinol the same night. Usually not preferred for very sensitive skin.",
                "constraints": {"avoid_in_pregnancy": False, "avoid_if_sensitive": True},
            }
        )

    # ── Azelaic acid (acne/pigment/rosacea-like sensitivity) ──
    if concern in ("acne", "pigmentation", "sensitivity") and tol_level("azelaic") != "bad":
        aza_low, aza_high = (10.0, 15.0)
        if sev == "şiddetli" and risk_level in ("normal", "moderate") and tol_level("azelaic") == "good":
            aza_high = 20.0
        plan.append(
            {
                "active": "azelaic_acid",
                "family": "azelaic",
                "role": "acne_pigment_redness",
                "recommended": True,
                "when": "evening",
                "concentration": {"range": _pct_range_str(aza_low, aza_high)},
                "frequency": {"per_week": "2-4"},
                "why_tr": "Akne + leke + kızarıklık ekseninde dengeli; çoğu ciltte toleransı iyi.",
                "why_en": "Balanced for acne + pigmentation + redness, and generally well tolerated across skin types.",
                "notes_tr": "Akne + leke + kızarıklık ekseninde iyi toleranslı bir seçenek.",
                "notes_en": "A well-tolerated option across acne, pigmentation, and redness pathways.",
                "constraints": {"avoid_in_pregnancy": False, "avoid_if_sensitive": False},
            }
        )

    # ── Tranexamic acid / Arbutin (pigmentation) ──
    if concern == "pigmentation":
        if tol_level("pigment") != "bad":
            plan.append(
                {
                    "active": "tranexamic_acid",
                    "family": "pigment",
                    "role": "pigment_modulation",
                    "recommended": True,
                    "when": "evening",
                    "concentration": {"range": _pct_range_str(2.0, 5.0)},
                    "frequency": {"per_week": "3-7"},
                    "why_tr": "Leke yolaklarında destek; retinoid/asit kadar irrite etmeyen seçeneklerden.",
                    "why_en": "Supports pigmentation pathways and is often less irritating than strong acids/retinoids.",
                    "notes_tr": "Niasinamid ile aynı adımda veya ayrı katman olarak olabilir.",
                    "notes_en": "Can be used in the same step as niacinamide or layered separately.",
                    "constraints": {"avoid_in_pregnancy": False, "avoid_if_sensitive": False},
                }
            )
            plan.append(
                {
                    "active": "alpha_arbutin",
                    "family": "pigment",
                    "role": "tyrosinase_support",
                    "recommended": True,
                    "when": "evening",
                    "concentration": {"range": _pct_range_str(2.0, 3.0)},
                    "frequency": {"per_week": "3-7"},
                    "why_tr": "Ton eşitsizliği/lekede destekleyici; toleransa göre sıklık ayarlanır.",
                    "why_en": "Supportive for uneven tone/pigmentation; frequency can be adjusted by tolerability.",
                    "notes_tr": "C vitamini genelde sabah; arbutin akşam ayrımı netlik sağlar.",
                    "notes_en": "Vitamin C is usually morning; keeping arbutin at night keeps the routine clearer.",
                    "constraints": {"avoid_in_pregnancy": False, "avoid_if_sensitive": False},
                }
            )

    # ── Retinol (aging/pigmentation, age-aware) ──
    if age_group.get("retinol_ok") and concern in ("aging", "pigmentation") and tol_level("retinol") != "bad":
        # stage-based: starter < standard < strong
        if strength_stage == "starter" or tol_level("retinol") in ("never", "mild") or risk_level in ("high", "crisis"):
            r_low, r_high = (0.1, 0.3)
        elif strength_stage == "strong":
            r_low, r_high = (0.5, 1.0)
        else:
            r_low, r_high = (0.3, 0.5)
        plan.append(
            {
                "active": "retinol",
                "family": "retinol",
                "role": "collagen_texture_pigment",
                "recommended": True,
                "when": "evening",
                "concentration": {"range": _pct_range_str(r_low, r_high)},
                "frequency": {"per_week": "1-3", "note_tr": "Motor zaten gün ataması yapar; burada aralık veriyoruz."},
                "constraints": {"avoid_in_pregnancy": True},
                "why_tr": "Kırışıklık/tekstür ve bazı leke tiplerinde en etkili gece aktiflerinden; risk/toleransta düşük %.",
                "why_en": "One of the most effective night actives for texture/collagen support and some pigmentation patterns; keep % lower under risk/tolerance limits.",
                "notes_tr": "Yaşlanma/leke için gece aktifi. Aynı gece güçlü asitlerle üst üste bindirme.",
                "notes_en": "Night active for aging/pigmentation. Avoid stacking with strong acids the same night.",
            }
        )

    # ── Vitamin C (LAA) (aging/pigmentation) ──
    if concern in ("aging", "pigmentation") and tol_level("vitamin_c") != "bad":
        c_low, c_high = (8.0, 15.0)
        if age_group.get("group") in ("adult", "mature"):
            c_high = 20.0
        if skin_type_key == "sensitive" or risk_level in ("high", "crisis") or tol_level("vitamin_c") in ("never", "mild"):
            c_low, c_high = (5.0, 10.0)
        plan.append(
            {
                "active": "vitamin_c_l_ascorbic_acid",
                "family": "vitamin_c",
                "role": "antioxidant_pigment_support",
                "recommended": True,
                "when": "morning",
                "concentration": {"range": _pct_range_str(c_low, c_high)},
                "why_tr": "Antioksidan koruma + leke/ton desteği; hassasiyette düşük % aralığı.",
                "why_en": "Antioxidant protection + pigmentation/tone support; keep % lower in sensitivity or high-risk phases.",
                "notes_tr": "Antioksidan destek. Hassasiyet varsa daha düşük yüzde aralığı seç.",
                "notes_en": "Antioxidant support. If sensitivity appears, choose the lower end of the range.",
                "constraints": {"avoid_in_pregnancy": False, "avoid_if_sensitive": True},
            }
        )

    # Keep it compact: return only recommended=True items plus sunscreen (always)
    compact = [x for x in plan if x.get("active") == "sunscreen" or x.get("recommended")]
    return compact

