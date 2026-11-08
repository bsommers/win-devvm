# shellcheck shell=bash
# Helpers shared by provision.sh, vm.sh and the backends (bash 3.2 compatible).

# Escape a value for use as a sed replacement with the | delimiter.
esc() { printf '%s' "$1" | sed 's/[&|\\]/\\&/g'; }

# Stable small integer (1..899) derived from a VM name; 0 for the historical default name,
# so the original win-devvm keeps its original MAC and ports.
vm_slot() {
  if [[ "$1" == win-devvm ]]; then echo 0; return; fi
  echo $(( $(printf '%s' "$1" | cksum | cut -d' ' -f1) % 899 + 1 ))
}

# Locally administered MAC for QEMU's user-mode NIC; default VM keeps 52:54:00:17:8c:66.
vm_mac() {
  local s; s="$(vm_slot "$1")"
  if (( s == 0 )); then echo 52:54:00:17:8c:66
  else printf '52:54:00:%02x:%02x:%02x' $((s % 256)) $((s / 256)) $(( $(printf '%s' "$1" | cksum | cut -d' ' -f1) % 256 )); fi
}
