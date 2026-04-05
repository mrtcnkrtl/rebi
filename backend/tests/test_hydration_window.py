from datetime import date

from hydration_window import compute_effective_water_liters, dates_in_window, water_liters_from_day_events


def test_water_liters_from_day_events_none():
    assert water_liters_from_day_events([]) is None
    assert water_liters_from_day_events([{"type": "stress", "payload": {}}]) is None


def test_water_liters_from_day_events_sum():
    ev = [
        {"type": "water_intake", "payload": {"ml": 500}},
        {"type": "water_intake", "payload": {"ml": 300}},
    ]
    assert abs(water_liters_from_day_events(ev) - 0.8) < 1e-6


def test_compute_no_tracking_uses_profile():
    prof = 2.0
    series = [("2026-04-01", None), ("2026-03-31", None)]
    w, note = compute_effective_water_liters(prof, series)
    assert w == prof
    assert "yok" in note.lower() or "profil" in note.lower()


def test_compute_blend_multi_day():
    prof = 2.0
    # bugün 0.5, dün 0.5, önceki günler bilinmiyor
    series = [
        ("d0", 0.5),
        ("d1", 0.5),
        ("d2", None),
        ("d3", None),
        ("d4", None),
        ("d5", None),
        ("d6", None),
    ]
    w, _ = compute_effective_water_liters(prof, series)
    assert 0.4 <= w <= 0.6


def test_dates_in_window_len():
    d = date(2026, 4, 1)
    xs = dates_in_window(d, 7)
    assert len(xs) == 7
    assert xs[0] == "2026-04-01"
