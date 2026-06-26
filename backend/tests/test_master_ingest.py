"""Tests for Master Veri ingest packing + literature block formatting (pure)."""

from ingest_master_veri import pack_claims_into_chunks, build_box_records
from knowledge.entity_resolver import build_resolver


def test_pack_claims_groups_by_size():
    box = {
        "name": "Retinoidler",
        "claims": [
            {"alt": "Mekanizma", "text": "A" * 800},
            {"alt": "Klinik", "text": "B" * 800},
            {"alt": "Kanıt", "text": "C" * 100},
        ],
    }
    chunks = pack_claims_into_chunks(box, max_chars=1300)
    assert len(chunks) == 2  # 800+800 exceeds 1300 -> split
    assert all(c.startswith("Retinoidler:") for c in chunks)
    assert "Mekanizma" in chunks[0]


def test_pack_claims_empty():
    assert pack_claims_into_chunks({"name": "X", "claims": []}) == []


def test_build_box_records_resolves_and_skips_topics():
    inv = {
        "boxes": [
            {
                "name": "Retinoidler",
                "kind": "active",
                "claims": [{"alt": "Genel", "text": "Kolajen sentezini uyarır."}],
            },
            {
                "name": "Brimonidine",
                "kind": "active",
                "claims": [{"alt": "Genel", "text": "Vazokonstriksiyon yapar."}],
            },
            {
                "name": "İnflamasyon Kaskadı",
                "kind": "topic",
                "claims": [{"alt": "Genel", "text": "Sitokin salınımı."}],
            },
        ]
    }
    r = build_resolver(load_from_db=False)
    records, stats = build_box_records(inv, r)
    # "İnflamasyon Kaskadı" is a topic with no concern match -> unmatched, no record.
    assert stats["topic_unmatched"] == 1
    assert stats["resolved"] >= 1
    by_name = {rec["name"]: rec for rec in records}
    assert by_name["Retinoidler"]["ingredient_id"] == "retinol"
    assert by_name["Retinoidler"]["is_candidate"] is False
    assert by_name["Brimonidine"]["is_candidate"] is True


def test_literature_block_format_no_db(monkeypatch):
    import knowledge.literature as lit

    monkeypatch.setattr(
        lit,
        "fetch_passages_by_ingredient",
        lambda ids, **kw: [lit.Passage("Retinol kolajen sentezini artırır.", "master_veri", None)],
    )
    block = lit.format_literature_block(["retinol"])
    assert "ham pasajlar" in block
    assert "Retinol" in block
