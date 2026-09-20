#!/usr/bin/env bash
# CI/pre-commit guard: every gitops/secrets/*.enc.yaml must be SOPS-encrypted.
# Fails if a file has no sops block, or any value under data/stringData is not ENC[...].
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() { echo "usage: bash scripts/check-secrets.sh   (checks gitops/secrets/*.enc.yaml)"; }
case "${1:-}" in -h|--help) usage; exit 0 ;; esac

bad=0
for f in "${REPO_DIR}"/gitops/secrets/*.enc.yaml; do
  [ -e "$f" ] || continue
  if ! grep -q '^sops:' "$f"; then echo "NOT ENCRYPTED (no sops block): $f"; bad=1; continue; fi
  # Top-level key tracking: inside data/stringData every indented value must be ENC[...].
  if ! awk '
    /^[A-Za-z]/ { in_data = ($0 ~ /^(data|stringData):/) ; next }
    in_data && /^[ ]+[^ #]/ { v=$0; sub(/^[^:]*:[ ]*/, "", v); if (v !~ /^ENC\[/) { bad=1 } }
    END { exit bad }' "$f"; then
    echo "PLAINTEXT VALUE in: $f"; bad=1
  fi
done
[ "$bad" -eq 0 ] && echo "all gitops/secrets/*.enc.yaml are encrypted"
exit "$bad"
