# shellcheck shell=bash
# Parallels Desktop backend (macOS on Apple Silicon -> Windows 11 ARM64). Sourced by provision.sh / vm.sh.
# Implements: hv_check hv_exists hv_destroy hv_create hv_start hv_stop hv_kill hv_state hv_view hv_ssh_dest hv_info
#
# Works with Parallels Desktop *Standard*, whose prlctl refuses create/set/start/stop/exec/send-key-event.
# Only `prlctl list|unregister` are used, so:
#   - the VM bundle is written from parallels/config.pvs.tmpl; `open` registers and starts it;
#   - it is started with `open <bundle>.pvm`, stopped over SSH, hard-killed via its prl_vm_app process;
#   - Windows media is remastered with the no-prompt EFI boot image ("Press any key" cannot be answered),
#     with autounattend.xml, setup-tools.ps1 and Parallels' own unattended payload (virtio-net driver,
#     toolgate driver, Parallels Tools installer) copied from the local Parallels install.
PVM="$PRL_VM_HOME/$VM_NAME.pvm"
PRL_TOOLS="$PRL_APP/Contents/Resources/Tools"

hv_check() {
  [[ "$(uname -s)" == Darwin && "$(uname -m)" == arm64 ]] || { echo "parallels backend needs macOS on Apple Silicon" >&2; exit 1; }
  [[ "$WIN_ARCH" == arm64 ]] || { echo "parallels backend supports WIN_ARCH=arm64 only" >&2; exit 1; }
  [[ -n "$WIN_ISO" && -r "$WIN_ISO" ]] || { echo "missing Windows 11 ARM64 ISO (set WIN_ISO): ${WIN_ISO:-<none found>}" >&2; exit 1; }
  for c in prlctl prl_disk_tool hdiutil ditto uuidgen; do command -v "$c" >/dev/null || { echo "missing tool: $c" >&2; exit 1; }; done
  for f in igt_arm64.exe prl_tg/DrvInARM64.exe prl_tg/arm64 netkvm/arm64; do
    [[ -e "$PRL_TOOLS/$f" ]] || { echo "missing Parallels payload: $PRL_TOOLS/$f" >&2; exit 1; }; done
}

prl_info() { prlctl list -i "$VM_NAME" 2>/dev/null; }
hv_exists() { prl_info | grep -q '^ID:'; }
hv_uuid()   { prl_info | awk '/^ID:/ {print $2}'; }
hv_state()  { prl_info | awk '/^State:/ {print $2}'; }

hv_kill() {
  local u; u="$(hv_uuid)"; [[ -n "$u" ]] || return 0
  u="${u//\{/\\{}"; u="${u//\}/\\}}"   # braces are regex metacharacters for pkill
  pkill -KILL -f "prl_vm_app .*--uuid $u" || true
  for _ in $(seq 1 20); do [[ "$(hv_state)" == running ]] || return 0; sleep 1; done
}

hv_destroy() {
  hv_exists && { hv_kill; prlctl unregister "$VM_NAME" >/dev/null; }
  [[ "$PVM" == *.pvm && -d "$PVM" ]] && rm -rf "$PVM"
  return 0
}

rand_mac() { printf '001C42%02X%02X%02X' $((RANDOM % 256)) $((RANDOM % 256)) $((RANDOM % 256)); }

# $1 = staged config dir (autounattend.xml, setup-tools.ps1, authorized_keys)
hv_create() {
  local media="$VM_DIR/media" iso="$VM_DIR/install.iso" mnt
  [[ ! -e "$PVM" ]] || { echo "bundle already exists: $PVM (use --force)" >&2; exit 1; }

  echo "remastering $(basename "$WIN_ISO") -> $iso"
  rm -rf "$media"
  mnt="$(hdiutil attach -readonly -nobrowse "$WIN_ISO" 2>/dev/null | awk -F'\t' '/\/Volumes\// {print $NF}')"
  [[ -d "$mnt" ]] || { echo "could not mount $WIN_ISO" >&2; exit 1; }
  ditto "$mnt" "$media"; hdiutil detach "$mnt" -quiet || true
  chmod -R u+w "$media"
  cp "$1"/* "$media/"
  mkdir -p "$media/drivers" "$media/prl_tg"
  cp "$PRL_TOOLS"/netkvm/arm64/* "$media/drivers/"            # virtio-net, loaded in WinPE
  cp "$PRL_TOOLS/prl_tg/DrvInARM64.exe" "$media/prl_tg/"; cp -R "$PRL_TOOLS/prl_tg/arm64" "$media/prl_tg/"
  cp "$PRL_TOOLS/igt_arm64.exe" "$media/"                       # Parallels Tools installer
  rm -f "$iso"
  # UDF carries the >4 GB install.wim; efisys_noprompt.bin boots straight into Setup (EFI platform id 0xEF).
  hdiutil makehybrid -quiet -o "$iso" "$media" -udf -udf-version 1.02 -udf-volume-name WINDEVVM \
    -iso -joliet -default-volume-name WINDEVVM \
    -eltorito-boot "$media/efi/microsoft/boot/efisys_noprompt.bin" -no-emul-boot -eltorito-platform 0xEF
  rm -rf "$media"

  echo "creating $PVM"
  mkdir -p "$PVM"
  prl_disk_tool create --hdd "$PVM/harddisk.hdd" --size "${VM_DISK_GB}G" >/dev/null
  local uuid hdd_uuid
  uuid="{$(uuidgen | tr 'A-Z' 'a-z')}"; hdd_uuid="{$(uuidgen | tr 'A-Z' 'a-z')}"
  sed -e "s|@@UUID@@|$uuid|g" -e "s|@@HDD_UUID@@|$hdd_uuid|g" -e "s|@@VMNAME@@|$(esc "$VM_NAME")|g" \
      -e "s|@@DATE@@|$(date -u '+%Y-%m-%d %H:%M:%S')|g" -e "s|@@CPUS@@|$VM_VCPUS|g" -e "s|@@RAM_MB@@|$VM_RAM_MB|g" \
      -e "s|@@DISK_MB@@|$((VM_DISK_GB * 1024))|g" -e "s|@@ISO@@|$(esc "$iso")|g" \
      -e "s|@@MAC@@|$(rand_mac)|g" -e "s|@@HOST_MAC@@|$(rand_mac)|g" \
      "$HERE/parallels/config.pvs.tmpl" > "$PVM/config.pvs"
  # Let the GUI register *and* start it: opening an unregistered bundle auto-starts the VM, whereas
  # `prlctl register` first leaves it stopped (and a second open pops an "already registered" dialog).
  hv_start
}

hv_start() {
  open "$PVM"
  for _ in $(seq 1 60); do [[ "$(hv_state)" == running ]] && return 0; sleep 1; done
  echo "warning: $VM_NAME not running after 60s; check the Parallels window (./vm.sh view)" >&2
}
hv_stop()  { "$HERE/vm.sh" ssh 'shutdown /s /t 0'; }
hv_view()  { open "$PVM"; }

# Guest IP from Parallels' shared-network DHCP leases (works before Parallels Tools report it).
hv_ip() {
  local mac; mac="$(grep -m1 -o '<MAC>[0-9A-Fa-f]*</MAC>' "$PVM/config.pvs" | sed 's/<[^>]*>//g' | tr 'A-F' 'a-f')"
  awk -F'[=,"]' -v m="$mac" '$5 == m {print $3, $1}' /Library/Preferences/Parallels/parallels_dhcp_leases 2>/dev/null \
    | sort -rn | awk 'NR == 1 {print $2}'
}
hv_ssh_dest() {
  local ip; ip="$(hv_ip)"
  [[ -n "$ip" ]] || { echo "no DHCP lease for $VM_NAME yet" >&2; return 1; }
  echo "$ip 22"
}

hv_info() {
  cat <<MSG
  screen   : ./vm.sh view          (Parallels window)
  ssh      : ./vm.sh ssh           (guest IP on the Parallels shared network: ./vm.sh ip)
  rdp      : Microsoft Remote Desktop -> \$(./vm.sh ip), user $ADMIN_USER
MSG
}
