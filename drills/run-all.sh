#!/usr/bin/env bash
# Run kill-node, fill-disk and delete-server in that order, then write drills/results/summary.json.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR source=lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

DRILL="run-all"
VIA=""
AGE_KEY=""

usage() {
  cat <<USAGE
usage: run-all.sh --host NAME --via terraform|local --age-key FILE --yes-really [options]
       run-all.sh --simulate [options]
       run-all.sh --summarize-only [options]

Runs the three drills in order (delete-server last, because it destroys everything) and stops at the
first failure. Then writes summary.json: per drill the newest REAL run, or the newest simulated one if
no real run exists. Every entry carries its mode; simulated ones also carry "label": "SIMULATED".

options:
  --via, --age-key        passed to delete-server.sh
  --summarize-only        rebuild summary.json from the existing result files; run nothing
USAGE
  common_usage
}

main() {
  local summarize_only=0 args=() dargs=() f result rc=0
  while [ $# -gt 0 ]; do
    case "$1" in
      -h|--help) usage; exit 0 ;;
      --summarize-only) summarize_only=1; shift ;;
      --via) [ $# -ge 2 ] || die "--via needs a value"; VIA="$2"; shift 2 ;;
      --age-key) [ $# -ge 2 ] || die "--age-key needs a value"; AGE_KEY="$2"; shift 2 ;;
      *) common_arg "$@"; args+=("${@:1:$COMMON_SHIFT}"); shift "$COMMON_SHIFT" ;;
    esac
  done
  # Re-state the parsed common options for the children (RESULTS_DIR also goes by environment).
  export RESULTS_DIR
  [ "$summarize_only" -eq 1 ] || {
    [ "$SIMULATE" -eq 1 ] || [ -n "$HOST_ARG" ] || die "pass --host NAME (and --yes-really), or --simulate"
    dargs=("--via" "$VIA" "--age-key" "$AGE_KEY")
    for f in kill-node fill-disk delete-server; do
      log "=== ${f} ==="
      if [ "$f" = "delete-server" ] && [ "$SIMULATE" -eq 0 ]; then
        result="$(bash "${DRILLS_DIR}/${f}.sh" ${args[@]+"${args[@]}"} "${dargs[@]}")" || rc=$?
      else
        result="$(bash "${DRILLS_DIR}/${f}.sh" ${args[@]+"${args[@]}"})" || rc=$?
      fi
      [ "$rc" -eq 0 ] || { log "${f} failed (exit ${rc}); stopping. Earlier results are kept."; break; }
      log "$(printf '%s\n' "$result" | tail -n 1)"
    done
  }
  write_summary
  return "$rc"
}

main "$@"
