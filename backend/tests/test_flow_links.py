"""Tests for concern resolution + flow-graph link generation (offline, pure)."""

from knowledge.entity_resolver import build_resolver
from ingest_flow_links import build_links_from_flow, _confidence_from_label


def test_concern_resolver_curated():
    r = build_resolver(load_from_db=False)
    assert r.resolve_concern("Kırışıklık").ingredient_id == "photoaging_premature_aging"
    assert r.resolve_concern("Leke").ingredient_id == "hyperpigmentation_melasma"
    assert r.resolve_concern("Komedon").ingredient_id == "comedones_open_closed"
    assert r.resolve_concern("Akne Vulgaris").ingredient_id == "acne_vulgaris"


def test_concern_resolver_candidate():
    r = build_resolver(load_from_db=False)
    res = r.resolve_concern("Sebum Dyslipidemi")
    assert res.is_candidate is True


def test_confidence_from_label():
    assert _confidence_from_label("Level 1b Kanıt") == ("supports", 0.9)
    assert _confidence_from_label("Tedavi") == ("supports", 0.8)
    assert _confidence_from_label("Aydınlatma") == ("supports", 0.6)
    assert _confidence_from_label("Kaçınılması gerekir")[0] == "avoid"


def test_build_links_from_flow():
    r = build_resolver(load_from_db=False)
    rows = [
        {"source": "Kırışıklık", "target": "Retinoidler", "label": "Level 1b Kanıt"},
        {"source": "Leke", "target": "C Vitamini", "label": "Aydınlatma"},
        {"source": "Cilt Sağlığı", "target": "Akne", "label": "En Yaygın"},  # skip node
        {"source": "Yaşlanma", "target": "Kırışıklık", "label": "Belirti"},  # concern->concern
    ]
    links, skipped = build_links_from_flow(rows, r)
    pairs = {(l["ingredient_id"], l["concern_id"]) for l in links}
    assert ("retinol", "photoaging_premature_aging") in pairs
    assert ("vitamin_c", "hyperpigmentation_melasma") in pairs
    assert len(links) == 2
    assert any(s["reason"] == "skip_node" for s in skipped)
