"""Yeni etkenler, göz altı sorunu, eşdeğer seçenekler ve hamilelik filtresi."""

from flow_engine import (
    NEW_ACTIVE_DOSES,
    apply_pregnancy_safety,
    run_flow,
)


def _flow(**kwargs):
    base = dict(
        age=30,
        gender="female",
        skin_type_key="combination",
        stress_score=4,
        sleep_hours=7.5,
        water_intake=2.0,
        smoking=False,
        alcohol=False,
        uv_index=3,
        humidity=50,
        temperature=22,
        actives_experience="regular",
    )
    base.update(kwargs)
    return run_flow(**base)


def _blob(items):
    return " ".join(
        (i.get("action") or "") + " " + " ".join(c.get("action") or "" for c in i.get("choices") or [])
        for i in items
    ).lower()


def test_pregnancy_filter_ignores_daha_and_swaps_glycolic():
    items = [
        {"action": "L-Askorbik asit %15-20 — C vitamini serumu", "detail": "Hassasiyette daha seyrek kullan"},
        {"action": "Glikolik asit %10 (AHA, INCI: Glycolic Acid)", "detail": "leke"},
    ]
    out = apply_pregnancy_safety(items)
    actions = [i["action"].lower() for i in out]
    assert any("l-askorbik" in a for a in actions)
    assert not any("laktik" in a for a in actions)
    assert any("mandelik asit" in a for a in actions)
    assert any(NEW_ACTIVE_DOSES["mandelic"]["tiers"]["hassas"]["pct"] in i["action"] for i in out)


def test_pregnancy_pigmentation_is_one_safe_product():
    r = _flow(concern="pigmentation", severity_score=5, is_pregnant=True)
    blob = _blob(r["routine_items"])
    assert "salisilik" not in blob
    assert "heksilrezorsinol" not in blob
    assert "glukozamin" in blob
    assert "askorbik" not in blob
    assert "traneksamik" not in blob


def _spf_action(items):
    return next(i["action"].lower() for i in items if "spf" in (i.get("action") or "").lower())


def test_pigmentation_picks_one_product_without_a_menu():
    r = _flow(concern="pigmentation", severity_score=4)
    blob = _blob(r["routine_items"])
    assert "traneksamik" in blob
    assert "niasinamid" in blob
    assert "arbutin" not in blob
    assert "glikolik" not in blob
    assert "heksilrezorsinol" not in blob
    assert "askorbik" not in blob
    assert all("choices" not in i for i in r["routine_items"])


def test_sensitive_pigmentation_picks_licorice():
    r = _flow(concern="pigmentation", severity_score=6, skin_type_key="sensitive")
    blob = _blob(r["routine_items"])
    assert "glikolik" not in blob
    assert "arbutin" not in blob
    assert "meyan kökü" in blob
    assert all("choices" not in i for i in r["routine_items"])


def test_severe_acne_is_one_step_and_sulfur_is_an_option():
    r = _flow(concern="acne", severity_score=9)
    steps = [
        i
        for i in r["routine_items"]
        if any("benzoil" in (c.get("action") or "").lower() for c in i.get("choices") or [])
        or "benzoil" in (i.get("action") or "").lower()
    ]
    assert len(steps) == 1
    it = steps[0]
    assert {c["id"] for c in it["choices"]} == {"benzoyl", "sulfur"}
    assert it["default_choice_id"] == "benzoyl"
    assert "azelaik" not in _blob(r["routine_items"])
    assert "sülfasetamid" not in _blob(r["routine_items"])


def test_spf_filter_is_chosen_from_user_data():
    sensitive = _flow(concern="aging", severity_score=4, skin_type_key="sensitive")
    oily = _flow(concern="acne", severity_score=4, skin_type_key="oily")
    pigment = _flow(concern="pigmentation", severity_score=4)
    assert "mineral filtre" in _spf_action(sensitive["routine_items"])
    assert "kimyasal" in _spf_action(oily["routine_items"])
    assert "demir oksit" in _spf_action(pigment["routine_items"])
    assert all("choices" not in i for i in pigment["routine_items"])


def _morning_eye(items):
    return next(i for i in items if i.get("concern_role") == "primary_undereye" and i.get("time") == "Sabah")


def test_undereye_primary_concern():
    r = _flow(concern="undereye", severity_score=6)
    assert r["multi_concern"]["primary"] == "undereye"
    blob = _blob(r["routine_items"])
    morning = _morning_eye(r["routine_items"])
    assert "c vitamini türevi" in morning["action"].lower()
    assert "choices" not in morning
    assert "kafein" not in morning["action"].lower()
    assert "göz çevresi" in blob
    assert "glikolik" not in blob
    assert "retinol" not in blob


def test_undereye_purple_is_caffeine_without_a_choice():
    r = _flow(concern="undereye", severity_score=6, undereye_look={"color": "purple", "puffiness": "none"})
    morning = _morning_eye(r["routine_items"])
    assert "kafein" in morning["action"].lower()
    assert "choices" not in morning


def test_undereye_brown_is_vitamin_c_without_a_choice():
    r = _flow(concern="undereye", severity_score=6, undereye_look={"color": "brown", "puffiness": "all_day"})
    morning = _morning_eye(r["routine_items"])
    assert "c vitamini türevi" in morning["action"].lower()
    assert "kafein" not in morning["action"].lower()
    assert "choices" not in morning


def test_undereye_both_colors_prefers_caffeine():
    r = _flow(concern="undereye", severity_score=6, undereye_look={"color": "both"})
    morning = _morning_eye(r["routine_items"])
    assert "kafein" in morning["action"].lower()
    assert "choices" not in morning


def test_most_severe_concern_stays_primary_with_undereye():
    r = _flow(
        concern="undereye",
        severity_score=3,
        concerns=[
            {"id": "undereye", "severity_score": 3},
            {"id": "acne", "severity_score": 9, "zones": ["chin"]},
        ],
    )
    assert r["multi_concern"]["primary"] == "acne"
    blob = _blob(r["routine_items"])
    assert "kafein" in blob or "göz çevresi" in blob


def test_high_risk_drops_caffeine_one_tier_and_keeps_it():
    """Yoğun kafein (%5) yüksek riskte bir kademe iner; madde kafein kalır."""
    calm = _flow(
        concern="undereye",
        severity_score=8,
        undereye_look={"color": "purple", "puffiness": "often"},
    )
    stressed = _flow(
        concern="undereye",
        severity_score=8,
        undereye_look={"color": "purple", "puffiness": "often"},
        stress_score=10,
        water_intake=0.5,
        sleep_hours=4,
        humidity=20,
    )
    calm_eye = _morning_eye(calm["routine_items"])["action"].lower()
    stressed_eye = _morning_eye(stressed["routine_items"])["action"].lower()
    assert "kafein %5" in calm_eye
    assert "kafein %3" in stressed_eye
    assert "kafein %5" not in stressed_eye
    assert "choices" not in _morning_eye(stressed["routine_items"])


def test_high_risk_drops_sulfur_option_one_tier():
    """Sülfür akne adımında kalır; yüksek riskte %5-10 yerine %3-5 yazılır."""
    r = _flow(
        concern="acne",
        severity_score=9,
        stress_score=10,
        water_intake=0.5,
        sleep_hours=4,
        humidity=20,
    )
    step = next(i for i in r["routine_items"] if i.get("choice_group") == "acne_antibacterial")
    sulfur = next(c["action"] for c in step["choices"] if c["id"] == "sulfur")
    assert "%3-5" in sulfur
    assert "%5-10" not in sulfur
    assert step["default_choice_id"] == "benzoyl"


def test_sensitive_licorice_stays_on_the_low_band_when_risk_is_high():
    r = _flow(
        concern="pigmentation",
        severity_score=6,
        skin_type_key="sensitive",
        stress_score=10,
        water_intake=0.5,
        sleep_hours=4,
        humidity=20,
    )
    blob = _blob(r["routine_items"])
    assert "meyan kökü" in blob
    assert "glabridin %0.03-0.1" in blob
    assert "glabridin %0.1-0.5" not in blob


def test_acne_without_barrier_need_has_no_moisturizer():
    r = _flow(concern="acne", severity_score=8, skin_type_key="combination")
    actions = [i.get("action") or "" for i in r["routine_items"]]
    assert not any(a.startswith("Nemlendirici:") for a in actions)
    assert not any(a.startswith("Gece:") for a in actions)


def test_dryness_chooses_dimethicone_morning_and_night():
    r = _flow(
        concern="dryness",
        severity_score=6,
        skin_type_key="combination",
        concerns=[{"id": "dryness", "severity_score": 6}],
    )
    actions = [i.get("action") or "" for i in r["routine_items"]]
    assert any(a.startswith("Nemlendirici: Dimetikon %1-5") for a in actions)
    assert any("Gece: gama linolenik asit (GLA) %0.1-1" in a for a in actions)
    assert not any("Centella" in a or "Seramid %1-2" in a for a in actions)


def test_sensitivity_uses_the_hassas_barrier_column():
    r = _flow(concern="sensitivity", severity_score=3, skin_type_key="combination")
    actions = [i.get("action") or "" for i in r["routine_items"]]
    assert any(a.startswith("Nemlendirici: Dimetikon %0.5-2") for a in actions)
    assert not any("Centella" in a or "Seramid %1-2" in a for a in actions)


def test_acne_barrier_stress_selects_linoleic():
    r = _flow(
        concern="acne",
        severity_score=8,
        skin_type_key="combination",
        stress_score=10,
        water_intake=0.5,
        humidity=20,
        sleep_hours=4,
    )
    actions = [i.get("action") or "" for i in r["routine_items"]]
    assert any("Gece: Linoleik asit %1-2.5" in a for a in actions)
    assert not any("Centella" in a or "Seramid %1-2" in a for a in actions)


def test_sensitive_oiliness_is_green_tea_only():
    r = _flow(concern="oiliness", severity_score=6, skin_type_key="sensitive")
    blob = _blob(r["routine_items"])
    assert "yeşil çay" in blob
    assert "çinko destekli" not in blob
    assert "salisilik" not in blob


def test_gentle_mild_acne_is_mandelic():
    r = _flow(concern="acne", severity_score=3, skin_type_key="sensitive")
    blob = _blob(r["routine_items"])
    assert "mandelik asit" in blob
    assert "salisilik" not in blob


def test_oily_sensitive_mild_acne_is_pha():
    r = _flow(
        concern="acne",
        severity_score=3,
        skin_type_key="oily",
        concerns=[{"id": "acne", "severity_score": 3}, {"id": "sensitivity", "severity_score": 2}],
    )
    blob = _blob(r["routine_items"])
    assert "glukonolakton" in blob
    assert "salisilik" not in blob


def test_dry_skin_barrier_uses_kuru_column():
    r = _flow(concern="dryness", severity_score=6, skin_type_key="dry")
    blob = _blob(r["routine_items"])
    assert NEW_ACTIVE_DOSES["barrier"]["dimethicone"]["kuru"] in blob
