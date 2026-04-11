from __future__ import annotations

import json
import re
import os
from typing import Optional

from google.genai import types

from config import get_logger
from knowledge.db import pg_conn
from rag_service import gemini_client, _gemini_response_text

log = get_logger("knowledge.classify")

def _exec(cur, sql: str, params=None):
    """
    Supabase Session Pooler (PgBouncer) may reuse server sessions.
    Force simple execution without server-side prepared statements.
    """
    if params is None:
        return cur.execute(sql, prepare=False)
    return cur.execute(sql, params, prepare=False)


def _norm_entity_name(x: str) -> str:
    s = (x or "").strip().lower()
    s = " ".join(s.split())
    return s[:120]


def _upsert_entity_links(
    *,
    user_id: str,
    folder_id: str | None,
    chunk_id: str,
    ingredients: list[str],
) -> None:
    names = [_norm_entity_name(v) for v in (ingredients or []) if _norm_entity_name(v)]
    if not names:
        return
    with pg_conn(autocommit=True) as conn:
        with conn.cursor() as cur:
            for name in sorted(set(names)):
                # upsert entity
                _exec(
                    cur,
                    """
                    insert into public.knowledge_entities (user_id, folder_id, name, kind)
                    values (%s, %s::uuid, %s, 'ingredient')
                    on conflict (user_id, folder_id, name) do update set name = excluded.name
                    returning id
                    """,
                    (user_id, folder_id, name),
                )
                entity_id = cur.fetchone()[0]
                # link
                _exec(
                    cur,
                    """
                    insert into public.knowledge_chunk_entities (chunk_id, entity_id, user_id, folder_id)
                    values (%s, %s, %s, %s::uuid)
                    on conflict (chunk_id, entity_id) do nothing
                    """,
                    (chunk_id, entity_id, user_id, folder_id),
                )


_INGREDIENT_TERMS = [
    # actives
    "niacinamide", "niasinamid",
    "adapalene", "adapalen",
    "azelaic", "azelaik",
    "salicylic", "salisilik", "bha",
    "glycolic", "glikolik",
    "lactic acid", "laktik asit",
    "retinol", "retinal",
    "tranexamic", "traneksamik",
    "arbutin", "alpha arbutin",
    "panthenol", "pantenol",
    "ceramide", "seramid",
    "urea", "üre",
    "zinc pca", "çinko pca",
    "sulfur", "kükürt",
    # common natural candidates
    "tea tree", "çay ağacı",
    "jojoba", "shea",
    "aloe", "papatya", "chamomile",
    "green tea", "yeşil çay",
    # more oils/extracts & common botanicals
    "rosehip", "kuşburnu",
    "argan",
    "squalane", "skualan",
    "propolis",
    "centella", "cica",
    "madecassoside", "madecassosid",
    "allantoin", "allantoin",
    "bisabolol",
    "licorice", "meyan",
    "kojic", "kojik",
    "vitamin e", "tokoferol", "tocopherol",
    "resveratrol", "resveratrol",
    "bakuchiol",
    "hyaluronic", "hyaluronik",
    "glycerin", "gliserin",
    "petrolatum", "vazelin",
    "omega-3", "omega 3",
]


def _regex_extract_ingredients(text: str) -> list[str]:
    t = (text or "").lower()
    found = set()
    for term in _INGREDIENT_TERMS:
        # word-ish boundary for latin terms; for TR terms just substring is fine
        if any(c in term for c in (" ", "ç", "ğ", "ı", "ö", "ş", "ü")):
            if term in t:
                found.add(term)
        else:
            if re.search(rf"\b{re.escape(term)}\b", t):
                found.add(term)
    # normalize a few synonyms to canonical-ish names
    norm = []
    for x in sorted(found):
        if x in ("niasinamid",):
            norm.append("niacinamide")
        elif x in ("adapalen",):
            norm.append("adapalene")
        elif x in ("azelaik",):
            norm.append("azelaic acid")
        elif x in ("salisilik", "bha"):
            norm.append("salicylic acid")
        elif x in ("glikolik",):
            norm.append("glycolic acid")
        elif x in ("traneksamik",):
            norm.append("tranexamic acid")
        elif x in ("pantenol",):
            norm.append("panthenol")
        elif x in ("seramid",):
            norm.append("ceramides")
        elif x in ("üre",):
            norm.append("urea")
        elif x in ("çinko pca",):
            norm.append("zinc pca")
        elif x in ("kükürt",):
            norm.append("sulfur")
        else:
            norm.append(x)
    # de-dup again after normalization
    out = []
    seen = set()
    for x in norm:
        if x not in seen:
            out.append(x)
            seen.add(x)
    return out[:12]


def _ensure_client():
    if not gemini_client:
        raise RuntimeError("Gemini client not ready; set GEMINI_API_KEY")
    return gemini_client


def _is_empty_klass(v) -> bool:
    if v is None:
        return True
    if isinstance(v, dict) and len(v.keys()) == 0:
        return True
    if isinstance(v, str) and v.strip() in {"", "{}", "null"}:
        return True
    return False


def classify_chunks(
    *,
    user_id: str,
    folder_slug: Optional[str] = None,
    document_id: Optional[str] = None,
    limit: int = 400,
    batch_size: int = 12,
    model: str = "gemini-2.0-flash",
    force: bool = False,
) -> dict:
    """
    Fills `knowledge_chunks.klass` with lightweight scientific routing metadata:
      - topic: acne|pigmentation|barrier|sun|eczema|rosacea|hair|general|...
      - ingredients: ["niacinamide", "adapalene", ...]
      - evidence_type: rct|meta|review|mechanism|guideline|observational|case|unknown
      - claims: short bullet-like claims list
      - language: tr|en|other
    """
    client = None
    # Force deterministic mode (no Gemini) when quota is unavailable.
    if (os.getenv("KNOWLEDGE_CLASSIFY_MODE") or "").strip().lower() == "regex":
        client = None
    else:
        try:
            client = _ensure_client()
        except Exception:
            client = None

    updated = 0
    skipped = 0
    failed = 0

    with pg_conn(autocommit=True) as conn:
        with conn.cursor() as cur:
            folder_id = None
            if document_id:
                _exec(
                    cur,
                    """
                    select folder_id from public.knowledge_documents
                    where id = %s::uuid and user_id = %s
                    """,
                    (document_id, user_id),
                )
                drow = cur.fetchone()
                if not drow or not drow[0]:
                    raise RuntimeError(f"Document not found for user: {document_id}")
                folder_id = drow[0]
            if folder_slug:
                _exec(
                    cur,
                    "select id from public.knowledge_folders where user_id=%s and slug=%s",
                    (user_id, folder_slug),
                )
                row = cur.fetchone()
                fid = row[0] if row else None
                if not fid:
                    raise RuntimeError(f"Folder not found for slug={folder_slug}")
                if document_id and str(fid) != str(folder_id):
                    raise RuntimeError("--document-id belongs to a different folder than --folder")
                folder_id = fid

            _exec(
                cur,
                """
                select id, chunk_text, klass
                from public.knowledge_chunks
                where user_id = %s
                  and (%s::uuid is null or folder_id = %s::uuid)
                  and (%s::uuid is null or document_id = %s::uuid)
                  and embed_ok is true
                  and embedding is not null
                order by created_at desc
                limit %s
                """,
                (
                    user_id,
                    folder_id,
                    folder_id,
                    document_id,
                    document_id,
                    max(int(limit), 1),
                ),
            )
            rows = cur.fetchall() or []

    # classify outside transaction loops (still updates inside new connections below)
    to_process = []
    for (chunk_id, chunk_text, klass) in rows:
        if (not force) and (not _is_empty_klass(klass)):
            skipped += 1
            continue
        to_process.append((chunk_id, (chunk_text or "")[:4500]))

    log.info("Chunks: %d total, %d to classify, %d skipped", len(rows), len(to_process), skipped)

    for i in range(0, len(to_process), batch_size):
        batch = to_process[i : i + batch_size]

        # If Gemini is unavailable or quota-limited, do deterministic regex ingredient extraction only.
        if client is None:
            with pg_conn(autocommit=True) as conn:
                with conn.cursor() as cur:
                    for (cid, txt) in batch:
                        ings = _regex_extract_ingredients(txt or "")
                        k = {
                            "id": str(cid),
                            "topic": "ingredient" if ings else "general",
                            "ingredients": ings,
                            "evidence_type": "unknown",
                            "claims": [],
                            "language": "tr" if any(ch in (txt or "") for ch in "çğıöşüÇĞİÖŞÜ") else "en",
                            "method": "regex",
                        }
                        _exec(
                            cur,
                            """
                            update public.knowledge_chunks
                            set klass = %s::jsonb
                            where id = %s and user_id = %s
                            """,
                            (json.dumps(k, ensure_ascii=False), cid, user_id),
                        )
                        updated += 1
                        if ings:
                            try:
                                _upsert_entity_links(
                                    user_id=user_id,
                                    folder_id=str(folder_id) if folder_id else None,
                                    chunk_id=str(cid),
                                    ingredients=ings,
                                )
                            except Exception:
                                pass
            continue

        payload = [{"id": str(cid), "text": text} for (cid, text) in batch]
        prompt = (
            "You are a scientific document chunk classifier for skincare/dermatology.\n"
            "For each chunk, produce a compact JSON classification.\n\n"
            "Output schema for each item:\n"
            "{\n"
            '  "id": "<uuid>",\n'
            '  "topic": "acne|pigmentation|barrier|sun|eczema|rosacea|hair|ingredient|general|other",\n'
            '  "ingredients": ["..."],\n'
            '  "evidence_type": "rct|meta|review|mechanism|guideline|observational|case|unknown",\n'
            '  "claims": ["short claim 1", "short claim 2"],\n'
            '  "language": "tr|en|other"\n'
            "}\n\n"
            "Rules:\n"
            "- Return ONLY JSON array.\n"
            "- Ingredients should be normalized to lowercase ASCII when possible (e.g., niacinamide, adapalene, azelaic acid).\n"
            "- Claims: 0-3 items, keep short.\n"
            "- If unsure, use topic=general and evidence_type=unknown.\n\n"
            f"Input JSON:\n{json.dumps(payload, ensure_ascii=False)}"
        )

        try:
            resp = client.models.generate_content(
                model=model,
                contents=prompt,
                config=types.GenerateContentConfig(
                    system_instruction="Return ONLY JSON. No markdown. Be conservative and accurate.",
                    temperature=0.2,
                    max_output_tokens=1800,
                    response_mime_type="application/json",
                ),
            )
            parsed = json.loads(_gemini_response_text(resp) or "[]")
            if not isinstance(parsed, list):
                raise RuntimeError("Classifier returned non-array JSON")

            id_to_klass = {}
            for item in parsed:
                if not isinstance(item, dict):
                    continue
                cid = item.get("id")
                if cid:
                    id_to_klass[str(cid)] = item

            with pg_conn(autocommit=True) as conn:
                with conn.cursor() as cur:
                    for (cid, _txt) in batch:
                        k = id_to_klass.get(str(cid))
                        if not k:
                            failed += 1
                            continue
                        _exec(
                            cur,
                            """
                            update public.knowledge_chunks
                            set klass = %s::jsonb
                            where id = %s and user_id = %s
                            """,
                            (json.dumps(k, ensure_ascii=False), cid, user_id),
                        )
                        updated += 1
                        try:
                            ings = k.get("ingredients") if isinstance(k, dict) else None
                            if isinstance(ings, list) and ings:
                                _upsert_entity_links(
                                    user_id=user_id,
                                    folder_id=str(folder_id) if folder_id else None,
                                    chunk_id=str(cid),
                                    ingredients=[str(x) for x in ings if x],
                                )
                        except Exception:
                            pass
        except Exception as e:
            # If quota exceeded, switch to regex mode for this and the rest of this run.
            msg = str(e)
            log.error("Classification batch failed (%d..%d): %s", i, i + len(batch) - 1, e)
            if "RESOURCE_EXHAUSTED" in msg or "429" in msg:
                client = None
                # fallback classify current batch deterministically
                with pg_conn(autocommit=True) as conn:
                    with conn.cursor() as cur:
                        for (cid, txt) in batch:
                            ings = _regex_extract_ingredients(txt or "")
                            k = {
                                "id": str(cid),
                                "topic": "ingredient" if ings else "general",
                                "ingredients": ings,
                                "evidence_type": "unknown",
                                "claims": [],
                                "language": "tr" if any(ch in (txt or "") for ch in "çğıöşüÇĞİÖŞÜ") else "en",
                                "method": "regex",
                            }
                            _exec(
                                cur,
                                """
                                update public.knowledge_chunks
                                set klass = %s::jsonb
                                where id = %s and user_id = %s
                                """,
                                (json.dumps(k, ensure_ascii=False), cid, user_id),
                            )
                            updated += 1
                            if ings:
                                try:
                                    _upsert_entity_links(
                                        user_id=user_id,
                                        folder_id=str(folder_id) if folder_id else None,
                                        chunk_id=str(cid),
                                        ingredients=ings,
                                    )
                                except Exception:
                                    pass
                continue
            failed += len(batch)

    return {
        "user_id": user_id,
        "folder_slug": folder_slug,
        "document_id": document_id,
        "model": model,
        "total_scanned": len(rows),
        "classified_updated": updated,
        "skipped_existing": skipped,
        "failed": failed,
    }


if __name__ == "__main__":
    import argparse

    ap = argparse.ArgumentParser()
    ap.add_argument("--user", required=True, help="supabase auth user uuid")
    ap.add_argument("--folder", default=None, help="folder slug (optional)")
    ap.add_argument(
        "--document-id",
        default=None,
        dest="document_id",
        help="only classify chunks for this knowledge_documents.id (e.g. after single-file ingest)",
    )
    ap.add_argument("--limit", type=int, default=400)
    ap.add_argument("--batch", type=int, default=12)
    ap.add_argument("--model", default="gemini-2.0-flash")
    ap.add_argument("--force", action="store_true", help="overwrite existing klass and rebuild entity links")
    args = ap.parse_args()

    result = classify_chunks(
        user_id=args.user,
        folder_slug=args.folder,
        document_id=args.document_id,
        limit=args.limit,
        batch_size=args.batch,
        model=args.model,
        force=bool(args.force),
    )
    print(json.dumps(result, indent=2, ensure_ascii=False))

