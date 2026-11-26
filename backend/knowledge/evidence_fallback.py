"""
LLM-free short summaries when Gemini composer fails (429 etc.).
Avoids dumping full RAG context_text to the user.
"""

from __future__ import annotations

import re


def clip_at_boundary(text: str, max_chars: int) -> str:
    """
    Uzun metni kelime ortasında kesme (örn. "genelde k" → "genelde…").
    Kısmi satır yeterince uzunsa satır içinde kelime sınırında keser;
    aksi halde son tam satıra düşer.
    """
    t = (text or "").strip()
    if max_chars <= 0 or len(t) <= max_chars:
        return t
    budget = max(8, max_chars - 1)
    cut = t[:budget]

    def _word_clip(s: str) -> str:
        sp = s.rfind(" ")
        if sp >= max(8, len(s) // 3):
            return s[:sp].rstrip(" ,;:/") + "…"
        return s.rstrip() + "…"

    if "\n" in cut:
        head, tail = cut.rsplit("\n", 1)
        if len(tail.strip()) >= 36:
            return f"{head}\n{_word_clip(tail)}"
        if head.strip():
            return head.rstrip() + "\n…"
    return _word_clip(cut)


def is_gemini_rate_limit_error(err: Exception) -> bool:
    et = str(err or "").lower()
    return any(x in et for x in ("429", "resource_exhausted", "quota", "rate limit"))


def is_gemini_retryable_error(err: Exception) -> bool:
    if is_gemini_rate_limit_error(err):
        return True
    et = str(err or "").lower()
    return any(x in et for x in ("503", "unavailable", "internal server error", "deadline"))


def is_gemini_non_retryable_error(err: Exception) -> bool:
    # Günlük bütçe dolduysa yeniden denemek (bekleyerek) anlamsız: hemen yedeğe düşülür.
    if type(err).__name__ == "GeminiBudgetExceeded":
        return True
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
    graph_added = False
    if m:
        g = m.group(1).strip()
        if g:
            lines.append(clip_at_boundary(g, max_chars_per_snippet * 2))
            graph_added = True

    # Remaining sections split by chunk delimiter or section headers.
    rest = "" if graph_added else kb
    if m and not graph_added:
        rest = kb[m.end() :].strip()
    elif not m:
        rest = kb

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
        snippet = clip_at_boundary(chunk, max_chars_per_snippet)
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
                lines.append(clip_at_boundary(g, max_chars_per_snippet * 2))
        except Exception:
            pass

    text = "\n".join(f"- {ln}" if not ln.startswith("-") else ln for ln in lines[:max_snippets]).strip()
    return clip_at_boundary(text, max_total) if len(text) > max_total else text
