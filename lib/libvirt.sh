# shellcheck shell=bash
# libvirt/KVM backend (Linux, rootless qemu:///session). Sourced by provision.sh / vm.sh.
# Implements: hv_check hv_exists hv_destroy hv_create hv_start hv_stop hv_kill hv_state hv_view hv_ssh_dest hv_info
V() { virsh -c "$LIBVIRT_URI" "$@"; }

hv_check() {
  for f in "$WIN_ISO" "$VIRTIO_ISO"; do [[ -r "$f" ]] || { echo "missing: $f" >&2; exit 1; }; done
  for c in virt-install virsh xorriso swtpm qemu-img; do command -v "$c" >/dev/null || { echo "missing tool: $c" >&2; exit 1; }; done
  [[ -r /dev/kvm && -w /dev/kvm ]] || { echo "/dev/kvm not accessible" >&2; exit 1; }
}

hv_exists() { V dominfo "$VM_NAME" >/dev/null 2>&1; }

hv_destroy() {
  V destroy "$VM_NAME" 2>/dev/null || true
  V undefine "$VM_NAME" --nvram --tpm 2>/dev/null || V undefine "$VM_NAME" --nvram || true
}

# $1 = staged config dir (autounattend.xml, setup-tools.ps1, authorized_keys)
hv_create() {
  xorriso -as mkisofs -quiet -J -r -V WINCONFIG -o "$VM_DIR/config.iso" "$1"
  qemu-img create -f qcow2 -o preallocation=off "$VM_DIR/disk.qcow2" "${VM_DISK_GB}G" >/dev/null
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
}

hv_start() { V start "$VM_NAME"; }
hv_stop()  { V shutdown "$VM_NAME"; }
hv_kill()  { V destroy "$VM_NAME"; }
hv_state() { V domstate "$VM_NAME"; }
hv_view()  { exec virt-viewer -c "$LIBVIRT_URI" "$VM_NAME"; }
hv_ssh_dest() { echo "127.0.0.1 $SSH_PORT"; }   # "<host> <port>"

hv_info() {
  cat <<MSG
  screen   : ./vm.sh view          (virt-viewer) or VNC: $(V domdisplay "$VM_NAME" 2>/dev/null || echo see 'virsh domdisplay')
  ssh      : ./vm.sh ssh           (127.0.0.1:$SSH_PORT -> guest:22)
  rdp      : xfreerdp /v:127.0.0.1:$RDP_PORT /u:$ADMIN_USER
MSG
}
