#!/usr/bin/env bash
# FreeBSD / OpenBSD dev VM on plain QEMU (HVF on macOS, KVM on Linux), guest arch = host arch.
#   ./bsd-vm.sh <freebsd|openbsd> {provision [--force]|start|stop|kill|status|ip|ssh [cmd...]|push <local> <remote>|pull <remote> <local>|console|destroy}
#
# FreeBSD: official BASIC-CLOUDINIT image, seeded with a cloud-init (nuageinit) config drive.
# OpenBSD: official installer image, answered over the serial console by lib/openbsd-install.py.
# Both end up with user $ADMIN_USER (key-only SSH, passwordless sudo/doas) on 127.0.0.1:$SSH_PORT.
#
# Environment (defaults in parentheses):
#   FREEBSD_VERSION (15.1)  OPENBSD_VERSION (8.0)  VM_RAM_MB (4096)  VM_VCPUS (4)  VM_DISK_GB (40)
#   ADMIN_USER (dev)  SSH_KEY (~/.ssh/id_windevvm)  SSH_PORT (2230 freebsd, 2231 openbsd)
#   VM_NAME (<guest>-devvm)  VM_DIR (~/vms/$VM_NAME)  IMAGE_CACHE (~/.cache/win-devvm)
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

GUEST="${1:-}"; shift || true
case "$GUEST" in
  freebsd) SSH_PORT="${SSH_PORT:-2230}" ;;
  openbsd) SSH_PORT="${SSH_PORT:-2231}" ;;
  *) sed -n '2,4p' "$0"; exit 2 ;;
esac
FREEBSD_VERSION="${FREEBSD_VERSION:-15.1}"
OPENBSD_VERSION="${OPENBSD_VERSION:-8.0}"
VM_NAME="${VM_NAME:-$GUEST-devvm}"
VM_DIR="${VM_DIR:-$HOME/vms/$VM_NAME}"
VM_RAM_MB="${VM_RAM_MB:-4096}"
VM_VCPUS="${VM_VCPUS:-4}"
VM_DISK_GB="${VM_DISK_GB:-40}"
ADMIN_USER="${ADMIN_USER:-dev}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_windevvm}"
IMAGE_CACHE="${IMAGE_CACHE:-$HOME/.cache/win-devvm}"
PIDFILE="$VM_DIR/qemu.pid"; SERIAL="$VM_DIR/serial.sock"; MONITOR="$VM_DIR/monitor.sock"

die() { echo "bsd-vm: $*" >&2; exit 1; }
need() { for c in "$@"; do command -v "$c" >/dev/null || die "missing tool: $c"; done; }

# --- host: accelerator, QEMU binary, guest arch names --------------------------
case "$(uname -s)" in Darwin) ACCEL=hvf ;; Linux) ACCEL=kvm ;; *) die "unsupported host OS" ;; esac
case "$(uname -m)" in
  arm64|aarch64) QEMU=qemu-system-aarch64; FBSD_ARCH=aarch64; FBSD_NAME=arm64-aarch64; OBSD_ARCH=arm64 ;;
  x86_64|amd64)  QEMU=qemu-system-x86_64;  FBSD_ARCH=amd64;   FBSD_NAME=amd64;         OBSD_ARCH=amd64 ;;
  *) die "unsupported host CPU" ;;
esac

sha256_of() { if command -v sha256sum >/dev/null; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi; }

# fetch <url> <file> <expected sha256>: download once into the cache, always verify
fetch() {
  mkdir -p "$IMAGE_CACHE"
  [[ -f "$2" ]] || { echo "downloading $1"; curl -fL --progress-bar -o "$2.part" "$1" && mv "$2.part" "$2"; }
  [[ "$(sha256_of "$2")" == "$3" ]] || die "checksum mismatch for $2 (delete it to download again)"
}

# --- QEMU ----------------------------------------------------------------------
running() { [[ -f "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; }

# qemu_start [extra qemu args...]
qemu_start() {
  running && die "$VM_NAME is already running"
  rm -f "$SERIAL" "$MONITOR"
  local args=(-name "$VM_NAME" -accel "$ACCEL" -cpu host -smp "$VM_VCPUS" -m "$VM_RAM_MB"
    -drive "if=virtio,format=qcow2,file=$VM_DIR/disk.qcow2"
    -netdev "user,id=n0,hostfwd=tcp:127.0.0.1:$SSH_PORT-:22" -device virtio-net-pci,netdev=n0
    -device virtio-rng-pci -display none
    -serial "unix:$SERIAL,server=on,wait=off" -monitor "unix:$MONITOR,server=on,wait=off"
    -daemonize -pidfile "$PIDFILE")
  if [[ "$QEMU" == qemu-system-aarch64 ]]; then
    local fw; fw="$(firmware)"
    [[ -f "$VM_DIR/vars.fd" ]] || dd if=/dev/zero of="$VM_DIR/vars.fd" bs=1048576 count=64 2>/dev/null
    args=(-machine virt "${args[@]}"
      -drive "if=pflash,format=raw,readonly=on,file=$fw" -drive "if=pflash,format=raw,file=$VM_DIR/vars.fd")
  else
    args=(-machine q35 "${args[@]}")
  fi
  "$QEMU" "${args[@]}" "$@"
}

firmware() {   # 64 MB UEFI image for the aarch64 "virt" machine
  local f
  for f in "$(dirname "$(dirname "$(command -v "$QEMU")")")/share/qemu/edk2-aarch64-code.fd" \
           /usr/share/qemu/edk2-aarch64-code.fd /usr/share/AAVMF/AAVMF_CODE.fd /usr/share/edk2/aarch64/QEMU_EFI-pflash.raw; do
    [[ -f "$f" ]] && { echo "$f"; return; }
  done
  die "no aarch64 UEFI firmware found (install qemu-efi-aarch64 / edk2)"
}

monitor() { python3 "$HERE/lib/qemu-sock.py" "$MONITOR" "$1"; }

# --- guest access ----------------------------------------------------------------
SSH_OPTS=(-i "$SSH_KEY" -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="$VM_DIR/known_hosts" -o LogLevel=ERROR)
guest_ssh() { ssh "${SSH_OPTS[@]}" -p "$SSH_PORT" "$ADMIN_USER@127.0.0.1" "$@"; }
wait_ssh() {
  local end=$(( $(date +%s) + ${1:-300} ))
  while (( $(date +%s) < end )); do
    guest_ssh -o BatchMode=yes -o ConnectTimeout=3 true 2>/dev/null && return 0
    running || die "$VM_NAME stopped while waiting for SSH (see $VM_DIR/serial.log)"
    sleep 3
  done
  die "no SSH on 127.0.0.1:$SSH_PORT after ${1:-300}s"
}

# --- provisioning ----------------------------------------------------------------
make_iso() {   # make_iso <dir> <out.iso> <volume label>
  if command -v xorriso >/dev/null; then xorriso -as mkisofs -quiet -J -r -V "$3" -o "$2" "$1"
  elif command -v hdiutil >/dev/null; then hdiutil makehybrid -quiet -iso -joliet -default-volume-name "$3" -o "$2" "$1"
  else die "need xorriso or hdiutil to build the config drive"; fi
}

provision_freebsd() {
  need xz
  local base="https://download.freebsd.org/releases/VM-IMAGES/$FREEBSD_VERSION-RELEASE/$FBSD_ARCH/Latest"
  local img="FreeBSD-$FREEBSD_VERSION-RELEASE-$FBSD_NAME-BASIC-CLOUDINIT-ufs.qcow2.xz" sum
  sum="$(curl -fsSL "$base/CHECKSUM.SHA256" | awk -v f="($img)" '$2==f {print $4}')"
  [[ -n "$sum" ]] || die "no checksum published for $img (is FREEBSD_VERSION=$FREEBSD_VERSION a current release?)"
  fetch "$base/$img" "$IMAGE_CACHE/$img" "$sum"
  xz -dc "$IMAGE_CACHE/$img" > "$VM_DIR/disk.qcow2"
  qemu-img resize -q "$VM_DIR/disk.qcow2" "${VM_DISK_GB}G"

  local seed; seed="$(mktemp -d)"
  printf 'instance-id: %s\nlocal-hostname: %s\n' "$VM_NAME-$(date +%s)" "$VM_NAME" > "$seed/meta-data"
  cat > "$seed/user-data" <<EOF
#cloud-config
users:
  - name: $ADMIN_USER
    groups: wheel
    shell: /bin/sh
    sudo: ALL=(ALL) NOPASSWD:ALL
    ssh_authorized_keys:
      - $(cat "$SSH_KEY.pub")
packages:
  - sudo
  - bash
  - git
EOF
  make_iso "$seed" "$VM_DIR/seed.iso" cidata; rm -rf "$seed"
  qemu_start -drive "if=virtio,format=raw,readonly=on,file=$VM_DIR/seed.iso"
  wait_ssh 600
}

provision_openbsd() {
  local v="${OPENBSD_VERSION/./}" base="https://cdn.openbsd.org/pub/OpenBSD/$OPENBSD_VERSION/$OBSD_ARCH"
  local img="install$v.img" sum
  sum="$(curl -fsSL "$base/SHA256" | awk -v f="($img)" '$2==f {print $4}')"
  [[ -n "$sum" ]] || die "no checksum published for $img (is OPENBSD_VERSION=$OPENBSD_VERSION a current release?)"
  fetch "$base/$img" "$IMAGE_CACHE/openbsd-$OPENBSD_VERSION-$OBSD_ARCH-$img" "$sum"
  qemu-img create -q -f qcow2 "$VM_DIR/disk.qcow2" "${VM_DISK_GB}G"
  # Throwaway installer password (root and $ADMIN_USER); SSH is key-only afterwards.
  ( umask 077; python3 -c 'import secrets; print(secrets.token_hex(12))' > "$VM_DIR/password" )
  qemu_start -drive "if=virtio,format=raw,readonly=on,file=$IMAGE_CACHE/openbsd-$OPENBSD_VERSION-$OBSD_ARCH-$img"
  python3 "$HERE/lib/openbsd-install.py" --socket "$SERIAL" --log "$VM_DIR/install.log" \
      --hostname "$VM_NAME" --user "$ADMIN_USER" --password-file "$VM_DIR/password" \
      --pubkey "$SSH_KEY.pub" --arch "$OBSD_ARCH" --sets "$OPENBSD_VERSION/$OBSD_ARCH" \
    || die "OpenBSD install failed (see $VM_DIR/install.log)"
  # The installer halts; restart without the install image.
  local i; for i in $(seq 1 30); do running || break; sleep 2; done
  running && { kill "$(cat "$PIDFILE")"; sleep 2; }
  qemu_start
  wait_ssh 300
}

cmd="${1:-status}"; shift || true
case "$cmd" in
  provision)
    need "$QEMU" qemu-img curl python3 ssh-keygen
    if [[ -e "$VM_DIR/disk.qcow2" ]]; then
      [[ "${1:-}" == --force ]] || die "$VM_NAME exists in $VM_DIR (use: provision --force)"
      running && kill "$(cat "$PIDFILE")" && sleep 2
      rm -rf "$VM_DIR"
    fi
    mkdir -p "$VM_DIR"; chmod 700 "$VM_DIR"
    [[ -f "$SSH_KEY" ]] || ssh-keygen -q -t ed25519 -N "" -C "$VM_NAME" -f "$SSH_KEY"
    "provision_$GUEST"
    echo "$VM_NAME ready: ./bsd-vm.sh $GUEST ssh   (127.0.0.1:$SSH_PORT, user $ADMIN_USER)"
    guest_ssh 'uname -srm' ;;
  start)   [[ -e "$VM_DIR/disk.qcow2" ]] || die "not provisioned: ./bsd-vm.sh $GUEST provision"
           qemu_start; wait_ssh 300; echo running ;;
  stop)    running || { echo stopped; exit 0; }
           if [[ "$GUEST" == openbsd ]]; then guest_ssh 'doas halt -p' || true; else guest_ssh 'sudo shutdown -p now' || true; fi
           for _ in $(seq 1 30); do running || break; sleep 2; done
           running && die "still running after 60 s (use: kill)"; echo stopped ;;
  kill)    running && kill "$(cat "$PIDFILE")"; echo stopped ;;
  status)  if running; then echo running; guest_ssh -o BatchMode=yes -o ConnectTimeout=3 'uname -srm' 2>/dev/null || echo "ssh: not reachable yet"
           elif [[ -e "$VM_DIR/disk.qcow2" ]]; then echo stopped; else echo "not provisioned"; fi ;;
  ip)      echo "127.0.0.1 $SSH_PORT" ;;
  ssh)     exec ssh "${SSH_OPTS[@]}" -p "$SSH_PORT" "$ADMIN_USER@127.0.0.1" "$@" ;;
  push)    [[ $# -eq 2 ]] || die "usage: bsd-vm.sh $GUEST push <local> <remote>"
           scp -q "${SSH_OPTS[@]}" -P "$SSH_PORT" -r "$1" "$ADMIN_USER@127.0.0.1:$2" ;;
  pull)    [[ $# -eq 2 ]] || die "usage: bsd-vm.sh $GUEST pull <remote> <local>"
           scp -q "${SSH_OPTS[@]}" -P "$SSH_PORT" -r "$ADMIN_USER@127.0.0.1:$1" "$2" ;;
  console) running || die "not running"; echo "serial console (Ctrl-C to leave)"; exec python3 "$HERE/lib/qemu-sock.py" "$SERIAL" ;;
  destroy) read -rp "Delete VM $VM_NAME and $VM_DIR? [y/N] " a; [[ $a == y ]] || exit 1
           running && kill "$(cat "$PIDFILE")"; rm -rf "$VM_DIR" ;;
  *) sed -n '2,4p' "$0"; exit 2 ;;
esac
