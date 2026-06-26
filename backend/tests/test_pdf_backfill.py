"""Tests for PDF entity -> canonical resolution used by the backfill (pure)."""

from knowledge.entity_resolver import build_resolver
from backfill_pdf_canonical import resolve_entity_names


def test_resolve_entity_names_splits_resolved_and_unresolved():
    r = build_resolver(load_from_db=False)
    names = [
        "retinol",
        "salisilik asit",
        "niasinamid",
        "çay ağacı yağı",
        "zzz bilinmeyen madde",
        "",
    ]
    resolved, unresolved = resolve_entity_names(names, r)
    assert resolved["retinol"] == "retinol"
    assert resolved["niasinamid"] == "niacinamid"
    assert resolved["çay ağacı yağı"] == "cay_agaci"
    assert "zzz bilinmeyen madde" in unresolved
    # empty string ignored entirely
    assert "" not in resolved and "" not in unresolved


def test_resolve_entity_names_empty_input():
    r = build_resolver(load_from_db=False)
    resolved, unresolved = resolve_entity_names([], r)
    assert resolved == {} and unresolved == []
