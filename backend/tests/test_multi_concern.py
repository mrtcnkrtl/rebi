"""Çoklu sorun: şiddet sıralaması, protokol ayrımı, kötüleştirmeme."""

from flow_engine import run_flow
from multi_concern import build_guards, normalize_concern_entries, rank_concerns


def _blob(items):
    return " ".join(str(i.get("action") or "") + " " + str(i.get("detail") or "") for i in items).lower()


def _flow(**kwargs):
    base = dict(
        age=26,
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


def test_rank_highest_severity_first_not_selection_order():
    ranked = rank_concerns(
        normalize_concern_entries(
            concern="pigmentation",
            severity_score=4,
            concerns=[
                {"id": "pigmentation", "severity_score": 4},
                {"id": "acne", "severity_score": 8, "zones": ["chin"]},
                {"id": "oiliness", "severity_score": 3},
            ],
        )
    )
    assert ranked[0]["id"] == "acne"
    assert ranked[0]["score"] == 8
    assert [e["id"] for e in ranked] == ["acne", "pigmentation", "oiliness"]


def test_tie_break_acne_before_oiliness():
    ranked = rank_concerns(
        normalize_concern_entries(
            concern="oiliness",
            severity_score=6,
            concerns=[
                {"id": "oiliness", "severity_score": 6},
                {"id": "acne", "severity_score": 6},
            ],
        )
    )
    assert ranked[0]["id"] == "acne"


def test_run_flow_ignores_first_selected_uses_highest_score():
    r = _flow(
        concern="pigmentation",
        severity_score=3,
        concerns=[
            {"id": "pigmentation", "severity_score": 3, "zones": ["left_cheek"]},
            {"id": "acne", "severity_score": 9, "zones": ["chin"]},
        ],
    )
    assert r["multi_concern"]["primary"] == "acne"
    blob = _blob(r["routine_items"])
    assert "benzoil" in blob or "azelaik" in blob
    assert "çene" in blob


def test_pigmentation_plus_acne_chin_still_gets_zone():
    r = _flow(
        concern="pigmentation",
        severity_score=8,
        concerns=[
            {"id": "pigmentation", "severity_score": 8},
            {"id": "acne", "severity_score": 5, "zones": ["chin"]},
        ],
    )
    assert r["multi_concern"]["primary"] == "pigmentation"
    blob = _blob(r["routine_items"])
    assert "çene" in blob
    assert "arbutin" in blob or "traneksamik" in blob
    assert r["acne_zone_info"]


def test_oiliness_pores_acne_are_not_the_same_skeleton():
    oily = _blob(_flow(concern="oiliness", severity_score=3)["routine_items"])
    pores = _blob(_flow(concern="pores", severity_score=3)["routine_items"])
    acne = _blob(_flow(concern="acne", severity_score=3)["routine_items"])

    assert "çinko" in oily or "niasinamid" in oily
    assert "salisilik" not in oily  # düşük yağlılıkta BHA yok
    assert "benzoil" not in oily

    assert "salisilik" in pores
    assert "benzoil" not in pores

    assert "salisilik" in acne
    assert "lezyon" in acne or "akne" in acne


def test_oiliness_high_adds_low_bha_still_no_bpo():
    oily = _blob(_flow(concern="oiliness", severity_score=9)["routine_items"])
    assert "salisilik" in oily
    assert "%0.5" in oily or "%1" in oily
    assert "benzoil" not in oily


def test_sensitivity_plus_acne_drops_bpo():
    r = _flow(
        concern="acne",
        severity_score=9,
        concerns=[
            {"id": "acne", "severity_score": 9},
            {"id": "sensitivity", "severity_score": 7},
        ],
    )
    blob = _blob(r["routine_items"])
    assert "benzoil" not in blob
    assert "azelaik" in blob
    assert r["multi_concern"]["guards"]["avoid_bpo"] is True


def test_highest_dryness_outranks_mild_acne():
    r = _flow(
        concern="acne",
        severity_score=3,
        concerns=[
            {"id": "acne", "severity_score": 3},
            {"id": "dryness", "severity_score": 8},
        ],
    )
    assert r["multi_concern"]["primary"] == "dryness"
    blob = _blob(r["routine_items"])
    assert "seramid" in blob or "squalane" in blob or "skualan" in blob
    assert "azelaik" in blob
    assert "benzoil" not in blob


def test_acne_primary_dryness_secondary_avoids_bpo_adds_ceramide():
    r = _flow(
        concern="acne",
        severity_score=8,
        concerns=[
            {"id": "acne", "severity_score": 8},
            {"id": "dryness", "severity_score": 6},
        ],
    )
    assert r["multi_concern"]["primary"] == "acne"
    blob = _blob(r["routine_items"])
    assert "benzoil" not in blob
    assert "azelaik" in blob
    assert "seramid" in blob or "squalane" in blob or "skualan" in blob


def test_pigmentation_forces_spf_50():
    r = _flow(
        concern="acne",
        severity_score=6,
        uv_index=2,
        concerns=[
            {"id": "acne", "severity_score": 6},
            {"id": "pigmentation", "severity_score": 4},
        ],
    )
    blob = _blob(r["routine_items"])
    assert "spf 50" in blob
    assert "arbutin" in blob or "traneksamik" in blob


def test_guards_from_all_selected():
    g = build_guards(
        [{"id": "acne", "score": 8}, {"id": "sensitivity", "score": 6}, {"id": "dryness", "score": 5}]
    )
    assert g["avoid_bpo"] is True
    assert g["max_bha_pct"] <= 1.0
    assert g["force_starter"] is True
