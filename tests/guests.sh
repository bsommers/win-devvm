#!/usr/bin/env bash
# shellcheck disable=SC1090,SC2034
# Guest test: every guests/*/guest.env defines the required fields and guest_stage().
# Each guest.env is sourced in a subshell with stub config. Plain bash (3.2 compatible).

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REQUIRED="OS_VARIANT IMAGE_KIND SSH_USER GUEST_STOP_CMD GUEST_READY_CMD"
rc=0
count=0
for env in "$ROOT"/guests/*/guest.env; do
  [ -f "$env" ] || continue
  name="$(basename "$(dirname "$env")")"
  count=$((count + 1))
  result="$(
    HERE="$ROOT" HYPERVISOR=libvirt ADMIN_USER=dev VM_NAME=guest-test
    if ! . "$env" >/dev/null 2>&1; then echo "SOURCE_ERROR"; exit 0; fi
    missing=""
    for v in $REQUIRED; do
      [ -n "${!v:-}" ] || missing="$missing $v"
    done
    declare -F guest_stage >/dev/null 2>&1 || missing="$missing guest_stage"
    case "${IMAGE_KIND:-}" in
      iso) ;;
      cloudimg) for v in IMAGE_URL IMAGE_FILE IMAGE_SUMS; do [ -n "${!v:-}" ] || missing="$missing $v"; done ;;
      *) missing="$missing IMAGE_KIND(iso|cloudimg)" ;;
    esac
    echo "$missing"
  )"
  if [ "$result" = "SOURCE_ERROR" ]; then
    echo "FAIL  $name: failed to source $env"; rc=1
  elif [ -n "$result" ]; then
    echo "FAIL  $name: missing${result}"; rc=1
  else
    echo "PASS  $name"
  fi
done
if [ "$count" -eq 0 ]; then echo "FAIL  no guests found"; exit 1; fi
exit $rc
