#!/usr/bin/env bash
# Mağaza derlemesi: ortam dosyasını doğrular, sonra release paketini üretir.
#
#   tool/build_release.sh android   # build/app/outputs/bundle/release/app-release.aab
#   tool/build_release.sh ios       # build/ios/ipa/*.ipa (yalnızca macOS + Xcode)
#
# Ortam dosyası: env/prod.json (varsayılan) ya da ENV_FILE=... ile. Şablon: env/example.json.
# Eksik ya da şablon değerli bir dosyayla derleme durur: SUPABASE_URL olmadan çıkan bir paketin
# kimsenin giriş yapamadığı bir uygulama olacağı mağazaya gitmeden yakalanır.
set -euo pipefail

cd "$(dirname "$0")/.."

platform="${1:-}"
env_file="${ENV_FILE:-env/prod.json}"

if [[ "$platform" != "android" && "$platform" != "ios" ]]; then
  echo "Kullanım: tool/build_release.sh android|ios" >&2
  exit 2
fi
if [[ ! -f "$env_file" ]]; then
  echo "$env_file yok. env/example.json dosyasını kopyalayıp doldurun." >&2
  exit 1
fi

py="$(command -v python3 || command -v python || true)"
if [[ -z "$py" ]]; then
  echo "python3 gerekli (ortam dosyası denetimi için)." >&2
  exit 1
fi

"$py" - "$env_file" <<'PYEOF'
import json
import sys

sys.stderr.reconfigure(encoding="utf-8")  # Windows konsolunda Türkçe karakterler bozulmasın
path = sys.argv[1]
try:
    env = json.load(open(path, encoding="utf-8"))
except Exception as e:  # noqa: BLE001
    sys.exit(f"{path} okunamadı: {e}")

errors = []
url = str(env.get("SUPABASE_URL", "")).strip()
key = str(env.get("SUPABASE_ANON_KEY", "")).strip()
api = str(env.get("API_URL", "")).strip()

if not url.startswith("https://") or "xxxx" in url:
    errors.append("SUPABASE_URL gerçek bir https adresi olmalı (şablon değeri kalmış olabilir).")
if len(key) < 40 or key.startswith("eyJ...") or "..." in key:
    errors.append("SUPABASE_ANON_KEY eksik ya da şablon değeri.")
if api and (not api.startswith("https://") or any(h in api for h in ("localhost", "127.0.0.1", "10.0.2.2"))):
    errors.append("API_URL https olmalı ve yerel adres göstermemeli (boş bırakırsanız canlı API kullanılır).")
if env.get("FIREBASE_ENABLED") is True:
    errors.append("FIREBASE_ENABLED=true: google-services.json / GoogleService-Info.plist eklendiğinden emin olun, sonra bu denetimi güncelleyin.")

if errors:
    print(f"{path} mağaza derlemesi için uygun değil:", file=sys.stderr)
    for e in errors:
        print(f"  - {e}", file=sys.stderr)
    sys.exit(1)

if str(env.get("REBI_PLUS_CHECKOUT_URL", "")).strip():
    print("UYARI: REBI_PLUS_CHECKOUT_URL dolu. iOS ve Google Play dijital abonelikler için uygulama içi satın alma ister; "
          "harici ödeme bağlantısı mağaza incelemesinde reddedilebilir (docs/MOBIL-YAYIN.md).", file=sys.stderr)
PYEOF

if [[ "${CHECK_ONLY:-}" == "1" ]]; then
  echo "Ortam dosyası geçerli."
  exit 0
fi

flutter pub get

case "$platform" in
  android)
    # REBI_REQUIRE_RELEASE_SIGNING: android/key.properties yoksa debug anahtarıyla sessizce imzalamak yerine dur.
    REBI_REQUIRE_RELEASE_SIGNING=true flutter build appbundle --release --dart-define-from-file="$env_file"
    ;;
  ios)
    flutter build ipa --release --dart-define-from-file="$env_file"
    ;;
esac
