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


def test_tag_items_ignores_forbidden_name_in_detail(monkeypatch):
    _stub_catalog(monkeypatch)
    items = [{"action": "Bakuchiol serum", "detail": "Hamilelikte retinol yasak."}]
    cr.tag_items_with_canonical_ids(items)
    assert "retinol" not in (items[0].get("canonical_ingredient_ids") or [])


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


# ---- alias matching guards -------------------------------------------------

def _m(phrase: str, query: str) -> bool:
    qnorm = cr._norm(query)
    return cr._phrase_matches(phrase, qnorm, {t for t in qnorm.split(" ") if t}, 3)


def test_short_codes_need_a_whole_word():
    """
    Aliases are matched against the raw query, so a 3-letter code used as a bare
    substring lands on the most common Turkish stems instead of its own box.
    """
    assert _m("aha", "aha nedir") is True
    assert _m("aha", "daha iyi bir sey var mi") is False
    assert _m("tar", "tar sampuani") is True
    assert _m("tar", "bana bir tarif ver") is False
    assert _m("ala", "ala antioksidan mi") is True
    assert _m("ala", "hangisini alabilirim") is False


def test_four_letter_concern_words_survive_turkish_suffixes():
    """'akne'/'leke' must still match inflected forms, which is why 4-letter
    phrases match a token prefix rather than requiring equality."""
    assert _m("akne", "aknem var ne yapmaliyim") is True
    assert _m("akne", "akneli cilt icin rutin") is True
    assert _m("leke", "lekelerim gecmiyor") is True
    # ...but not as an infix of an unrelated word.
    assert _m("mica", "kimyasal gunes kremi") is False


def test_long_phrases_still_match_as_substring_and_by_token():
    assert _m("hyaluronik asit", "hyaluronik asit kullanmali miyim") is True
    # Token path tolerates words inserted between the alias words.
    assert _m("yagli cilt", "yagli ve gozenekli cilt icin") is True


# ---- exact match precedence -------------------------------------------------

def _rows():
    return [
        {"ingredient_id": "retinol", "name_tr": "Retinol", "name_en": "Retinol",
         "slug": "retinol", "aliases": ["retinyl linoleate", "retinoid"]},
        {"ingredient_id": "linoleic_acid", "name_tr": "Linoleik Asit", "name_en": "Linoleic Acid",
         "slug": "linoleic_acid", "aliases": ["linoleate"]},
        {"ingredient_id": "oleic_acid", "name_tr": "Oleik Asit", "name_en": "Oleic Acid",
         "slug": "oleic_acid", "aliases": ["oleate"]},
    ]


def _ids(query: str):
    hits = cr._match_rows(cr._norm(query), _rows(), "ingredient_id")
    return [h["ingredient_id"] for h in hits]


def test_exact_alias_beats_fragment_matches():
    """
    'retinyl linoleate' is a retinol ester, but it also contains the 'linoleate'
    and 'oleate' aliases of two fatty acid boxes. The exact alias has to win,
    otherwise the ester is served as evidence for the acids it is named after.
    """
    assert _ids("retinyl linoleate") == ["retinol"]


def test_fragment_matches_survive_when_nothing_matches_exactly():
    # A descriptive question has no exact alias, so every plausible box is kept.
    assert set(_ids("linoleate ve oleate farki nedir")) == {"linoleic_acid", "oleic_acid"}


def test_curated_alias_map_is_shared_with_the_cabinet():
    """
    The cabinet reads aliases from the DB, the tagger from CURATED_ALIASES.
    merge_data_catalog.sync_curated_aliases is what keeps them equal; if that
    call is dropped, phrasings like 'kolajen' stop being answerable.
    """
    import merge_data_catalog as mdc
    from knowledge.entity_resolver import CURATED_ALIASES

    assert callable(mdc.sync_curated_aliases)
    for phrase in ("kolajen", "retinoid", "tretinoin", "arbutin", "gunes koruyucu"):
        assert phrase in CURATED_ALIASES, phrase


# ---- routine enrichment: fold oils/vitamins, align active plan -------------

def test_enrich_folds_humectant_into_evening_moisturizer(monkeypatch):
    _stub_links(
        monkeypatch,
        supports=[
            _link("glycerin", "Gliserin", "supports", 1, "Nem çeker."),
            _link("retinol", "Retinol", "supports", 1, "Gece aktif."),
        ],
        avoid=[],
    )
    monkeypatch.setattr(cr, "tag_items_with_canonical_ids", lambda items: 0)
    items = [
        {"time": "Sabah", "category": "Bakım", "action": "Temizleme", "detail": "", "step_order": 10},
        {
            "time": "Akşam",
            "category": "Bakım",
            "action": "Gece: Seramid krem",
            "detail": "Bariyer.",
            "step_order": 30,
        },
    ]
    report = cr.enrich_routine_from_cabinet(items, "dryness")
    folded_ids = [f["ingredient_id"] for f in report["folded"]]
    assert "glycerin" in folded_ids
    assert "retinol" not in folded_ids
    assert "Gliserin" in items[1]["action"]
    assert "glycerin" in items[1]["canonical_ingredient_ids"]


def test_enrich_folds_iron_oxides_into_spf(monkeypatch):
    _stub_links(
        monkeypatch,
        supports=[_link("iron_oxides", "Demir Oksitler", "supports", 2, "Görünür ışık.")],
        avoid=[],
    )
    monkeypatch.setattr(cr, "tag_items_with_canonical_ids", lambda items: 0)
    items = [
        {
            "time": "Sabah",
            "category": "Koruma",
            "action": "SPF 50 (geniş spektrumlu SPF)",
            "detail": "Son adım.",
            "step_order": 40,
        },
        {
            "time": "Akşam",
            "category": "Bakım",
            "action": "Gece krem",
            "detail": "",
            "step_order": 30,
        },
    ]
    cr.enrich_routine_from_cabinet(items, "pigmentation")
    assert "Demir Oksitler" in items[0]["action"]
    assert "iron_oxides" in items[0]["canonical_ingredient_ids"]
    assert "Demir Oksitler" not in items[1]["action"]


def test_enrich_flags_avoid_mention(monkeypatch):
    _stub_links(
        monkeypatch,
        supports=[],
        avoid=[_link("olive_oil", "Zeytinyağı", "avoid", 3, "Bariyeri bozar.")],
    )
    monkeypatch.setattr(cr, "tag_items_with_canonical_ids", lambda items: 0)
    items = [
        {
            "time": "Akşam",
            "category": "Bakım",
            "action": "Gece: Zeytinyağı masajı",
            "detail": "Yağ katmanı.",
            "step_order": 30,
            "canonical_ingredient_ids": ["olive_oil"],
        }
    ]
    report = cr.enrich_routine_from_cabinet(items, "sensitivity")
    assert "olive_oil" in report["avoid_stripped"]
    assert "kaçın" in items[0]["detail"].lower()
    assert "olive_oil" not in (items[0].get("canonical_ingredient_ids") or [])


def test_align_active_plan_drops_actives_not_in_routine(monkeypatch):
    monkeypatch.setattr(cr, "tag_items_with_canonical_ids", lambda items: 0)
    items = [
        {
            "time": "Akşam",
            "category": "Bakım",
            "action": "Niasinamid %10",
            "detail": "",
            "canonical_ingredient_ids": ["niacinamid"],
        }
    ]
    plan = [
        {"active": "sunscreen", "when": "morning"},
        {"active": "niacinamide", "when": "evening"},
        {"active": "salicylic_acid", "when": "evening"},
        {"active": "retinol", "when": "evening"},
    ]
    kept = {p["active"] for p in cr.align_active_plan_with_routine(plan, items)}
    assert kept == {"sunscreen", "niacinamide"}
