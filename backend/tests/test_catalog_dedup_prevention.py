"""Graph ingredients must resolve onto existing curated survivors (no new dup rows)."""

from knowledge.entity_resolver import build_resolver
from merge_data_catalog import _resolve_graph_target


def test_graph_english_names_map_to_db_survivors():
    r = build_resolver(load_from_db=False)
    cases = {
        "Niacinamide": "niacinamid",
        "Ceramide": "seramidler",
        "Hyaluronic Acid": "hyaluronik_asit",
        "Salicylic Acid": "salisilik_asit",
        "Azelaic Acid": "azelaik_asit",
        "Benzoyl Peroxide": "benzoil_peroksit",
        "Tranexamic Acid": "traneksamik_asit",
        "Ascorbic Acid": "vitamin_c",
        "Alpha Arbutin": "alfa_arbutin",
    }
    for en, expected in cases.items():
        assert _resolve_graph_target(r, en, None) == expected, en


def test_graph_only_ingredient_falls_through_to_none():
    r = build_resolver(load_from_db=False)
    # Not a curated/db survivor -> must NOT be force-merged onto an existing box.
    assert _resolve_graph_target(r, "Totally Novel Peptide XYZ", None) is None


def test_resolve_prefers_en_then_tr():
    r = build_resolver(load_from_db=False)
    # en unknown, tr known
    assert _resolve_graph_target(r, "Unknownium", "Seramid") == "seramidler"


def test_none_resolver_is_safe():
    assert _resolve_graph_target(None, "Ceramide") is None
