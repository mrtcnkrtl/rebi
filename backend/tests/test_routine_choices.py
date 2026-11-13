"""Aynı işi gören maddeler menü olmaz; satır motordan gelen tek formül olarak kalır."""

from flow_engine import attach_structured_fields_to_routine_items, choices_for_routine_item, run_flow


def _attach(item):
    attach_structured_fields_to_routine_items([item])
    return item


def test_formula_stays_one_step_without_a_menu():
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
    assert "choices" not in it
    assert "niasinamid" in it["action"].lower()
    assert "azelaik" in it["action"].lower()


def test_moisturizer_stays_the_written_formula():
    it = {
        "time": "Sabah",
        "category": "Bakım",
        "step_order": 30,
        "action": "Nemlendirici: Niasinamid %5 + Hyaluronik asit (hafif jel)",
    }
    _attach(it)
    assert "choices" not in it
    assert "+" in it["action"]


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


def test_cleanser_or_split_is_not_a_menu():
    it = {
        "time": "Sabah",
        "category": "Bakım",
        "step_order": 10,
        "action": "Temizleme: Misel su veya süt bazlı temizleyici",
    }
    _attach(it)
    assert "choices" not in it


def test_choices_for_item_skips_lifestyle():
    assert (
        choices_for_routine_item(
            {"time": "Günlük", "category": "Yaşam", "action": "Yürüyüş veya hafif hareket"}
        )
        is None
    )


def test_oily_morning_moisturizer_is_one_formula():
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
    actions = [str(i.get("action") or "") for i in r["routine_items"]]
    assert not any(a.lower().startswith("nemlendirici") for a in actions)
    assert not any(a.lower().startswith("gece:") for a in actions)
    oil = next(i for i in r["routine_items"] if "niasinamid" in (i.get("action") or "").lower())
    assert "çinko" in oil["action"].lower()
    assert "choices" not in oil
