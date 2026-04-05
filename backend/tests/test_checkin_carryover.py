from checkin_carryover import (
    blend_sleep_hours,
    blend_stress_mapped,
    effective_makeup_with_history,
)


def test_blend_sleep_no_history():
    s, n = blend_sleep_hours(7, [])
    assert s == 7
    assert "yalnız" in n


def test_blend_sleep_with_yesterday():
    past = [{"sleep_hours": 5}]
    s, _ = blend_sleep_hours(7, past)
    assert 5.5 < s < 7


def test_blend_stress_no_history():
    m, n = blend_stress_mapped(3, [])
    assert m == 6
    assert "yalnız" in n


def test_makeup_history_bad_pattern():
    past = [
        {"adaptation": {"checkin_extras": {"makeup_used_today": True, "makeup_removal_today": "water"}}},
        {"adaptation": {"checkin_extras": {"makeup_used_today": True, "makeup_removal_today": "none"}}},
    ]
    mf, mr, note = effective_makeup_with_history(
        "acne", 5, "cleanser", None, None, past
    )
    assert mf == 5
    assert mr == "water"
    assert note is not None
