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

## OpenBSD (`GUEST=openbsd`) - NOT implemented (spike notes)
No official cloud image. Options evaluated:
1. Official `install<ver>.iso`/`miniroot`/`pxeboot`+`bsd.rd` (+ `SHA256`, signify `SHA256.sig`) with `autoinstall(8)`:
   response file `install.conf` fetched over HTTP **port 80** from the DHCP next-server; if the fetch fails the installer
   asks for a URL. Under rootless slirp port 80 on 10.0.2.2 maps to host loopback:80, which an unprivileged user cannot
   bind (`ip_unprivileged_port_start=1024`), so a console-driven step (serial/VNC keystrokes) would be required. Sets can
   come from `cdn.openbsd.org` via NAT. `site<ver>.tgz` + `install.site` can add the SSH key and `pkg_add git rust qemu`.
   A local `/auto_install.conf` inside `bsd.rd`'s ramdisk avoids HTTP but needs OpenBSD tooling (`rdsetroot`, FFS write).
2. Community pre-built cloud images (not official, no signature): rejected as untrusted.
Recommended next step: a one-off `guests/openbsd/build-image.sh` that drives the official installer on a serial console
via qemu, bakes the host SSH key + `pkg_add` set, and publishes a local qcow2 consumed as a `cloudimg` without seed.
