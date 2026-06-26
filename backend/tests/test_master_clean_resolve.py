"""Tests for Master Veri cleaner + canonical entity resolver (offline, pure)."""

from clean_master_veri import fix_encoding, parse_header, guess_kind
from knowledge.entity_resolver import build_resolver, normalize, guess_kind_folder


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
