# win-devvm

Unattended Windows 11 dev VM on a Linux host: rootless libvirt/KVM, UEFI + swtpm TPM 2.0, virtio disk/net, SLIRP user networking (passt had no connectivity on the original host). One command builds a config ISO, creates the disk, installs Windows, and provisions a Rust/MSVC toolchain over SSH/RDP.

## Features
- Fully unattended install (`autounattend.xml` rendered from a template; TPM/SecureBoot/RAM checks bypassed).
- No root: `qemu:///session`, user-mode networking, ports forwarded on `127.0.0.1` only.
- Key-based SSH (ed25519 key generated on first run) and RDP.
- Idempotent in-guest tool setup via winget (Git, rustup, VS Build Tools, Python, Node, gh, CMake, ...).
- All settings overridable through environment variables.

## Quickstart
```
./provision.sh        # ~15 min Windows install + ~20-30 min tools
./vm.sh view          # watch the install
./vm.sh status        # "tools: DONE" when C:\setup-tools.done exists
./vm.sh ssh           # host:2222 -> guest:22
xfreerdp /v:127.0.0.1:3390 /u:dev
```
State lives in `~/vms/win-devvm`.

## Files
| File | Purpose |
|---|---|
| `config.env` | Defaults for name, resources, ISO paths, edition, credentials, ports |
| `provision.sh` | Validates prerequisites, builds config ISO + disk, defines and starts the VM |
| `vm.sh` | Day-2 control |
| `autounattend.xml.tmpl` | Answer file template (`@@EDITION@@ @@VMNAME@@ @@USER@@ @@PASS@@`) |
| `setup-tools.ps1` | First-logon guest provisioning |

## CLI reference
| Command | Effect |
|---|---|
| `./provision.sh` | Create and start the VM; fails if it already exists |
| `./provision.sh --force` | Destroy the existing VM and `$VM_DIR`, then recreate |
| `./vm.sh start` / `stop` / `kill` | `virsh start` / graceful `shutdown` / `destroy` (hard power-off) |
| `./vm.sh status` (default) | Domain state + tool-setup state via SSH |
| `./vm.sh view` | Open `virt-viewer` |
| `./vm.sh ssh [cmd...]` | SSH as `$ADMIN_USER` with the generated key |
| `./vm.sh destroy` | Prompted deletion of the VM and `$VM_DIR` |

## Documentation
See [docs/](docs/README.md): [purpose](docs/purpose.md), [architecture](docs/architecture.md), [running](docs/running.md), [how-to](docs/how-to.md), [provisioning deep-dive](docs/provisioning.md), [diagrams](docs/diagrams/README.md).

## Gotchas
- The default password in `config.env` is a lab placeholder and is public in this repo. Override `ADMIN_PASS`.
- The "Press any key to boot from CD" prompt is handled by tapping space for 20 s. Longer taps hit Setup's Cancel dialog and stall the install (dismiss with Enter).
- Guest build log: `C:\setup-tools.log`.
- Bilterm Windows build: `ssh` in, clone, `cargo build --release`, then `scripts/build-release-mac-win.sh --windows`.
