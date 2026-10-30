# win-devvm

Unattended Windows 11 dev VM on this Linux host (rootless libvirt/KVM, UEFI + swtpm TPM 2.0, virtio disk/net, SLIRP user networking (passt had no connectivity here)).

| File | Purpose |
|---|---|
| `config.env` | name, RAM/CPU/disk, ISO paths, edition, creds, forwarded ports (all env-overridable) |
| `provision.sh` | builds config ISO, creates disk, defines + starts the VM (`--force` recreates) |
| `autounattend.xml.tmpl` | answer file: virtio drivers, TPM/SB/RAM bypass, GPT layout, local admin, autologon |
| `setup-tools.ps1` | runs at first logon: virtio guest tools, OpenSSH, RDP, winget (Git, rustup, VS Build Tools, Python, Node, gh, CMake…), Rust MSVC toolchain |
| `vm.sh` | `start|stop|kill|status|view|ssh|destroy` |

## Use
```
./provision.sh        # ~15 min Windows install + ~20-30 min tools; watch with ./vm.sh view
./vm.sh status        # "tools: DONE" when C:\setup-tools.done exists
./vm.sh ssh           # key auth (~/.ssh/id_windevvm, generated), host:2222 -> guest:22
xfreerdp /v:127.0.0.1:3390 /u:dev
```
Disk/state lives in `~/vms/win-devvm`. Defaults: 16 GB RAM, 8 vCPU, 120 GB, edition `Windows 11 Pro`.

## Notes / gotchas
- Default password in `config.env` is for a local lab VM only; change it (and the autologon is limited to 3 logons).
- The "Press any key to boot from CD" prompt is handled by tapping space for 20 s after start. Do not tap longer: it hits Setup's Cancel dialog and stalls the install (dismiss with Enter).
- Build log in guest: `C:\setup-tools.log`. Re-run tools by running `setup-tools.ps1` from the config CD.
- Bilterm Windows build: `ssh` in, clone repo, `cargo build --release` (native MSVC) — then `scripts/build-release-mac-win.sh --windows`.
