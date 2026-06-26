"""Tests for canonical dedupe planning, resolver alias pinning, and literature quality."""

from knowledge.entity_resolver import build_resolver
from knowledge.literature import Passage, clean_text, quality_ok, rank_passages
from dedupe_canonical import MERGE_MAP, plan_pairs, merge_jsonb_list


# --- resolver: English forms pinned to single survivor id ---

def test_english_forms_resolve_to_db_key_survivor():
    r = build_resolver(load_from_db=False)
    cases = {
        "ceramide": "seramidler",
        "ceramides": "seramidler",
        "niacinamide": "niacinamid",
        "hyaluronic acid": "hyaluronik_asit",
        "salicylic acid": "salisilik_asit",
        "tranexamic acid": "traneksamik_asit",
        "benzoyl peroxide": "benzoil_peroksit",
        "ascorbic acid": "vitamin_c",
        "alpha arbutin": "alfa_arbutin",
        "azelaic acid": "azelaik_asit",
    }
    for name, expected in cases.items():
        res = r.resolve(name)
        assert not res.is_candidate, f"{name} should resolve"
        assert res.ingredient_id == expected, f"{name} -> {res.ingredient_id} != {expected}"


def test_merge_map_survivors_match_alias_targets():
    # every dup in MERGE_MAP should resolve (via alias) to its survivor
    r = build_resolver(load_from_db=False)
    for survivor, dups in MERGE_MAP.items():
        for dup in dups:
            res = r.resolve(dup.replace("_", " "))
            assert res.ingredient_id == survivor, f"{dup} -> {res.ingredient_id} != {survivor}"


def test_merge_jsonb_list_unions_dedupes_and_drops_empty():
    out = merge_jsonb_list(["a", "b"], ["b", "c"], "c", None, "", "d")
    assert out == ["a", "b", "c", "d"]


def test_plan_pairs_flattens_and_skips_self():
    pairs = plan_pairs({"a": ["b", "c"], "x": ["x"], "y": []})
    assert ("a", "b") in pairs and ("a", "c") in pairs
    assert ("x", "x") not in pairs
    assert all(s != d for s, d in pairs)


# --- literature quality + ranking ---

def test_clean_text_collapses_pdf_noise():
    raw = "Niasina\nmid   Niacinamid\te\x00 Aktif"
    assert clean_text(raw) == "Niasina mid Niacinamid e Aktif"


def test_quality_rejects_fragmented_pdf_line():
    bad = "Niasina mid B 3 e A k tif Bil es ken Sac DIK AT de risi"
    assert quality_ok(bad) is False


def test_quality_accepts_clean_paragraph():
    good = (
        "Niasinamid bariyer fonksiyonunu destekler ve seramid sentezini "
        "artirarak transepidermal su kaybini azaltir; ayrica sebum uretimini "
        "dengeler ve hiperpigmentasyonu hafifletir."
    )
    assert quality_ok(good) is True


def test_quality_rejects_too_short():
    assert quality_ok("Kisa bir not.") is False


def test_rank_prefers_master_veri_then_length():
    long_pdf = (
        "Bu bir pdf pasaji olup yeterince uzun ve temiz bir paragraf icerir; "
        "icerik kalitesi yuksek oldugundan filtreden gecer ve siralamaya girer. " * 2
    )
    master = (
        "Master veri kaynagindan gelen ozet bir klinik kanit pasaji burada yer alir "
        "ve bariyer fonksiyonu ile nem dengesi hakkinda anlamli bilgi sunar tamamen."
    )
    passages = [
        Passage(long_pdf, "pdf", None),
        Passage(master, "master_veri", None),
    ]
    ranked = rank_passages(passages, limit=5)
    assert ranked[0].source_kind == "master_veri"


def test_rank_dedupes_identical():
    txt = (
        "Ayni icerikli temiz bir literatur pasaji bariyer ve nem dengesi hakkinda "
        "detayli bilgi verir, seramid sentezi ve transepidermal su kaybini aciklar."
    )
    ranked = rank_passages([Passage(txt, "pdf", None), Passage(txt, "pdf", None)], limit=5)
    assert len(ranked) == 1
