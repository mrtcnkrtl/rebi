"""
Ücretsiz bilimsel literatür ipuçları (Rebi RAG’ı değildir).

- PubMed: NCBI E-utilities (API anahtarı isteğe bağlı, ücretsiz)
  https://www.ncbi.nlm.nih.gov/books/NBK25501/
- Europe PMC: REST (anahtar gerekmez)
  https://europepmc.org/RestfulWebService

Yalnızca başlık + bağlantı; tam metin/özet çekilmez (token ve telif sınırı).
"""

from __future__ import annotations

import html
import re
from typing import Any
from urllib.parse import quote

import httpx

from config import (
    NCBI_API_KEY,
    PUBMED_CONTACT_EMAIL,
    PUBMED_FREE_HINTS,
    get_logger,
)

log = get_logger("knowledge.free_literature")

EUTILS_BASE = "https://eutils.ncbi.nlm.nih.gov/entrez/eutils"
EUROPE_PMC_SEARCH = "https://www.ebi.ac.uk/europepmc/webservices/rest/search"


def _sanitize_pubmed_term(q: str, max_len: int = 220) -> str:
    t = (q or "").strip()
    t = re.sub(r"[\x00-\x08\x0b\x0c\x0e-\x1f]", " ", t)
    t = " ".join(t.split())
    if len(t) > max_len:
        t = t[:max_len].rsplit(" ", 1)[0]
    return t


def _title_from_esummary(doc: dict[str, Any]) -> str:
    raw = doc.get("title") or doc.get("sorttitle") or doc.get("booktitle") or ""
    return html.unescape(str(raw)).strip() or "(başlık yok)"


async def _pubmed_titles(term: str, *, max_results: int = 4) -> list[tuple[str, str]]:
    """(pmid, title) listesi."""
    term = _sanitize_pubmed_term(term)
    if len(term) < 2:
        return []

    params: dict[str, str | int] = {
        "db": "pubmed",
        "retmode": "json",
        "retmax": max_results,
        "sort": "relevance",
        "term": term,
        "tool": "rebi_knowledge",
    }
    if PUBMED_CONTACT_EMAIL:
        params["email"] = PUBMED_CONTACT_EMAIL
    if NCBI_API_KEY:
        params["api_key"] = NCBI_API_KEY

    async with httpx.AsyncClient(timeout=12.0) as client:
        r = await client.get(f"{EUTILS_BASE}/esearch.fcgi", params=params)
        r.raise_for_status()
        data = r.json()
    idlist = (data.get("esearchresult") or {}).get("idlist") or []
    if not idlist:
        return []

    sum_params: dict[str, str | int] = {
        "db": "pubmed",
        "retmode": "json",
        "id": ",".join(idlist),
        "tool": "rebi_knowledge",
    }
    if PUBMED_CONTACT_EMAIL:
        sum_params["email"] = PUBMED_CONTACT_EMAIL
    if NCBI_API_KEY:
        sum_params["api_key"] = NCBI_API_KEY

    async with httpx.AsyncClient(timeout=12.0) as client:
        r2 = await client.get(f"{EUTILS_BASE}/esummary.fcgi", params=sum_params)
        r2.raise_for_status()
        summary = r2.json()

    result = summary.get("result") or {}
    uids = result.get("uids") or idlist
    out: list[tuple[str, str]] = []
    for uid in uids:
        doc = result.get(str(uid))
        if not isinstance(doc, dict):
            continue
        out.append((str(uid), _title_from_esummary(doc)))
    return out


async def _europepmc_titles(term: str, *, max_results: int = 4) -> list[tuple[str, str]]:
    """(pmid veya source id, title); PubMed sonuç yoksa yedek."""
    term = _sanitize_pubmed_term(term)
    if len(term) < 2:
        return []

    q = quote(term, safe="")
    url = f"{EUROPE_PMC_SEARCH}?query={q}&format=json&pageSize={max_results}&resultType=core&sort=relevance"
    headers = {}
    if PUBMED_CONTACT_EMAIL:
        headers["User-Agent"] = f"Rebi/1.0 (mailto:{PUBMED_CONTACT_EMAIL})"

    async with httpx.AsyncClient(timeout=12.0, headers=headers) as client:
        r = await client.get(url)
        r.raise_for_status()
        data = r.json()

    lst = (data.get("resultList") or {}).get("result") or []
    out: list[tuple[str, str]] = []
    for item in lst:
        if not isinstance(item, dict):
            continue
        title = html.unescape(str(item.get("title") or "")).strip()
        if not title:
            continue
        pmid = item.get("pmid")
        src = str(pmid or item.get("id") or item.get("source") or "")
        if not src:
            continue
        out.append((src, title[:220]))
    return out


def _format_hints_block(
    lines: list[str],
    *,
    source_label: str,
) -> str:
    body = "\n".join(lines)
    return (
        f"Harici — {source_label} (Rebi seçilmiş verisi değil; yalnızca indeks araması):\n"
        f"{body}\n\n"
        "Tam metin ve metod için makaleye git; teşhis/tedavi kararı vermez."
    )


async def fetch_skin_literature_hints(user_message: str, *, max_results: int = 4) -> str:
    """
    Kullanıcı sorusuna göre kısa literatür satırları (başlık + URL).
    Boş string: sonuç yok veya kapalı / hata.
    """
    if not PUBMED_FREE_HINTS:
        return ""

    q = (user_message or "").strip()
    if len(q) < 3:
        return ""

    try:
        pairs = await _pubmed_titles(q, max_results=max_results)
        label = "PubMed (NCBI)"
        if not pairs:
            pairs = await _europepmc_titles(q, max_results=max_results)
            label = "Europe PMC"
        if not pairs:
            return ""

        lines: list[str] = []
        for i, (pid, title) in enumerate(pairs, start=1):
            if label.startswith("PubMed"):
                url = f"https://pubmed.ncbi.nlm.nih.gov/{pid}/"
            elif str(pid).isdigit():
                url = f"https://europepmc.org/article/MED/{pid}"
            else:
                url = f"https://europepmc.org/search?query={quote(q[:120])}"
            lines.append(f"{i}. {title}\n   {url}")
        return _format_hints_block(lines, source_label=label)
    except Exception as e:
        log.warning("free_literature hints failed: %s", e)
        return ""
