# Architecture

## Components
| Component | Role |
|---|---|
| `config.env` | Sourced by both scripts; every value is `${VAR:-default}` |
| `provision.sh` | Host orchestrator |
| `autounattend.xml.tmpl` | Rendered with `sed` into `autounattend.xml` |
| `setup-tools.ps1` | Guest provisioner, delivered on the config ISO |
| `vm.sh` | Day-2 wrapper around `virsh`, `virt-viewer`, `ssh` |

Host tools: `virt-install`, `virsh`, `xorriso`, `swtpm`, `qemu-img`, `ssh-keygen`, optionally `virt-viewer`.

## Execution flow (`provision.sh`)
1. Load config; verify `$WIN_ISO` and `$VIRTIO_ISO` are readable, required tools exist, `/dev/kvm` is rw.
2. If the domain exists: with `--force`, `destroy` + `undefine --nvram --tpm` and `rm -rf $VM_DIR`; otherwise exit 1.
3. `mkdir -p $VM_DIR` (0700). Render the template (`@@EDITION@@`, `@@VMNAME@@` = uppercased name truncated to 15 chars for NetBIOS, `@@USER@@`, `@@PASS@@`; `& | \` are escaped for sed).
4. Generate `$SSH_KEY` if missing; stage `autounattend.xml`, `setup-tools.ps1`, `authorized_keys`; build `config.iso` (label `WINCONFIG`) with `xorriso`.
5. `qemu-img create -f qcow2` the disk (thin).
6. `virt-install` defines and starts the VM (no console, `--wait 0`).
7. Tap `KEY_SPACE` once per second for 20 s to pass the "press any key" boot prompt.

Then, in the guest: Windows Setup reads `autounattend.xml` from whichever CD has it → partitions disk → installs → reboots → autologon → `FirstLogonCommands` scans drives D-H for `setup-tools.ps1` and runs it.

## VM hardware
UEFI firmware; swtpm TPM 2.0 (`tpm-crb`); `host-passthrough` CPU; virtio disk (`cache=none`, `discard=unmap`, boot order 1); three SATA CD-ROMs: Windows ISO (boot order 2), virtio-win ISO, config ISO; virtio video; VNC on 127.0.0.1; virtio-serial channel for the QEMU guest agent.

Drive letters of the CDs vary, so every consumer probes several letters: driver paths `E:`/`F:`/`D:` in the answer file, `D-G` in `setup-tools.ps1`, `D-H` in `FirstLogonCommands`.

## Storage
```
$VM_DIR (default ~/vms/win-devvm, 0700)
├── disk.qcow2   sparse, VM_DISK_GB, GPT: EFI 300 MB FAT32 / MSR 16 MB / C: NTFS (rest)
└── config.iso   autounattend.xml, setup-tools.ps1, authorized_keys
```
The Windows and virtio ISOs are referenced in place (read-only). TPM and NVRAM state are managed by libvirt under the session profile (`~/.config/libvirt/qemu`), which is why undefine passes `--nvram --tpm`. There is no backing-file/COW chain; the qcow2 is a single image.

## Networking
`--network none` at the libvirt level; a QEMU user-mode netdev (SLIRP) is injected through `--qemu-commandline` with a virtio-net NIC at PCI `0x1e`, fixed MAC `52:54:00:17:8c:66`.

| Host | Guest |
|---|---|
| `127.0.0.1:$SSH_PORT` (2222) | 22 |
| `127.0.0.1:$RDP_PORT` (3390) | 3389 |

The fixed MAC and PCI slot mean two VMs on one host would collide only if run concurrently with the same ports; change `SSH_PORT`/`RDP_PORT` (the MAC is hard-coded in `provision.sh`).

## State and completion signals
Guest markers: `C:\setup-tools.done` (success), `C:\setup-tools.failed` (comma-separated failures), `C:\setup-tools.log` (transcript). `vm.sh status` reads `.done` over SSH.

See [diagrams](diagrams/README.md).
