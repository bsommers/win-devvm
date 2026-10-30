# Running

## Prerequisites
- Linux host with KVM (`/dev/kvm` readable and writable by you).
- Packages: libvirt/QEMU (session mode), `virt-install`, `virsh`, `xorriso`, `swtpm`, `qemu-img`, `openssh-client`; `virt-viewer` for `vm.sh view`; an RDP client (e.g. `xfreerdp`) optional. `provision.sh` calls `/usr/bin/python3 /usr/bin/virt-install`, so virt-install must live at that path.
- A Windows 11 ISO at `$WIN_ISO` containing an image named `$WIN_EDITION`.
- `virtio-win.iso` at `$VIRTIO_ISO`.
- Internet access from the guest (winget).

## Configuration (`config.env`)
Override per invocation, e.g. `VM_RAM_MB=8192 ./provision.sh`. `vm.sh` must see the same values as `provision.sh`.

| Variable | Default | Meaning |
|---|---|---|
| `VM_NAME` | `win-devvm` | libvirt domain; also computer name (upper-cased, 15 chars) |
| `VM_RAM_MB` | `16384` | Memory |
| `VM_VCPUS` | `8` | vCPUs |
| `VM_DISK_GB` | `120` | qcow2 virtual size |
| `LIBVIRT_URI` | `qemu:///session` | Connection |
| `VM_DIR` | `~/vms/$VM_NAME` | Disk and config ISO |
| `WIN_ISO` | `~/Windows11_Client_x64_en-us_26300_9457.iso` | Installer |
| `VIRTIO_ISO` | `~/.cache/cvm/lab-images/virtio-win.iso` | Drivers and guest tools |
| `WIN_EDITION` | `Windows 11 Pro` | Must match an `/IMAGE/NAME` in install.wim |
| `ADMIN_USER` / `ADMIN_PASS` | `dev` / `devvm-Passw0rd!` | Local admin; change the password |
| `SSH_PORT` / `RDP_PORT` | `2222` / `3390` | Host loopback forwards |
| `SSH_KEY` | `~/.ssh/id_windevvm` | Generated (ed25519, no passphrase) if missing |

Passwords containing `& | \` are escaped; characters special to XML (`< >`) are **not** escaped in the template and will break the answer file.

## Commands
| Command | Notes |
|---|---|
| `./provision.sh [--force]` | See [architecture](architecture.md) |
| `./vm.sh {start\|stop\|kill\|status\|view\|ssh\|destroy}` | No argument = `status`. `stop` is an ACPI shutdown |

## Exit codes
| Code | Source |
|---|---|
| 0 | Success |
| 1 | `provision.sh`: missing ISO/tool, no `/dev/kvm`, or VM exists without `--force`. `vm.sh destroy`: confirmation declined |
| 2 | `vm.sh`: unknown command (prints usage) |
| other | Propagated from `virsh`, `virt-install`, `ssh`, `xorriso` (`set -e`) |

## Timeline
~15 min install (several reboots) then ~20-30 min tool setup. Done when `./vm.sh status` prints `tools: DONE`.
