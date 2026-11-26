"""Check-in / risk usage önekleri üst üste binmesin; eski kayıtlar tekilleşsin."""

from flow_engine import (
    _dedupe_usage_overlays,
    _strip_checkin_usage_overlays,
    _strip_risk_usage_overlays,
    overlay_daily_risk_on_saved_routine,
    sanitize_routine_items_details,
)


STACKED = (
    "Sıklık/güç hafif düşürüldü: Haftada 1-2x düşür. Tahriş riski azaltıldı. "
    "Check-in: cilt hissi (kuru); haftalık sıklık düşürüldü: Kurulukta sıklık yarıya iner. "
    "Sıklık/güç hafif düşürüldü: Haftada 1-2x düşür. Tahriş riski azaltıldı. "
    "Check-in: cilt hissi (kuru); haftalık sıklık düşürüldü: Kurulukta sıklık yarıya iner. "
    "Sıklık/güç hafif düşürüldü: Haftada 1-2x düşür. Tahriş riski azaltıldı. "
    "Check-in: cilt hissi (kuru); haftalık sıklık düşürüldü: Kurulukta sıklık yarıya iner. "
    "Kişisel not: ince tabaka sür."
)


def test_dedupe_collapses_triple_stack_to_one_of_each():
    out = _dedupe_usage_overlays(STACKED)
    assert out.count("Sıklık/güç hafif düşürüldü") == 1
    assert out.count("Check-in: cilt hissi") == 1
    assert "Kişisel not" in out
    assert ".." not in out


def test_strip_risk_keeps_checkin():
    u = (
        "Sıklık/güç hafif düşürüldü: Haftada 1-2x düşür. Tahriş riski azaltıldı. "
        "Check-in: cilt hissi (kuru); haftalık sıklık düşürüldü: Kurulukta sıklık yarıya iner. "
        "İnce tabaka."
    )
    out = _strip_risk_usage_overlays(u)
    assert "Sıklık/güç" not in out
    assert "Check-in: cilt hissi" in out
    assert "İnce tabaka" in out


def test_strip_checkin_keeps_risk():
    u = (
        "Sıklık/güç hafif düşürüldü: Haftada 1-2x düşür. Tahriş riski azaltıldı. "
        "Check-in: cilt hissi (kuru); haftalık sıklık düşürüldü: Kurulukta sıklık yarıya iner. "
        "İnce tabaka."
    )
    out = _strip_checkin_usage_overlays(u)
    assert "Check-in:" not in out
    assert "Sıklık/güç" in out
    assert "İnce tabaka" in out


def test_sanitize_items_dedupes_usage():
    items = [{"category": "Bakım", "action": "BHA", "usage": STACKED, "detail": "x"}]
    sanitize_routine_items_details(items)
    assert items[0]["usage"].count("Sıklık/güç") == 1
    assert items[0]["usage"].count("Check-in:") == 1


def test_overlay_risk_does_not_stack_on_repeat():
    items = [
        {
            "category": "Bakım",
            "action": "Salisilik asit %0.5 tonik",
            "usage": "İnce tabaka, akşam.",
            "detail": "gözenek",
        }
    ]
    once = overlay_daily_risk_on_saved_routine(items, "high")
    twice = overlay_daily_risk_on_saved_routine(once, "high")
    u = twice[0]["usage"]
    assert u.count("Sıklık/güç hafif düşürüldü") <= 1
    assert "İnce tabaka" in u
