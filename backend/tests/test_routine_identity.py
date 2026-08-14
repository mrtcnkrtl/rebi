"""Routine identity: stamp ids from engine phrases, check-in by id, cabinet plan."""

from knowledge.routine_identity import (
    stamp_canonical_ids,
    trigger_for_item,
    build_cabinet_active_plan,
)
import knowledge.cabinet_router as cr


def test_stamp_reads_engine_retinol_and_bha_from_action_not_detail():
    items = [
        {
            "category": "Bakım",
            "time": "Akşam",
            "action": "Serbest retinol %0.3 (INCI: Retinol; A vitamini alkolü — retinyl palmitat/ester türleri değil)",
            "detail": "",
            "step_order": 20,
        },
        {
            "category": "Bakım",
            "time": "Akşam",
            "action": "Salisilik asit %2 tonik (BHA, INCI: Salicylic Acid)",
            "detail": "Hamilelikte retinol yasak.",
            "step_order": 20,
        },
        {
            "category": "Bakım",
            "time": "Akşam",
            "action": "🤰 Bakuchiol (Hamilelik Güvenli)",
            "detail": "Hamilelikte retinol yasak.",
            "step_order": 20,
        },
    ]
    stamp_canonical_ids(items)
    assert "retinol" in items[0]["canonical_ingredient_ids"]
    assert "salisilik_asit" in items[1]["canonical_ingredient_ids"]
    assert "retinol" not in items[1]["canonical_ingredient_ids"]
    assert "bakuchiol" in items[2]["canonical_ingredient_ids"]
    assert "retinol" not in items[2]["canonical_ingredient_ids"]


def test_stamp_multi_ids_on_combined_night_cream():
    items = [
        {
            "category": "Bakım",
            "time": "Akşam",
            "action": "Gece (yoğun tek katman): Seramid %2-5 + Kolesterol + Gliserin + Üre",
            "detail": "",
            "step_order": 30,
        }
    ]
    stamp_canonical_ids(items)
    ids = set(items[0]["canonical_ingredient_ids"])
    assert {"seramidler", "cholesterol", "glycerin", "urea"} <= ids


def test_checkin_pauses_retinol_serum_but_not_urea_in_barrier_cream():
    serum = {
        "category": "Bakım",
        "action": "Serbest retinol %0.3 (INCI: Retinol)",
        "step_order": 20,
        "canonical_ingredient_ids": ["retinol"],
    }
    cream = {
        "category": "Bakım",
        "action": "Gece: Seramid + Üre",
        "step_order": 30,
        "canonical_ingredient_ids": ["seramidler", "urea"],
    }
    t_serum = trigger_for_item(serum, "irritasyon")
    t_cream = trigger_for_item(cream, "irritasyon")
    assert t_serum["action"] == "pause"
    assert t_cream["action"] == "increase"


def test_cabinet_plan_drops_pregnant_unsafe_and_missing(monkeypatch):
    monkeypatch.setattr(
        cr,
        "chain_actives_for_concern",
        lambda *a, **k: [
            {"ingredient_id": "retinol", "name_tr": "Retinol", "priority": 1, "effect_status": "supports", "time_of_day": "PM", "notes_tr": "Gece."},
            {"ingredient_id": "niacinamid", "name_tr": "Niasinamid", "priority": 1, "effect_status": "supports", "time_of_day": "AM/PM", "notes_tr": "B3."},
            {"ingredient_id": "mineral_spf", "name_tr": "SPF", "priority": 1, "effect_status": "supports", "time_of_day": "AM", "notes_tr": "Sabah."},
        ],
    )
    monkeypatch.setattr(cr, "tag_items_with_canonical_ids", lambda items: 0)
    items = [
        {"category": "Bakım", "action": "Niasinamid %10 serum (INCI: Niacinamide)", "step_order": 20},
        {"category": "Koruma", "action": "SPF 50 (geniş spektrumlu SPF)", "step_order": 40},
    ]
    plan = build_cabinet_active_plan("acne", items, is_pregnant=True, avoided_families=set())
    actives = {p["active"] for p in plan}
    assert "retinol" not in actives
    assert "niacinamid" in actives
    assert "mineral_spf" in actives or any(p["role"] == "spf" for p in plan)


def test_cabinet_plan_respects_bha_tolerance(monkeypatch):
    monkeypatch.setattr(
        cr,
        "chain_actives_for_concern",
        lambda *a, **k: [
            {"ingredient_id": "salisilik_asit", "name_tr": "BHA", "priority": 1, "effect_status": "supports", "time_of_day": "PM", "notes_tr": ""},
            {"ingredient_id": "niacinamid", "name_tr": "Niasinamid", "priority": 1, "effect_status": "supports", "time_of_day": "PM", "notes_tr": ""},
        ],
    )
    monkeypatch.setattr(cr, "tag_items_with_canonical_ids", lambda items: 0)
    items = [
        {"category": "Bakım", "action": "Salisilik asit %2 tonik (BHA, INCI: Salicylic Acid)", "step_order": 20},
        {"category": "Bakım", "action": "Niasinamid %10 serum (INCI: Niacinamide)", "step_order": 20},
    ]
    plan = build_cabinet_active_plan("acne", items, avoided_families={"bha"})
    actives = {p["active"] for p in plan}
    assert "salisilik_asit" not in actives
    assert "niacinamid" in actives


def test_adapt_pauses_retinol_but_increases_urea_in_barrier_cream():
    from flow_engine import adapt_existing_routine

    items = [
        {
            "time": "Akşam",
            "category": "Bakım",
            "action": "Serbest retinol %0.3 (INCI: Retinol)",
            "detail": "",
            "step_order": 20,
            "canonical_ingredient_ids": ["retinol"],
        },
        {
            "time": "Akşam",
            "category": "Bakım",
            "action": "Gece: Seramid %2-5 + Üre",
            "detail": "",
            "step_order": 30,
            "canonical_ingredient_ids": ["seramidler", "urea"],
        },
    ]
    out = adapt_existing_routine(
        items,
        {"skin_feeling": "irritasyon"},
        {"level": "normal", "detail": ""},
    )
    by_new = {c["item"]: c["new"] for c in out["changes"]}
    assert any("ara ver" in v for k, v in by_new.items() if "retinol" in k.lower())
    cream_key = next(k for k in by_new if "Seramid" in k)
    assert by_new[cream_key] == "artırıldı"
    cream_row = next(r for r in out["adapted_items"] if "Seramid" in r["action"])
    assert "⏸️" not in cream_row["action"]


def test_merge_strips_curated_alias_from_wrong_box():
    from merge_data_catalog import _keep_owned_aliases

    owner = {"omega-3": "omega_3", "bak": "benzalkonium_chloride"}
    kept, changed = _keep_owned_aliases(
        ["gla", "omega-3", "evening primrose"],
        "gamma_linolenic_acid",
        owner,
    )
    assert changed is True
    assert "omega-3" not in kept
    assert "gla" in kept
    kept2, changed2 = _keep_owned_aliases(["omega-3"], "omega_3", owner)
    assert changed2 is False
    assert kept2 == ["omega-3"]
