"""Sorun başı süre/sıklık motora bağlanır."""

from concern_history import apply_history_to_guards, cap_weekly_days_from_timeline, normalize_history_lists
from flow_engine import run_flow
from multi_concern import normalize_concern_entries, rank_concerns


def test_timeline_fields_survive_normalize():
    ranked = rank_concerns(
        normalize_concern_entries(
            concern="acne",
            severity_score=6,
            concerns=[
                {
                    "id": "acne",
                    "severity_score": 8,
                    "duration": "lt1",
                    "frequency": "flare",
                    "note": "  Çene adetten önce  ",
                }
            ],
        )
    )
    assert ranked[0]["duration"] == "lt1"
    assert ranked[0]["frequency"] == "flare"
    assert ranked[0]["note"] == "Çene adetten önce"


def test_flare_caps_weekly_days():
    items = [
        {"category": "Bakım", "weekly_days": [0, 1, 2, 3]},
        {"category": "Yaşam", "weekly_days": [0, 1, 2, 3]},
    ]
    cap_weekly_days_from_timeline(items, [{"id": "acne", "frequency": "flare", "duration": "1y+"}])
    assert items[0]["weekly_days"] == [0, 1]
    assert items[1]["weekly_days"] == [0, 1, 2, 3]


def test_sun_trigger_raises_spf():
    g = apply_history_to_guards(
        {"min_spf": 30, "max_bha_nights": 4, "notes": []},
        [{"id": "acne", "score": 5}],
        {"triggers": ["sun"], "expectations": [], "nutrition": {}, "past_treatments": []},
    )
    assert g["min_spf"] == 50


def test_run_flow_includes_timeline_item():
    r = run_flow(
        concern="acne",
        severity_score=8,
        age=26,
        gender="female",
        skin_type_key="combination",
        stress_score=4,
        sleep_hours=7.5,
        water_intake=2.0,
        smoking=False,
        alcohol=False,
        uv_index=2,
        humidity=50,
        temperature=22,
        concerns=[
            {
                "id": "acne",
                "severity_score": 8,
                "duration": "1y+",
                "frequency": "flare",
                "note": "Çene",
                "zones": ["chin"],
            }
        ],
        triggers=["period", "food"],
        nutrition={"sugar": 5, "dairy": 3, "fastfood": 0, "veggies": 1},
        past_treatments=["derm"],
        expectations=["comfort"],
    )
    blob = " ".join(
        str(i.get("action") or "") + " " + str(i.get("detail") or "") for i in r["routine_items"]
    ).lower()
    assert "süre" in blob or "sıklık" in blob or "çene" in blob
    assert r["multi_concern"]["guards"].get("force_starter") is True
    bakim_nights = [
        i.get("weekly_days")
        for i in r["routine_items"]
        if i.get("category") == "Bakım" and isinstance(i.get("weekly_days"), list) and len(i["weekly_days"]) > 0
    ]
    if bakim_nights:
        assert max(len(w) for w in bakim_nights) <= 2


def test_eye_corner_zone_even_when_primary_is_aging():
    from flow_engine import run_flow

    r = run_flow(
        concern="aging",
        severity_score=6,
        age=32,
        gender="female",
        skin_type_key="normal",
        stress_score=3,
        sleep_hours=7.5,
        water_intake=2.0,
        smoking=False,
        alcohol=False,
        uv_index=3,
        humidity=50,
        temperature=22,
        concerns=[{"id": "aging", "severity_score": 6, "zones": ["eye_corner"]}],
    )
    blob = " ".join(str(i.get("action") or "") for i in r["routine_items"]).lower()
    assert "göz kenarı" in blob
    assert any(z.get("zone") == "eye_corner" for z in r.get("acne_zone_info") or [])


def test_normalize_history_filters_unknown():
    h = normalize_history_lists(
        triggers=["sun", "hack"],
        past_treatments=["derm", "xyz"],
        expectations=["comfort"],
        nutrition={"sugar": 99, "nope": 1},
    )
    assert h["triggers"] == ["sun"]
    assert h["past_treatments"] == ["derm"]
    assert h["nutrition"]["sugar"] == 7
