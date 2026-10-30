#!/usr/bin/env bash
# Day-2 helper for the win-devvm VM.
#   ./vm.sh {start|stop|kill|status|wait|view|ip|ssh [cmd...]|push <local> <remote>|pull <remote> <local>|destroy}
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; source "$HERE/config.env"
# shellcheck source=/dev/null
source "$HERE/lib/$HYPERVISOR.sh"

# Per-VM known_hosts: a reprovisioned guest gets a new host key (and, on Parallels, maybe a new IP).
SSH_OPTS=(-i "$SSH_KEY" -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="$VM_DIR/known_hosts" -o LogLevel=ERROR)
dest() { read -r SSH_HOST SSH_PORT_ < <(hv_ssh_dest); }
guest_ssh() { dest; ssh "${SSH_OPTS[@]}" -p "$SSH_PORT_" "$ADMIN_USER@$SSH_HOST" "$@"; }
tools_state() {
  guest_ssh -o BatchMode=yes -o ConnectTimeout=3 \
    'if (Test-Path C:\setup-tools.done) {"tools: DONE"} elseif (Test-Path C:\setup-tools.failed) {"tools: FAILED " + (Get-Content C:\setup-tools.failed)} else {"tools: installing (see C:\setup-tools.log)"}' 2>/dev/null
}

case "${1:-status}" in
  start)   hv_start ;;
  stop)    hv_stop ;;
  kill)    hv_kill ;;
  view)    hv_view ;;
  ip)      read -r h _ < <(hv_ssh_dest); echo "$h" ;;
  ssh)     shift; dest; exec ssh "${SSH_OPTS[@]}" -p "$SSH_PORT_" "$ADMIN_USER@$SSH_HOST" "$@" ;;
  push)    [[ $# -eq 3 ]] || { echo "usage: vm.sh push <local> <remote>" >&2; exit 2; }
           dest; scp -q "${SSH_OPTS[@]}" -P "$SSH_PORT_" -r "$2" "$ADMIN_USER@$SSH_HOST:$3" ;;
  pull)    [[ $# -eq 3 ]] || { echo "usage: vm.sh pull <remote> <local>" >&2; exit 2; }
           dest; scp -q "${SSH_OPTS[@]}" -P "$SSH_PORT_" -r "$ADMIN_USER@$SSH_HOST:$2" "$3" ;;
  status)  hv_state; tools_state || echo "ssh: not reachable yet" ;;
  wait)    # block until guest tool setup finishes (exit 0 DONE, 1 FAILED); WAIT_TIMEOUT seconds (default 2h)
           end=$(( $(date +%s) + ${WAIT_TIMEOUT:-7200} ))
           while (( $(date +%s) < end )); do
             s="$(tools_state || true)"
             case "$s" in "tools: DONE"*) echo "$s"; exit 0 ;; "tools: FAILED"*) echo "$s"; exit 1 ;; esac
             sleep 30
           done; echo "timeout waiting for tool setup" >&2; exit 1 ;;
  destroy) read -rp "Delete VM $VM_NAME and $VM_DIR? [y/N] " a; [[ $a == y ]] || exit 1
           hv_destroy; rm -rf "$VM_DIR" ;;
  *) sed -n 3p "$0"; exit 2 ;;
esac
