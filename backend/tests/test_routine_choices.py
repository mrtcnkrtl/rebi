"""Rutin adımlarında gerçek 2 yollu seçenek kartları."""

from flow_engine import attach_structured_fields_to_routine_items, choices_for_routine_item, run_flow


def _attach(item):
    attach_structured_fields_to_routine_items([item])
    return item


def test_choices_sequential_or_single_formula():
    it = {
        "time": "Akşam",
        "category": "Bakım",
        "step_order": 20,
        "action": (
            "Niasinamid %10 serum (INCI: Niacinamide; niasin ile karıştırma) + "
            "Azelaik asit %10-15 (INCI: Azelaic Acid; dikarboksilli asit) "
            "(sırayla veya tek formül)"
        ),
    }
    _attach(it)
    ids = {c["id"] for c in it["choices"]}
    assert ids == {"single", "sequence"}
    assert it["choice_key"]
    seq = next(c for c in it["choices"] if c["id"] == "sequence")
    assert "→ sonra" in seq["action"]


def test_choices_moisturizer_two_ingredients():
    it = {
        "time": "Sabah",
        "category": "Bakım",
        "step_order": 30,
        "action": "Nemlendirici: Niasinamid %5 + Hyaluronik asit (hafif jel)",
    }
    _attach(it)
    assert len(it["choices"]) == 2
    labels = {c["label"] for c in it["choices"]}
    assert "Niasinamid %5" in labels
    assert "Hyaluronik asit" in labels


def test_no_choices_canonical_311():
    it = {
        "time": "Akşam",
        "category": "Bakım",
        "step_order": 30,
        "action": "Gece: Seramid %2-5 + Kolesterol + Yağ asidi (3:1:1 oran, gece onarım)",
    }
    _attach(it)
    assert "choices" not in it


def test_no_choices_three_ingredient_barrier():
    it = {
        "time": "Sabah",
        "category": "Bakım",
        "step_order": 30,
        "action": "Nemlendirici: Seramid %2-5 + Squalane + Kolesterol (bariyer kremi)",
    }
    _attach(it)
    assert "choices" not in it


def test_choices_cleanser_or_split():
    it = {
        "time": "Sabah",
        "category": "Bakım",
        "step_order": 10,
        "action": "Temizleme: Misel su veya süt bazlı temizleyici",
    }
    _attach(it)
    labels = {c["label"] for c in it["choices"]}
    assert "Misel su" in labels
    assert "süt bazlı temizleyici" in labels


def test_choices_for_item_skips_lifestyle():
    assert (
        choices_for_routine_item(
            {"time": "Günlük", "category": "Yaşam", "action": "Yürüyüş veya hafif hareket"}
        )
        is None
    )


def test_oily_morning_moisturizer_offers_two_picks():
    r = run_flow(
        age=26,
        gender="female",
        skin_type_key="oily",
        concern="oiliness",
        severity_score=4,
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
    moist = [
        i
        for i in r["routine_items"]
        if str(i.get("action") or "").lower().startswith("nemlendirici")
    ]
    assert moist
    assert len(moist[0].get("choices") or []) == 2
