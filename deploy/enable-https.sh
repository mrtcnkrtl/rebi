#!/usr/bin/env bash
# Repo kökünden çalıştırın. Önce HTTP ile site ayağa kalkmış olmalı; DNS A kayıtları doğru olmalı.
# Sertifika alırken 80/443 boş olmalı — bu yüzden web konteyneri geçici durur.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DOMAIN="${DOMAIN:-rebiovil.com}"
COMPOSE_HTTP=(docker compose -f docker-compose.yml)
COMPOSE_HTTPS=(docker compose -f docker-compose.yml -f docker-compose.https.yml)

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "certbot için root veya sudo gerekir: sudo LETSENCRYPT_EMAIL=siz@ornek.com bash deploy/enable-https.sh"
  exit 1
fi

if [[ -z "${LETSENCRYPT_EMAIL:-}" ]]; then
  echo "Let's Encrypt e-postası gerekli. Örnek:"
  echo "  export LETSENCRYPT_EMAIL=sizin@emailiniz.com"
  echo "  sudo -E bash deploy/enable-https.sh"
  exit 1
fi

if ! command -v certbot >/dev/null 2>&1; then
  apt-get update -qq
  apt-get install -y certbot
fi

echo "Web konteyneri durduruluyor (80 boş olmalı)..."
"${COMPOSE_HTTP[@]}" stop web 2>/dev/null || true
"${COMPOSE_HTTPS[@]}" stop web 2>/dev/null || true

certbot certonly --standalone --non-interactive --agree-tos \
  -m "$LETSENCRYPT_EMAIL" \
  -d "$DOMAIN" -d "www.${DOMAIN}" \
  --keep-until-expiring

echo "HTTPS ile yeniden başlatılıyor..."
"${COMPOSE_HTTPS[@]}" up -d --build

echo ""
echo "Tamam: https://${DOMAIN}"
echo "Otomatik yenileme için crontab'a şunu ekleyin (root):"
echo "  0 3 * * * cd $ROOT && docker compose -f docker-compose.yml -f docker-compose.https.yml stop web && certbot renew --quiet && docker compose -f docker-compose.yml -f docker-compose.https.yml start web"
