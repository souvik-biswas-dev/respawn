#!/usr/bin/env bash
# Decrypt gitops/secrets/*.enc.yaml with SOPS and apply them to the cluster.
#
# Why this and not ArgoCD + ksops: ksops needs a custom ArgoCD repo-server image and
# a key mounted into it. That is a lot of moving parts for a one-node platform. A
# decrypt-then-apply step is one command, easy to read at 2 a.m., and ArgoCD never
# sees plaintext. Cost: secrets are applied by a person (or the rebuild runbook), not
# by Git sync. ArgoCD's canary app does not manage these Secrets, so it will not prune them.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SECRETS_DIR="${REPO_DIR}/gitops/secrets"
KUBECONFIG_FILE="${KUBECONFIG:-${REPO_DIR}/.kubeconfig/respawn.yaml}"
DRY_RUN=0

usage() {
  cat <<USAGE
usage: apply-secrets.sh [--dry-run]

Decrypts every gitops/secrets/*.enc.yaml and applies it with kubectl.
Needs sops, kubectl and your age private key (SOPS_AGE_KEY_FILE, or the sops default
location ~/.config/sops/age/keys.txt). Run 'make restore-key' first on a new machine.

options:
  --dry-run   decrypt and validate with 'kubectl --dry-run=client'; change nothing
  -h, --help  show this help

env: KUBECONFIG (default: ${KUBECONFIG_FILE})
USAGE
}

need() { command -v "$1" >/dev/null 2>&1 || { echo "error: $1 not found in PATH" >&2; exit 1; }; }

apply_one() {
  local file="$1" ns
  # Read the namespace from the (unencrypted) metadata; value fields stay encrypted.
  ns="$(sops --decrypt --extract '["metadata"]["namespace"]' "$file")"
  if [ "$DRY_RUN" -eq 1 ]; then
    sops --decrypt "$file" | kubectl --kubeconfig "$KUBECONFIG_FILE" apply --dry-run=client -f -
    return
  fi
  # The namespace may not exist yet if ArgoCD has not synced the app. Creating it here is
  # harmless: ArgoCD adopts it later.
  kubectl --kubeconfig "$KUBECONFIG_FILE" create namespace "$ns" --dry-run=client -o yaml \
    | kubectl --kubeconfig "$KUBECONFIG_FILE" apply -f -
  sops --decrypt "$file" | kubectl --kubeconfig "$KUBECONFIG_FILE" apply -f -
}

main() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --dry-run) DRY_RUN=1 ;;
      -h|--help) usage; exit 0 ;;
      *) echo "unknown option: $1" >&2; usage >&2; exit 1 ;;
    esac
    shift
  done
  need sops
  need kubectl
  [ "$DRY_RUN" -eq 1 ] || [ -f "$KUBECONFIG_FILE" ] || { echo "error: no kubeconfig at ${KUBECONFIG_FILE} (run make bootstrap)" >&2; exit 1; }

  local found=0 f
  for f in "${SECRETS_DIR}"/*.enc.yaml; do
    [ -e "$f" ] || continue
    found=1
    echo "applying ${f#"${REPO_DIR}"/}"
    apply_one "$f"
  done
  [ "$found" -eq 1 ] || { echo "error: no *.enc.yaml files in ${SECRETS_DIR}" >&2; exit 1; }
}

main "$@"
