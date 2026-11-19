#!/usr/bin/env bash
# Build a local OpenBSD amd64 qcow2 by driving the OFFICIAL installer (miniroot) over the serial console.
# OpenBSD ships no cloud image. Steps: fetch SHA256 + SHA256.sig, verify the signature with the pinned release key
# (pure-python ed25519 signify check), verify miniroot's SHA256, boot it under qemu/KVM, answer the installer via
# build-image.py, reboot, then (as root on the serial console) harden sshd, set doas, pkg_add the build tools.
# Output: $OPENBSD_OUT (default ~/.cache/win-devvm/images/openbsd-$OPENBSD_REL-amd64.qcow2) + .sha256 next to it.
# Needs: qemu-system-x86_64, /dev/kvm, curl, python3 with `cryptography`. Run from anywhere.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPENBSD_REL="${OPENBSD_REL:-8.0}"
SHORT="${OPENBSD_REL/./}"
MIRROR="${OPENBSD_MIRROR:-https://cdn.openbsd.org/pub/OpenBSD}"
CACHE="${IMAGE_CACHE:-$HOME/.cache/win-devvm/images}"
WORK="${OPENBSD_WORK:-/datanapps/vms/openbsd-build}"      # never /tmp (tmpfs)
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_windevvm}"
BUILD_USER="${BUILD_USER:-bill}"
DISK_GB="${GUEST_DISK_GB:-40}"
OUT="${OPENBSD_OUT:-$CACHE/openbsd-$OPENBSD_REL-amd64.qcow2}"
PUBKEY="$HERE/openbsd-$SHORT-base.pub"                    # pinned signify key (from $MIRROR/$OPENBSD_REL/)
PY="${PYTHON:-python3}"
[[ -r "$PUBKEY" ]] || { echo "no pinned signify key $PUBKEY (fetch $MIRROR/$OPENBSD_REL/openbsd-$SHORT-base.pub, check it against the previous release's /etc/signify)" >&2; exit 1; }
[[ -r "$SSH_KEY.pub" ]] || { echo "missing $SSH_KEY.pub" >&2; exit 1; }
for t in qemu-system-x86_64 qemu-img curl "$PY"; do command -v "$t" >/dev/null || { echo "missing tool: $t" >&2; exit 1; }; done
[[ -w /dev/kvm ]] || { echo "/dev/kvm not writable" >&2; exit 1; }
mkdir -p "$WORK" "$CACHE"

base="$MIRROR/$OPENBSD_REL/amd64"
for f in SHA256 SHA256.sig miniroot$SHORT.img; do
  [[ -s "$WORK/$f" ]] || curl -fL --retry 3 -o "$WORK/$f" "$base/$f"
done
"$PY" "$HERE/build-image.py" verify "$PUBKEY" "$WORK/SHA256" "$WORK/SHA256.sig" "$WORK/miniroot$SHORT.img" "miniroot$SHORT.img"

rm -f "$WORK/disk.qcow2"
qemu-img create -q -f qcow2 "$WORK/disk.qcow2" "${DISK_GB}G"
"$PY" "$HERE/build-image.py" install \
  --work "$WORK" --miniroot "$WORK/miniroot$SHORT.img" --disk "$WORK/disk.qcow2" \
  --rel "$OPENBSD_REL" --mirror-host "${MIRROR#*://}" --user "$BUILD_USER" --pubkey "$SSH_KEY.pub" \
  --packages "${OPENBSD_PKGS:-git rust qemu}"

qemu-img convert -O qcow2 -c "$WORK/disk.qcow2" "$OUT.part" && mv "$OUT.part" "$OUT"
( cd "$(dirname "$OUT")" && sha256sum "$(basename "$OUT")" > "$(basename "$OUT").sha256" )
echo "built $OUT"; cat "$OUT.sha256"
