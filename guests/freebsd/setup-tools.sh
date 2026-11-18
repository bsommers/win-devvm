#!/bin/sh
# FreeBSD first-boot tool setup (run as root by nuageinit runcmd). Usage: setup-tools.sh <user>
# Writes /var/db/devvm-ready on success, /var/db/devvm-failed on failure; log: /var/log/devvm-setup.log.
user="${1:-dev}"
exec >>/var/log/devvm-setup.log 2>&1
set -x
fail() { touch /var/db/devvm-failed; exit 1; }
export ASSUME_ALWAYS_YES=yes
# network may lag behind nuageinit: retry bootstrap/update
n=0; until { pkg -N >/dev/null 2>&1 || pkg bootstrap -y; } && pkg update -f; do n=$((n+1)); [ $n -ge 20 ] && fail; sleep 10; done
pkg install -y sudo || fail
mkdir -p /usr/local/etc/sudoers.d
echo "$user ALL=(ALL) NOPASSWD: ALL" > /usr/local/etc/sudoers.d/devvm
chmod 440 /usr/local/etc/sudoers.d/devvm
# git, rust (cargo), qemu (system emulation, for bilterm's `dos` smoke), ncurses (terminfo/display), curl
pkg install -y git rust qemu ncurses curl || fail
touch /var/db/devvm-ready
