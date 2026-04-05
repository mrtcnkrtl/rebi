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
