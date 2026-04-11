#!/usr/bin/env bash
# Masaüstündeki "data aı" klasöründeki PDF/docx/txt/md/html dosyalarını
# Supabase Postgres (knowledge_*) tablolarına yükler ve Gemini ile embed eder.
#
# Gerekli .env (backend/.env):
#   GEMINI_API_KEY
#   SUPABASE_DATABASE_URL veya DATABASE_URL
#   — veya —
#   SUPABASE_URL + SUPABASE_DB_PASSWORD (Supabase Dashboard → Settings → Database)
#
# İsteğe bağlı: KNOWLEDGE_CATALOG_USER_ID (yoksa varsayılan katalog UUID kullanılır)

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/backend"

if [[ ! -f .env ]]; then
  echo "backend/.env bulunamadı." >&2
  exit 1
fi

set -a
# shellcheck disable=SC1091
source ./.env
set +a

USER_ID="${KNOWLEDGE_CATALOG_USER_ID:-00000000-0000-4000-8000-000000000001}"
# Masaüstü klasörü (Türkçe ı): "data aı"
DATA_DIR="${DESKTOP_KNOWLEDGE_DIR:-$HOME/Desktop/data aı}"

if [[ ! -d "$DATA_DIR" ]]; then
  echo "Klasör yok: $DATA_DIR" >&2
  echo "Yolu DESKTOP_KNOWLEDGE_DIR ile değiştirebilirsiniz." >&2
  exit 1
fi

echo "Kaynak: $DATA_DIR"
echo "Kullanıcı (katalog): $USER_ID"
echo "Ek argümanlar: $*"
echo ""

python3 -m knowledge.ingest \
  --user "$USER_ID" \
  --folder "data-pdfs" \
  --title "Rebi masaüstü katalog" \
  --dir "$DATA_DIR" \
  --store-raw \
  "$@"
