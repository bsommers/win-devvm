#!/usr/bin/env bash
# lib/images.sh - cached, checksum-verified image download + qcow2 overlays.
# Sourced; no top-level side effects. Logging goes to stderr.

IMAGE_CACHE="${IMAGE_CACHE:-$HOME/.cache/win-devvm/images}"

_img_log() { printf '[images] %s\n' "$*" >&2; }

# _img_sha256 <file> -> hex digest
_img_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

# _img_parse_sums <sums-file> <file-name> -> hash on stdout (empty if absent)
# Handles "<hash>  <name>", "<hash> *<name>" and "SHA256 (<name>) = <hash>".
_img_parse_sums() {
  awk -v n="$2" '
    $1 == "SHA256" && $2 == "(" n ")" { print $4; exit }
    $1 ~ /^[0-9a-fA-F]+$/ && length($1) == 64 { f=$2; sub(/^\*/, "", f); if (f == n) { print $1; exit } }
  ' "$1"
}

# _img_key: stdin -> filesystem-safe key
_img_key() { tr -c 'A-Za-z0-9' '_'; }

# _img_expected <sums-spec> <file-name> -> expected hash on stdout
_img_expected() {
  local spec="$1" name="$2" sums h
  case "$spec" in
    sha256:*) printf '%s\n' "${spec#sha256:}"; return 0 ;;
  esac
  sums="$IMAGE_CACHE/.sums-$(printf '%s' "$spec" | _img_key)"
  if [ "${IMAGE_OFFLINE:-0}" != 1 ]; then
    if curl -fsSL "$spec" -o "$sums.tmp"; then
      mv "$sums.tmp" "$sums"
    else
      rm -f "$sums.tmp"
      [ -f "$sums" ] || { _img_log "cannot fetch sums $spec"; return 1; }
      _img_log "sums fetch failed; using cached copy"
    fi
  fi
  [ -f "$sums" ] || { _img_log "no cached sums for $spec (offline)"; return 1; }
  h="$(_img_parse_sums "$sums" "$name")"
  [ -n "$h" ] || { _img_log "no checksum for $name in $spec"; return 1; }
  printf '%s\n' "$h"
}

# image_fetch <url> <file-name> <sums-url|sha256:hex> -> prints cached path
image_fetch() {
  [ $# -eq 3 ] || { _img_log "usage: image_fetch url name sums"; return 2; }
  local url="$1" name="$2" spec="$3" dest want got
  mkdir -p "$IMAGE_CACHE" || return 1
  dest="$(cd "$IMAGE_CACHE" && pwd)/$name"
  want="$(_img_expected "$spec" "$name")" || return 1
  want="$(printf '%s' "$want" | tr 'A-F' 'a-f')"
  if [ ! -f "$dest" ]; then
    if [ "${IMAGE_OFFLINE:-0}" = 1 ]; then _img_log "offline and $name not cached"; return 1; fi
    _img_log "downloading $url"
    curl -fL -C - --retry 3 -o "$dest" "$url" >&2 || { _img_log "download failed"; return 1; }
  fi
  got="$(_img_sha256 "$dest")"
  if [ "$got" != "$want" ]; then
    _img_log "checksum mismatch for $name (want $want got $got); removing"
    rm -f "$dest"
    return 1
  fi
  _img_log "verified $name"
  printf '%s\n' "$dest"
}

# image_overlay <base-image> <out.qcow2> <size-GB>
image_overlay() {
  [ $# -eq 3 ] || { _img_log "usage: image_overlay base out size-GB"; return 2; }
  local base="$1" out="$2" size="$3" fmt abs
  [ -f "$base" ] || { _img_log "base image missing: $base"; return 1; }
  abs="$(cd "$(dirname "$base")" && pwd)/$(basename "$base")"
  fmt="$(qemu-img info --output=json "$abs" | sed -n 's/.*"format": *"\([^"]*\)".*/\1/p' | head -n1)"
  [ -n "$fmt" ] || { _img_log "cannot detect format of $abs"; return 1; }
  qemu-img create -q -f qcow2 -F "$fmt" -b "$abs" "$out" "${size}G" >&2
}
