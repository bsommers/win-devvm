# Plan: multi-OS guests (Linux/BSD) on macOS ARM64 and Linux x86_64

Status legend: [ ] todo · [~] in progress · [x] done

## Findings that shape the plan

- win-devvm already has a clean `hv_*` lifecycle contract (11 functions), but **no guest-OS abstraction**:
  `provision.sh`, `hv_create`, `vm.sh` (`tools_state`, `stop`) and `config.env` names are Windows-hardcoded.
- No tests or CI exist.
- bilterm does **not** hold `libvirt.sh` / `config.env`; those are this repo's own files. Only
  `bilterm/scripts/build-release-assets.sh` is a donor (checksum-merge + `gh release upload --clobber` pattern).
- cvm lives at `/home/bill/ecosystem/autonomous-ai/cvm` (not `~/src/projects/cvm`). It is an AI-agent sandbox runner,
  Ubuntu 24.04 amd64 only, with no Fedora/BSD, no checksum verification, no aarch64 QEMU. **Do not depend on it; copy
  selected helpers** (Apache-2.0).
- Strategy: Linux/BSD guests use **cloud images + a `cidata` seed ISO** (skips installers). OpenBSD has no official
  cloud image and needs a separate path (autoinstall `install.conf` / custom media).

## What to borrow vs. extend

| Need | Source | Action |
|---|---|---|
| SSH key + host-key pinning, `vm_poll_ssh`, `vm_wait_for_cloud_init`, random port | cvm `lib/backends/common.sh` | Copy, remove `ubuntu` user hardcode |
| Seed ISO (`cidata`), user-data/meta-data writers | cvm `common.sh` (`vm_make_seed_iso`, `vm_write_user_data`) | Copy; generalize per guest |
| Image download | cvm `vm_download_base_image` | Copy and **add sha256/GPG verification** (cvm lacks it) |
| qcow2 overlay on a prepared base, clean shutdown | cvm `lib/backends/kvm.sh` | Adapt; add `qemu-system-aarch64` + HVF + AAVMF/edk2 |
| Capability-gated backend dispatch + contract test | cvm `backends.sh`, `test_backend_contract.bats` | Copy the pattern for `hv_*` |
| Lint/test layout, bash 3.2 discipline | cvm `tests/` | Copy (macOS ships bash 3.2) |
| Release publishing for images | bilterm `build-release-assets.sh` | Adapt checksum-merge + upload; drop cargo/zig |
| Rootless libvirt user-net, hostfwd, UEFI | win-devvm `lib/libvirt.sh` | Extend; parameterize Windows bits |
| Parallels | win-devvm `lib/parallels.sh` | Extend only for Linux ARM64 (new pvs template, no remaster) |
| Registry, snapshots, fleet, vault, MCP, daemon | cvm | **Do not borrow** |

Not worth reusing: cvm's agent/auth/mesh layers, its Ubuntu-only install hash, bhyve/firecracker/etc. backends.

## Milestones

### M0 — Safety net (before refactoring)
- [~] Add shellcheck + plain-bash smoke suite (done); CI workflow written but NOT yet run on GitHub
- [x] Contract test: each `lib/<hv>.sh` defines all `hv_*` functions
- [x] Fix hidden coupling: `esc()` used by `parallels.sh:243` but defined in `provision.sh:10`
- [x] Remove hardcoded `/usr/bin/python3 /usr/bin/virt-install` in `libvirt.sh:23`

### M1 — Guest abstraction (no new OS yet; Windows must keep working)
- [x] Introduce `GUEST` (default `windows11`) and `guests/<name>/` dirs: answer/seed templates, post-install script, `guest.env`
- [x] `guest.env` fields: `OS_VARIANT`, `ARCH`, `NEED_TPM`, `CONFIG_LABEL`, `BOOT_KEYS`, `SSH_USER`, `READY_CMD`, `STOP_CMD`, `IMAGE_KIND` (iso|cloudimg)
- [x] Move Windows specifics into `guests/windows11/` (autounattend, `setup-tools.ps1`, `tools_state`, `shutdown /s`)
- [x] Parameterize `hv_create` / `provision.sh` / `vm.sh` (`tools_state`, `hv_stop`, banner)
- [x] Rename `WIN_*` vars with back-compat aliases; per-VM MAC and ports (current fixed MAC/`SSH_PORT` prevent 2 VMs)
- [ ] Regression: Windows 11 provision still green on both hosts (NOT run: needs real VM on each host)

### M2 — Linux x86_64 guests on Linux host (libvirt)
- [ ] Image fetcher with checksum verification + cache (`~/.cache/win-devvm/images`)
- [ ] `cidata` seed builder (copy from cvm), cloud-init user-data with ssh key + dev-tool runcmd
- [ ] `cloudimg` path in `hv_create`: qcow2 overlay, virtio, no TPM, `--osinfo` from `guest.env`
- [ ] Guests: `ubuntu` (24.04), `fedora` (Cloud Base), optional `debian`
- [ ] `vm.sh`: POSIX ready-probe (`cloud-init status --wait`), `shutdown -h now`

### M3 — BSD guests on Linux host
- [ ] `freebsd`: BASIC-CLOUDINIT image + seed (nuageinit/cloud-init); `shutdown -p now`
- [ ] `openbsd`: no cloud image — spike: `install.conf` autoinstall via HTTP/`siteXX` on bootable media; decide scope after spike
- [ ] Verify virtio-net/blk, UEFI boot, serial console fallback

### M4 — Linux ARM64 guests on macOS (Parallels)
- [ ] New `parallels/config-linux.pvs.tmpl` (no TPM/SATA-Windows hardware); no ISO remaster for cloud images
- [ ] Convert qcow2 -> raw/hdd for Parallels; seed ISO attach
- [ ] Guests: `ubuntu-arm64`, `fedora-arm64`
- [ ] Note: Standard edition `prlctl` limits already handled by `open`/SSH/signals approach

### M5 — Alternate macOS backend: QEMU+HVF (optional)
- [ ] `lib/qemu-hvf.sh`: `qemu-system-aarch64`, HVF, edk2 AAVMF, user-net hostfwd; avoids Parallels licensing
- [ ] Reuse cvm `kvm.sh` command-line shape
- [ ] Also enables aarch64 guests on Linux hosts (TCG/KVM on ARM)

### M6 — Dev tooling provisioning
- [ ] Per-guest `post-install` (apt/dnf/pkg_add): git, build tools, rustup, node, docker/podman, editors
- [ ] Shared package-set manifests (`tools/*.list`) instead of inline lists
- [ ] Idempotent with completion markers analogous to `C:\setup-tools.done`

### M7 — Release/distribution
- [ ] `scripts/build-release-assets.sh` adapted from bilterm: publish prepared images/provisioning bundle, `SHA256SUMS` merge, `gh release upload --clobber`
- [ ] Docs: update README, `docs/architecture.md` (contract + guest layer), how-to per guest

## Open decisions (need your call)
1. OpenBSD scope: spike first, or drop from v1?
2. macOS: Parallels only, or also build the QEMU+HVF backend (M5)?
3. Keep repo name `win-devvm`, or rename once non-Windows guests land?
4. Prebuilt images published in releases (M7), or always build locally?

## Suggested order
M0 → M1 → M2 → M4 (high value: Ubuntu/Fedora ARM on Mac) → M3 → M6 → M7 → M5.
Delegate mechanical edits (renames, fetchers, lint fixes) to haiku subagents; integration (M1, M4) to sonnet.
