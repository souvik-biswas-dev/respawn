#!/usr/bin/env bash
# Restore the canary Postgres from the newest BackupVouch backup in the S3 bucket, then resume backups.
#
# Used after a rebuild (docs/RUNBOOK.md section 2) and by the delete-server drill. It does NOT use
# BackupVouch's status: on a rebuilt cluster that status is gone, so it lists the bucket instead.
# BackupVouch only verifies backups and never restores (its RUNBOOK, "A real restore"), so the
# restore itself is plain pg_restore of the custom-format dump that `pg_dump -Fc` produced.
#
# Why the policy is suspended first: a rebuilt database is empty. A scheduled backup of it would
# become the "newest" backup and, after keepLast runs, retention would delete the good ones.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KUBECONFIG_FILE="${KUBECONFIG:-${REPO_DIR}/.kubeconfig/respawn.yaml}"
NS="${CANARY_NAMESPACE:-canary}"
POLICY="${BACKUP_POLICY:-canary-db}"
PG_POD="${PG_POD:-canary-postgres-0}"
PG_USER="${PG_USER:-canary}"
PG_DB="${PG_DB:-canary}"

ASSUME_YES=0
DRY_RUN=0
RESUME_ONLY=0
KEEP_SUSPENDED=0
OBJECT_KEY=""

usage() {
  cat <<USAGE
usage: restore-data.sh [options]

Restores database '${PG_DB}' in pod ${PG_POD} (namespace ${NS}) from the newest .dump object in the
bucket named by BackupPolicy ${POLICY}, then sets spec.suspend=false so backups resume.
Needs: kubectl, aws (AWS CLI v2), access to the cluster and to the bucket (credentials are read
from the policy's Secret in the cluster).

options:
  --object KEY      restore this object key instead of the newest
  --resume-only     do not restore anything; just resume backups (first install, nothing to restore)
  --keep-suspended  restore, but leave backups suspended
  --dry-run         read-only: show the endpoint, the object it would restore, and stop
  --yes             do not ask for confirmation
  -h, --help        show this help

The restore REPLACES the tables in the target database (pg_restore --clean, one transaction).
The canary writer keeps running and recovers by itself: after the swap its insert fails on a
duplicate sequence, it reconnects, re-reads MAX(seq) and carries on from the restored data.

env: KUBECONFIG (default ${KUBECONFIG_FILE}), CANARY_NAMESPACE, BACKUP_POLICY, PG_POD, PG_USER, PG_DB,
     AWS_DEFAULT_REGION (default us-east-1; many S3-compatible stores ignore it)

Prints key=value lines at the end (restored_object, restored_rows, restored_last_seq) for the drills.
USAGE
}

log() { echo "[restore-data] $*" >&2; }
die() { echo "error: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "$1 not found in PATH"; }

kc() { kubectl --kubeconfig "$KUBECONFIG_FILE" "$@"; }

policy_field() { kc -n "$NS" get backuppolicy "$POLICY" -o "jsonpath={$1}"; }

secret_field() { # secret name, key
  kc -n "$NS" get secret "$1" -o "jsonpath={.data.$2}" | base64 -d
}

set_suspend() { # true|false
  kc -n "$NS" patch backuppolicy "$POLICY" --type merge -p "{\"spec\":{\"suspend\":$1}}" >/dev/null
}

find_newest_object() { # prints the newest key, empty if none
  # Keys are <prefix><UTC timestamp>.dump, so a plain sort is a time sort.
  aws --endpoint-url "$ENDPOINT_URL" s3api list-objects-v2 \
      --bucket "$BUCKET" --prefix "$PREFIX" --query 'Contents[].Key' --output text 2>/dev/null \
    | tr '\t' '\n' | grep '\.dump$' | sort | tail -n 1 || true
}

load_storage_settings() {
  local endpoint use_tls secret
  endpoint="$(policy_field .spec.storage.endpoint)"
  BUCKET="$(policy_field .spec.storage.bucket)"
  PREFIX="$(policy_field .spec.storage.prefix)"
  use_tls="$(policy_field .spec.storage.useTLS)"
  secret="$(policy_field .spec.storage.credentialsSecretRef.name)"
  [ -n "$endpoint" ] && [ -n "$BUCKET" ] && [ -n "$secret" ] || die "BackupPolicy ${POLICY} has no storage settings"
  case "$endpoint" in *example.invalid*) die "storage endpoint is still the placeholder (${endpoint}); set a real off-server S3 endpoint in gitops/apps/backupvouch/config/canary-backuppolicy.yaml" ;; esac
  if [ "$use_tls" = "true" ]; then ENDPOINT_URL="https://${endpoint}"; else ENDPOINT_URL="http://${endpoint}"; fi
  AWS_ACCESS_KEY_ID="$(secret_field "$secret" accessKey)"
  AWS_SECRET_ACCESS_KEY="$(secret_field "$secret" secretKey)"
  export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY
  export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"
}

confirm() {
  [ "$ASSUME_YES" -eq 1 ] && return 0
  local answer
  read -r -p "Replace database '${PG_DB}' with ${BUCKET}/${OBJECT_KEY}? Type 'restore' to continue: " answer
  [ "$answer" = "restore" ] || die "aborted"
}

do_restore() {
  log "streaming s3://${BUCKET}/${OBJECT_KEY} into pg_restore in ${PG_POD}"
  # pipefail (set above) makes a failed download fail the whole pipeline, not just pg_restore.
  aws --endpoint-url "$ENDPOINT_URL" s3 cp "s3://${BUCKET}/${OBJECT_KEY}" - \
    | kc -n "$NS" exec -i "$PG_POD" -c postgres -- \
        pg_restore -U "$PG_USER" -d "$PG_DB" --clean --if-exists --no-owner --no-privileges --single-transaction
}

report() {
  local row rows last
  row="$(kc -n "$NS" exec "$PG_POD" -c postgres -- psql -U "$PG_USER" -d "$PG_DB" -Atc 'SELECT count(*) || chr(32) || coalesce(max(seq), 0) FROM canary')"
  rows="${row%% *}"
  last="${row##* }"
  log "restored table: ${rows} rows, highest seq ${last}"
  echo "restored_object=${OBJECT_KEY}"
  echo "restored_rows=${rows}"
  echo "restored_last_seq=${last}"
}

main() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --object) [ $# -ge 2 ] || die "--object needs a value"; OBJECT_KEY="$2"; shift ;;
      --resume-only) RESUME_ONLY=1 ;;
      --keep-suspended) KEEP_SUSPENDED=1 ;;
      --dry-run) DRY_RUN=1 ;;
      --yes) ASSUME_YES=1 ;;
      -h|--help) usage; exit 0 ;;
      *) echo "unknown option: $1" >&2; usage >&2; exit 1 ;;
    esac
    shift
  done

  need kubectl
  [ -f "$KUBECONFIG_FILE" ] || die "no kubeconfig at ${KUBECONFIG_FILE} (run make bootstrap, or set KUBECONFIG)"
  kc -n "$NS" get backuppolicy "$POLICY" >/dev/null 2>&1 \
    || die "BackupPolicy ${POLICY} not found in ${NS}: has ArgoCD synced backupvouch-config yet? (kubectl -n argocd get applications)"

  if [ "$RESUME_ONLY" -eq 1 ]; then
    [ "$DRY_RUN" -eq 1 ] && { log "dry run: would set spec.suspend=false on ${POLICY}"; exit 0; }
    set_suspend false
    log "backups resumed (first run starts at the next scheduled time)"
    exit 0
  fi

  need aws
  need base64
  load_storage_settings

  if [ -z "$OBJECT_KEY" ]; then
    OBJECT_KEY="$(find_newest_object)"
    [ -n "$OBJECT_KEY" ] || die "no .dump objects under s3://${BUCKET}/${PREFIX}. If this is the first install there is nothing to restore: run 'make resume-backups'"
  fi
  log "newest backup: s3://${BUCKET}/${OBJECT_KEY}"
  if [ "$DRY_RUN" -eq 1 ]; then
    log "dry run: would suspend ${POLICY}, wait for ${PG_POD}, restore, report, resume. Stopping."
    exit 0
  fi

  confirm
  set_suspend true
  log "waiting for ${PG_POD} to be ready"
  kc -n "$NS" wait --for=condition=Ready "pod/${PG_POD}" --timeout=300s >/dev/null
  do_restore
  report
  if [ "$KEEP_SUSPENDED" -eq 1 ]; then
    log "backups left suspended; resume with: make resume-backups"
  else
    set_suspend false
    log "backups resumed"
  fi
}

main "$@"
