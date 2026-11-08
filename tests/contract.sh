#!/usr/bin/env bash
# shellcheck disable=SC1090,SC2034  # backends are sourced by runtime path; stub vars are read by backends
# Contract test: every lib/<backend>.sh must define the 11 hv_* lifecycle functions.
# Plain bash (3.2 compatible); no bats. Each backend is sourced in a subshell with stub
# config, so nothing is executed beyond top-level assignments and function definitions.
# Exit status: 0 if all backends pass, 1 otherwise.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REQUIRED="hv_check hv_exists hv_destroy hv_create hv_start hv_stop hv_kill hv_state hv_view hv_ssh_dest hv_info"

rc=0
count=0
for lib in "$ROOT"/lib/*.sh; do
  [ -f "$lib" ] || continue
  name="$(basename "$lib" .sh)"
  # common.sh holds shared helpers, not a hypervisor backend
  [ "$name" = "common" ] && continue
  count=$((count + 1))

  # Stub config: only what backends reference at top level or may read while sourcing.
  result="$(
    HERE="$ROOT"
    VM_NAME=contract-test
    VM_DIR="${TMPDIR:-/tmp}/contract-test-nonexistent"
    VM_DISK_GB=1 VM_RAM_MB=1024 VM_VCPUS=1
    WIN_ARCH=arm64 WIN_ISO='' VIRTIO_ISO=''
    LIBVIRT_URI=qemu:///session SSH_PORT=2222 RDP_PORT=3389 ADMIN_USER=user
    PRL_VM_HOME=/nonexistent PRL_APP=/nonexistent
    if ! . "$lib" >/dev/null 2>&1; then
      echo "SOURCE_ERROR"
      exit 0
    fi
    missing=""
    for fn in $REQUIRED; do
      declare -F "$fn" >/dev/null 2>&1 || missing="$missing $fn"
    done
    echo "$missing"
  )"

  if [ "$result" = "SOURCE_ERROR" ]; then
    echo "FAIL  $name: failed to source $lib"
    rc=1
  elif [ -n "$result" ]; then
    echo "FAIL  $name: missing${result}"
    rc=1
  else
    echo "PASS  $name"
  fi
done

if [ "$count" -eq 0 ]; then
  echo "FAIL  no backends found in $ROOT/lib"
  exit 1
fi
exit $rc
