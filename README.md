# win-devvm

Unattended Windows 11 dev VM, two backends selected automatically by host OS:

| Host | Backend (`HYPERVISOR`) | Guest |
|---|---|---|
| Linux | `libvirt` — rootless KVM, UEFI + swtpm TPM 2.0, virtio disk/net, SLIRP user networking | Windows 11 x64 |
| macOS (Apple Silicon) | `parallels` — Parallels Desktop (works with **Standard** edition), shared network | Windows 11 **ARM64** |

One command builds the install media, creates the disk, installs Windows, and provisions a Rust/MSVC toolchain (native arch + the other Windows target for cross builds) reachable over SSH/RDP.

## Features
- Fully unattended install (`autounattend.xml` rendered from a template; TPM/SecureBoot/RAM checks bypassed).
- libvirt: no root — `qemu:///session`, user-mode networking, ports forwarded on `127.0.0.1` only.
- Parallels: no Pro licence needed — the VM bundle is generated from a template and opened in Parallels; the Windows ISO is remastered to skip "Press any key to boot from CD"; Parallels' own virtio-net driver and Parallels Tools are injected from the local Parallels install.
- Key-based SSH (ed25519 key generated on first run) and RDP; per-VM `known_hosts`.
- Idempotent, reboot-tolerant in-guest tool setup via winget (Git, VS Build Tools with x64 + ARM64 MSVC, rustup, Python, Node, gh, CMake, ...).
- All settings overridable through environment variables.

## Quickstart
```
./provision.sh        # ~15 min Windows install + ~20-30 min tools
./vm.sh view          # watch the install (virt-viewer / Parallels window)
./vm.sh wait          # block until "tools: DONE" (or FAILED)
./vm.sh ssh           # PowerShell in the guest
```
macOS: put a Windows 11 ARM64 ISO (`*A64FRE*.iso`) in `~/Downloads` or `~/Library/Parallels/Downloads`, or set `WIN_ISO`.
State lives in `~/vms/win-devvm`; the Parallels bundle in `~/Parallels/win-devvm.pvm`.

## Files
| File | Purpose |
|---|---|
| `config.env` | Defaults for backend, name, resources, ISO paths, edition, credentials, ports |
| `provision.sh` | Validates prerequisites, renders the answer file, hands off to the backend |
| `vm.sh` | Day-2 control |
| `lib/libvirt.sh`, `lib/parallels.sh` | Backends (`hv_*` functions) |
| `parallels/config.pvs.tmpl` | Parallels VM config template (Windows 11 ARM64, SATA disk/CD, virtio NIC, vTPM) |
| `autounattend.xml.tmpl` | Answer file template (`@@EDITION@@ @@VMNAME@@ @@USER@@ @@PASS@@ @@ARCH@@ @@TG_REBOOT@@`) |
| `setup-tools.ps1` | Guest provisioning (first logon, then each logon until done) |
| `bsd-vm.sh` | FreeBSD / OpenBSD VMs on QEMU (provision and day-2 control) |
| `lib/openbsd-install.py`, `lib/qemu-sock.py` | OpenBSD installer responder; QEMU monitor / serial socket client |

## CLI reference
| Command | Effect |
|---|---|
| `./provision.sh` | Create and start the VM; fails if it already exists |
| `./provision.sh --force` | Destroy the existing VM and `$VM_DIR`, then recreate |
| `./vm.sh start` / `stop` / `kill` | Start / graceful shutdown / hard power-off |
| `./vm.sh status` (default) | VM state + tool-setup state via SSH |
| `./vm.sh wait` | Poll until tool setup is DONE (exit 0) or FAILED (exit 1); `WAIT_TIMEOUT` seconds |
| `./vm.sh view` | Open the console (virt-viewer / Parallels window) |
| `./vm.sh ip` | Guest SSH address |
| `./vm.sh ssh [cmd...]` | SSH as `$ADMIN_USER` with the generated key |
| `./vm.sh push <local> <remote>` / `pull <remote> <local>` | `scp -r` to/from the guest (remote paths relative to the user's home) |
| `./vm.sh destroy` | Prompted deletion of the VM and `$VM_DIR` |

## FreeBSD and OpenBSD guests

`bsd-vm.sh` builds BSD dev VMs on plain QEMU (HVF on macOS, KVM on Linux; no libvirt or
Parallels). The guest CPU matches the host: arm64 on Apple Silicon, amd64 on x86_64.

```
./bsd-vm.sh freebsd provision     # ~3 min after the 0.6 GB image download
./bsd-vm.sh openbsd provision     # ~4 min after the 0.7 GB installer download
./bsd-vm.sh freebsd ssh           # user dev, key-only, passwordless sudo (doas on OpenBSD)
./bsd-vm.sh openbsd ssh 'uname -a'
```

| Guest | How it is installed | SSH |
|---|---|---|
| FreeBSD 15.1 | Official `BASIC-CLOUDINIT` image plus a cloud-init config drive (user, key, `sudo`, `bash`, `git`); root filesystem grows to `VM_DISK_GB` | `127.0.0.1:2230` |
| OpenBSD 8.0 | Official `installNN.img`; `lib/openbsd-install.py` answers the installer over the serial console, then adds the key and a `doas` rule | `127.0.0.1:2231` |

Commands: `provision [--force]`, `start`, `stop`, `kill`, `status`, `ip`, `ssh [cmd...]`,
`push <local> <remote>`, `pull <remote> <local>`, `console` (serial), `destroy`.
Settings (environment): `FREEBSD_VERSION`, `OPENBSD_VERSION`, `VM_RAM_MB` (4096), `VM_VCPUS` (4),
`VM_DISK_GB` (40), `ADMIN_USER` (dev), `SSH_KEY`, `SSH_PORT`, `VM_NAME`, `VM_DIR`, `IMAGE_CACHE`.

Downloads are cached in `~/.cache/win-devvm` and checked against the project's published
SHA-256 on every provision. State lives in `~/vms/<guest>-devvm`. The OpenBSD installer
password is random, kept in `~/vms/openbsd-devvm/password` (mode 600), and not needed for SSH.

Tested on macOS arm64 (QEMU 11, HVF). The amd64 path (Linux/KVM, or an Intel Mac) is written
but untested; OpenBSD there also depends on the boot prompt being reachable over serial.
When a new release comes out, set the version variable; if the OpenBSD installer gains a
question without a default, add a rule to `RULES` in `lib/openbsd-install.py`
(`~/vms/openbsd-devvm/install.log` shows where it stopped).

## Documentation
See [docs/](docs/README.md): [purpose](docs/purpose.md), [architecture](docs/architecture.md), [running](docs/running.md), [how-to](docs/how-to.md), [provisioning deep-dive](docs/provisioning.md), [diagrams](docs/diagrams/README.md).

## Gotchas
- The default password in `config.env` is a lab placeholder and is public in this repo. Override `ADMIN_PASS`.
- libvirt: the "Press any key to boot from CD" prompt is handled by tapping space for 20 s. Longer taps hit Setup's Cancel dialog and stall the install (dismiss with Enter).
- Parallels Standard caps a VM at 4 vCPUs / 8 GB and its `prlctl` cannot create/start/stop VMs; `vm.sh` uses `open`, SSH and process signals instead. Don't run `prlctl register` on the bundle yourself before the first start: Parallels then opens it without starting it.
- The Parallels config template was captured from Parallels Desktop 27; a much newer Parallels may migrate or reject it.
- Guest build log: `C:\setup-tools.log`.
- Bilterm Windows builds: `scripts/build-windows-vm.sh` in the bilterm repo drives this VM end to end.
