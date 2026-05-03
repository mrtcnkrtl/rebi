"""Tests for skincare Graph KB formatting and normalization."""

from unittest.mock import patch

from knowledge import graph_kb


def test_norm_turkish_chars():
    assert graph_kb._norm("NİASİNAMİD") == "niasinamid"
    assert graph_kb._norm("  Glikolik   Asit  ") == "glikolik asit"


def test_format_edges_basic():
    edges = [
        {
            "entity_a_tr": "Retinol",
            "entity_b_tr": "Glikolik Asit",
            "relation_type": "conflicts_with",
            "condition_note": "Aynı gece önerilmez",
            "safety_critical": True,
        }
    ]
    lines = graph_kb._format_edges(edges, max_lines=5)
    assert len(lines) == 1
    assert "Retinol" in lines[0]
    assert "çakışma" in lines[0]
    assert "Glikolik" in lines[0]
    assert "(!)" in lines[0]


def test_format_graph_evidence_block_handles_db_errors():
    with patch("knowledge.graph_kb.pg_conn") as m:
        m.side_effect = RuntimeError("no database")
        assert graph_kb.format_graph_evidence_block("retinol ve aha aynı gece") == ""


def test_format_graph_context_alias():
    assert graph_kb.format_graph_context_for_prompt("x", max_chars=10) == graph_kb.format_graph_evidence_block(
        "x", max_chars=10
    )


def test_condition_match_phrases():
    phrases = graph_kb._condition_match_phrases("Akne Vulgaris / Rosacea")
    assert any("akne" in p for p in phrases)
