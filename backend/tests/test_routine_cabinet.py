"""Routine ↔ canonical cabinet bridge (Faz 0/2): slug mapping + id tagging."""

import knowledge.cabinet_router as cr
from knowledge.cabinet_router import CONCERN_SLUG_TO_CANONICAL, concern_ids_for_slug


def test_concern_slug_maps_primary_first():
    assert concern_ids_for_slug("acne")[0] == "acne_vulgaris"
    assert concern_ids_for_slug("aging")[0] == "photoaging_premature_aging"
    assert concern_ids_for_slug("pores") == ["enlarged_pores"]


def test_concern_slug_unknown_and_general_empty():
    assert concern_ids_for_slug("general") == []
    assert concern_ids_for_slug("does_not_exist") == []
    # case-insensitive
    assert concern_ids_for_slug("ACNE") == concern_ids_for_slug("acne")


def test_all_flow_slugs_covered():
    for slug in ("acne", "aging", "pigmentation", "dryness", "sensitivity", "pores", "oiliness", "general"):
        assert slug in CONCERN_SLUG_TO_CANONICAL


def _stub_catalog(monkeypatch):
    cache = {
        "loaded": True,
        "ingredients": [
            {"ingredient_id": "retinol", "name_tr": "Retinol", "name_en": "Retinol", "slug": "retinol", "aliases": []},
            {"ingredient_id": "niacinamid", "name_tr": "Niasinamid", "name_en": "Niacinamide", "slug": "niacinamid", "aliases": ["vitamin b3"]},
            {"ingredient_id": "salisilik_asit", "name_tr": "Salisilik Asit", "name_en": "Salicylic Acid", "slug": "salisilik_asit", "aliases": ["bha"]},
        ],
        "concerns": [],
    }
    monkeypatch.setattr(cr, "_CACHE", cache)


def test_tag_items_marks_actives_and_skips_generic(monkeypatch):
    _stub_catalog(monkeypatch)
    items = [
        {"action": "Retinol %0.3 serum", "detail": "Kolajen sentezi."},
        {"action": "Niasinamid %10 serum", "detail": "Sebum dengesi."},
        {"action": "Temizleme: nazik jel", "detail": "Cildi arindirir."},
    ]
    n = cr.tag_items_with_canonical_ids(items)
    assert n == 2
    assert items[0]["canonical_ingredient_ids"] == ["retinol"]
    assert items[1]["canonical_ingredient_ids"] == ["niacinamid"]
    assert "canonical_ingredient_ids" not in items[2]


def test_tag_items_uses_alias(monkeypatch):
    _stub_catalog(monkeypatch)
    items = [{"action": "Vitamin B3 içeren bakım", "detail": ""}]
    cr.tag_items_with_canonical_ids(items)
    assert items[0]["canonical_ingredient_ids"] == ["niacinamid"]


def test_tag_items_merges_without_duplicates(monkeypatch):
    _stub_catalog(monkeypatch)
    items = [{"action": "Retinol", "detail": "", "canonical_ingredient_ids": ["retinol"]}]
    cr.tag_items_with_canonical_ids(items)
    assert items[0]["canonical_ingredient_ids"] == ["retinol"]


def test_tag_items_empty_is_noop(monkeypatch):
    _stub_catalog(monkeypatch)
    assert cr.tag_items_with_canonical_ids([]) == 0


def test_chain_actives_empty_for_unmapped_slug():
    # general/unknown slugs resolve to no concern ids -> no DB call, empty result
    assert cr.chain_actives_for_concern("general") == []
    assert cr.chain_actives_for_concern("nope") == []


# ---- routine expert block: supports chain + avoid section ------------------

def _link(iid, name, effect, priority, note):
    return {
        "ingredient_id": iid,
        "ingredient_tr": name,
        "effect_status": effect,
        "priority": priority,
        "notes_tr": note,
        "time_of_day": "AM/PM",
    }


def _stub_links(monkeypatch, supports, avoid):
    def fake(concern_ids, limit=8, effect_statuses=None):
        if effect_statuses == ["avoid"]:
            return avoid[:limit]
        if effect_statuses == ["supports"]:
            return supports[:limit]
        return (supports + avoid)[:limit]

    monkeypatch.setattr(cr, "_fetch_links_by_concern", fake)
    monkeypatch.setattr(
        "knowledge.literature.format_literature_block", lambda *a, **k: "", raising=False
    )


def test_expert_block_lists_avoid_separately(monkeypatch):
    _stub_links(
        monkeypatch,
        supports=[_link("glycerin", "Gliserin", "supports", 1, "Humektan.")],
        avoid=[_link("olive_oil", "Zeytinyağı", "avoid", 4, "Bariyeri bozar.")],
    )
    text, meta = cr.format_routine_expert_block("dryness", max_chars=4000)
    assert "Gliserin" in text
    assert "kaçınılması gerekenler" in text.lower()
    assert "Zeytinyağı" in text
    assert meta["avoid_ingredient_ids"] == ["olive_oil"]
    # avoid rows must not pollute the recommended-chain id list
    assert "olive_oil" not in meta["ingredient_ids"]


def test_expert_block_omits_avoid_section_when_none(monkeypatch):
    _stub_links(
        monkeypatch,
        supports=[_link("glycerin", "Gliserin", "supports", 1, "Humektan.")],
        avoid=[],
    )
    text, meta = cr.format_routine_expert_block("dryness", max_chars=4000)
    assert "kaçınılması gerekenler" not in text.lower()
    assert "avoid_ingredient_ids" not in meta


def test_expert_block_empty_when_no_supports(monkeypatch):
    # An avoid-only concern yields no chain, so the block stays empty rather
    # than shipping a warning list with nothing to recommend.
    _stub_links(monkeypatch, supports=[], avoid=[_link("olive_oil", "Zeytinyağı", "avoid", 4, "x")])
    text, meta = cr.format_routine_expert_block("dryness")
    assert text == ""
    assert meta["ingredient_ids"] == []
