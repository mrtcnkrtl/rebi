#!/usr/bin/env bash
# Ubuntu sunucuda bir kez çalıştırın: Docker kurar, /opt/rebi hazırlar.
# Sonra projeyi klonlayıp .env dosyalarını doldurun (REBIOVIL-SIFIRDAN.md).

set -euo pipefail

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "Bu script'i root veya sudo ile çalıştırın: sudo bash bootstrap-server.sh"
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y ca-certificates curl gnupg

install -m 0755 -d /etc/apt/keyrings
if [[ ! -f /etc/apt/keyrings/docker.gpg ]]; then
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
fi
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "${VERSION_CODENAME}") stable" \
  > /etc/apt/sources.list.d/docker.list
apt-get update -qq
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

TARGET_USER="${SUDO_USER:-$USER}"
if [[ "$TARGET_USER" == "root" ]]; then
  TARGET_USER="$(logname 2>/dev/null || echo root)"
fi

mkdir -p /opt/rebi
chown -R "$TARGET_USER:$TARGET_USER" /opt/rebi

echo ""
echo "Docker kuruldu. Sıradaki adımlar (kullanıcı: $TARGET_USER):"
echo "  1) su - $TARGET_USER   (veya yeni SSH oturumu)"
echo "  2) cd /opt/rebi && git clone <REPO_URL> ."
echo "  3) cp deploy/env.docker.example .env && nano .env"
echo "  4) cp deploy/.env.api.example deploy/.env.api && nano deploy/.env.api"
echo "  5) docker compose up -d --build"
echo "  6) HTTPS için: bash deploy/enable-https.sh"
echo ""
echo "Ayrıntılı Türkçe rehber: docs/REBIOVIL-SIFIRDAN.md"
