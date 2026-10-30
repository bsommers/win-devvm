#!/usr/bin/env bash
# Provision and boot an unattended Windows 11 dev VM on this Linux host (rootless libvirt/KVM).
# Usage: ./provision.sh            create + start install (≈20-40 min, then tool setup ≈20-30 min)
#        ./provision.sh --force    destroy any existing VM of the same name first
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/config.env"
V() { virsh -c "$LIBVIRT_URI" "$@"; }
FORCE=0; [[ "${1:-}" == "--force" ]] && FORCE=1

for f in "$WIN_ISO" "$VIRTIO_ISO"; do [[ -r "$f" ]] || { echo "missing: $f" >&2; exit 1; }; done
for c in virt-install virsh xorriso swtpm; do command -v "$c" >/dev/null || { echo "missing tool: $c" >&2; exit 1; }; done
[[ -r /dev/kvm && -w /dev/kvm ]] || { echo "/dev/kvm not accessible" >&2; exit 1; }

if V dominfo "$VM_NAME" >/dev/null 2>&1; then
  if (( FORCE )); then
    V destroy "$VM_NAME" 2>/dev/null || true
    V undefine "$VM_NAME" --nvram --tpm 2>/dev/null || V undefine "$VM_NAME" --nvram || true
    rm -rf "$VM_DIR"
  else echo "VM $VM_NAME exists (use --force to recreate)" >&2; exit 1; fi
fi

mkdir -p "$VM_DIR"; chmod 700 "$VM_DIR"

# --- config ISO: autounattend.xml + setup-tools.ps1 + host SSH pubkey ---------
STAGE="$(mktemp -d)"; trap 'rm -rf "$STAGE"' EXIT
esc() { printf '%s' "$1" | sed 's/[&|\\]/\\&/g'; }
sed -e "s|@@EDITION@@|$(esc "$WIN_EDITION")|" -e "s|@@VMNAME@@|$(esc "${VM_NAME^^}" | cut -c1-15)|" \
    -e "s|@@USER@@|$(esc "$ADMIN_USER")|g" -e "s|@@PASS@@|$(esc "$ADMIN_PASS")|g" \
    "$HERE/autounattend.xml.tmpl" > "$STAGE/autounattend.xml"
cp "$HERE/setup-tools.ps1" "$STAGE/"
[[ -f "$SSH_KEY" ]] || ssh-keygen -q -t ed25519 -N "" -C "$VM_NAME" -f "$SSH_KEY"
cp "$SSH_KEY.pub" "$STAGE/authorized_keys"
xorriso -as mkisofs -quiet -J -r -V WINCONFIG -o "$VM_DIR/config.iso" "$STAGE"

# --- disk ---------------------------------------------------------------------
qemu-img create -f qcow2 -o preallocation=off "$VM_DIR/disk.qcow2" "${VM_DISK_GB}G" >/dev/null

# --- define + start -----------------------------------------------------------
/usr/bin/python3 /usr/bin/virt-install --connect "$LIBVIRT_URI" \
  --name "$VM_NAME" --osinfo win11 \
  --memory "$VM_RAM_MB" --vcpus "$VM_VCPUS" --cpu host-passthrough \
  --boot uefi \
  --tpm backend.type=emulator,backend.version=2.0,model=tpm-crb \
  --disk path="$VM_DIR/disk.qcow2",bus=virtio,cache=none,discard=unmap,boot.order=1 \
  --disk path="$WIN_ISO",device=cdrom,bus=sata,boot.order=2 \
  --disk path="$VIRTIO_ISO",device=cdrom,bus=sata \
  --disk path="$VM_DIR/config.iso",device=cdrom,bus=sata \
  --network none \
  --qemu-commandline="-netdev user,id=n0,hostfwd=tcp:127.0.0.1:$SSH_PORT-:22,hostfwd=tcp:127.0.0.1:$RDP_PORT-:3389 -device virtio-net-pci,netdev=n0,mac=52:54:00:17:8c:66,bus=pcie.0,addr=0x1e" \
  --graphics vnc,listen=127.0.0.1 --video virtio \
  --channel unix,target.type=virtio,target.name=org.qemu.guest_agent.0 \
  --noautoconsole --wait 0

# Windows' "Press any key to boot from CD" prompt times out; tap a key for ~20s (stop before Setup UI starts) so unattended boot works.
for _ in $(seq 1 20); do V send-key "$VM_NAME" KEY_SPACE >/dev/null 2>&1 || true; sleep 1; done

cat <<MSG

VM '$VM_NAME' started. Windows installs unattended, reboots a few times, then runs setup-tools.ps1.
  progress : ./vm.sh status        (done when C:\\setup-tools.done exists)
  screen   : ./vm.sh view          (virt-viewer) or VNC: $(V domdisplay "$VM_NAME" 2>/dev/null || echo see 'virsh domdisplay')
  ssh      : ssh -i $SSH_KEY -p $SSH_PORT $ADMIN_USER@127.0.0.1
  rdp      : xfreerdp /v:127.0.0.1:$RDP_PORT /u:$ADMIN_USER
MSG
