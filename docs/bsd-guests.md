# BSD guests (libvirt, rootless KVM)

## FreeBSD (`GUEST=freebsd`) - implemented
`VM_NAME=bsd1 GUEST=freebsd ./provision.sh && ./vm.sh wait` (then `./vm.sh ssh`).

- Image: official `FreeBSD-<REL>-RELEASE-amd64-BASIC-CLOUDINIT-ufs.qcow2.xz` from
  `download.freebsd.org/releases/VM-IMAGES/<REL>-RELEASE/amd64/Latest/` (default `FREEBSD_REL=15.1`). Verified against the
  `CHECKSUM.SHA256` published next to it (HTTPS only; FreeBSD does not sign VM-image checksums), then decompressed in the
  image cache (`lib/images.sh`, `*.xz` support).
- Config: nuageinit (in base) reads the NoCloud `cidata` seed: user `$ADMIN_USER` (`/bin/sh`, no password) + host SSH key.
  `PasswordAuthentication no` is the image default. Base has no sudo/bash; `guests/freebsd/setup-tools.sh` installs sudo
  (NOPASSWD drop-in) and `git rust qemu ncurses curl` via `pkg`.
- Quirks handled in `guest.env`: `MACHINE=q35` (osinfo would pick i440fx, the NIC sits on `pcie.0`); `UEFI_BOOT` turns off
  Secure Boot/enrolled keys (loader.efi is unsigned); runcmd runs before sshd and the image's first-boot pkgbase update
  reboots the VM, so the setup is (re)started from `/etc/rc.local` until `/var/db/devvm-ready` or `/var/db/devvm-failed`
  exists (log `/var/log/devvm-setup.log`). sshd comes up only after the first-boot update (a few minutes).
- `./vm.sh wait` blocks until the tools are installed (`tools: DONE`) or failed.

## OpenBSD (`GUEST=openbsd`) - implemented via a locally built image
OpenBSD has no official cloud image, so the image is built once and cached; then it provisions like any cloud-image guest:
`guests/openbsd/build-image.sh && VM_NAME=openbsd1 GUEST=openbsd ./provision.sh && VM_NAME=openbsd1 GUEST=openbsd ./vm.sh ssh`.

- Build (`guests/openbsd/build-image.sh`, helper `build-image.py`, needs qemu+KVM, curl, python3 with `cryptography`; env
  `OPENBSD_REL` (default 8.0), `OPENBSD_MIRROR`, `OPENBSD_PKGS`, `SSH_KEY`, `BUILD_USER`, `OPENBSD_OUT`, `OPENBSD_WORK`
  (default `/datanapps/vms/openbsd-build`, never /tmp)):
  1. downloads `SHA256`, `SHA256.sig` and `miniroot<rel>.img` from the release dir; verifies `SHA256.sig` with a pure-python
     signify (ed25519) check against the pinned `guests/openbsd/openbsd-<rel>-base.pub`, then verifies miniroot's SHA256 from
     that signed list. The pinned key was fetched over HTTPS from the mirror; for a new release cross-check it against
     `/etc/signify/` of the previous release.
  2. boots the miniroot under qemu/KVM with the serial console on a unix socket and answers the installer prompts
     (expect-style, no pexpect): DHCP via slirp, sets over HTTPS from the mirror (installer verifies their signatures),
     `-game* -xserv* -xfont*` (xbase stays: the qemu pkg needs X11 libs), MBR whole-disk, user `bill` with the host public key (`$SSH_KEY.pub`), root ssh login off, random
     throwaway root/user passwords that are locked at the end.
  3. reboots the installed disk, prepends `PasswordAuthentication no` / `KbdInteractiveAuthentication no` to sshd_config
     (sshd takes the first value), adds `permit nopass keepenv :wheel` to doas.conf, `pkg_add git rust qemu` (and
     `ncurses` if a package of that name exists; base already has libcurses), checks `ssh bill@... uname -a` from the host,
     halts, and writes `~/.cache/win-devvm/images/openbsd-<rel>-amd64.qcow2` + `.sha256`.
- Provision: `guest.env` points `IMAGE_URL`/`IMAGE_SUMS` at those `file://` paths; `provision.sh` makes a qcow2 overlay
  (cloudimg path) and ignores the cidata seed (no cloud-init). `guest_stage` fails early with a hint if the image is missing.
  The SSH key is baked at build time; rebuild to change it. `MACHINE=q35`, `UEFI_BOOT=hd` (BIOS boot). Ready as soon as
  ssh answers. Stop: `doas halt -p`. Run `syspatch` after the first login for errata.
- Rejected alternatives: autoinstall(8) (needs `install.conf` over HTTP port 80, not bindable rootless; or an FFS-patched
  `bsd.rd`), and community pre-built cloud images (unsigned, untrusted).
