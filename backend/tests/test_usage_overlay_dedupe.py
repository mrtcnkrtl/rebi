"""Check-in / risk usage: motor jargonu kullanıcıya sızmasın; önekler tek kalsın."""

from flow_engine import (
    _dedupe_usage_overlays,
    _risk_condition_sentence,
    _strip_checkin_usage_overlays,
    _strip_risk_usage_overlays,
    overlay_daily_risk_on_saved_routine,
    sanitize_routine_items_details,
)


STACKED_LEGACY = (
    "Sıklık/güç hafif düşürüldü: Haftada 1-2x düşür. Tahriş riski azaltıldı. "
    "Check-in: cilt hissi (kuru); haftalık sıklık düşürüldü: Kurulukta sıklık yarıya iner. "
    "Sıklık/güç hafif düşürüldü: Haftada 1-2x düşür. Tahriş riski azaltıldı. "
    "Check-in: cilt hissi (kuru); haftalık sıklık düşürüldü: Kurulukta sıklık yarıya iner. "
    "Kişisel not: ince tabaka sür."
)


def test_sanitize_strips_legacy_motor_jargon_from_usage():
    items = [{"category": "Bakım", "action": "BHA", "usage": STACKED_LEGACY, "detail": "x"}]
    sanitize_routine_items_details(items)
    u = items[0]["usage"]
    assert "Sıklık/güç" not in u
    assert "Check-in:" not in u
    assert "Tahriş riski" not in u
    assert "Kişisel not" in u


def test_dedupe_does_not_reintroduce_legacy_jargon():
    only_legacy = (
        "Sıklık/güç hafif düşürüldü: Haftada 2-3x düşür. Tahriş riski azaltıldı. "
        "Sıklık/güç hafif düşürüldü: Haftada 2-3x düşür. Tahriş riski azaltıldı."
    )
    out = _dedupe_usage_overlays(only_legacy)
    assert out == ""
    assert "Sıklık/güç" not in out


def test_risk_sentence_is_user_facing():
    s = _risk_condition_sentence("high", 0.5, "Haftada 1-2x düşür", paused=False)
    assert "Sıklık/güç" not in s
    assert "Tahriş riski" not in s
    assert "Cildin hassas" in s


def test_strip_risk_keeps_user_checkin():
    u = (
        "Cildin hassas görünüyor; bu adımı biraz daha seyrek kullanmanı öneririm (Haftada 1-2x düşür). "
        "Cildin “kuru” hissettiği için bu hafta sıklığı azalttım: Kurulukta sıklık yarıya iner. "
        "İnce tabaka."
    )
    out = _strip_risk_usage_overlays(u)
    assert "Cildin hassas" not in out
    assert "hissettiği için" in out
    assert "İnce tabaka" in out


def test_strip_checkin_keeps_risk():
    u = (
        "Cildin hassas görünüyor; bu adımı biraz daha seyrek kullanmanı öneririm (Haftada 1-2x düşür). "
        "Cildin “kuru” hissettiği için bu hafta sıklığı azalttım: Kurulukta sıklık yarıya iner. "
        "İnce tabaka."
    )
    out = _strip_checkin_usage_overlays(u)
    assert "hissettiği için" not in out
    assert "Cildin hassas" in out
    assert "İnce tabaka" in out


def test_dedupe_friendly_overlays():
    stacked = (
        "Cildin hassas görünüyor; bu adımı biraz daha seyrek kullanmanı öneririm (Haftada 1-2x düşür). "
        "Cildin “kuru” hissettiği için bu hafta sıklığı azalttım: Kurulukta sıklık yarıya iner. "
        "Cildin hassas görünüyor; bu adımı biraz daha seyrek kullanmanı öneririm (Haftada 1-2x düşür). "
        "Cildin “kuru” hissettiği için bu hafta sıklığı azalttım: Kurulukta sıklık yarıya iner. "
        "İnce tabaka."
    )
    out = _dedupe_usage_overlays(stacked)
    assert out.count("Cildin hassas görünüyor") == 1
    assert out.count("hissettiği için") == 1
    assert "İnce tabaka" in out


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
    assert u.count("Cildin hassas görünüyor") <= 1
    assert "Sıklık/güç" not in u
    assert "İnce tabaka" in u
