"""Derişik serum: ≤4 gece/hafta, toleransa göre, en fazla 2."""

from flow_engine import (
    concentrated_nights_cap,
    limit_concentrated_evening_serums,
    run_flow,
)


def _flow(**kwargs):
    base = dict(
        age=26,
        gender="female",
        skin_type_key="combination",
        stress_score=4,
        sleep_hours=7.5,
        water_intake=2.0,
        smoking=False,
        alcohol=False,
        uv_index=3,
        humidity=50,
        temperature=22,
        actives_experience="regular",
    )
    base.update(kwargs)
    return run_flow(**base)


def _evening_concentrated(items):
    out = []
    for it in items:
        if it.get("concentrated_serum") or (
            it.get("time") == "Akşam"
            and it.get("category") == "Bakım"
            and isinstance(it.get("weekly_days"), list)
            and it.get("frequency_per_week_cap")
        ):
            out.append(it)
    return out


def test_concentrated_nights_cap_tolerance():
    assert concentrated_nights_cap(experience="regular") == 4
    assert concentrated_nights_cap(experience="occasional") == 3
    assert concentrated_nights_cap(experience="none") == 2
    assert concentrated_nights_cap(
        experience="regular",
        actives_tolerance={"retinol": "mild"},
        families={"retinol"},
    ) == 3
    assert concentrated_nights_cap(
        experience="regular",
        actives_tolerance={"aha": "never"},
        families={"aha"},
    ) == 2
    assert concentrated_nights_cap(
        experience="regular",
        item={"dose_tier": "hassas"},
        families={"pigment"},
    ) == 2


def test_limit_max_two_and_spread_days():
    items = [
        {
            "time": "Akşam",
            "category": "Bakım",
            "action": "Retinol %0.3 serum",
            "detail": "Her gece uygula.",
            "priority": 2,
            "step_order": 20,
            "concern_role": "primary",
            "weekly_days": [0, 1, 2, 3, 4, 5, 6],
        },
        {
            "time": "Akşam",
            "category": "Bakım",
            "action": "Alfa-arbutin %2 serum",
            "detail": "İkincil leke.",
            "priority": 3,
            "step_order": 22,
            "concern_role": "support_pigmentation",
            "weekly_days": [0, 2, 4, 6],
        },
        {
            "time": "Akşam",
            "category": "Bakım",
            "action": "Salisilik asit %2 tonik",
            "detail": "İkincil gözenek.",
            "priority": 3,
            "step_order": 23,
            "concern_role": "support_pores",
            "weekly_days": [1, 3, 5],
        },
        {
            "time": "Akşam",
            "category": "Bakım",
            "action": "Seramid + squalane",
            "detail": "Bariyer.",
            "priority": 3,
            "step_order": 28,
        },
    ]
    out = limit_concentrated_evening_serums(
        items,
        experience="regular",
        ranked=[
            {"id": "aging", "score": 7},
            {"id": "pigmentation", "score": 5},
            {"id": "pores", "score": 5},
        ],
    )
    conc = [i for i in out if i.get("concentrated_serum")]
    assert len(conc) == 2
    assert all(len(i["weekly_days"]) <= 4 for i in conc)
    assert any("retinol" in (i.get("action") or "").lower() for i in conc)
    assert any("seramid" in (i.get("action") or "").lower() for i in out)
    assert not any("salisilik" in (i.get("action") or "").lower() for i in out)


def test_single_concern_keeps_one_concentrated():
    out = limit_concentrated_evening_serums(
        [
            {
                "time": "Akşam",
                "category": "Bakım",
                "action": "Retinol %0.3",
                "detail": "Yaşlanma.",
                "priority": 2,
                "step_order": 20,
            },
            {
                "time": "Akşam",
                "category": "Bakım",
                "action": "Alfa-arbutin %2",
                "detail": "Ekstra.",
                "priority": 3,
                "step_order": 22,
                "concern_role": "support_pigmentation",
            },
        ],
        experience="regular",
        ranked=[{"id": "aging", "score": 6}],
    )
    conc = [i for i in out if i.get("concentrated_serum")]
    assert len(conc) == 1
    assert "retinol" in (conc[0].get("action") or "").lower()


def test_flow_concentrated_never_exceeds_four_nights():
    r = _flow(
        concern="aging",
        severity_score=8,
        actives_experience="regular",
    )
    for it in r["routine_items"]:
        if not it.get("concentrated_serum"):
            continue
        wd = it.get("weekly_days") or []
        assert len(wd) <= 4
        assert it.get("frequency_per_week_cap", 4) <= 4


def test_flow_stings_caps_to_two_nights():
    """Batma → bariyer fazı; derişik akne aktifi yok. Streak/cap bariyer sonrası tedavi için geçerli."""
    r = _flow(
        concern="acne",
        severity_score=5,
        special_flags={"stings_with_products": True},
        actives_experience="regular",
    )
    assert r["multi_concern"]["phase"] == "barrier"
    conc = [i for i in r["routine_items"] if i.get("concentrated_serum")]
    for it in conc:
        assert len(it.get("weekly_days") or []) <= 2
    # Bariyer odaklı gece kremi (cica|panthenol)
    care = " ".join(
        (i.get("action") or "").lower()
        for i in r["routine_items"]
        if i.get("category") in ("Bakım", "Koruma")
    )
    assert "panthenol" in care or "centella" in care or "cica" in care


def test_flow_max_two_when_secondary_needed():
    r = _flow(
        concern="acne",
        severity_score=6,
        concerns=[
            {"id": "acne", "severity_score": 6},
            {"id": "pigmentation", "severity_score": 5},
            {"id": "pores", "severity_score": 5},
        ],
    )
    conc = [i for i in r["routine_items"] if i.get("concentrated_serum")]
    assert len(conc) <= 2
