#!/usr/bin/env bash
# CI'da backend testlerini çalıştırır. Bir test kırılırsa adını ve kısa hata iletisini
# GitHub annotation'ı olarak yazar: annotation'lar oturum açmadan API'den okunabilir,
# iş günlükleri okunamaz. Kullanım: backend dizininde `bash ../scripts/run_backend_tests.sh`.
set -u

out="$(mktemp)"
rc=0
python -m pytest -q -m "not slow" -rfE "$@" >"$out" 2>&1 || rc=$?
cat "$out"

if [ "$rc" -ne 0 ]; then
  grep -E '^(FAILED|ERROR) ' "$out" | head -n 20 | while IFS= read -r line; do
    # Annotation iletisinde % ve satır sonu kaçışlanmalı.
    msg="${line//'%'/'%25'}"
    echo "::error title=pytest::${msg}"
  done
fi
rm -f "$out"
exit "$rc"
