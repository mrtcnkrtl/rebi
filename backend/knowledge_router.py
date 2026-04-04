"""
REBI AI - Bilgi Yönlendirici (Knowledge Router)
=================================================
Flow Engine'den gelen sorgu planını alır ve Supabase'den
hedefli, metadata-filtrelemeli sorgularla veri çeker.

Vektör araması yapmaz -> embedding token'ı harcamaz.
Sadece Supabase PostgreSQL filtreleri kullanır.
"""

from supabase import create_client
from config import SUPABASE_URL, SUPABASE_SERVICE_KEY, get_logger

log = get_logger("knowledge_router")

supabase = None
if SUPABASE_URL and SUPABASE_SERVICE_KEY:
    try:
        supabase = create_client(SUPABASE_URL, SUPABASE_SERVICE_KEY)
        log.info("Supabase bağlantısı kuruldu")
    except Exception as e:
        log.error("Supabase bağlantı hatası: %s", e)


async def execute_query_plan(query_plan: list[dict]) -> dict:
    """
    Flow Engine'den gelen sorgu planını çalıştırır.
    Her sorgu metadata filtreleri ile Supabase'e gider.
    """
    if not supabase:
        log.warning("Supabase bağlantısı yok, boş döndürülüyor")
        return {"knowledge_chunks": [], "sources": [], "total_retrieved": 0, "by_category": {}}

    all_chunks = []
    all_sources = set()
    by_category = {}

    for query in query_plan:
        try:
            kategori = query.get("kategori", "")
            alt_kategori = query.get("alt_kategori", "")
            limit = query.get("limit", 10)
            purpose = query.get("purpose", "")
            search_text = query.get("search_text", "")

            q = supabase.table("knowledge_base").select("content, metadata")

            if kategori:
                q = q.filter("metadata->>kategori", "eq", kategori)
            if alt_kategori:
                q = q.filter("metadata->>alt_kategori", "eq", alt_kategori)
            if search_text:
                q = q.ilike("content", f"%{search_text}%")

            q = q.limit(limit)
            result = q.execute()

            if result.data:
                for row in result.data:
                    content = row.get("content", "")
                    metadata = row.get("metadata", {})
                    source = metadata.get("source", "Bilinmiyor")
                    all_chunks.append(content)
                    all_sources.add(source)
                    cat_key = purpose or f"{kategori}/{alt_kategori}"
                    if cat_key not in by_category:
                        by_category[cat_key] = []
                    by_category[cat_key].append(content)

        except Exception as e:
            log.error("Sorgu hatası [%s/%s]: %s", kategori, alt_kategori, e)
            continue

    log.info("Bilgi tabanı sorgusu: %d parça, %d kaynak", len(all_chunks), len(all_sources))
    return {
        "knowledge_chunks": all_chunks,
        "sources": list(all_sources),
        "total_retrieved": len(all_chunks),
        "by_category": by_category,
    }


async def get_targeted_context(knowledge_result: dict, max_chars: int = 3000) -> str:
    """Çekilen bilgiyi AI'a gönderilecek kompakt bir bağlam metnine dönüştürür."""
    if not knowledge_result["knowledge_chunks"]:
        return ""

    context_parts = []
    remaining = max_chars

    for category, chunks in knowledge_result["by_category"].items():
        if remaining <= 0:
            break
        header = f"[{category}]"
        context_parts.append(header)
        remaining -= len(header)

        for chunk in chunks[:3]:
            clean = chunk.replace("\x00", "").strip()
            if not clean:
                continue
            if len(clean) > remaining:
                clean = clean[:remaining] + "..."
            context_parts.append(clean)
            remaining -= len(clean)
            if remaining <= 0:
                break
        context_parts.append("")

    return "\n".join(context_parts).strip()
