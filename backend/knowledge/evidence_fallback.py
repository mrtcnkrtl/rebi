"""
LLM-free short summaries when Gemini composer fails (429 etc.).
Avoids dumping full RAG context_text to the user.
"""

from __future__ import annotations

import re


def is_gemini_rate_limit_error(err: Exception) -> bool:
    et = str(err or "").lower()
    return any(x in et for x in ("429", "resource_exhausted", "quota", "rate limit"))


def is_gemini_retryable_error(err: Exception) -> bool:
    if is_gemini_rate_limit_error(err):
        return True
    et = str(err or "").lower()
    return any(x in et for x in ("503", "unavailable", "internal server error", "deadline"))


def is_gemini_non_retryable_error(err: Exception) -> bool:
    et = str(err or "").lower()
    return any(x in et for x in ("400", "invalid argument", "403", "permission denied", "not found"))


def build_graceful_evidence_fallback(
    context_text: str,
    *,
    user_message: str = "",
    max_snippets: int = 3,
    max_chars_per_snippet: int = 220,
    max_total: int = 900,
) -> str:
    """
    Turn merged context_text into a few short lines (graph block first if present).
    """
    kb = (context_text or "").strip()
    if not kb:
        return ""

    lines: list[str] = []

    # Prefer structural graph block when present in context.
    m = re.search(
        r"\[Yapısal bilgi tabanı\]\s*\n(.*?)(?=\n\n---|\n\[|\Z)",
        kb,
        flags=re.DOTALL | re.IGNORECASE,
    )
    if m:
        g = m.group(1).strip()
        if g:
            lines.append(g[: min(len(g), max_chars_per_snippet * 2)])
            # When structural graph is present, avoid dumping long vector passages.
            max_snippets = min(max_snippets, len(lines) + 1)

    # Remaining sections split by chunk delimiter or section headers.
    rest = kb
    if m:
        rest = kb[m.end() :].strip()

    chunks = re.split(r"\n\n---\n\n", rest)
    for chunk in chunks:
        if len(lines) >= max_snippets:
            break
        chunk = chunk.strip()
        if not chunk:
            continue
        label = ""
        if chunk.startswith("["):
            nl = chunk.find("\n")
            if nl > 0:
                label = chunk[1 : chunk.find("]")].strip() if "]" in chunk[: nl + 1] else ""
                chunk = chunk[nl + 1 :].strip()
        snippet = chunk[:max_chars_per_snippet].strip()
        if len(chunk) > max_chars_per_snippet:
            snippet += "…"
        if not snippet:
            continue
        if label:
            lines.append(f"{label}: {snippet}")
        else:
            lines.append(snippet)

    if not lines and user_message:
        # Last resort: refresh graph-only block (no vector dump).
        try:
            from knowledge.graph_kb import format_graph_evidence_block

            g = (format_graph_evidence_block(user_message) or "").strip()
            if g:
                lines.append(g[:max_chars_per_snippet * 2])
        except Exception:
            pass

    text = "\n".join(f"- {ln}" if not ln.startswith("-") else ln for ln in lines[:max_snippets]).strip()
    if len(text) > max_total:
        text = text[: max_total - 1].rstrip() + "…"
    return text
