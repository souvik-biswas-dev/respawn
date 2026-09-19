#!/usr/bin/env bash
# Put the age private key back after a rebuild or on a new machine.
# The key comes from the operator's safe store (password manager, printed copy). It is never in Git.
#   1. installs it where sops looks for it (~/.config/sops/age/keys.txt, mode 0600)
#   2. stores it as Secret sops-age in namespace argocd, so a later move to ksops needs no new key handling
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KUBECONFIG_FILE="${KUBECONFIG:-${REPO_DIR}/.kubeconfig/respawn.yaml}"
DEST="${SOPS_AGE_KEY_FILE:-${HOME}/.config/sops/age/keys.txt}"
KEY_FILE=""
NO_CLUSTER=0

usage() {
  cat <<USAGE
usage: restore-key.sh [KEY_FILE] [--no-cluster]

  KEY_FILE      path to the age private key (asked for if omitted)
  --no-cluster  only install the key locally; skip the cluster Secret
  -h, --help    show this help

Local destination: ${DEST}
The key is never printed.
USAGE
}

main() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --no-cluster) NO_CLUSTER=1 ;;
      -h|--help) usage; exit 0 ;;
      -*) echo "unknown option: $1" >&2; usage >&2; exit 1 ;;
      *) KEY_FILE="$1" ;;
    esac
    shift
  done
  if [ -z "$KEY_FILE" ]; then
    read -r -p "Path to the age private key file: " KEY_FILE
  fi
  [ -f "$KEY_FILE" ] || { echo "error: no such file: ${KEY_FILE}" >&2; exit 1; }
  grep -q '^AGE-SECRET-KEY-' "$KEY_FILE" || { echo "error: ${KEY_FILE} does not look like an age private key" >&2; exit 1; }

  if [ "$(realpath "$KEY_FILE")" != "$(realpath -m "$DEST")" ]; then
    mkdir -p "$(dirname "$DEST")"
    install -m 0600 "$KEY_FILE" "$DEST"
  fi
  echo "key installed at ${DEST}"

  if [ "$NO_CLUSTER" -eq 1 ]; then
    return
  fi
  command -v kubectl >/dev/null 2>&1 || { echo "error: kubectl not found (use --no-cluster to skip)" >&2; exit 1; }
  [ -f "$KUBECONFIG_FILE" ] || { echo "error: no kubeconfig at ${KUBECONFIG_FILE} (use --no-cluster to skip)" >&2; exit 1; }
  kubectl --kubeconfig "$KUBECONFIG_FILE" create namespace argocd --dry-run=client -o yaml \
    | kubectl --kubeconfig "$KUBECONFIG_FILE" apply -f -
  kubectl --kubeconfig "$KUBECONFIG_FILE" -n argocd create secret generic sops-age \
    --from-file=keys.txt="$KEY_FILE" --dry-run=client -o yaml \
    | kubectl --kubeconfig "$KUBECONFIG_FILE" apply -f -
  echo "secret argocd/sops-age stored"
}

main "$@"
