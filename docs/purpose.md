# Purpose

## Problem
Building and testing native Windows (MSVC) artifacts from a Linux workstation needs a real Windows install with a full toolchain. Doing this by hand is slow and unrepeatable. `win-devvm` makes it a single reproducible, rootless command.

## Non-goals
Not a hardened or production Windows image, not a multi-VM manager, not a licence provider (you supply the ISO; no product key is set).

## Threat model
The VM is a disposable **lab** machine for a single trusted user on a single-user host.

| Asset / surface | Posture |
|---|---|
| Host exposure | Forwards (`SSH_PORT`, `RDP_PORT`) and VNC bind to `127.0.0.1` only. SLIRP gives no inbound access from the LAN. |
| Privilege | Everything runs as the invoking user (`qemu:///session`); no sudo, no host-wide libvirt changes. |
| Guest outbound | Unrestricted NAT via SLIRP. The guest can reach the internet and host-local services reachable through the NAT gateway. |
| Credentials | `ADMIN_PASS` is written in **plaintext** into the rendered `autounattend.xml`, `$VM_DIR/config.iso` (mode per umask; dir is 0700), and Windows keeps unattend copies (e.g. `C:\Windows\Panther`) in the guest. Treat it as non-secret; change it after first login. |
| Autologon | Enabled for 3 logons with that password. |
| SSH | Key auth; key at `$SSH_KEY` (no passphrase). Host keys accepted on first use (`accept-new`). Guest password auth for sshd is not disabled. |
| Guest hardening | Windows install requirements are bypassed (TPM/SecureBoot/RAM); the guest has an administrator account and an open firewall for 22/3389. |

## Boundaries
Do not store secrets in the guest that you would not expose to anything running on the host as your user, and do not publish `$VM_DIR`. Do not forward the ports beyond loopback.
