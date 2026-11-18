"""Çoklu sorun: şiddet sıralaması, bariyer-önce tek odak, check-in ilerleme."""

from flow_engine import adapt_existing_routine, apply_focus_checkin_advance, run_flow
from multi_concern import (
    barrier_needs_repair,
    build_focus_queue,
    build_guards,
    normalize_concern_entries,
    rank_concerns,
)


def _blob(items):
    parts = []
    for i in items:
        parts.append(str(i.get("action") or ""))
        parts.append(str(i.get("detail") or ""))
        for c in i.get("choices") or []:
            parts.append(str(c.get("action") or ""))
    return " ".join(parts).lower()


def _care_blob(items):
    """Bakım/Koruma only — Sonra plan satırlarını hariç tut."""
    return " ".join(
        f"{i.get('action') or ''} {i.get('detail') or ''}"
        for i in items
        if i.get("category") in ("Bakım", "Koruma")
    ).lower()


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


def test_rank_highest_severity_first_not_selection_order():
    ranked = rank_concerns(
        normalize_concern_entries(
            concern="pigmentation",
            severity_score=4,
            concerns=[
                {"id": "pigmentation", "severity_score": 4},
                {"id": "acne", "severity_score": 8, "zones": ["chin"]},
                {"id": "oiliness", "severity_score": 3},
            ],
        )
    )
    assert ranked[0]["id"] == "acne"
    assert ranked[0]["score"] == 8
    assert [e["id"] for e in ranked] == ["acne", "pigmentation", "oiliness"]


def test_tie_break_acne_before_oiliness():
    ranked = rank_concerns(
        normalize_concern_entries(
            concern="oiliness",
            severity_score=6,
            concerns=[
                {"id": "oiliness", "severity_score": 6},
                {"id": "acne", "severity_score": 6},
            ],
        )
    )
    assert ranked[0]["id"] == "acne"


def test_run_flow_ignores_first_selected_uses_highest_score():
    r = _flow(
        concern="pigmentation",
        severity_score=3,
        concerns=[
            {"id": "pigmentation", "severity_score": 3, "zones": ["left_cheek"]},
            {"id": "acne", "severity_score": 9, "zones": ["chin"]},
        ],
    )
    assert r["multi_concern"]["primary"] == "acne"
    assert r["multi_concern"]["phase"] == "treatment"
    blob = _care_blob(r["routine_items"])
    assert "benzoil" in blob or "azelaik" in blob
    assert "çene" in blob
    deferred_ids = [d["id"] for d in r["multi_concern"]["deferred"]]
    assert "pigmentation" in deferred_ids
    # İkincil leke serumu Bakım'da yok (Sonra planında olabilir)
    assert "heksilrezorsinol" not in blob
    assert "arbutin" not in blob


def test_pigmentation_plus_acne_chin_still_gets_zone():
    r = _flow(
        concern="pigmentation",
        severity_score=8,
        concerns=[
            {"id": "pigmentation", "severity_score": 8},
            {"id": "acne", "severity_score": 5, "zones": ["chin"]},
        ],
    )
    assert r["multi_concern"]["primary"] == "pigmentation"
    blob = _blob(r["routine_items"])
    assert "çene" in blob
    assert "retinol" in blob
    assert "arbutin" not in blob
    assert "glikolik" not in blob
    assert r["acne_zone_info"]


def test_oiliness_pores_acne_are_not_the_same_skeleton():
    oily = _blob(_flow(concern="oiliness", severity_score=3)["routine_items"])
    pores = _blob(_flow(concern="pores", severity_score=3)["routine_items"])
    acne = _blob(_flow(concern="acne", severity_score=3)["routine_items"])

    assert "çinko" in oily or "niasinamid" in oily or "yeşil çay" in oily
    assert "salisilik" not in oily  # düşük yağlılıkta BHA yok
    assert "benzoil" not in oily

    assert "salisilik" in pores
    assert "benzoil" not in pores

    assert "salisilik" in acne
    assert "lezyon" in acne or "akne" in acne


def test_oiliness_high_adds_low_bha_still_no_bpo():
    oily = _blob(_flow(concern="oiliness", severity_score=9)["routine_items"])
    assert "salisilik" in oily
    assert "%0.5" in oily or "%1" in oily
    assert "benzoil" not in oily


def test_sensitivity_plus_acne_barrier_first_no_bpo():
    r = _flow(
        concern="acne",
        severity_score=9,
        concerns=[
            {"id": "acne", "severity_score": 9},
            {"id": "sensitivity", "severity_score": 7},
        ],
    )
    assert r["multi_concern"]["phase"] == "barrier"
    assert r["multi_concern"]["primary"] in ("sensitivity", "dryness")
    deferred_ids = [d["id"] for d in r["multi_concern"]["deferred"]]
    assert "acne" in deferred_ids
    blob = _blob(r["routine_items"])
    assert "benzoil" not in blob
    assert r["multi_concern"]["guards"]["avoid_bpo"] is True
    assert any(i.get("concern_role") == "focus_state" for i in r["routine_items"])


def test_highest_dryness_barrier_before_mild_acne():
    r = _flow(
        concern="acne",
        severity_score=3,
        concerns=[
            {"id": "acne", "severity_score": 3},
            {"id": "dryness", "severity_score": 8},
        ],
    )
    assert r["multi_concern"]["phase"] == "barrier"
    assert r["multi_concern"]["primary"] == "dryness"
    blob = _blob(r["routine_items"])
    assert "nemlendirici" in blob or "linolenik" in blob or "panthenol" in blob or "seramid" in blob or "centella" in blob or "cica" in blob
    assert "benzoil" not in blob
    assert "acne" in [d["id"] for d in r["multi_concern"]["deferred"]]


def test_dryness_ge6_barrier_defers_acne_no_secondary_stack():
    r = _flow(
        concern="acne",
        severity_score=8,
        concerns=[
            {"id": "acne", "severity_score": 8},
            {"id": "dryness", "severity_score": 6},
        ],
    )
    assert r["multi_concern"]["phase"] == "barrier"
    blob = _care_blob(r["routine_items"])
    assert "benzoil" not in blob
    # Bariyer gece kremi birleşik; ayrı support_oiliness yok
    assert "support_oiliness" not in blob
    assert (
        "panthenol" in blob
        or "centella" in blob
        or "cica" in blob
        or "nemlendirici" in blob
    )


def test_pigmentation_forces_spf_50_but_not_stacked_serum():
    r = _flow(
        concern="acne",
        severity_score=6,
        uv_index=2,
        concerns=[
            {"id": "acne", "severity_score": 6},
            {"id": "pigmentation", "severity_score": 4},
        ],
    )
    blob = _care_blob(r["routine_items"])
    assert "spf 50" in blob
    assert r["multi_concern"]["primary"] == "acne"
    assert "pigmentation" in [d["id"] for d in r["multi_concern"]["deferred"]]
    # İkincil leke serumu Bakım'da yok
    assert "heksilrezorsinol" not in blob
    assert "arbutin" not in blob


def test_no_morning_treatment_when_focus_acne():
    r = _flow(concern="acne", severity_score=5)
    morning = [
        i for i in r["routine_items"]
        if i.get("time") == "Sabah" and i.get("category") == "Bakım"
    ]
    blob = " ".join((i.get("action") or "").lower() for i in morning)
    assert "salisilik" not in blob
    assert "retinol" not in blob
    assert "yeşil çay" not in blob


def test_barrier_needs_repair_thresholds():
    assert barrier_needs_repair(
        [{"id": "acne", "score": 9}, {"id": "sensitivity", "score": 5}]
    )
    assert barrier_needs_repair(
        [{"id": "acne", "score": 8}, {"id": "dryness", "score": 6}]
    )
    assert barrier_needs_repair([], stings_with_products=True)
    assert not barrier_needs_repair([{"id": "acne", "score": 8}])


def test_build_focus_queue_defers_rest():
    ranked = rank_concerns(
        [
            {"id": "acne", "score": 8, "zones": []},
            {"id": "pigmentation", "score": 5, "zones": []},
            {"id": "undereye", "score": 4, "zones": []},
        ]
    )
    q = build_focus_queue(ranked)
    assert q["phase"] == "treatment"
    assert q["focus"]["id"] == "acne"
    assert [d["id"] for d in q["deferred"]] == ["pigmentation", "undereye"]
    assert q["advance_rule"] == "resolved_after_min_days"


def _backdate_focus(items, days=14):
    """Test: odakta N gün geçmiş gibi focus_started_on ayarla."""
    from datetime import date, timedelta

    started = (date.today() - timedelta(days=days)).isoformat()
    for it in items:
        if it.get("concern_role") == "focus_state":
            it["focus_started_on"] = started
    return items


def test_checkin_resolved_after_min_days_advances_focus():
    r = _flow(
        concern="acne",
        severity_score=8,
        concerns=[
            {"id": "acne", "severity_score": 8},
            {"id": "pigmentation", "severity_score": 5},
        ],
    )
    items = r["routine_items"]
    focus = next(i for i in items if i.get("concern_role") == "focus_state")
    assert focus["focus_id"] == "acne"
    assert focus.get("focus_started_on")
    assert "şimdiden alma" in (focus.get("detail") or "").lower()
    # 2. sorun maddesi plana yazılır ama Bakım adımı olmaz
    plan = focus.get("deferred_plan") or []
    assert any(p.get("id") == "pigmentation" for p in plan)
    assert any(i.get("concern_role") == "deferred_preview" for i in items)
    care = " ".join(
        (i.get("action") or "") for i in items if i.get("category") in ("Bakım", "Koruma")
    ).lower()
    assert "traneksamik" not in care and "kojik" not in care

    # Erken «çözüldü» → geçiş yok
    items2, ch_early, adv_early = apply_focus_checkin_advance(
        items, skin_feeling="iyi", concern_resolved=True
    )
    assert adv_early is False
    f2 = next(i for i in items2 if i.get("concern_role") == "focus_state")
    assert f2["focus_id"] == "acne"
    early_txt = (f2.get("detail") or "") + " ".join(c.get("reason") or "" for c in ch_early)
    assert "en az" in early_txt.lower()

    # Min gün + çözüldü → lekeye geç
    _backdate_focus(items2, days=14)
    items3, _, adv2 = apply_focus_checkin_advance(
        items2, skin_feeling="iyi", concern_resolved=True
    )
    assert adv2 is True
    f3 = next(i for i in items3 if i.get("concern_role") == "focus_state")
    assert f3["focus_id"] == "pigmentation"
    blob = _blob(items3)
    assert "traneksamik" in blob or "kojik" in blob or "meyan" in blob or "retinol" in blob
    assert "benzoil" not in blob


def test_deferred_actives_only_appear_after_focus_advance():
    """Bariyerde akne/yağ maddesi yok; check-in ilerleyince odak maddesi gelir, diğeri hâlâ yok."""
    r = _flow(
        concern="oiliness",
        severity_score=6,
        concerns=[
            {"id": "oiliness", "severity_score": 6},
            {"id": "acne", "severity_score": 7},
            {"id": "sensitivity", "severity_score": 8},
        ],
    )
    assert r["multi_concern"]["phase"] == "barrier"
    focus0 = next(i for i in r["routine_items"] if i.get("concern_role") == "focus_state")
    plan0 = focus0.get("deferred_plan") or []
    assert {p.get("id") for p in plan0} >= {"acne", "oiliness"}
    care0 = " ".join(
        (i.get("action") or "") for i in r["routine_items"] if i.get("category") in ("Bakım", "Koruma")
    ).lower()
    assert "azelaik" not in care0 and "benzoil" not in care0
    assert "yeşil çay" not in care0 and "egcg" not in care0
    assert "şimdiden alma" in (focus0.get("detail") or "").lower()
    # Plan satırlarında madde yazılı (Yaşam / sonra)
    preview = " ".join(
        (i.get("action") or "") for i in r["routine_items"] if i.get("concern_role") == "deferred_preview"
    ).lower()
    assert "azelaik" in preview or "benzoil" in preview
    assert "yeşil çay" in preview or "egcg" in preview

    items = _backdate_focus(list(r["routine_items"]), days=14)
    items, _, a1 = apply_focus_checkin_advance(
        items, skin_feeling="iyi", concern_resolved=True
    )
    assert a1 is True
    f = next(i for i in items if i.get("concern_role") == "focus_state")
    assert f["focus_id"] == "acne"
    care1 = " ".join(
        (i.get("action") or "") for i in items if i.get("category") in ("Bakım", "Koruma")
    ).lower()
    assert "azelaik" in care1 or "benzoil" in care1 or "salisilik" in care1
    assert "yeşil çay" not in care1 and "egcg" not in care1

    items = _backdate_focus(items, days=14)
    items, _, a2 = apply_focus_checkin_advance(
        items, skin_feeling="iyi", concern_resolved=True
    )
    assert a2 is True
    f2 = next(i for i in items if i.get("concern_role") == "focus_state")
    assert f2["focus_id"] == "oiliness"
    care2 = " ".join(
        (i.get("action") or "") for i in items if i.get("category") in ("Bakım", "Koruma")
    ).lower()
    assert "yeşil çay" in care2 or "egcg" in care2
    assert "azelaik" not in care2 and "benzoil" not in care2


def test_checkin_irritasyon_returns_to_barrier():
    r = _flow(
        concern="acne",
        severity_score=8,
        concerns=[{"id": "acne", "severity_score": 8}],
    )
    items, _, adv = apply_focus_checkin_advance(r["routine_items"], skin_feeling="irritasyon")
    assert adv is True
    f = next(i for i in items if i.get("concern_role") == "focus_state")
    assert f["phase"] == "barrier" or f["focus_id"] == "barrier"


def test_adapt_existing_routine_resolved_too_early_stays():
    r = _flow(
        concern="acne",
        severity_score=7,
        concerns=[
            {"id": "acne", "severity_score": 7},
            {"id": "pores", "severity_score": 4},
        ],
    )
    out = adapt_existing_routine(
        r["routine_items"],
        {
            "skin_feeling": "iyi",
            "concern_resolved": True,
            "sleep_hours": 7,
            "stress_today": 2,
        },
        {"level": "normal", "score": 1, "detail": ""},
    )
    assert out.get("focus_advanced") is False
    f = next(i for i in out["adapted_items"] if i.get("concern_role") == "focus_state")
    assert f["focus_id"] == "acne"
    assert f.get("focus_started_on")


def test_guards_from_all_selected():
    g = build_guards(
        [{"id": "acne", "score": 8}, {"id": "sensitivity", "score": 6}, {"id": "dryness", "score": 5}]
    )
    assert g["avoid_bpo"] is True
    assert g["max_bha_pct"] <= 1.0
    assert g["force_starter"] is True
