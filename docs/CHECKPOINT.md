# Checkpoint — multi-OS guests (as of 2026-11-08)

Branch: `feat/multi-os-m0-m1` (off master `d8a7f48`). Not pushed. Plan: `docs/PLAN-multi-os.md`.

## Done
- **M0** tests/lint/CI: `tests/{contract,syntax,run}.sh`, `.shellcheckrc`, `.github/workflows/ci.yml` (ubuntu-latest, macos-14).
- **M1** guest layer: `GUEST` (default `windows11`), `guests/windows11/guest.env`, `lib/common.sh` (`esc`, `vm_slot`, `vm_mac`),
  per-guest settings read by `provision.sh`, `vm.sh`, `lib/libvirt.sh`, `lib/parallels.sh`. `WIN_*` names kept as aliases.
  Fixed `esc()` coupling and hardcoded virt-install path.
- Evidence: `bash tests/run.sh` passes on the merged branch (bash 5.3); M1 agent reported byte-identical `autounattend.xml`
  render for 3 input sets x 2 backends (not re-run by supervisor). Default VM_NAME/ports/MAC unchanged.

## NOT verified
- Real Windows provision on Linux (libvirt) and macOS (Parallels): `virt-install` args, optional TPM array, `hv_stop` via
  `GUEST_STOP_CMD`, `vm.sh status/wait` on a live guest, empty `BOOT_KEYS` loop.
- bash 3.2 (macOS) and the GitHub Actions workflow have never run.
- bilterm `scripts/build-windows-vm.sh` drives `vm.sh`; grep found no references to moved files, still re-check after merge.

## Decisions / findings
- `libvirt.sh`/`config.env` are this repo's files, not bilterm's. Only `bilterm/scripts/build-release-assets.sh` is a donor (M7).
- cvm is at `/home/bill/ecosystem/autonomous-ai/cvm`. Ubuntu-24.04-amd64-only agent sandbox: copy helpers, don't depend on it.
  Copy: SSH key/host pinning, `vm_make_seed_iso`, `vm_write_user_data`, `vm_download_base_image` (add checksum verify), kvm.sh overlay/shutdown.
- Linux/BSD guests via cloud images + `cidata` seed ISO; OpenBSD needs a separate autoinstall path (spike).

## Open questions for the user (unanswered)
1. OpenBSD in v1 or spike first? 2. macOS: Parallels only, or also QEMU+HVF (M5)? 3. Rename repo from `win-devvm`? 4. Publish prebuilt images or build locally?

## Next
1. User runs a real Windows provision on each host (M1 regression gate), pushes branch, confirms CI green on macos-14.
2. Start M2 (Ubuntu/Fedora x86_64 on libvirt): image fetch + checksum, cidata seed, `cloudimg` path in `hv_create`, POSIX ready probe.
3. Housekeeping: worktrees `.claude/worktrees/agent-*` and branches `worktree-agent-*` can be removed once this branch is merged. Suggest `/compact` before M2.
