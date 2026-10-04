from __future__ import annotations

from main import _aggregate_daily_events
from today_plan import (
    WATER_TARGET_ML,
    build_environment_advice,
    build_reminders,
)


def _event(event_type: str, payload: dict, event_time: str = "2026-10-04T09:00:00+00:00") -> dict:
    return {"type": event_type, "payload": payload, "event_time": event_time}


def _ids(reminders: list[dict]) -> set[str]:
    return {r["id"] for r in reminders}


def test_makeup_events_collapse_into_one_state():
    agg = _aggregate_daily_events([
        _event("makeup", {"used": True}),
        _event("makeup", {"removed": True, "method": "double"}),
    ])

    assert agg["makeup"] == {
        "logged": True,
        "used": True,
        "removed": True,
        "removal_method": "double",
    }


def test_makeup_not_used_is_logged_without_removal():
    agg = _aggregate_daily_events([_event("makeup", {"used": False})])

    assert agg["makeup"]["logged"] is True
    assert agg["makeup"]["used"] is False
    assert agg["makeup"]["removed"] is False


def test_unknown_removal_method_is_dropped():
    agg = _aggregate_daily_events([_event("makeup", {"used": True, "method": "serviette"})])

    assert agg["makeup"]["removal_method"] is None
    assert agg["makeup"]["removed"] is False


def test_finished_products_are_listed_with_timestamp():
    agg = _aggregate_daily_events([
        _event("product_finished", {"product": "Niasinamid serum", "step_order": 20}),
    ])

    assert agg["products_finished"] == [{
        "product": "Niasinamid serum",
        "step_order": 20,
        "at": "2026-10-04T09:00:00+00:00",
    }]


def test_routine_blocks_are_tracked_separately():
    agg = _aggregate_daily_events([_event("routine_completed_block", {"morning": True})])

    assert agg["routine_morning_done"] is True
    assert agg["routine_evening_done"] is False
    assert agg["routine_steps_done"] == 1


def test_empty_day_asks_for_every_log():
    reminders = build_reminders({"uv_index": 3, "humidity": 50, "temperature": 20}, {})

    assert _ids(reminders) >= {
        "routine_morning",
        "routine_evening",
        "makeup_log",
        "water_intake",
        "nutrition_log",
        "daily_checkin",
    }
    assert [r["start"] for r in reminders] == sorted(r["start"] for r in reminders)


def test_completed_work_drops_its_reminder():
    agg = _aggregate_daily_events([
        _event("routine_completed_block", {"morning": True, "evening": True}),
        _event("water_intake", {"ml": WATER_TARGET_ML}),
        _event("nutrition", {"junk_food": False}),
        _event("makeup", {"used": False}),
    ])

    reminders = build_reminders({"uv_index": 3, "humidity": 50, "temperature": 20}, agg, checkin_done=True)

    assert reminders == []


def test_makeup_day_adds_evening_cleansing_reminder():
    agg = _aggregate_daily_events([_event("makeup", {"used": True})])

    reminders = build_reminders({"uv_index": 3, "humidity": 50, "temperature": 20}, agg)
    removal = next(r for r in reminders if r["id"] == "makeup_removal")

    assert removal["log_event"] == "makeup"
    assert (removal["start"], removal["end"]) == ("21:00", "23:00")
    assert "makeup_log" not in _ids(reminders)


def test_removed_makeup_needs_no_cleansing_reminder():
    agg = _aggregate_daily_events([_event("makeup", {"removed": True, "method": "cleanser"})])

    assert "makeup_removal" not in _ids(build_reminders({}, agg))


def test_spf_refresh_only_when_uv_is_high_and_not_done():
    high_uv = {"uv_index": 7, "humidity": 50, "temperature": 20}

    assert "spf_refresh" in _ids(build_reminders(high_uv, {}))
    assert "spf_refresh" not in _ids(build_reminders({"uv_index": 2, "humidity": 50, "temperature": 20}, {}))

    done = _aggregate_daily_events([_event("spf_refresh", {}), _event("spf_refresh", {})])
    assert "spf_refresh" not in _ids(build_reminders(high_uv, done))


def test_lip_balm_reminder_follows_cold_or_dry_weather():
    assert "lip_balm" in _ids(build_reminders({"uv_index": 2, "humidity": 50, "temperature": 4}, {}))
    assert "lip_balm" in _ids(build_reminders({"uv_index": 2, "humidity": 20, "temperature": 22}, {}))
    assert "lip_balm" not in _ids(build_reminders({"uv_index": 2, "humidity": 55, "temperature": 22}, {}))


def test_water_reminder_repeats_until_target_is_reached():
    water = next(r for r in build_reminders({}, {}) if r["id"] == "water_intake")

    assert water["every_minutes"] == 120
    assert water["log_event"] == "water_intake"

    almost = _aggregate_daily_events([_event("water_intake", {"ml": WATER_TARGET_ML - 1})])
    assert "water_intake" in _ids(build_reminders({}, almost))


def test_advice_covers_sunscreen_moisturizer_and_balm():
    advice = build_environment_advice({"uv_index": 9, "humidity": 20, "temperature": 3}, "dry")
    actions = " ".join(item["action"].lower() for item in advice)

    assert "spf" in actions
    assert "dudak balsamı" in actions
    assert any("Bakım" == item["category"] for item in advice)


def test_advice_falls_back_to_normal_skin_for_unknown_type():
    known = build_environment_advice({"uv_index": 6, "humidity": 50, "temperature": 20}, "normal")
    unknown = build_environment_advice({"uv_index": 6, "humidity": 50, "temperature": 20}, "bilinmiyor")

    assert known == unknown
