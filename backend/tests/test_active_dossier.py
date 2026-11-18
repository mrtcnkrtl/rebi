"""Aktif madde dosyası: doz kademeleri + sistem seçim kuralları."""

from active_dossier import (
    DOSES,
    NOT_MONO_CANDIDATE,
    barrier_supports,
    cef_stack_ok,
    pick_aha,
    pick_acne_antibacterial,
    pick_pigment_active,
    wants_pha,
)
from flow_engine import NEW_ACTIVE_DOSES, _dose, _skin_kojic, _skin_tea_tree, run_flow


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


def test_dossier_doses_merged_into_new_active():
    for key in (
        "glycolic",
        "lactic",
        "kojic",
        "cay_agaci",
        "aloe",
        "shea",
        "colloidal_oatmeal",
        "glycerin",
        "vitamin_e",
        "ferulic",
    ):
        assert key in NEW_ACTIVE_DOSES
        assert "tiers" in NEW_ACTIVE_DOSES[key]
        assert "hassas" in NEW_ACTIVE_DOSES[key]["tiers"]
        assert "standart" in NEW_ACTIVE_DOSES[key]["tiers"]


def test_glycolic_leave_on_cap_is_10():
    assert NEW_ACTIVE_DOSES["glycolic"]["leave_on_cap"] == "%10"
    assert "10" in _dose("glycolic", "yogun")


def test_kojic_sccs_cap_is_1():
    assert NEW_ACTIVE_DOSES["kojic"]["leave_on_cap"] == "%1"
    assert _dose("kojic", "standart") == "%1"


def test_malic_and_glycerin_not_mono_candidates():
    assert "malic_acid" in NOT_MONO_CANDIDATE
    assert "glycerin" in NOT_MONO_CANDIDATE
    assert "ferulic_acid" in NOT_MONO_CANDIDATE


def test_pick_pigment_rules():
    assert pick_pigment_active(score=5, gentle=False, pregnant=True, retinol_ok=True) == "nag_niacinamide"
    assert pick_pigment_active(score=8, gentle=False, pregnant=False, retinol_ok=True) == "retinol"
    assert pick_pigment_active(score=5, gentle=True, pregnant=False, retinol_ok=True) == "licorice"
    assert pick_pigment_active(score=2, gentle=False, pregnant=False, retinol_ok=True) == "kojic"
    assert pick_pigment_active(score=5, gentle=False, pregnant=False, retinol_ok=True) == "niacin_txa"
    assert pick_pigment_active(score=5, gentle=False, pregnant=False, retinol_ok=True, avoid_txa=True) == "kojic"


def test_pick_acne_tea_tree_when_bpo_avoided_mild():
    assert pick_acne_antibacterial(score=2, avoid_bpo=True, stings=True) == "tea_tree"
    assert pick_acne_antibacterial(score=9, avoid_bpo=False) == "benzoyl"
    assert pick_acne_antibacterial(score=8, avoid_bpo=True) == "azelaic"


def test_pick_aha_and_pha_gate():
    assert pick_aha(skin_key="oily", gentle=False) == "glycolic"
    assert pick_aha(skin_key="dry", gentle=False) == "lactic"
    assert pick_aha(skin_key="sensitive", gentle=True, avoid_aha=True) == "pha"
    assert wants_pha(oily_sensitive=True, gentle=True)
    assert wants_pha(aha_intolerance=True)
    assert wants_pha(dark_phototype=True)
    assert wants_pha(high_uv_season=True)
    assert not wants_pha(skin_key="oily", gentle=False)


def test_barrier_supports_and_cef():
    assert "colloidal_oatmeal" in barrier_supports(itching=True)
    assert "shea" in barrier_supports(high_tewl=True, skin_key="dry")
    assert "shea" not in barrier_supports(high_tewl=True, skin_key="oily")
    assert cef_stack_ok(has_vitamin_c=True)
    assert not cef_stack_ok(has_vitamin_c=False)


def test_mild_pigmentation_emits_kojic():
    r = _flow(concern="pigmentation", severity_score=2, skin_type_key="combination")
    blob = _blob(r["routine_items"])
    assert "kojik" in blob
    assert "traneksamik" not in blob
    assert all("choices" not in i for i in r["routine_items"] if "kojik" in (i.get("action") or "").lower())


def test_mid_pigmentation_still_txa():
    r = _flow(concern="pigmentation", severity_score=5, skin_type_key="combination")
    blob = _blob(r["routine_items"])
    assert "traneksamik" in blob
    assert "kojik" not in blob


def test_tea_tree_helpers_and_dose_text():
    assert "melaleuca" in _skin_tea_tree("standart").lower()
    assert "%5" in _skin_tea_tree("standart")
    assert "kojic" in _skin_kojic("standart").lower() or "kojik" in _skin_kojic("standart").lower()
    assert DOSES["cay_agaci"]["tiers"]["standart"]["pct"] == "%5 jel"


def test_equivalence_emits_system_pick_without_choices():
    from flow_engine import make_equivalence_item, _skin_benzoyl, _skin_sulfur

    item = make_equivalence_item(
        {"time": "Akşam", "category": "Bakım", "detail": "test"},
        "acne_antibacterial",
        {"benzoyl": _skin_benzoyl(5), "sulfur": _skin_sulfur("standart")},
        default="benzoyl",
    )
    assert item is not None
    assert "choices" not in item
    assert "choice_group" not in item
    assert item["system_pick"]["id"] == "benzoyl"
    assert "benzoil" in item["action"].lower()
    assert item["system_pick"]["candidates"] == ["benzoyl", "sulfur"]
