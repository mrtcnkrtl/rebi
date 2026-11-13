"""Ana ekrandaki "bu hafta" şeridi: `/today/plan` yanıtındaki `week` (son 7 günün sabah/akşam rutini)."""

from __future__ import annotations

from datetime import date, timedelta

import main
from fake_supabase import FakeSupabase

USER = "11111111-1111-4111-8111-111111111111"
TODAY = date(2026, 11, 13)


def _done(day: date, **blocks) -> dict:
    return {"user_id": USER, "type": "routine_completed_block", "log_date": str(day), "payload": blocks,
            "event_time": f"{day}T09:00:00+00:00"}


def _week(monkeypatch, rows, progress=None):
    db = FakeSupabase(daily_events=rows)
    monkeypatch.setattr(main, "should_use_supabase_db", lambda sb, uid: True)
    return main._routine_week(db, USER, TODAY, progress or {})


def test_seven_days_oldest_first_today_from_progress(monkeypatch):
    week = _week(monkeypatch, [], {"routine_morning_done": True, "routine_evening_done": False})
    assert [d["log_date"] for d in week] == [str(TODAY - timedelta(days=6 - i)) for i in range(7)]
    assert week[-1] == {"log_date": str(TODAY), "morning": True, "evening": False}
    assert all(not d["morning"] and not d["evening"] for d in week[:-1])


def test_previous_days_come_from_completed_block_events(monkeypatch):
    rows = [
        _done(TODAY - timedelta(days=1), morning=True),
        _done(TODAY - timedelta(days=1), evening=True),
        _done(TODAY - timedelta(days=3), morning=True),
        # Yeniden açma: aynı blok için son olay geçerli.
        {**_done(TODAY - timedelta(days=3), morning=False), "event_time": f"{TODAY - timedelta(days=3)}T10:00:00+00:00"},
        # Pencere dışı (8 gün önce) ve başka kullanıcı sayılmaz.
        _done(TODAY - timedelta(days=8), morning=True, evening=True),
        {**_done(TODAY - timedelta(days=2), morning=True), "user_id": "someone-else"},
    ]
    week = {d["log_date"]: d for d in _week(monkeypatch, rows)}
    assert week[str(TODAY - timedelta(days=1))] == {"log_date": str(TODAY - timedelta(days=1)), "morning": True, "evening": True}
    assert week[str(TODAY - timedelta(days=3))]["morning"] is False
    assert week[str(TODAY - timedelta(days=2))]["morning"] is False
    assert len(week) == 7


def test_today_events_are_not_double_counted_from_the_table(monkeypatch):
    # Bugünün olayı tabloda olsa da bugün yalnızca `progress`ten okunur (blok yeniden açıldıysa progress false der).
    week = _week(monkeypatch, [_done(TODAY, morning=True)], {"routine_morning_done": False})
    assert week[-1]["morning"] is False


def test_database_error_yields_empty_previous_days(monkeypatch):
    class Broken:
        def table(self, name):
            raise RuntimeError("db down")

    monkeypatch.setattr(main, "should_use_supabase_db", lambda sb, uid: True)
    week = main._routine_week(Broken(), USER, TODAY, {"routine_evening_done": True})
    assert len(week) == 7
    assert week[-1]["evening"] is True
    assert not any(d["morning"] or d["evening"] for d in week[:-1])
