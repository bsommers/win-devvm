# Running

## Prerequisites (Parallels, macOS)
- Apple Silicon Mac with Parallels Desktop (Standard is enough) installed in `/Applications`.
- A Windows 11 **ARM64** ISO (`*A64FRE*.iso`, e.g. the one Parallels' own installer downloads to `~/Library/Parallels/Downloads`) containing `$WIN_EDITION`.
- ~6 GB free in `$VM_DIR` for the remastered media, plus the VM disk (sparse).
- Internet access from the guest (winget, rustup).

## Prerequisites (libvirt, Linux)
- Linux host with KVM (`/dev/kvm` readable and writable by you).
- Packages: libvirt/QEMU (session mode), `virt-install`, `virsh`, `xorriso`, `swtpm`, `qemu-img`, `openssh-client`; `virt-viewer` for `vm.sh view`; an RDP client (e.g. `xfreerdp`) optional. `provision.sh` calls `/usr/bin/python3 /usr/bin/virt-install`, so virt-install must live at that path.
- A Windows 11 ISO at `$WIN_ISO` containing an image named `$WIN_EDITION`.
- `virtio-win.iso` at `$VIRTIO_ISO`.
- Internet access from the guest (winget).

## Configuration (`config.env`)
Override per invocation, e.g. `VM_RAM_MB=8192 ./provision.sh`. `vm.sh` must see the same values as `provision.sh`.

| Variable | Default | Meaning |
|---|---|---|
| `HYPERVISOR` | `parallels` on macOS, else `libvirt` | Backend |
| `VM_NAME` | `win-devvm` | VM name; also computer name (upper-cased, 15 chars) |
| `VM_RAM_MB` | `16384` (Parallels: `8192`) | Memory |
| `VM_VCPUS` | `8` (Parallels: `4`) | vCPUs |
| `WIN_ARCH` | `amd64` (Parallels: `arm64`) | Answer-file `processorArchitecture` |
| `PRL_VM_HOME` | `~/Parallels` | Parallels: where `$VM_NAME.pvm` is created |
| `PRL_APP` | `/Applications/Parallels Desktop.app` | Parallels: source of the driver/tools payload |
| `VM_DISK_GB` | `120` | qcow2 virtual size |
| `LIBVIRT_URI` | `qemu:///session` | Connection |
| `VM_DIR` | `~/vms/$VM_NAME` | libvirt: disk + config ISO; Parallels: remastered `install.iso`; both: `known_hosts` |
| `WIN_ISO` | libvirt: `~/Windows11_Client_x64_en-us_26300_9457.iso`; Parallels: newest `*A64FRE*.iso` in `~/Downloads` or `~/Library/Parallels/Downloads` | Installer |
| `VIRTIO_ISO` | `~/.cache/cvm/lab-images/virtio-win.iso` | Drivers and guest tools |
| `WIN_EDITION` | `Windows 11 Pro` | Must match an `/IMAGE/NAME` in install.wim |
| `ADMIN_USER` / `ADMIN_PASS` | `dev` / `devvm-Passw0rd!` | Local admin; change the password |
| `SSH_PORT` / `RDP_PORT` | `2222` / `3390` | libvirt: host loopback forwards (Parallels uses the guest IP, ports 22/3389) |
| `SSH_KEY` | `~/.ssh/id_windevvm` | Generated (ed25519, no passphrase) if missing |

Passwords containing `& | \` are escaped; characters special to XML (`< >`) are **not** escaped in the template and will break the answer file.

## Commands
| Command | Notes |
|---|---|
| `./provision.sh [--force]` | See [architecture](architecture.md) |
| `./vm.sh {start\|stop\|kill\|status\|wait\|view\|ip\|ssh\|push\|pull\|destroy}` | No argument = `status`. `stop` is an ACPI shutdown (libvirt) or `shutdown /s` over SSH (Parallels) |

## Exit codes
| Code | Source |
|---|---|
| 0 | Success |
| 1 | `provision.sh`: missing ISO/tool/payload, no `/dev/kvm`, wrong host for the backend, or VM exists without `--force`. `vm.sh destroy`: confirmation declined. `vm.sh wait`: setup FAILED or timed out |
| 2 | `vm.sh`: unknown command (prints usage) |
| other | Propagated from `virsh`, `virt-install`, `ssh`, `xorriso` (`set -e`) |

## Timeline
~15 min install (several reboots) then ~20-30 min tool setup. Done when `./vm.sh status` prints `tools: DONE`.
