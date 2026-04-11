#!/usr/bin/env bash
# Yeni tek PDF → knowledge.ingest (chunk + embedding) + isteğe bağlı classify_chunks
# Kullanım: ./scripts/ingest_one_pdf.sh /yol/dosya.pdf
# Env: backend/.env veya ortamda SUPABASE_* , GEMINI_API_KEY, isteğe bağlı KNOWLEDGE_CATALOG_USER_ID

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PDF="${1:-}"
if [[ -z "$PDF" || ! -f "$PDF" ]]; then
  echo "Kullanım: $0 /tam/yol/dosya.pdf" >&2
  exit 1
fi

USER_ID="${KNOWLEDGE_CATALOG_USER_ID:-00000000-0000-4000-8000-000000000001}"
cd "$ROOT/backend"

echo "==> Ingest + embedding: $PDF"
OUT="$(mktemp)"
python3 -m knowledge.ingest \
  --user "$USER_ID" \
  --folder "data-pdfs" \
  --title "Rebi katalog" \
  --file "$PDF" \
  --store-raw | tee "$OUT"

DOC_ID="$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d.get('inserted_document_ids',[''])[0] or '')" "$OUT")"
rm -f "$OUT"

if [[ -n "$DOC_ID" ]]; then
  echo ""
  echo "==> İsteğe bağlı: madde / sınıf için (LLM veya regex):"
  echo "python3 -m knowledge.classify_chunks --user \"$USER_ID\" --folder data-pdfs --document-id \"$DOC_ID\" --limit 500"
else
  echo "Uyarı: inserted_document_ids boş (dosya çok kısa veya zaten yüklü olabilir)." >&2
fi
