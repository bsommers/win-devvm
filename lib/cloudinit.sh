#!/usr/bin/env bash
# lib/cloudinit.sh - NoCloud seed generation. Sourced; no top-level side effects.

# ci_write_user_data <dir> <user> <pubkey-file> [<extra-runcmd-file>]
ci_write_user_data() {
  local dir="$1" user="$2" keyf="$3" extra="${4:-}" key line
  [ -f "$keyf" ] || { echo "pubkey file missing: $keyf" >&2; return 1; }
  if [ -n "$extra" ] && [ ! -f "$extra" ]; then
    echo "runcmd file missing: $extra" >&2; return 1
  fi
  mkdir -p "$dir" || return 1
  key="$(head -n1 "$keyf")"
  {
    echo "#cloud-config"
    echo "users:"
    echo "  - name: $user"
    echo "    sudo: ALL=(ALL) NOPASSWD:ALL"
    echo "    shell: /bin/bash"
    echo "    lock_passwd: true"
    echo "    ssh_authorized_keys:"
    echo "      - $key"
    echo "ssh_pwauth: false"
    echo "runcmd:"
    if [ -n "$extra" ]; then
      while IFS= read -r line || [ -n "$line" ]; do
        [ -n "$line" ] && printf '  - %s\n' "$line"
      done < "$extra"
    fi
    echo "  - touch /var/lib/devvm-ready"
  } > "$dir/user-data"
}

# ci_write_meta_data <dir> <instance-id> <hostname>
ci_write_meta_data() {
  mkdir -p "$1" || return 1
  printf 'instance-id: %s\nlocal-hostname: %s\n' "$2" "$3" > "$1/meta-data"
}

# ci_make_seed <dir> <out.iso>  (only user-data + meta-data are included)
ci_make_seed() {
  local dir="$1" out="$2" stage rc
  command -v xorriso >/dev/null 2>&1 || { echo "xorriso not found" >&2; return 1; }
  stage="$(mktemp -d)" || return 1
  cp "$dir/user-data" "$dir/meta-data" "$stage/" && rm -f "$out" \
    && xorriso -as mkisofs -quiet -J -r -V cidata -o "$out" "$stage" >&2
  rc=$?
  rm -rf "$stage"
  return $rc
}
