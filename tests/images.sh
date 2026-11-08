#!/usr/bin/env bash
# Tests for lib/images.sh and lib/cloudinit.sh (no network, no root).
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export IMAGE_CACHE="$T/cache"
# shellcheck source=../lib/images.sh
. "$ROOT/lib/images.sh"
# shellcheck source=../lib/cloudinit.sh
. "$ROOT/lib/cloudinit.sh"
fail=0
ok() { echo "ok   - $1"; }
bad() { echo "FAIL - $1"; fail=1; }
check() { local n="$1"; shift; if "$@"; then ok "$n"; else bad "$n"; fi; }
rep() { printf "%${2}s" '' | tr ' ' "$1"; }

mkdir -p "$T/src"; printf 'hello image\n' > "$T/src/a.img"
H="$(_img_sha256 "$T/src/a.img")"
URL="file://$T/src/a.img"
B="$(rep b 64)"; C="$(rep c 64)"; Z="$(rep 0 64)"

printf '%s  a.img\n%s *b.img\n' "$H" "$B" > "$T/ubuntu"
printf 'SHA256 (a.img) = %s\nSHA256 (c.img) = %s\n' "$H" "$C" > "$T/fedora"
check "parse ubuntu plain" test "$(_img_parse_sums "$T/ubuntu" a.img)" = "$H"
check "parse ubuntu star" test "$(_img_parse_sums "$T/ubuntu" b.img)" = "$B"
check "parse bsd" test "$(_img_parse_sums "$T/fedora" c.img)" = "$C"
check "parse missing empty" test -z "$(_img_parse_sums "$T/fedora" zzz)"

p="$(image_fetch "$URL" a.img "sha256:$H" 2>/dev/null)"
check "fetch returns cached path" test "$p" = "$IMAGE_CACHE/a.img"
rm -f "$T/src/a.img"   # source gone: a cache hit must not need it
p="$(image_fetch "$URL" a.img "sha256:$H" 2>/dev/null)"
check "cache hit skips download" test "$p" = "$IMAGE_CACHE/a.img"
p="$(image_fetch "$URL" a.img "file://$T/fedora" 2>/dev/null)"
check "fetch via sums url (bsd)" test "$p" = "$IMAGE_CACHE/a.img"
p="$(IMAGE_OFFLINE=1 image_fetch "$URL" a.img "file://$T/fedora" 2>/dev/null)"
check "offline uses cached sums" test "$p" = "$IMAGE_CACHE/a.img"

image_fetch "$URL" a.img "sha256:$Z" >/dev/null 2>&1
check "mismatch returns nonzero" test $? -ne 0
check "mismatch deletes file" test ! -e "$IMAGE_CACHE/a.img"

if command -v qemu-img >/dev/null 2>&1; then
  qemu-img create -q -f qcow2 "$T/base.qcow2" 1G
  image_overlay "$T/base.qcow2" "$T/o.qcow2" 2 2>/dev/null
  check "overlay backs base" grep -q "backing file: $T/base.qcow2" < <(qemu-img info "$T/o.qcow2")
  check "overlay backing format is qcow2" grep -q "backing file format: qcow2" < <(qemu-img info "$T/o.qcow2")
else echo "skip - qemu-img missing"; fi

echo "ssh-ed25519 AAAAKEY test@x" > "$T/k.pub"; printf 'echo hi\n' > "$T/extra"
ci_write_user_data "$T/ci" bob "$T/k.pub" "$T/extra"
ci_write_meta_data "$T/ci" iid-1 vm1
UD="$T/ci/user-data"
check "user-data header" grep -q '^#cloud-config' "$UD"
check "user-data user" grep -q 'name: bob' "$UD"
check "user-data key" grep -q 'AAAAKEY' "$UD"
check "user-data sudo" grep -q 'NOPASSWD' "$UD"
check "user-data pwauth" grep -q 'ssh_pwauth: false' "$UD"
check "runcmd extra" grep -q '  - echo hi' "$UD"
check "runcmd ready last" test "$(tail -n1 "$UD")" = "  - touch /var/lib/devvm-ready"
check "meta-data" grep -q 'instance-id: iid-1' "$T/ci/meta-data"

if command -v xorriso >/dev/null 2>&1; then
  ci_make_seed "$T/ci" "$T/seed.iso" 2>/dev/null
  check "seed label cidata" grep -aqi 'cidata' "$T/seed.iso"
else echo "skip - xorriso missing"; fi
exit $fail
