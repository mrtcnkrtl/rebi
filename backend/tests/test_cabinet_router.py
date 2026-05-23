"""Tests for cabinet catalog router (in-memory cache)."""

from knowledge import cabinet_router as cr


def _seed_cache():
    cr.invalidate_catalog_cache()
    cr._CACHE["loaded"] = True
    cr._CACHE["ingredients"] = [
        {
            "ingredient_id": "almond_oil",
            "slug": "almond_oil",
            "name_tr": "Badem yağı",
            "name_en": "Almond oil",
            "kind": "oil",
            "folder_slug": "ingredients/oils-botanicals",
            "aliases": ["badem yagi", "badem"],
            "summary_tr": "Taşıyıcı yağ özet.",
        }
    ]
    cr._CACHE["concerns"] = [
        {
            "concern_id": "hair_dryness",
            "slug": "hair_dryness",
            "name_tr": "Kuru saç",
            "name_en": "Dry hair",
            "body_area": "hair",
            "folder_slug": "concerns/hair",
            "aliases": ["sacim kuru", "kuru sac"],
        }
    ]


def test_resolve_almond_and_hair():
    _seed_cache()
    r = cr.resolve_query("Saçım kuru, badem yağı kullanabilir miyim?")
    assert any(i.get("ingredient_id") == "almond_oil" for i in r["ingredients"])
    assert any(c.get("concern_id") == "hair_dryness" for c in r["concerns"])


def test_lookup_partial_no_link(monkeypatch):
    _seed_cache()

    def fake_fetch(ing_ids, cnd_ids):
        return []

    monkeypatch.setattr(cr, "_fetch_links", fake_fetch)
    result = cr.lookup("badem yağı ile kuru saç")
    assert result["status"] == "partial_no_link"
    text, meta = cr.format_cabinet_evidence_block("badem yağı kuru saç")
    assert meta["cabinet_status"] == "partial_no_link"
    assert "eşlemesi yok" in text


def test_lookup_hit_with_link(monkeypatch):
    _seed_cache()

    def fake_fetch(ing_ids, cnd_ids):
        return [
            {
                "ingredient_tr": "Badem yağı",
                "concern_tr": "Kuru saç",
                "effect_status": "supports",
                "notes_tr": "Uçlara az miktar.",
                "time_of_day": "Gece",
                "min_conc_recommended": None,
                "max_conc_recommended": None,
            }
        ]

    monkeypatch.setattr(cr, "_fetch_links", fake_fetch)
    result = cr.lookup("badem yağı kuru saç")
    assert result["status"] == "hit"
    text, meta = cr.format_cabinet_evidence_block("badem yağı kuru saç")
    assert meta["cabinet_status"] == "hit"
    assert "Eşleme" in text
