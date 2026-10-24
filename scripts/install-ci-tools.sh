#!/usr/bin/env bash
# Install pinned lint tools from their GitHub releases, verifying each download against a SHA-256
# that was cross-checked with the publisher's own checksum file. Used by CI; works locally too.
# usage: scripts/install-ci-tools.sh TOOL...   (kubeconform kustomize promtool gitleaks)
# Installs into ${TOOLS_BIN:-$HOME/.local/bin}.
set -euo pipefail

BIN="${TOOLS_BIN:-$HOME/.local/bin}"
mkdir -p "$BIN"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# name | url | sha256 | path of the binary inside the archive
fetch() { # name url sha inner
  local name="$1" url="$2" sha="$3" inner="$4"
  local file="${work}/${name}.tgz"
  curl -fsSL --retry 3 -o "$file" "$url"
  echo "${sha}  ${file}" | sha256sum -c - >/dev/null || { echo "checksum mismatch for ${name}; refusing to install" >&2; exit 1; }
  tar -xzf "$file" -C "$work" "$inner"
  install -m 0755 "${work}/${inner}" "${BIN}/${name}"
  echo "installed ${name} -> ${BIN}/${name}"
}

install_tool() {
  case "$1" in
    kubeconform) fetch kubeconform https://github.com/yannh/kubeconform/releases/download/v0.8.0/kubeconform-linux-amd64.tar.gz 9bc2bffbf71f261128533edaf912153948b7ff238f9a531ae6d34466ec287883 kubeconform ;;
    kustomize) fetch kustomize https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv5.8.3/kustomize_v5.8.3_linux_amd64.tar.gz cb9e31198d3f63b44848bd0afc4c8efc56e6cfef9c93a4a39a211940e6decd61 kustomize ;;
    promtool) fetch promtool https://github.com/prometheus/prometheus/releases/download/v3.15.1/prometheus-3.15.1.linux-amd64.tar.gz 6a726885328ad9efebbf36e876ce2fb6225468a71fd1e7ce3ba666d5f4d97a84 prometheus-3.15.1.linux-amd64/promtool ;;
    gitleaks) fetch gitleaks https://github.com/gitleaks/gitleaks/releases/download/v8.30.1/gitleaks_8.30.1_linux_x64.tar.gz 551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb gitleaks ;;
    *) echo "unknown tool: $1 (kubeconform kustomize promtool gitleaks)" >&2; exit 2 ;;
  esac
}

[ $# -gt 0 ] || { echo "usage: $0 TOOL..." >&2; exit 2; }
[ "$(uname -s)-$(uname -m)" = "Linux-x86_64" ] || { echo "these pins are for linux amd64 only" >&2; exit 2; }
for t in "$@"; do install_tool "$t"; done
