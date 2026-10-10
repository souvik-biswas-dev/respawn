#!/usr/bin/env bash
# Drill: kill the k3s process on the server and time the recovery. Spec: docs/DRILLS.md.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR source=lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

DRILL="kill-node"
MANUAL_AFTER=180

usage() {
  cat <<USAGE
usage: kill-node.sh --host NAME --yes-really [options]
       kill-node.sh --simulate [options]

Sends SIGKILL to the k3s service on the server (systemctl kill -s KILL k3s over SSH) and waits for
the health check in docs/DRILLS.md to pass. systemd is expected to restart k3s by itself; if it has
not after --manual-after seconds the drill restarts it the way docs/RUNBOOK.md section 3 does, and
says so in the result notes.
Expected alerts: NodeDown or PodCrashLooping (read back from Prometheus after recovery).

options:
  --manual-after N    seconds before the manual restart (default ${MANUAL_AFTER})
USAGE
  common_usage
}

remote() { ssh -o BatchMode=yes -o ConnectTimeout=10 "${HOST_USER}@${HOST_ADDR}" "$@"; }

simulate() {
  sim_begin
  LAST_SEQ_BEFORE="$(rand_between 50000 400000)"
  sim_step "systemd restarts k3s" 8 25
  sim_step "k3s API answers" 15 45
  sim_step "ArgoCD apps Healthy/Synced" 20 70
  sim_step "canary sequence increasing" 10 20
  # Pods keep running while only the k3s process dies, so no rows are lost.
  FIRST_SEQ_AFTER=$(( LAST_SEQ_BEFORE + SIM_TOTAL ))
  RPO_SECONDS="$(compute_rpo "$LAST_SEQ_BEFORE" "$FIRST_SEQ_AFTER")"
  ALERTS_FIRED="PodCrashLooping"
  add_note "SIMULATED: no server was touched. Timings are random. alerts_fired is the EXPECTED set from docs/DRILLS.md, not an observation."
  env_set provider simulated
  sim_finish
  write_result
}

real() {
  need python3
  guard_checks
  need kubectl; need ssh
  [ -n "$TIMEOUT" ] || TIMEOUT=600
  require_int --timeout "$TIMEOUT"
  guard_plan \
    "send SIGKILL to the k3s service (systemctl kill -s KILL k3s)" \
    "wait up to ${TIMEOUT}s for systemd to restart it; restart it by hand after ${MANUAL_AFTER}s" \
    "poll the health check every ${POLL_SECONDS}s"
  T_START="$(now)"
  precheck
  LAST_SEQ_BEFORE="$(read_seq)" || die "cannot read the canary sequence"

  T_FAULT="$(now)"
  log "fault injected at $(date -u +%H:%M:%SZ), last_seq_before=${LAST_SEQ_BEFORE}"
  remote "sudo systemctl kill -s KILL k3s" || die "could not signal k3s over SSH"

  local manual=0
  begin_step "k3s API answers"
  until kc get --raw /readyz >/dev/null 2>&1; do
    [ $(( $(now) - T_FAULT )) -lt "$TIMEOUT" ] || die "timed out after ${TIMEOUT}s: k3s API never came back (RUNBOOK section 3)"
    if [ "$manual" -eq 0 ] && [ $(( $(now) - T_FAULT )) -ge "$MANUAL_AFTER" ]; then
      log "systemd did not bring k3s back in ${MANUAL_AFTER}s; restarting it by hand"
      remote "sudo systemctl restart k3s" || log "manual restart failed over SSH"
      add_note "k3s did not restart by itself within ${MANUAL_AFTER}s; the drill restarted it with systemctl restart k3s."
      manual=1
    fi
    sleep "$POLL_SECONDS"
  done
  end_step

  begin_step "health check passes (ArgoCD, app endpoint, canary writing)"
  FIRST_SEQ_AFTER=""
  wait_healthy $(( TIMEOUT - ($(now) - T_FAULT) + 1 )) || die "timed out after ${TIMEOUT}s: ${HC_REASON}"
  end_step
  T_RECOVERED="$(now)"

  RPO_SECONDS="$(compute_rpo "$LAST_SEQ_BEFORE" "$FIRST_SEQ_AFTER")"
  collect_alerts "$T_FAULT"
  env_set provider "${DRILL_PROVIDER:-unknown}"
  env_set host "$HOST_ARG"
  write_result
}

main() {
  while [ $# -gt 0 ]; do
    case "$1" in
      -h|--help) usage; exit 0 ;;
      --manual-after) [ $# -ge 2 ] || die "--manual-after needs a value"; require_int --manual-after "$2"; MANUAL_AFTER="$2"; shift 2 ;;
      *) common_arg "$@"; shift "$COMMON_SHIFT" ;;
    esac
  done
  if [ "$SIMULATE" -eq 1 ]; then simulate; else real; fi
}

main "$@"
