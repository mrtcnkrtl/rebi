from types import SimpleNamespace

from concern_checkin_extras import apply_concern_extra_risk


def _req(**kwargs):
    return SimpleNamespace(**kwargs)


def test_acne_today_flags():
    base = {"score": 3, "level": "normal", "label": "Normal", "detail": "x"}
    req = _req(
        picked_skin_today=True,
        high_glycemic_intake_today=True,
        heavy_dairy_today=False,
    )
    out = apply_concern_extra_risk("acne", req, [], base)
    assert out["score"] >= base["score"] + 2


def test_sun_spf_combo():
    base = {"score": 2, "level": "normal", "label": "Normal", "detail": "x"}
    req = _req(long_sun_exposure_today=True, spf_applied_today=False)
    out = apply_concern_extra_risk("pigmentation", req, [], base)
    assert out["score"] >= 3


def test_repeated_sugar_raises_more_than_one_day_and_eases_the_acid():
    from flow_engine import adapt_existing_routine

    base = {"score": 3, "level": "normal", "label": "Normal", "detail": "x"}
    one = apply_concern_extra_risk("acne", _req(high_glycemic_intake_today=True), [], base)
    past = [
        {"adaptation": {"checkin_extras": {"high_glycemic_intake_today": True}}},
        {"adaptation": {"checkin_extras": {"high_glycemic_intake_today": True}}},
    ]
    repeat = apply_concern_extra_risk("acne", _req(high_glycemic_intake_today=True), past, base)
    assert repeat["score"] > one["score"]

    acid = {
        "time": "Akşam",
        "category": "Bakım",
        "action": "Salisilik asit %1",
        "usage": "Haftada 3 gece.",
        "weekly_days": [0, 2, 4],
        "canonical_ingredient_ids": ["salisilik_asit"],
    }
    daily = {
        "skin_feeling": "iyi",
        "concern": "acne",
        "high_glycemic_intake_today": True,
        "past_logs": past,
    }
    risk = {"level": "normal", "score": 2, "detail": ""}
    first = adapt_existing_routine([acid], daily, risk)
    stepped = next(i for i in first["adapted_items"] if "salisilik" in i["action"].lower())
    assert "%0.5" in stepped["action"]
    assert stepped["weekly_days"] == [0, 2]
    assert any(i.get("concern_role") == "checkin_moisturizer" for i in first["adapted_items"])
    assert any(i.get("concern_role") == "checkin_diet" for i in first["adapted_items"])

    again = adapt_existing_routine(first["adapted_items"], daily, risk)
    stepped2 = next(i for i in again["adapted_items"] if "salisilik" in i["action"].lower())
    assert "%0.5" in stepped2["action"]
    assert stepped2["weekly_days"] == [0]

    calm_daily = {"skin_feeling": "iyi", "concern": "acne", "high_glycemic_intake_today": False, "past_logs": []}
    calm = adapt_existing_routine(again["adapted_items"], calm_daily, risk)
    raised = next(i for i in calm["adapted_items"] if "salisilik" in i["action"].lower())
    assert "%1" in raised["action"] and "%0.5" not in raised["action"]
    assert raised["weekly_days"] == [0, 2]
    assert not any(i.get("concern_role") == "checkin_moisturizer" for i in calm["adapted_items"])

    calm2 = adapt_existing_routine(calm["adapted_items"], calm_daily, risk)
    restored = next(i for i in calm2["adapted_items"] if "salisilik" in i["action"].lower())
    assert restored["weekly_days"] == [0, 2, 4]


def test_carryover_spf_history():
    base = {"score": 2, "level": "normal", "label": "Normal", "detail": "x"}
    req = _req(spf_applied_today=None, long_sun_exposure_today=None)
    past = [
        {"adaptation": {"checkin_extras": {"spf_applied_today": False}}},
        {"adaptation": {"checkin_extras": {"spf_applied_today": False}}},
        {"adaptation": {"checkin_extras": {"spf_applied_today": False}}},
    ]
    out = apply_concern_extra_risk("aging", req, past, base)
    assert out["score"] > base["score"]
