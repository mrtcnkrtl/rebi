# Knowledge ingestion (Google embeddings → Supabase pgvector)

## 1) DB migration

Bu repo zaten startup'ta `supabase/migrations/*.sql` dosyalarını uyguluyor.

- Yeni migration: `supabase/migrations/20260408120000_knowledge_store.sql`
- İçerik: `knowledge_folders`, `knowledge_documents`, `knowledge_chunks` + `vector(768)` embedding

## 2) Ingest (local files)

Desteklenen dosyalar: `.pdf`, `.txt`, `.md`, `.html`

Gerekli env:

- `SUPABASE_DATABASE_URL` (veya `DATABASE_URL`)
- `GEMINI_API_KEY`

Çalıştırma:

```bash
cd backend
python -m knowledge.ingest \
  --user "<SUPABASE_USER_UUID>" \
  --folder "pubmed" \
  --title "PubMed seed" \
  --dir "../knowledge-data/pubmed" \
  --store-raw
```

Notlar:

- Chunks önce DB’ye yazılır, sonra embedding batch’leri işlenir.
- Hata ayıklama için her chunk’ta `embed_ok` ve `embed_error` alanı tutulur.

## 3) Re-embed (hatalıları düzelt)

```bash
cd backend
python3 -m knowledge.reembed_failed --user "<SUPABASE_USER_UUID>" --folder "pubmed"
```

## 4) Klasmanlara böl (chunk classification)

`klass` alanını doldurur (topic/ingredients/evidence_type/claims/language).

```bash
cd backend
python3 -m knowledge.classify_chunks --user "<SUPABASE_USER_UUID>" --folder "pubmed"
```

