#!/usr/bin/env bash
# Create or destroy a free local Ubuntu VM with Multipass, set up like the Terraform
# server (an `ops` user with your SSH key), so the Ansible in infra/ansible works unchanged.
# Cost: zero. It runs on your own computer. Install Multipass first: https://multipass.run
set -euo pipefail

NAME="respawn-local"
CPUS=2
MEMORY="4G"
DISK="20G"
KEY_FILE="${HOME}/.ssh/id_ed25519.pub"
TMP_FILE=""

usage() {
  cat <<USAGE
usage: multipass-vm.sh <up|destroy|ip> [options]

  up        create the VM (or report that it exists) and print an inventory snippet
  destroy   delete the VM and free its disk. This is what the delete-server drill does locally.
  ip        print the VM's IPv4 address

options (for up):
  --name NAME      VM name              (default: ${NAME})
  --cpus N         CPU cores            (default: ${CPUS})
  --memory SIZE    memory, e.g. 4G      (default: ${MEMORY})
  --disk SIZE      disk, e.g. 20G       (default: ${DISK})
  --key FILE       PUBLIC ssh key file  (default: ${KEY_FILE})
  -h, --help       show this help
USAGE
}

cleanup() {
  # Global on purpose: an EXIT trap cannot see a function'"'"'s local variables.
  [ -z "${TMP_FILE}" ] || rm -f "${TMP_FILE}"
}

die() {
  echo "error: $*" >&2
  exit 1
}

need_multipass() {
  command -v multipass >/dev/null 2>&1 || die "multipass is not installed (https://multipass.run)"
}

vm_exists() {
  multipass info "${NAME}" >/dev/null 2>&1
}

vm_ip() {
  multipass info "${NAME}" --format csv | awk -F, 'NR==2 {print $3}'
}

write_cloud_init() {
  local out="$1" pubkey
  [ -f "${KEY_FILE}" ] || die "public key not found: ${KEY_FILE} (create one with: ssh-keygen -t ed25519)"
  pubkey="$(head -n 1 "${KEY_FILE}")"
  case "${pubkey}" in
    ssh-ed25519\ * | ssh-rsa\ * | ecdsa-sha2-*) ;;
    *) die "${KEY_FILE} does not look like a PUBLIC key" ;;
  esac
  # Same content as infra/terraform/modules/server/cloud-init.yaml.tftpl.
  cat >"${out}" <<CLOUDINIT
#cloud-config
users:
  - name: ops
    groups: [sudo]
    shell: /bin/bash
    sudo: "ALL=(ALL) NOPASSWD:ALL"
    lock_passwd: true
    ssh_authorized_keys:
      - ${pubkey}
package_update: true
packages:
  - python3
CLOUDINIT
}

cmd_up() {
  need_multipass
  if vm_exists; then
    echo "VM ${NAME} already exists."
  else
    TMP_FILE="$(mktemp)"
    trap cleanup EXIT
    write_cloud_init "${TMP_FILE}"
    multipass launch 24.04 --name "${NAME}" --cpus "${CPUS}" --memory "${MEMORY}" --disk "${DISK}" --cloud-init "${TMP_FILE}"
  fi
  print_inventory
}

print_inventory() {
  local ip
  ip="$(vm_ip)"
  cat <<SNIPPET

VM is up at ${ip}. Put this in infra/ansible/inventory/hosts.yml:

all:
  children:
    respawn:
      hosts:
        respawn-1:
          ansible_host: ${ip}
          ansible_user: ops
          respawn_protected: false
      vars:
        k3s_public_address: ${ip}
        argocd_bootstrap_repo_url: https://github.com/YOUR-USER/respawn.git

A rebuilt VM gets a new SSH host key. If ssh complains, run: ssh-keygen -R ${ip}
SNIPPET
}

cmd_destroy() {
  need_multipass
  vm_exists || die "VM ${NAME} does not exist"
  multipass delete "${NAME}"
  multipass purge
  echo "VM ${NAME} destroyed."
}

cmd_ip() {
  need_multipass
  vm_exists || die "VM ${NAME} does not exist"
  vm_ip
}

main() {
  local action="${1:-}"
  [ -n "${action}" ] || {
    usage
    exit 1
  }
  shift || true
  while [ $# -gt 0 ]; do
    case "$1" in
      --name) NAME="${2:?--name needs a value}"; shift 2 ;;
      --cpus) CPUS="${2:?--cpus needs a value}"; shift 2 ;;
      --memory) MEMORY="${2:?--memory needs a value}"; shift 2 ;;
      --disk) DISK="${2:?--disk needs a value}"; shift 2 ;;
      --key) KEY_FILE="${2:?--key needs a value}"; shift 2 ;;
      -h | --help) usage; exit 0 ;;
      *) die "unknown option: $1" ;;
    esac
  done
  case "${action}" in
    up) cmd_up ;;
    destroy) cmd_destroy ;;
    ip) cmd_ip ;;
    -h | --help) usage ;;
    *) usage; exit 1 ;;
  esac
}

main "$@"
