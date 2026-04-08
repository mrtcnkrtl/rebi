from __future__ import annotations

import json
import os
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, Optional

from config import GEMINI_API_KEY, SUPABASE_URL, get_logger

log = get_logger("knowledge.ingest")

def _sanitize_text_for_pg(text: str) -> str:
    """
    Postgres TEXT cannot contain NUL (0x00) bytes.
    PDFs (and some HTML extractions) may contain embedded NULs.
    """
    if not text:
        return ""
    return str(text).replace("\x00", "").replace("\u0000", "")


def _postgres_dsn() -> str | None:
    u = (os.getenv("SUPABASE_DATABASE_URL") or os.getenv("DATABASE_URL") or "").strip()
    if u:
        return u
    # Fallback: SUPABASE_URL + SUPABASE_DB_PASSWORD (same convention as db_bootstrap.py)
    pw = (os.getenv("SUPABASE_DB_PASSWORD") or "").strip()
    if pw and SUPABASE_URL:
        m = re.search(r"https?://([^.]+)\.supabase\.co", (SUPABASE_URL or "").strip().rstrip("/"), re.I)
        ref = m.group(1) if m else None
        if ref:
            # password may contain special chars -> quote
            from urllib.parse import quote_plus

            return f"postgresql://postgres:{quote_plus(pw)}@db.{ref}.supabase.co:5432/postgres"
    return None


def _strip_html(text: str) -> str:
    # very lightweight HTML strip (no external deps)
    text = re.sub(r"(?is)<script.*?>.*?</script>", " ", text)
    text = re.sub(r"(?is)<style.*?>.*?</style>", " ", text)
    text = re.sub(r"(?is)<[^>]+>", " ", text)
    text = re.sub(r"\s+", " ", text).strip()
    return _sanitize_text_for_pg(text)


def _read_text_file(path: Path) -> tuple[str, str]:
    ext = path.suffix.lower()
    if ext in {".txt", ".md"}:
        return path.read_text(encoding="utf-8", errors="ignore"), ext.lstrip(".")
    if ext in {".html", ".htm"}:
        raw = path.read_text(encoding="utf-8", errors="ignore")
        return _strip_html(raw), "html"
    if ext == ".pdf":
        try:
            from PyPDF2 import PdfReader  # type: ignore
        except Exception as e:
            raise RuntimeError("PyPDF2 missing; install it to ingest PDFs") from e
        reader = PdfReader(str(path))
        pages = []
        for p in reader.pages:
            try:
                pages.append(p.extract_text() or "")
            except Exception:
                pages.append("")
        return _sanitize_text_for_pg("\n\n".join(pages).strip()), "pdf"
    # fallback
    return _sanitize_text_for_pg(path.read_text(encoding="utf-8", errors="ignore")), "other"


def chunk_text(text: str, max_chars: int = 2500, min_chars: int = 400) -> list[str]:
    """
    Simple chunker: paragraph-based, then merges to max_chars.
    This is intentionally deterministic for debugging.
    """
    t = _sanitize_text_for_pg(text or "").strip()
    t = re.sub(r"\n{3,}", "\n\n", t)
    paras = [p.strip() for p in re.split(r"\n\s*\n", t) if p.strip()]
    chunks: list[str] = []
    buf = ""
    for p in paras:
        if not buf:
            buf = p
            continue
        if len(buf) + 2 + len(p) <= max_chars:
            buf = buf + "\n\n" + p
        else:
            if len(buf) >= min_chars:
                chunks.append(buf)
                buf = p
            else:
                # if buffer too small, force merge even if exceeding max_chars a bit
                buf = buf + "\n\n" + p
    if buf.strip():
        chunks.append(buf.strip())
    # final guard: split very large chunks
    out: list[str] = []
    for c in chunks:
        if len(c) <= max_chars * 2:
            out.append(c)
            continue
        # hard split
        for i in range(0, len(c), max_chars):
            out.append(c[i : i + max_chars].strip())
    return [c for c in out if c]


@dataclass
class IngestDoc:
    path: Path
    title: str
    source_type: str
    text: str


def discover_files(root: Path) -> list[Path]:
    exts = {".pdf", ".txt", ".md", ".html", ".htm"}
    paths = []
    for p in root.rglob("*"):
        if p.is_file() and p.suffix.lower() in exts:
            paths.append(p)
    return sorted(paths)


def _ensure_gemini_client():
    if not GEMINI_API_KEY:
        raise RuntimeError("GEMINI_API_KEY is missing")
    from google import genai  # type: ignore

    return genai.Client(api_key=GEMINI_API_KEY)


def embed_texts_google(
    texts: list[str],
    model: str = "gemini-embedding-001",
    output_dimensionality: int = 768,
) -> list[list[float]]:
    """
    Returns a list of embedding vectors (float lists).
    Uses google-genai client.
    """
    client = _ensure_gemini_client()
    # google-genai supports embed_content; API responses vary slightly by version
    try:
        from google.genai import types  # type: ignore

        resp = client.models.embed_content(
            model=model,
            contents=texts,
            config=types.EmbedContentConfig(output_dimensionality=int(output_dimensionality)),
        )
    except Exception:
        # fallback for older client versions without config typing
        resp = client.models.embed_content(
            model=model,
            contents=texts,
        )
    # Normalize response into list[list[float]] across google-genai versions.
    def _values_from_item(item):
        if item is None:
            return None
        # object forms
        for attr in ("values",):
            v = getattr(item, attr, None)
            if v is not None:
                return v
        emb = getattr(item, "embedding", None)
        if emb is not None:
            v = getattr(emb, "values", None)
            if v is not None:
                return v
            # sometimes embedding itself is list
            if isinstance(emb, (list, tuple)):
                return emb
        # dict forms
        if isinstance(item, dict):
            if "values" in item and item["values"] is not None:
                return item["values"]
            if "embedding" in item and item["embedding"] is not None:
                e = item["embedding"]
                if isinstance(e, dict) and e.get("values") is not None:
                    return e.get("values")
                if isinstance(e, (list, tuple)):
                    return e
        return None

    # google-genai typically returns resp.embeddings (list)
    data = getattr(resp, "embeddings", None)
    if data is None and isinstance(resp, dict):
        data = resp.get("embeddings") or resp.get("data")
    if data is None:
        data = getattr(resp, "data", None) or resp

    # ensure list
    if not isinstance(data, list):
        data = [data]

    embs: list[list[float]] = []
    for item in data:
        v = _values_from_item(item)
        if v is None:
            raise RuntimeError("Unexpected embedding response shape")
        embs.append([float(x) for x in list(v)])
    return embs


def _pg_vector_literal(vec: list[float]) -> str:
    # pgvector accepts: '[1,2,3]'
    return "[" + ",".join(f"{x:.8f}" for x in vec) + "]"


def ingest_directory(
    *,
    user_id: str,
    folder_slug: str,
    folder_title: str,
    root_dir: Path,
    store_raw_text: bool = False,
    embed_model: str = "gemini-embedding-001",
    batch_size: int = 16,
) -> dict:
    dsn = _postgres_dsn()
    if not dsn:
        raise RuntimeError("SUPABASE_DATABASE_URL or DATABASE_URL is required for ingestion")
    try:
        import psycopg  # type: ignore
    except Exception as e:
        raise RuntimeError("psycopg is required; install psycopg[binary]") from e

    files = discover_files(root_dir)
    log.info("Discovered %d files under %s", len(files), root_dir)

    docs: list[IngestDoc] = []
    for p in files:
        text, st = _read_text_file(p)
        text = _sanitize_text_for_pg(text or "").strip()
        if len(text) < 200:
            log.warning("Skipping (too short): %s", p)
            continue
        docs.append(IngestDoc(path=p, title=p.stem, source_type=st, text=text))

    inserted_docs = 0
    inserted_chunks = 0
    embedded_chunks = 0
    failed_chunks = 0

    with psycopg.connect(dsn, autocommit=True) as conn:
        with conn.cursor() as cur:
            # folder upsert
            cur.execute(
                """
                insert into public.knowledge_folders (user_id, slug, title)
                values (%s, %s, %s)
                on conflict (user_id, slug) do update set title = excluded.title
                returning id
                """,
                (user_id, folder_slug, folder_title),
            )
            folder_id = cur.fetchone()[0]

            for d in docs:
                # insert document
                cur.execute(
                    """
                    insert into public.knowledge_documents
                      (user_id, folder_id, source_type, title, source_url, raw_text)
                    values (%s, %s, %s, %s, %s, %s)
                    returning id
                    """,
                    (
                        user_id,
                        folder_id,
                        d.source_type,
                        d.title,
                        str(d.path),
                        d.text if store_raw_text else None,
                    ),
                )
                doc_id = cur.fetchone()[0]
                inserted_docs += 1

                chunks = chunk_text(d.text)
                chunks = [_sanitize_text_for_pg(c) for c in chunks]
                # insert chunks without embeddings first
                for idx, ch in enumerate(chunks):
                    cur.execute(
                        """
                        insert into public.knowledge_chunks
                          (user_id, folder_id, document_id, chunk_index, chunk_text, embed_model, embed_ok)
                        values (%s, %s, %s, %s, %s, %s, false)
                        """,
                        (user_id, folder_id, doc_id, idx, ch, embed_model),
                    )
                inserted_chunks += len(chunks)

                # embed and update in batches
                for i in range(0, len(chunks), batch_size):
                    batch = chunks[i : i + batch_size]
                    try:
                        vecs = embed_texts_google(batch, model=embed_model, output_dimensionality=768)
                        if len(vecs) != len(batch):
                            raise RuntimeError("Embedding count mismatch")
                        for j, v in enumerate(vecs):
                            lit = _pg_vector_literal(v)
                            cur.execute(
                                """
                                update public.knowledge_chunks
                                set embedding = %s::vector, embed_ok = true, embed_error = null
                                where document_id = %s and chunk_index = %s
                                """,
                                (lit, doc_id, i + j),
                            )
                        embedded_chunks += len(batch)
                    except Exception as e:
                        failed_chunks += len(batch)
                        err = str(e)[:500]
                        for j in range(len(batch)):
                            cur.execute(
                                """
                                update public.knowledge_chunks
                                set embed_ok = false, embed_error = %s
                                where document_id = %s and chunk_index = %s
                                """,
                                (err, doc_id, i + j),
                            )
                        log.error("Embedding failed for %s batch %d..%d: %s", d.path.name, i, i + len(batch) - 1, err)

    return {
        "folder_slug": folder_slug,
        "folder_title": folder_title,
        "root_dir": str(root_dir),
        "discovered_files": len(files),
        "inserted_docs": inserted_docs,
        "inserted_chunks": inserted_chunks,
        "embedded_chunks": embedded_chunks,
        "failed_chunks": failed_chunks,
    }


if __name__ == "__main__":
    """
    Example:
      SUPABASE_DATABASE_URL=... GEMINI_API_KEY=...
      python -m knowledge.ingest --user <uuid> --folder pubmed --title "PubMed seed" --dir ./data/pubmed
    """
    import argparse

    ap = argparse.ArgumentParser()
    ap.add_argument("--user", required=True, help="supabase auth user uuid")
    ap.add_argument("--folder", required=True, help="folder slug, e.g. pubmed")
    ap.add_argument("--title", required=True, help="folder title")
    ap.add_argument("--dir", required=True, help="directory to ingest")
    ap.add_argument("--store-raw", action="store_true", help="store raw_text in documents table")
    ap.add_argument("--model", default="text-embedding-004")
    args = ap.parse_args()

    result = ingest_directory(
        user_id=args.user,
        folder_slug=args.folder,
        folder_title=args.title,
        root_dir=Path(args.dir),
        store_raw_text=bool(args.store_raw),
        embed_model=str(args.model),
    )
    print(json.dumps(result, indent=2, ensure_ascii=False))

