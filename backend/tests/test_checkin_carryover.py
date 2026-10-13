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


def test_wipe_today_counts_as_weak_removal_like_water():
    mf, mr, note = effective_makeup_with_history("acne", 4, "cleanser", True, "wipe", [])

    assert (mf, mr, note) == (4, "water", None)


def test_wipe_in_history_is_a_bad_removal_pattern():
    past = [
        {"adaptation": {"checkin_extras": {"makeup_used_today": True, "makeup_removal_today": "wipe"}}},
    ]

    mf, mr, note = effective_makeup_with_history("acne", 5, "cleanser", None, None, past)

    assert mr == "water"
    assert note is not None


def test_unknown_removal_value_still_falls_back_to_the_profile():
    mf, mr, _ = effective_makeup_with_history("acne", 3, "double", True, "uydurma", [])

    assert mr == "double"


def test_wipe_as_profile_default_is_treated_as_water():
    _, mr, _ = effective_makeup_with_history("acne", 3, "wipe", None, None, [])

    assert mr == "water"
