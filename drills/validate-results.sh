#!/usr/bin/env bash
# Validate every drill result against drills/schema/*.json. Used by `make drill-validate` and CI.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR source=lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

DRILL="validate"

usage() {
  cat <<'USAGE'
usage: validate-results.sh [DIR]

Checks every *.json in DIR (default drills/results) against drills/schema/result.schema.json, and
summary.json against summary.schema.json. Also fails if a file says mode "real" but is a sample-*.json,
because samples are always simulated. Needs python3 with the jsonschema module.
USAGE
}

main() {
  case "${1:-}" in -h|--help) usage; exit 0 ;; esac
  local dir="${1:-$RESULTS_DIR}" f name count=0 failed=0
  [ -d "$dir" ] || die "no such directory: ${dir}"
  for f in "$dir"/*.json; do
    [ -e "$f" ] || break
    name="$(basename "$f")"
    if [ "$name" = "summary.json" ]; then
      validate_json "$f" "$SUMMARY_SCHEMA_FILE" || { echo "FAIL ${name}" >&2; failed=1; continue; }
    else
      validate_json "$f" "$SCHEMA_FILE" || { echo "FAIL ${name}" >&2; failed=1; continue; }
      case "$name" in
        sample-*) grep -q '"mode": "simulated"' "$f" || { echo "FAIL ${name}: a sample must be simulated" >&2; failed=1; continue; } ;;
      esac
    fi
    echo "ok   ${name}"
    count=$((count + 1))
  done
  echo "${count} file(s) valid"
  [ "$failed" -eq 0 ]
}

main "$@"
