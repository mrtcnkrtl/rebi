#!/usr/bin/env bash
# Web ve mobil aynı çeviri dosyalarını kullanır. Tek kaynak: frontend/src/locales.
# Web tarafında bir metin değiştiğinde bu betiği çalıştırın (test/locales_sync_test.dart farkı yakalar).
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
src="$here/../frontend/src/locales"
dst="$here/assets/locales"
rm -rf "$dst"
mkdir -p "$dst"
for dir in "$src"/*/; do
  lang="$(basename "$dir")"
  mkdir -p "$dst/$lang"
  cp "$dir"/*.json "$dst/$lang/"
done
echo "Çeviriler kopyalandı: $(ls "$dst" | tr '\n' ' ')"
