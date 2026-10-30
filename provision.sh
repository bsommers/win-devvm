#!/usr/bin/env bash
# Provision and boot an unattended Windows 11 dev VM: libvirt/KVM on Linux, Parallels Desktop on macOS (ARM64).
# Usage: ./provision.sh            create + start install (≈20-40 min, then tool setup ≈20-30 min)
#        ./provision.sh --force    destroy any existing VM of the same name first
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/config.env"
# shellcheck source=/dev/null
source "$HERE/lib/$HYPERVISOR.sh"
FORCE=0; [[ "${1:-}" == "--force" ]] && FORCE=1
esc() { printf '%s' "$1" | sed 's/[&|\\]/\\&/g'; }

hv_check
command -v ssh-keygen >/dev/null || { echo "missing tool: ssh-keygen" >&2; exit 1; }

if hv_exists; then
  if (( FORCE )); then hv_destroy; rm -rf "$VM_DIR"
  else echo "VM $VM_NAME exists (use --force to recreate)" >&2; exit 1; fi
fi

mkdir -p "$VM_DIR"; chmod 700 "$VM_DIR"

# --- config payload: autounattend.xml + setup-tools.ps1 + host SSH pubkey -----
STAGE="$(mktemp -d)"; trap 'rm -rf "$STAGE"' EXIT
# Parallels: reboot after the toolgate driver install in specialize (mirrors Parallels' own answer file).
TG_REBOOT=Never; [[ "$HYPERVISOR" == parallels ]] && TG_REBOOT=Always
COMPUTER="$(printf '%s' "$VM_NAME" | tr 'a-z' 'A-Z' | cut -c1-15)"
sed -e "s|@@EDITION@@|$(esc "$WIN_EDITION")|" -e "s|@@VMNAME@@|$(esc "$COMPUTER")|" \
    -e "s|@@USER@@|$(esc "$ADMIN_USER")|g" -e "s|@@PASS@@|$(esc "$ADMIN_PASS")|g" \
    -e "s|@@ARCH@@|$WIN_ARCH|g" -e "s|@@TG_REBOOT@@|$TG_REBOOT|g" \
    "$HERE/autounattend.xml.tmpl" > "$STAGE/autounattend.xml"
cp "$HERE/setup-tools.ps1" "$STAGE/"
[[ -f "$SSH_KEY" ]] || ssh-keygen -q -t ed25519 -N "" -C "$VM_NAME" -f "$SSH_KEY"
cp "$SSH_KEY.pub" "$STAGE/authorized_keys"

# --- define + start (backend) -------------------------------------------------
hv_create "$STAGE"

cat <<MSG

VM '$VM_NAME' started ($HYPERVISOR, $WIN_ARCH). Windows installs unattended, reboots a few times, then runs setup-tools.ps1.
  progress : ./vm.sh status        (done when C:\\setup-tools.done exists)
$(hv_info)
MSG
