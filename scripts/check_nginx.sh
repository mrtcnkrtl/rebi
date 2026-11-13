#!/usr/bin/env bash
# deploy/nginx/*.conf dosyalarını canlıdakiyle aynı imajda (nginx:alpine) `nginx -t` ile doğrular.
# CI'da çalışır: bozuk bir nginx ayarı sunucuya hiç ulaşmasın (canlıda ayar dosyası konteynere bağlıdır;
# bozuk dosya web konteynerinin bir sonraki açılışında siteyi tamamen düşürür).
# HTTPS ayarı sertifika dosyası ister; doğrulama için geçici, kendinden imzalı bir sertifika üretilir.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/letsencrypt/live/rebiovil.com"
openssl req -x509 -nodes -newkey rsa:2048 -days 1 -subj "/CN=rebiovil.com" \
  -keyout "$tmp/letsencrypt/live/rebiovil.com/privkey.pem" \
  -out "$tmp/letsencrypt/live/rebiovil.com/fullchain.pem" >/dev/null 2>&1

for conf in prod.conf prod.https.conf; do
  echo "nginx -t: deploy/nginx/$conf"
  docker run --rm \
    --add-host api:127.0.0.1 \
    -v "$root/deploy/nginx/$conf:/etc/nginx/conf.d/default.conf:ro" \
    -v "$tmp/letsencrypt:/etc/letsencrypt:ro" \
    nginx:alpine nginx -t
done
echo "nginx ayarları geçerli."
