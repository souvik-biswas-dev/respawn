#!/usr/bin/env bash
# Drill: fill the data disk past 95% and time detection plus recovery. Spec: docs/DRILLS.md.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR source=lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

DRILL="fill-disk"
# k3s's local-path provisioner keeps the Postgres volume under here, so this is the data disk.
FILL_PATH="/var/lib/rancher/k3s"
ALERT_TIMEOUT=900
FILLER_CREATED=0
FILLER=""

usage() {
  cat <<USAGE
usage: fill-disk.sh --host NAME --yes-really [options]
       fill-disk.sh --simulate [options]

Allocates one filler file (fallocate) on the server so the filesystem holding ${FILL_PATH} is 97% full,
waits for the DiskCritical alert to fire (its rule has "for: 5m"), removes the filler and waits for the
health check. The filler is deleted by an EXIT trap even if the drill fails or is interrupted.
The disk is filled to 97%, not 100%, on purpose: Postgres normally keeps writing, so the RTO here is
mostly the time to be alerted. DiskFillingSoon has "for: 30m" and usually does not fire inside the wait.

options:
  --path DIR            directory on the server's data disk (default ${FILL_PATH})
  --alert-timeout N     seconds to wait for DiskCritical; 0 skips the wait (default ${ALERT_TIMEOUT})
USAGE
  common_usage
}

remote() { ssh -o BatchMode=yes -o ConnectTimeout=10 "${HOST_USER}@${HOST_ADDR}" "$@"; }

cleanup_filler() {
  [ "$FILLER_CREATED" -eq 1 ] || return 0
  local _try
  for _try in 1 2 3; do
    if remote "sudo rm -f '${FILLER}'"; then
      FILLER_CREATED=0
      log "filler file removed"
      return 0
    fi
    sleep 5
  done
  echo "ERROR: could not remove ${FILLER}. Do it by hand: ssh ${HOST_USER}@${HOST_ADDR} sudo rm -f ${FILLER}" >&2
}

simulate() {
  sim_begin
  LAST_SEQ_BEFORE="$(rand_between 50000 400000)"
  sim_step "allocate filler to 97%" 3 12
  sim_step "wait for DiskCritical alert" 330 450
  sim_step "remove filler" 1 4
  sim_step "canary sequence increasing" 8 20
  FIRST_SEQ_AFTER=$(( LAST_SEQ_BEFORE + SIM_TOTAL ))
  RPO_SECONDS="$(compute_rpo "$LAST_SEQ_BEFORE" "$FIRST_SEQ_AFTER")"
  ALERTS_FIRED="DiskCritical"
  add_note "SIMULATED: no disk was filled. Timings are random. alerts_fired is the EXPECTED set, not an observation."
  env_set provider simulated
  sim_finish
  write_result
}

real() {
  need python3
  guard_checks
  need kubectl; need ssh
  case "$FILL_PATH" in /[A-Za-z0-9._/-]*) ;; *) die "--path must be an absolute path of letters, digits and ._/-" ;; esac
  require_int --alert-timeout "$ALERT_TIMEOUT"
  [ -n "$TIMEOUT" ] || TIMEOUT=300
  require_int --timeout "$TIMEOUT"
  FILLER="${FILL_PATH%/}/respawn-drill-filler.bin"
  guard_plan \
    "allocate ${FILLER} on ${HOST_ARG} until the filesystem is 97% full" \
    "wait up to ${ALERT_TIMEOUT}s for the DiskCritical alert, then delete the filler (also on failure or Ctrl-C)" \
    "wait up to ${TIMEOUT}s for the health check"
  CLEANUP_HOOK=cleanup_filler
  T_START="$(now)"
  precheck
  LAST_SEQ_BEFORE="$(read_seq)" || die "cannot read the canary sequence"

  local size avail need pct
  read -r size avail <<<"$(remote "df -B1 --output=size,avail '${FILL_PATH}' | tail -n 1")" || die "df failed over SSH"
  case "${size:-x}${avail:-x}" in *[!0-9]*) die "could not read df output from the server" ;; esac
  need=$(( avail - size * 3 / 100 )) # leave 3% available, as node_exporter's avail/size sees it
  [ "$need" -gt 0 ] || die "the disk is already more than 97% full; nothing to do"

  T_FAULT="$(now)"
  begin_step "allocate filler to 97%"
  FILLER_CREATED=1 # set before the call: a half-finished fallocate must still be cleaned up
  remote "sudo fallocate -l ${need} '${FILLER}'" || die "fallocate failed"
  read -r size avail <<<"$(remote "df -B1 --output=size,avail '${FILL_PATH}' | tail -n 1")"
  pct=$(( 100 - avail * 100 / size ))
  log "disk is now ${pct}% used"
  [ "$pct" -ge 95 ] || die "disk only reached ${pct}% (target 95%+)"
  end_step

  if [ "$ALERT_TIMEOUT" -gt 0 ]; then
    begin_step "wait for DiskCritical alert"
    until alert_firing DiskCritical; do
      if [ $(( $(now) - STEP_T0 )) -ge "$ALERT_TIMEOUT" ]; then
        add_note "DiskCritical did not fire within ${ALERT_TIMEOUT}s; the filler was removed anyway."
        break
      fi
      sleep "$POLL_SECONDS"
    done
    end_step
  fi

  begin_step "remove filler"
  cleanup_filler
  [ "$FILLER_CREATED" -eq 0 ] || die "filler file could not be removed"
  end_step

  begin_step "health check passes (Postgres writable, canary writing)"
  FIRST_SEQ_AFTER=""
  wait_healthy "$TIMEOUT" || die "timed out after ${TIMEOUT}s: ${HC_REASON}"
  end_step
  T_RECOVERED="$(now)"

  RPO_SECONDS="$(compute_rpo "$LAST_SEQ_BEFORE" "$FIRST_SEQ_AFTER")"
  collect_alerts "$T_FAULT"
  add_note "RTO includes the time spent waiting for the alert (detection is part of recovery). Disk was filled to ${pct}%, not 100%."
  env_set provider "${DRILL_PROVIDER:-unknown}"
  env_set host "$HOST_ARG"
  write_result
}

main() {
  while [ $# -gt 0 ]; do
    case "$1" in
      -h|--help) usage; exit 0 ;;
      --path) [ $# -ge 2 ] || die "--path needs a value"; FILL_PATH="$2"; shift 2 ;;
      --alert-timeout) [ $# -ge 2 ] || die "--alert-timeout needs a value"; ALERT_TIMEOUT="$2"; shift 2 ;;
      *) common_arg "$@"; shift "$COMMON_SHIFT" ;;
    esac
  done
  if [ "$SIMULATE" -eq 1 ]; then simulate; else real; fi
}

main "$@"
