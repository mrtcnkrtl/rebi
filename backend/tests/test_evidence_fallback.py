"""Tests for graceful evidence fallback when Gemini fails."""

from knowledge.evidence_fallback import (
    build_graceful_evidence_fallback,
    is_gemini_rate_limit_error,
    is_gemini_retryable_error,
)


def test_rate_limit_detection():
    assert is_gemini_rate_limit_error(Exception("429 RESOURCE_EXHAUSTED"))
    assert is_gemini_retryable_error(Exception("503 Service Unavailable"))


def test_graceful_fallback_prefers_graph_block():
    kb = (
        "[Yapısal bilgi tabanı]\n"
        "Bilinen ilişkiler:\n- Retinol — çakışma — Glikolik Asit (!)\n\n"
        "---\n\n"
        "[Anlamsal arama — ilgili pasajlar]\n"
        + ("Uzun pasaj metni. " * 200)
    )
    out = build_graceful_evidence_fallback(kb, max_total=600)
    assert "Retinol" in out
    assert len(out) <= 620
    assert "Uzun pasaj metni" not in out


def test_graceful_fallback_empty():
    assert build_graceful_evidence_fallback("") == ""
