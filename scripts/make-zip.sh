#!/usr/bin/env bash
# Build respawn-step-<n>.zip one level above the repo, excluding junk and secrets.
set -euo pipefail

usage() { echo "usage: bash scripts/make-zip.sh <step-number>"; }
[ "${1:-}" ] || { usage; exit 1; }

step="$1"
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repo_name="$(basename "$repo_dir")"
out="$(dirname "$repo_dir")/respawn-step-${step}.zip"

cd "$(dirname "$repo_dir")"
rm -f "$out"
zip -r "$out" "$repo_name" \
  -x "*/.git/*" "*/node_modules/*" "*/.terraform/*" "*.tfstate" "*.tfstate.*" \
     "*/dist/*" "*/.DS_Store" "*.agekey" "*/keys.txt" "*.pem" >/dev/null

echo "created: $out"
unzip -l "$out" | tail -n 1
