#!/usr/bin/env bash
# Provision and boot an unattended dev VM (guest per GUEST, default windows11): libvirt/KVM on Linux, Parallels Desktop on macOS (ARM64).
# Usage: ./provision.sh            create + start install (≈20-40 min, then tool setup ≈20-30 min)
#        ./provision.sh --force    destroy any existing VM of the same name first
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/config.env"
# shellcheck source=/dev/null
source "$HERE/lib/$HYPERVISOR.sh"
FORCE=0; [[ "${1:-}" == "--force" ]] && FORCE=1

hv_check
command -v ssh-keygen >/dev/null || { echo "missing tool: ssh-keygen" >&2; exit 1; }

if hv_exists; then
  if (( FORCE )); then hv_destroy; rm -rf "$VM_DIR"
  else echo "VM $VM_NAME exists (use --force to recreate)" >&2; exit 1; fi
fi

mkdir -p "$VM_DIR"; chmod 700 "$VM_DIR"

# --- config payload: guest answer file/provisioner + host SSH pubkey ---------
STAGE="$(mktemp -d)"; trap 'rm -rf "$STAGE"' EXIT
guest_stage "$STAGE"   # guests/$GUEST/guest.env: render answer file + guest provisioner
[[ -f "$SSH_KEY" ]] || ssh-keygen -q -t ed25519 -N "" -C "$VM_NAME" -f "$SSH_KEY"
cp "$SSH_KEY.pub" "$STAGE/authorized_keys"

# --- define + start (backend) -------------------------------------------------
hv_create "$STAGE"

cat <<MSG

VM '$VM_NAME' started ($HYPERVISOR, $ARCH). $GUEST_BANNER
  progress : ./vm.sh status        $GUEST_PROGRESS_HINT
$(hv_info)
MSG
