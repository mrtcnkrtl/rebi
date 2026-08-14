"""Tests for Master Veri cleaner + canonical entity resolver (offline, pure)."""

from clean_master_veri import fix_encoding, parse_header, guess_kind
from knowledge.entity_resolver import (
    build_resolver,
    normalize,
    guess_kind_folder,
    _NEVER_SUBSTRING,
)


# ---- fix_encoding ---------------------------------------------------------

def test_fix_encoding_spaced_diacritics():
    assert fix_encoding("Çay Ağacı Ya ğ ı") == "Çay Ağacı Yağı"
    assert fix_encoding("Mineral Güne ş  Filtresi") == "Mineral Güneş Filtresi"
    assert fix_encoding("kırı ş ıklık") == "kırışıklık"


def test_fix_encoding_capital_split():
    assert fix_encoding("Günlük Su İ çimi") == "Günlük Su İçimi"


def test_fix_encoding_null_ranges():
    # digit null digit -> dash range; trailing nulls dropped
    assert fix_encoding("Benzoyl Peroksit 5_x0000_10%") == "Benzoyl Peroksit 5-10%"


# ---- parse_header ---------------------------------------------------------

def test_parse_header_name_and_synonyms():
    name, syn = parse_header("Retinoidler _x0000_Tretinoin, Retinol, Retinaldeyde)")
    assert name == "Retinoidler"
    assert "Tretinoin" in syn and "Retinol" in syn


def test_parse_header_drops_numeric_synonyms():
    name, syn = parse_header("Benzoyl Peroksit _x0000_5_x0000_10%_x0000_")
    assert name == "Benzoyl Peroksit"
    assert syn == []


def test_guess_kind_oil():
    assert guess_kind("Çay Ağacı Yağı", "Tedavi Ajanı") == "oil"
    assert guess_kind("Retinoidler", "Tedavi Ajanı") == "active"
    assert guess_kind("İnflamasyon Kaskadı", "Akne Vulgaris") == "topic"


# ---- resolver -------------------------------------------------------------

def test_resolver_known_names():
    r = build_resolver(load_from_db=False)
    assert r.resolve("Retinoidler").ingredient_id == "retinol"
    assert r.resolve("Vitamin C").ingredient_id == "vitamin_c"
    assert r.resolve("Çay Ağacı Yağı").ingredient_id == "cay_agaci"
    assert r.resolve("Seramidler").ingredient_id == "seramidler"


def test_resolver_unknown_is_candidate():
    r = build_resolver(load_from_db=False)
    res = r.resolve("Brimonidine")
    assert res.is_candidate is True
    assert res.ingredient_id is None


def test_resolver_oil_folder_routing():
    r = build_resolver(load_from_db=False)
    res = r.resolve("Lavanta Yağı")
    assert res.folder_slug == "ingredients/oils-botanicals"


def test_normalize_turkish():
    assert normalize("Niasinamid") == "niasinamid"
    assert normalize("ÇİNKO OKSİT") == "cinko oksit"


def test_guess_kind_folder_extract():
    assert guess_kind_folder("Yeşil Çay Özü")[1] == "ingredients/extracts"


# ---- substring guard ------------------------------------------------------

def test_ambiguous_fragments_never_substring_match():
    """
    'rice' sits inside 'licorice' and 'oleic acid' inside 'linoleic acid', so a
    plain substring match files them under the wrong box. These must stay
    unresolved unless an exact/curated entry claims them.
    """
    r = build_resolver(load_from_db=False)
    for name in ("rice", "rose", "palmitate", "thiourea", "silicon"):
        assert r.resolve(name).is_candidate is True, name


def test_colorant_and_lookalike_fragments_blocked():
    """
    'mica' hides inside 'cheMICAl sunscreen', 'milk' inside 'milk thistle' and
    'cyanidin' inside 'procyanidin' — each pointing at an unrelated box.
    """
    r = build_resolver(load_from_db=False)
    for name in ("mica", "milk", "cyanidin", "resorcinol"):
        assert r.resolve(name).is_candidate is True, name


def test_bare_zinc_is_the_sunscreen_mineral():
    # "zinc" must not drift to the antifungal pyrithione salt.
    r = build_resolver(load_from_db=False)
    assert r.resolve("zinc").ingredient_id == "zinc_oxide"


def test_oleic_acid_resolves_to_its_own_box_not_linoleic():
    r = build_resolver(load_from_db=False)
    assert r.resolve("oleic acid").ingredient_id == "oleic_acid"
    assert r.resolve("oleik asit").ingredient_id == "oleic_acid"


def test_retinoid_esters_route_to_retinol():
    r = build_resolver(load_from_db=False)
    assert r.resolve("retinyl linoleate").ingredient_id == "retinol"
    assert r.resolve("retinyl palmitate").ingredient_id == "retinol"


def test_blocklist_entries_are_normalized():
    # resolve() compares the normalized query against the set, so any entry
    # that is not already normalized would be dead weight.
    for entry in _NEVER_SUBSTRING:
        assert normalize(entry) == entry
