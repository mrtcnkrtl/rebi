"""Tests for expanded PDF ingredient extraction + entity->catalog promotion routing."""

from knowledge.classify_chunks import _regex_extract_ingredients
from merge_data_catalog import _classify_entity_folder


def test_regex_extracts_oils_and_extracts():
    text = (
        "İçinde badem yağı, jojoba, argan oil, lavanta yağı ve çay ağacı var. "
        "Ayrıca yeşil çay özü, kuşburnu yağı, squalane ve niasinamid içerir."
    )
    got = set(_regex_extract_ingredients(text))
    assert "almond oil" in got
    assert "argan oil" in got
    assert "tea tree oil" in got
    assert "rosehip oil" in got
    assert "green tea extract" in got
    assert "niacinamide" in got


def test_regex_normalizes_turkish_aliases():
    got = set(_regex_extract_ingredients("çinko oksit ve titanyum dioksit güneş filtresi"))
    assert "zinc oxide" in got
    assert "titanium dioxide" in got


def test_classify_entity_folder_routes():
    assert _classify_entity_folder("almond oil") == ("oil", "ingredients/oils-botanicals")
    assert _classify_entity_folder("shea butter") == ("oil", "ingredients/oils-botanicals")
    assert _classify_entity_folder("green tea extract") == ("extract", "ingredients/extracts")
    assert _classify_entity_folder("snail mucin") == ("extract", "ingredients/extracts")
    assert _classify_entity_folder("niacinamide") == ("active", "ingredients/actives")
