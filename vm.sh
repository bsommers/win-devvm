#!/usr/bin/env bash
# Day-2 helper for the win-devvm VM.   ./vm.sh {start|stop|kill|status|view|ssh|destroy}
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; source "$HERE/config.env"
V() { virsh -c "$LIBVIRT_URI" "$@"; }
case "${1:-status}" in
  start)   V start "$VM_NAME" ;;
  stop)    V shutdown "$VM_NAME" ;;
  kill)    V destroy "$VM_NAME" ;;
  view)    exec virt-viewer -c "$LIBVIRT_URI" "$VM_NAME" ;;
  ssh)     shift; exec ssh -i "$SSH_KEY" -p "$SSH_PORT" -o StrictHostKeyChecking=accept-new "$ADMIN_USER@127.0.0.1" "$@" ;;
  status)  V domstate "$VM_NAME"
           if ssh -i "$SSH_KEY" -p "$SSH_PORT" -o BatchMode=yes -o ConnectTimeout=3 -o StrictHostKeyChecking=accept-new "$ADMIN_USER@127.0.0.1" \
                'if (Test-Path C:\setup-tools.done) {"tools: DONE"} else {"tools: installing (see C:\setup-tools.log)"}' 2>/dev/null; then :; else echo "ssh: not reachable yet"; fi ;;
  destroy) read -rp "Delete VM $VM_NAME and $VM_DIR? [y/N] " a; [[ $a == y ]] || exit 1
           V destroy "$VM_NAME" 2>/dev/null || true; V undefine "$VM_NAME" --nvram --tpm || V undefine "$VM_NAME" --nvram; rm -rf "$VM_DIR" ;;
  *) sed -n 2p "$0"; exit 2 ;;
esac
