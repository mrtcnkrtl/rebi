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
import unicodedata
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

_STOPWORDS = {
    "ve",
    "veya",
    "ile",
    "mi",
    "mı",
    "mu",
    "mü",
    "nedir",
    "ne",
    "nasil",
    "nasıl",
    "kac",
    "kaç",
    "icin",
    "için",
    "gibi",
    "daha",
    "cok",
    "çok",
    "az",
    "mu",
    "mü",
    "ya",
    "ben",
    "sen",
    "o",
    "bu",
    "su",
    "şu",
    "bana",
    "bende",
    "bende",
    "benim",
    "sende",
    "sende",
    "senin",
    "ama",
    "fakat",
    "cunku",
    "çünkü",
    "yuz",
    "yüz",
    "cilt",
    "sac",
    "saç",
    "tirnak",
    "tırnak",
}


def _norm_query_for_skip(q: str) -> str:
    t = unicodedata.normalize("NFD", (q or "").strip())
    t = "".join(c for c in t if unicodedata.category(c) != "Mn")
    t = t.casefold()
    # dotless ı -> i for fuzzy matching
    t = t.replace("ı", "i")
    return t


def skip_external_literature_for_query(q: str) -> bool:
    """
    Sohbet meta-sorusu veya PubMed aramasına uygun olmayan kısa ifadelerde
    dış arama yapma (alakasız makale başlıkları önlenir).
    """
    t = _norm_query_for_skip(q)
    if len(t) < 5:
        return False
    needles = (
        "nereden alı",
        "nerden alı",
        "nereden geliyor",
        "nerden geliyor",
        "kaynak",
        "hangi veri",
        "veri tabanı",
        "veritabanı",
        "bilgini nereden",
        "bilgileri nereden",
        "bilgileri nedern",
        "bilgiyi nereden",
        "bilgiyi nedern",
        "nasıl öğrendin",
        "sen kimsin",
        "kimlisin",
        "ne işe yarıyorsun",
        "rebi nedir",
        "rebi ne demek",
        "rebi ne iş",
        "rebi ne yapar",
        "rebi kim",
        "rebi nasıl çalışır",
        "rebi ai nedir",
        "what is rebi",
        "what does rebi",
        "kaç soru",
        "kaç mesaj",
        "mesaj hakkı",
        "mesaj limit",
        "günlük kota",
        "günlük mesaj",
        "hakkım kaldı",
        "kalan hakk",
        "ücretsiz planda",
        "hangi model",
        "yapay zek",
        "prompt",
    )
    if any(n in t for n in needles):
        return True
    loc = ("nereden" in t) or ("nedern" in t) or ("nerden" in t)
    if loc and any(w in t for w in ("bilgi", "veri", "kaynak", "bilgiler", "veriler")):
        return True
    return False


def _sanitize_pubmed_term(q: str, max_len: int = 220) -> str:
    t = (q or "").strip()
    t = re.sub(r"[\x00-\x08\x0b\x0c\x0e-\x1f]", " ", t)
    t = " ".join(t.split())
    if len(t) > max_len:
        t = t[:max_len].rsplit(" ", 1)[0]
    return t


def _tokenize_for_relevance(s: str) -> list[str]:
    t = _norm_query_for_skip(s)
    # keep letters/digits only as tokens
    toks = re.findall(r"[a-z0-9]+", t)
    out: list[str] = []
    for x in toks:
        if len(x) < 3:
            continue
        if x in _STOPWORDS:
            continue
        out.append(x)
    # de-dupe preserving order
    seen: set[str] = set()
    uniq: list[str] = []
    for x in out:
        if x in seen:
            continue
        seen.add(x)
        uniq.append(x)
    return uniq[:16]


def _compact_literature_query(user_message: str) -> str:
    """
    Use a compact keyword query for PubMed/EuropePMC to reduce irrelevant hits.
    """
    toks = _tokenize_for_relevance(user_message)
    if not toks:
        return _sanitize_pubmed_term(user_message)
    # Prefer 5-8 strongest tokens (longer first, stable)
    toks = sorted(toks, key=lambda x: (-len(x), x))[:8]
    return _sanitize_pubmed_term(" ".join(toks))


def _needs_derm_context(user_message: str) -> bool:
    t = _norm_query_for_skip(user_message)
    needles = (
        "cilt",
        "skin",
        "derm",
        "dermat",
        "acne",
        "akne",
        "hair",
        "sac",
        "scalp",
        "tirnak",
        "nail",
        "eczema",
        "rosacea",
        "melasma",
        "pigment",
        "spf",
        "sunscreen",
    )
    return not any(n in t for n in needles)


def _with_derm_context(term: str, user_message: str) -> str:
    """
    If the query is short/ambiguous, add a dermatology anchor to reduce off-topic titles.
    """
    term = _sanitize_pubmed_term(term)
    if not term:
        return term
    if _needs_derm_context(user_message):
        # Broad anchor without overfitting a single disease
        return f"({term}) AND (skin OR dermatology OR hair OR scalp OR nail)"
    return term


def _query_wants_skin_context(user_message: str) -> bool:
    """
    If the user is clearly asking about topical/face/skin usage, prefer skin-scoped literature.
    This avoids off-topic medical uses (e.g., surgery/bleeding) for ingredients like tranexamic acid.
    """
    t = _norm_query_for_skip(user_message)
    needles = (
        "cilt",
        "skin",
        "yuz",
        "yüz",
        "face",
        "topical",
        "cream",
        "serum",
        "leke",
        "melasma",
        "hiperpig",
        "pigment",
        "akne",
        "acne",
    )
    return any(n in t for n in needles)


def _abstract_seems_skin_related(title: str, abstract: str) -> bool:
    blob = _norm_query_for_skip((title or "") + " " + (abstract or ""))
    needles = (
        "melasma",
        "hyperpig",
        "pigment",
        "skin",
        "topical",
        "dermat",
        "cream",
        "serum",
        "epiderm",
        "stratum",
        "acne",
        "rosacea",
    )
    return any(n in blob for n in needles)


def _title_relevant_to_query(user_message: str, title: str) -> bool:
    """
    Lightweight relevance filter: require at least 1-2 keyword overlaps.
    Prevents obviously off-topic papers (e.g., psychiatric) for skincare questions.
    """
    q_toks = _tokenize_for_relevance(user_message)
    if not q_toks:
        return True
    t_toks = set(_tokenize_for_relevance(title))
    if not t_toks:
        return False
    overlap = sum(1 for x in q_toks[:10] if x in t_toks)
    # Stricter when query is longer (more intent words)
    need = 2 if len(q_toks) >= 6 else 1
    return overlap >= need


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


def _strip_xml_tags(s: str) -> str:
    s = re.sub(r"<[^>]+>", " ", s or "")
    s = html.unescape(s)
    s = re.sub(r"\s{2,}", " ", s).strip()
    return s


def _extract_pubmed_articles(xml_text: str) -> list[dict[str, str]]:
    """
    Very lightweight PubMed XML parsing (no heavy deps).
    Extracts: pmid, title, abstract.
    """
    x = xml_text or ""
    out: list[dict[str, str]] = []
    # Split on PubmedArticle blocks
    blocks = re.split(r"</?PubmedArticle>", x, flags=re.I)
    for b in blocks:
        if "<PMID" not in b:
            continue
        pmid_m = re.search(r"<PMID[^>]*>(\d+)</PMID>", b, flags=re.I)
        pmid = pmid_m.group(1) if pmid_m else ""
        title_m = re.search(r"<ArticleTitle[^>]*>([\s\S]*?)</ArticleTitle>", b, flags=re.I)
        title = _strip_xml_tags(title_m.group(1)) if title_m else ""
        abs_parts = re.findall(r"<AbstractText[^>]*>([\s\S]*?)</AbstractText>", b, flags=re.I)
        abstract = " ".join(_strip_xml_tags(p) for p in abs_parts if p)[:5000].strip()
        if pmid and (title or abstract):
            out.append({"pmid": pmid, "title": title, "abstract": abstract})
        if len(out) >= 4:
            break
    return out


async def fetch_pubmed_abstracts(
    user_message: str, *, max_results: int = 2
) -> list[dict[str, str]]:
    """
    Fetch PubMed abstracts (title+abstract) for building reusable internal evidence.
    Returns [] on disable/error.
    """
    # Abstract fetch is used to enrich internal evidence; allow even when public hint links are disabled.
    q_raw = (user_message or "").strip()
    if len(q_raw) < 3 or skip_external_literature_for_query(q_raw):
        return []
    q_compact = _compact_literature_query(q_raw)
    # Prefer a derm anchor when user intent is skincare/topical; prevents off-topic medical uses.
    term = _with_derm_context(q_compact, q_raw)
    ids = await _pubmed_titles(term, max_results=max(1, int(max_results)))
    if not ids:
        return []
    pmids = [pid for (pid, _t) in ids[: max(1, int(max_results))] if str(pid).isdigit()]
    if not pmids:
        return []

    params: dict[str, str | int] = {
        "db": "pubmed",
        "retmode": "xml",
        "id": ",".join(pmids),
        "tool": "rebi_knowledge",
    }
    if PUBMED_CONTACT_EMAIL:
        params["email"] = PUBMED_CONTACT_EMAIL
    if NCBI_API_KEY:
        params["api_key"] = NCBI_API_KEY

    async with httpx.AsyncClient(timeout=14.0) as client:
        r = await client.get(f"{EUTILS_BASE}/efetch.fcgi", params=params)
        r.raise_for_status()
        xml = r.text or ""

    arts = _extract_pubmed_articles(xml)
    # Keep only relevant titles
    out: list[dict[str, str]] = []
    for a in arts:
        if a.get("title") and not _title_relevant_to_query(q_raw, a.get("title") or ""):
            continue
        # If user intent is skincare, drop abstracts that look purely non-derm (e.g., surgery/bleeding).
        if _query_wants_skin_context(q_raw) and not _abstract_seems_skin_related(a.get("title") or "", a.get("abstract") or ""):
            continue
        out.append(a)
        if len(out) >= max(1, int(max_results)):
            break
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


def _format_hints_block(lines: list[str]) -> str:
    body = "\n".join(lines)
    return (
        "Aynı konuda literatürde geçen birkaç çalışma başlığı:\n"
        f"{body}\n"
        "Bağlantıdan özeti veya tam metne geçebilirsin. Rahatsızlık veya tedavi kararı için doktorun en doğru adres."
    )


async def fetch_skin_literature_hints(user_message: str, *, max_results: int = 4) -> str:
    """
    Kullanıcı sorusuna göre kısa literatür satırları (başlık + URL).
    Boş string: sonuç yok veya kapalı / hata.
    """
    pairs = await fetch_skin_literature_pairs(user_message, max_results=max_results)
    if not pairs:
        return ""
    lines: list[str] = []
    for i, (title, url) in enumerate(pairs, start=1):
        lines.append(f"{i}. {title}\n   {url}")
    return _format_hints_block(lines)


async def fetch_skin_literature_pairs(
    user_message: str, *, max_results: int = 4
) -> list[tuple[str, str]]:
    """
    (title, url) listesi. Başlıklar alaka filtresinden geçer.
    Boş liste: sonuç yok veya kapalı / hata.
    """
    if not PUBMED_FREE_HINTS:
        return []

    q_raw = (user_message or "").strip()
    if len(q_raw) < 3 or skip_external_literature_for_query(q_raw):
        return []

    # compact + context-anchored query reduces irrelevant titles
    q_compact = _compact_literature_query(q_raw)
    q = _with_derm_context(q_compact, q_raw)

    try:
        pairs = await _pubmed_titles(q, max_results=max_results)
        label = "PubMed (NCBI)"
        if not pairs:
            pairs = await _europepmc_titles(q, max_results=max_results)
            label = "Europe PMC"
        if not pairs:
            return []

        out: list[tuple[str, str]] = []
        for (pid, title) in pairs:
            if not _title_relevant_to_query(q_raw, title):
                continue
            if label.startswith("PubMed"):
                url = f"https://pubmed.ncbi.nlm.nih.gov/{pid}/"
            elif str(pid).isdigit():
                url = f"https://europepmc.org/article/MED/{pid}"
            else:
                url = f"https://europepmc.org/search?query={quote(q_compact[:120])}"
            out.append((title, url))
            if len(out) >= max(1, int(max_results)):
                break
        return out
    except Exception as e:
        log.warning("free_literature hints failed: %s", e)
        return []
