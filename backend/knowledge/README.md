# Knowledge ingestion (Google embeddings → Supabase pgvector)

## 1) DB migration

Bu repo zaten startup'ta `supabase/migrations/*.sql` dosyalarını uyguluyor.

- Yeni migration: `supabase/migrations/20260408120000_knowledge_store.sql`
- İçerik: `knowledge_folders`, `knowledge_documents`, `knowledge_chunks` + `vector(768)` embedding

## 2) Ingest (local files)

Sohbet RAG’ı **`data-pdfs`** slug’ı ve katalog kullanıcısı (`KNOWLEDGE_CATALOG_USER_ID`, yoksa `00000000-0000-4000-8000-000000000001`) ile bu tablolardan okur.  
**Embedding**, ingest sırasında chunk’lar yazıldıktan hemen sonra otomatik çalışır (`GEMINI_API_KEY` gerekir).

Desteklenen dosyalar: `.pdf`, `.txt`, `.md`, `.html`

Gerekli env:

- `SUPABASE_DATABASE_URL` (veya `DATABASE_URL` / `SUPABASE_URL` + `SUPABASE_DB_PASSWORD`)
- `GEMINI_API_KEY`

### Yeni tek PDF → chunk + embedding (en yaygın)

```bash
cd backend
python -m knowledge.ingest \
  --user "${KNOWLEDGE_CATALOG_USER_ID:-00000000-0000-4000-8000-000000000001}" \
  --folder "data-pdfs" \
  --title "Rebi katalog" \
  --file "/tam/yol/yeni.pdf" \
  --store-raw
```

JSON çıktıda `inserted_document_ids` ve `embedded_chunks` / `failed_chunks` kontrol edilir. Ardından isteğe bağlı madde endeksi:

```bash
python3 -m knowledge.classify_chunks \
  --user "${KNOWLEDGE_CATALOG_USER_ID:-00000000-0000-4000-8000-000000000001}" \
  --folder "data-pdfs" \
  --document-id "<yukarıdaki inserted_document_ids[0]>" \
  --limit 500
```

### Klasör (toplu)

```bash
cd backend
python -m knowledge.ingest \
  --user "<SUPABASE_USER_UUID>" \
  --folder "data-pdfs" \
  --title "Rebi katalog" \
  --dir "../knowledge-data/data-pdfs" \
  --store-raw
```

Aynı **mutlak dosya yolu** bu klasörde zaten varsa varsayılan olarak **atlanır** (çift kayıt olmaz). Güncel PDF için: `--replace-existing` (eski doküman + chunk’lar silinir, yeniden yüklenir).

Notlar:

- Chunks önce DB’ye yazılır, sonra embedding batch’leri işlenir.
- Hata ayıklama için her chunk’ta `embed_ok` ve `embed_error` alanı tutulur.

## 3) Re-embed (hatalıları düzelt)

```bash
cd backend
python3 -m knowledge.reembed_failed --user "<SUPABASE_USER_UUID>" --folder "data-pdfs"
```

## 4) Klasmanlara böl (chunk classification)

`klass` alanını doldurur (topic/ingredients/evidence_type/claims/language).

```bash
cd backend
python3 -m knowledge.classify_chunks --user "<SUPABASE_USER_UUID>" --folder "data-pdfs"
```

