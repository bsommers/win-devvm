# Purpose

## Problem
Building and testing native Windows (MSVC) artifacts — x64 from a Linux workstation, ARM64 from an Apple Silicon Mac — needs a real Windows install with a full toolchain. Doing this by hand is slow and unrepeatable. `win-devvm` makes it a single reproducible, rootless command.

## Non-goals
Not a hardened or production Windows image, not a multi-VM manager, not a licence provider (you supply the ISO; no product key is set).

## Threat model
The VM is a disposable **lab** machine for a single trusted user on a single-user host.

| Asset / surface | Posture |
|---|---|
| Host exposure | libvirt: forwards (`SSH_PORT`, `RDP_PORT`) and VNC bind to `127.0.0.1` only; SLIRP gives no inbound access from the LAN. Parallels: the guest sits on the Shared (NAT) network, reachable on 22/3389 from the host (and other VMs on that network), not from the LAN. |
| Privilege | Everything runs as the invoking user (`qemu:///session` / your Parallels user); no sudo, no host-wide libvirt changes. |
| Host sharing (Parallels) | Mac profile folders and guest-volume sharing are off in the template; clipboard / drag-and-drop stay on. |
| Guest outbound | Unrestricted NAT via SLIRP. The guest can reach the internet and host-local services reachable through the NAT gateway. |
| Credentials | `ADMIN_PASS` is written in **plaintext** into the rendered `autounattend.xml`, `$VM_DIR/config.iso` (mode per umask; dir is 0700), and Windows keeps unattend copies (e.g. `C:\Windows\Panther`) in the guest. Treat it as non-secret; change it after first login. |
| Autologon | Enabled for 10 logons with that password. |
| Defender | `%USERPROFILE%` excluded from real-time scanning for build speed. |
| SSH | Key auth; key at `$SSH_KEY` (no passphrase). Host keys accepted on first use (`accept-new`). Guest password auth for sshd is not disabled. |
| Guest hardening | Windows install requirements are bypassed (TPM/SecureBoot/RAM); the guest has an administrator account and an open firewall for 22/3389. |

## Boundaries
Do not store secrets in the guest that you would not expose to anything running on the host as your user, and do not publish `$VM_DIR`. Do not forward the ports beyond loopback.
