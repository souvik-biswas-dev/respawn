#!/usr/bin/env bash
# Drill: destroy the server and run the full rebuild path (docs/ARCHITECTURE.md "Recovery path").
# This is the headline RTO/RPO number. Spec: docs/DRILLS.md.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR source=lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

DRILL="delete-server"
VIA=""
AGE_KEY=""
VM_NAME="respawn-local"
ALLOW_STALE_BACKUP=0
MAX_BACKUP_AGE=7200 # the policy is hourly; two hours old means something is already wrong
TF="${TF:-terraform}"
TF_ENV="${REPO_DIR}/infra/terraform/envs/prod"
NEW_IP=""

usage() {
  cat <<USAGE
usage: delete-server.sh --via terraform|local --host NAME --age-key FILE --yes-really [options]
       delete-server.sh --simulate [options]

DESTROYS THE SERVER, then rebuilds it with the steps of docs/RUNBOOK.md section 2 and times each one:
destroy, create, wait for SSH, ansible bootstrap, restore-key, apply-secrets, wait for ArgoCD to create
the canary, restore-data, health check. The timer stops when the health check in docs/DRILLS.md passes.
Backups are NOT deleted (they live off the server) but the restore REPLACES the canary tables.

options:
  --via terraform|local   how the VM is destroyed and recreated: Terraform (env TF=tofu works) or the
                          Multipass script infra/local/multipass-vm.sh. Required: no default on purpose.
  --age-key FILE          age private key for restore-key (required)
  --vm-name NAME          Multipass VM name for --via local (default ${VM_NAME})
  --allow-stale-backup    skip the check that a verified backup newer than 2h exists
RPO is the canary rows lost: last_seq_before minus the highest seq that survived the restore.
USAGE
  common_usage
}

typed_confirmation() {
  [ "$NO_PROMPT" -eq 0 ] && [ -t 0 ] || return 0
  local answer
  read -r -p "Type the server name (${HOST_ARG}) to destroy it: " answer
  [ "$answer" = "$HOST_ARG" ] || die "aborted: the name did not match"
}

simulate() {
  sim_begin
  LAST_SEQ_BEFORE="$(rand_between 50000 400000)"
  sim_step "destroy server" 8 40
  sim_step "create server" 20 70
  sim_step "wait for ssh" 15 60
  sim_step "ansible bootstrap" 240 420
  sim_step "restore-key and apply-secrets" 5 15
  sim_step "wait for ArgoCD to create the canary" 120 300
  sim_step "restore-data" 15 60
  sim_step "canary sequence increasing" 8 25
  # Backups are hourly, so loss is bounded by about an hour (1 row per second).
  RPO_SECONDS="$(rand_between 300 3300)"
  FIRST_SEQ_AFTER=$(( LAST_SEQ_BEFORE - RPO_SECONDS ))
  ALERTS_FIRED="CanaryWriteGap NodeDown"
  add_note "SIMULATED: no server was destroyed. Timings and the RPO are random (RPO drawn inside the hourly-backup bound). alerts_fired is the EXPECTED set, not an observation."
  env_set provider simulated
  sim_finish
  write_result
}

destroy_and_create() {
  case "$VIA" in
    terraform)
      run_step "destroy server" "$TF" -chdir="$TF_ENV" destroy -target=module.server -auto-approve -input=false
      run_step "create server" "$TF" -chdir="$TF_ENV" apply -auto-approve -input=false
      NEW_IP="$("$TF" -chdir="$TF_ENV" output -raw server_ip)" || die "cannot read terraform output server_ip"
      ;;
    local)
      run_step "destroy server" bash "${REPO_DIR}/infra/local/multipass-vm.sh" destroy --name "$VM_NAME"
      run_step "create server" bash "${REPO_DIR}/infra/local/multipass-vm.sh" up --name "$VM_NAME"
      NEW_IP="$(bash "${REPO_DIR}/infra/local/multipass-vm.sh" ip --name "$VM_NAME")" || die "cannot read the VM address"
      ;;
  esac
  [ -n "$NEW_IP" ] || die "no address for the new server"
  log "new server address: ${NEW_IP}"
  # A rebuilt server has a new SSH host key; an old known_hosts line for the same address would block Ansible.
  ssh-keygen -R "$NEW_IP" >/dev/null 2>&1 || true
}

wait_ssh() {
  begin_step "wait for ssh"
  until ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new "${HOST_USER}@${NEW_IP}" true >/dev/null 2>&1; do
    check_deadline "ssh never answered on ${NEW_IP}"
    sleep "$POLL_SECONDS"
  done
  end_step
}

check_deadline() { [ $(( $(now) - T_FAULT )) -lt "$TIMEOUT" ] || die "timed out after ${TIMEOUT}s: $1"; }

wait_canary_objects() {
  begin_step "wait for ArgoCD to create the canary"
  until kc -n "$NS_CANARY" get pod canary-postgres-0 >/dev/null 2>&1 \
     && kc -n "$NS_CANARY" get backuppolicy "$POLICY_NAME" >/dev/null 2>&1; do
    check_deadline "ArgoCD never created canary-postgres-0 and the BackupPolicy"
    sleep "$POLL_SECONDS"
  done
  end_step
}

do_restore_data() {
  local out
  begin_step "restore-data"
  out="$(bash "${DRILLS_DIR}/restore-data.sh" --yes)" || die "restore-data failed"
  end_step
  RESTORED_LAST_SEQ="$(printf '%s\n' "$out" | sed -n 's/^restored_last_seq=//p')"
  case "$RESTORED_LAST_SEQ" in ''|*[!0-9]*) die "restore-data did not report restored_last_seq" ;; esac
}

real() {
  need python3
  guard_checks
  need kubectl; need ssh; need ansible-playbook; need sops; need aws
  [ "$VIA" = "terraform" ] || [ "$VIA" = "local" ] || die "--via terraform|local is required"
  [ -n "$AGE_KEY" ] && [ -f "$AGE_KEY" ] || die "--age-key FILE is required (the age private key from your safe store)"
  if [ "$VIA" = "local" ]; then need multipass; else need "$TF"; fi
  [ -n "$TIMEOUT" ] || TIMEOUT=3600
  require_int --timeout "$TIMEOUT"
  guard_plan \
    "DESTROY the server ${HOST_ARG} (via ${VIA}) and everything on it" \
    "rebuild it: create, ansible bootstrap, restore-key, apply-secrets, ArgoCD sync, restore-data (REPLACES the canary tables)" \
    "stop the clock when the health check passes (timeout ${TIMEOUT}s)"
  typed_confirmation
  T_START="$(now)"
  precheck
  if [ "$ALLOW_STALE_BACKUP" -eq 0 ]; then
    local age
    age="$(backup_age_seconds)" || die "no verified backup found in Prometheus (backup_last_success_timestamp_seconds). Without one the drill would measure total data loss. Use --allow-stale-backup to override."
    [ "$age" -le "$MAX_BACKUP_AGE" ] || die "the newest verified backup is ${age}s old (limit ${MAX_BACKUP_AGE}s); fix BackupStale first or use --allow-stale-backup"
    log "newest verified backup is ${age}s old"
  fi
  LAST_SEQ_BEFORE="$(read_seq)" || die "cannot read the canary sequence"

  T_FAULT="$(now)"
  log "fault injected at $(date -u +%H:%M:%SZ), last_seq_before=${LAST_SEQ_BEFORE}"
  destroy_and_create
  wait_ssh
  check_deadline "before ansible"
  run_step "ansible bootstrap" bash -c "cd '${REPO_DIR}/infra/ansible' && ansible-playbook -i '${INVENTORY_FILE}' site.yml -e 'ansible_host=${NEW_IP}' -e 'k3s_public_address=${NEW_IP}'"
  begin_step "restore-key and apply-secrets"
  bash "${REPO_DIR}/scripts/restore-key.sh" "$AGE_KEY" >&2 || die "restore-key failed"
  bash "${REPO_DIR}/scripts/apply-secrets.sh" >&2 || die "apply-secrets failed"
  end_step
  wait_canary_objects
  do_restore_data

  begin_step "health check passes"
  FIRST_SEQ_AFTER=""
  wait_healthy $(( TIMEOUT - ($(now) - T_FAULT) + 1 )) || die "timed out after ${TIMEOUT}s: ${HC_REASON}"
  end_step
  T_RECOVERED="$(now)"

  FIRST_SEQ_AFTER="$RESTORED_LAST_SEQ" # what survived the restore, not what the writer wrote afterwards
  RPO_SECONDS="$(compute_rpo "$LAST_SEQ_BEFORE" "$FIRST_SEQ_AFTER")"
  ALERTS_FIRED=""
  add_note "alerts_fired is not observable: Prometheus is destroyed with the server and its history is gone."
  add_note "RPO is bounded by the backup schedule (hourly) plus the backup duration."
  case "$VIA" in local) env_set provider "${DRILL_PROVIDER:-multipass}" ;; *) env_set provider "${DRILL_PROVIDER:-terraform}" ;; esac
  env_set host "$HOST_ARG"
  env_set via "$VIA"
  write_result
}

main() {
  while [ $# -gt 0 ]; do
    case "$1" in
      -h|--help) usage; exit 0 ;;
      --via) [ $# -ge 2 ] || die "--via needs a value"; VIA="$2"; shift 2 ;;
      --age-key) [ $# -ge 2 ] || die "--age-key needs a value"; AGE_KEY="$2"; shift 2 ;;
      --vm-name) [ $# -ge 2 ] || die "--vm-name needs a value"; VM_NAME="$2"; shift 2 ;;
      --allow-stale-backup) ALLOW_STALE_BACKUP=1; shift ;;
      *) common_arg "$@"; shift "$COMMON_SHIFT" ;;
    esac
  done
  if [ "$SIMULATE" -eq 1 ]; then simulate; else real; fi
}

main "$@"
