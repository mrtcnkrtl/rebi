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
