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

## Documentation
See [docs/](docs/README.md): [purpose](docs/purpose.md), [architecture](docs/architecture.md), [running](docs/running.md), [how-to](docs/how-to.md), [provisioning deep-dive](docs/provisioning.md), [diagrams](docs/diagrams/README.md).

## Gotchas
- The default password in `config.env` is a lab placeholder and is public in this repo. Override `ADMIN_PASS`.
- libvirt: the "Press any key to boot from CD" prompt is handled by tapping space for 20 s. Longer taps hit Setup's Cancel dialog and stall the install (dismiss with Enter).
- Parallels Standard caps a VM at 4 vCPUs / 8 GB and its `prlctl` cannot create/start/stop VMs; `vm.sh` uses `open`, SSH and process signals instead. Don't run `prlctl register` on the bundle yourself before the first start: Parallels then opens it without starting it.
- The Parallels config template was captured from Parallels Desktop 27; a much newer Parallels may migrate or reject it.
- Guest build log: `C:\setup-tools.log`.
- Bilterm Windows builds: `scripts/build-windows-vm.sh` in the bilterm repo drives this VM end to end.
