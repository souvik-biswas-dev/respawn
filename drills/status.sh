#!/usr/bin/env bash
# One-shot health check (docs/DRILLS.md "Health check"). Exit 0 when recovered, 1 when not.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR source=lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

DRILL="status"

usage() {
  cat <<'USAGE'
usage: status.sh [-h|--help]

Checks: k3s API answers, ArgoCD apps Healthy/Synced, canary /healthz is 200, BackupPolicy not suspended,
canary sequence increasing across two reads (a few seconds apart). Optional env RESPAWN_APP_URL adds a
check that a public URL returns 200. Kubeconfig: .kubeconfig/respawn.yaml (env KUBECONFIG).
USAGE
}

main() {
  case "${1:-}" in -h|--help) usage; exit 0 ;; '') ;; *) die "unknown option: $1 (try --help)" ;; esac
  need kubectl; need python3
  [ -f "$KUBECONFIG_FILE" ] || die "no kubeconfig at ${KUBECONFIG_FILE} (run make bootstrap, or set KUBECONFIG)"
  HC_PREV_SEQ=""
  health_check || true # the first call only records the sequence
  sleep 3
  if health_check; then
    echo "HEALTHY (canary seq ${HC_SEQ})"
  else
    echo "NOT HEALTHY: ${HC_REASON}"
    exit 1
  fi
}

main "$@"
