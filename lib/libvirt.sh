# shellcheck shell=bash
# libvirt/KVM backend (Linux, rootless qemu:///session). Sourced by provision.sh / vm.sh.
# Implements: hv_check hv_exists hv_destroy hv_create hv_start hv_stop hv_kill hv_state hv_view hv_ssh_dest hv_info
V() { virsh -c "$LIBVIRT_URI" "$@"; }

hv_check() {
  for f in "$IMAGE_ISO" "$VIRTIO_ISO"; do [[ -r "$f" ]] || { echo "missing: $f" >&2; exit 1; }; done
  for c in virt-install virsh xorriso swtpm qemu-img; do command -v "$c" >/dev/null || { echo "missing tool: $c" >&2; exit 1; }; done
  [[ -r /dev/kvm && -w /dev/kvm ]] || { echo "/dev/kvm not accessible" >&2; exit 1; }
}

hv_exists() { V dominfo "$VM_NAME" >/dev/null 2>&1; }

hv_destroy() {
  V destroy "$VM_NAME" 2>/dev/null || true
  V undefine "$VM_NAME" --nvram --tpm 2>/dev/null || V undefine "$VM_NAME" --nvram || true
}

# $1 = staged config dir (guest_stage output + authorized_keys)
hv_create() {
  xorriso -as mkisofs -quiet -J -r -V "$CONFIG_LABEL" -o "$VM_DIR/config.iso" "$1"
  qemu-img create -f qcow2 -o preallocation=off "$VM_DIR/disk.qcow2" "${VM_DISK_GB}G" >/dev/null
  local vi tpm=()
  vi=("$(command -v virt-install)")
  [[ -x /usr/bin/python3 ]] && vi=(/usr/bin/python3 "${vi[0]}")   # system python (gi bindings), as before
  (( NEED_TPM )) && tpm=(--tpm 'backend.type=emulator,backend.version=2.0,model=tpm-crb')
  "${vi[@]}" --connect "$LIBVIRT_URI" \
    --name "$VM_NAME" --osinfo "$OS_VARIANT" \
    --memory "$VM_RAM_MB" --vcpus "$VM_VCPUS" --cpu host-passthrough \
    --boot uefi \
    ${tpm[@]+"${tpm[@]}"} \
    --disk path="$VM_DIR/disk.qcow2",bus=virtio,cache=none,discard=unmap,boot.order=1 \
    --disk path="$IMAGE_ISO",device=cdrom,bus=sata,boot.order=2 \
    --disk path="$VIRTIO_ISO",device=cdrom,bus=sata \
    --disk path="$VM_DIR/config.iso",device=cdrom,bus=sata \
    --network none \
    --qemu-commandline="-netdev user,id=n0,hostfwd=tcp:127.0.0.1:$SSH_PORT-:22,hostfwd=tcp:127.0.0.1:$RDP_PORT-:3389 -device virtio-net-pci,netdev=n0,mac=$VM_MAC,bus=pcie.0,addr=0x1e" \
    --graphics vnc,listen=127.0.0.1 --video virtio \
    --channel unix,target.type=virtio,target.name=org.qemu.guest_agent.0 \
    --noautoconsole --wait 0
  # Some installers (Windows: "Press any key to boot from CD") time out; tap BOOT_KEYS for BOOT_KEYS_SECS so unattended boot works.
  if [[ -n "$BOOT_KEYS" ]]; then
    # shellcheck disable=SC2086
    for _ in $(seq 1 "$BOOT_KEYS_SECS"); do V send-key "$VM_NAME" $BOOT_KEYS >/dev/null 2>&1 || true; sleep 1; done
  fi
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
  rdp      : xfreerdp /v:127.0.0.1:$RDP_PORT /u:$SSH_USER
MSG
}
