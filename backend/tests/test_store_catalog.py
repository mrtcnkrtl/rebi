"""Mağaza kataloğu: onaylı doz bantları, vitrin API, satış kapalıyken checkout."""

from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

import main
from flow_engine import NEW_ACTIVE_DOSES
from seed_store_catalog import build_catalog_rows, catalog_pcts_for, make_slug, slugify_pct
from store import filter_products, match_shelf_product, public_product, quote_cart, store_open, visible_products


@pytest.fixture()
def client(monkeypatch):
    monkeypatch.setenv("API_ALLOW_INSECURE_AUTH", "1")
    # Boş tablo → yedek katalog; gerçek Supabase yok.
    monkeypatch.setattr(main, "get_supabase", lambda: None)
    return TestClient(main.app)


def test_approved_new_active_bands_are_in_the_catalog_unchanged():
    for key, meta in NEW_ACTIVE_DOSES.items():
        tiers = (meta or {}).get("tiers") or {}
        if not tiers:
            continue
        expected = []
        for t in tiers.values():
            pct = (t or {}).get("pct")
            if pct and pct not in expected:
                expected.append(pct)
        assert catalog_pcts_for(key) == expected, key


def test_vitamin_c_and_niacinamide_have_distinct_concentration_skus():
    vitc = catalog_pcts_for("vitamin_c")
    nia = catalog_pcts_for("niacinamid")
    assert "%10-15" in vitc and "%15-20" in vitc
    assert any("%3" in p or "%4" in p or "%5" in p for p in nia)
    assert len(vitc) >= 3


def test_catalog_rows_are_coming_soon_without_price():
    rows = build_catalog_rows()
    assert len(rows) >= 40
    for row in rows:
        assert row["status"] == "coming_soon"
        assert row["price_minor"] is None
        assert make_slug(row["external_ref"]["dose_key"], row["external_ref"]["pct"]) == row["slug"]
        pub = public_product(row)
        assert pub["purchasable"] is False
        assert "id" not in pub and "external_ref" not in pub


def test_slugify_keeps_turkish_letters_as_ascii():
    assert "yesil" in slugify_pct("%1 EGCG veya %2 yeşil çay ekstresi")
    assert "arbutin" in slugify_pct("%2 α-arbutin")


def test_visible_products_hides_draft_and_filter_works():
    rows = build_catalog_rows() + [
        {**build_catalog_rows()[0], "slug": "draft-only", "status": "draft"},
    ]
    shown = visible_products(rows)
    assert all(p["status"] in ("coming_soon", "active") for p in shown)
    assert not any(p["slug"] == "draft-only" for p in shown)
    serums = filter_products(shown, product_type="serum")
    assert serums and all(p["product_type"] == "serum" for p in serums)
    hit = filter_products(shown, q="niasinamid")
    assert hit and all("niasinamid" in (p["name_tr"] or "").casefold() or "niacinamide" in (p["name_en"] or "").casefold() for p in hit)


def test_match_shelf_product_prefers_step_and_label():
    products = visible_products(build_catalog_rows())
    hit = match_shelf_product("Niasinamid %4-5 serum", 20, products)
    assert hit and "niacinamid" in hit["slug"]
    assert match_shelf_product("Bilinmeyen krem", 99, products) is None


def test_quote_marks_coming_soon_unavailable():
    rows = build_catalog_rows()
    slug = rows[0]["slug"]
    quote = quote_cart([{"slug": slug, "quantity": 1}], rows)
    assert quote["lines"] == []
    assert slug in quote["unavailable"]


def test_store_api_list_detail_status_and_checkout_closed(client):
    assert store_open() is False
    st = client.get("/store/status")
    assert st.status_code == 200 and st.json()["open"] is False

    listing = client.get("/store/products")
    assert listing.status_code == 200
    body = listing.json()
    assert body["open"] is False and len(body["products"]) >= 40

    slug = body["products"][0]["slug"]
    detail = client.get(f"/store/products/{slug}")
    assert detail.status_code == 200
    assert detail.json()["product"]["slug"] == slug
    assert detail.json()["product"]["purchasable"] is False

    missing = client.get("/store/products/not-a-real-slug")
    assert missing.status_code == 404

    quote = client.post("/store/quote", json={"items": [{"slug": slug, "quantity": 2}]})
    assert quote.status_code == 200
    assert slug in quote.json()["unavailable"]

    checkout = client.post(
        "/store/checkout",
        json={"items": [{"slug": slug, "quantity": 1}], "return_url": "https://rebiovil.com/magaza"},
    )
    assert checkout.status_code == 503
    assert "açık değil" in checkout.json()["detail"].lower() or "henüz" in checkout.json()["detail"].lower()


def test_store_match_query_returns_shelf_hint(client):
    res = client.get("/store/products", params={"match": "C vitamini %10-15", "match_step": 25})
    assert res.status_code == 200
    match = res.json().get("match")
    assert match and "vitamin-c" in match["slug"]
