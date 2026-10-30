# How-to

## Recipes
**Run a command in the guest**
```
./vm.sh ssh 'rustc --version'
```
**Copy files** (remote paths are relative to `C:\Users\dev`)
```
./vm.sh push ./file bt/file
./vm.sh pull bt/out.zip ./
```
**Different size / ports**
```
VM_RAM_MB=8192 VM_VCPUS=4 SSH_PORT=2223 RDP_PORT=3391 ./provision.sh
```
(use the same variables with `vm.sh`)

**Rebuild from scratch**: `./provision.sh --force`.

**Re-run tool setup**: in the guest, `Remove-Item C:\setup-tools.done; powershell -ExecutionPolicy Bypass -File C:\win-devvm\setup-tools.ps1`. The script is idempotent; until it succeeds it also re-runs at every logon (scheduled task `win-devvm-setup`).

**Add a package**: append its winget id to `$required` or `$optional` in `setup-tools.ps1`; for new VMs only, or rerun as above.

**Scripted/CI use**: `provision.sh` returns once the VM starts, not when it is ready. Block with `./vm.sh wait` (exit 0 = DONE, 1 = FAILED or `WAIT_TIMEOUT`).

**Windows release build (Bilterm)**: from the bilterm repo on the host, `scripts/build-windows-vm.sh vX.Y.Z --arch all --test [--upload]` (finds this checkout via `WIN_DEVVM_DIR`, default `../win-devvm`).

## Debugging
- Screen: `./vm.sh view` (Parallels window, or virt-viewer) or VNC address from `virsh -c qemu:///session domdisplay win-devvm`.
- Parallels host log: `grep win-devvm /Library/Logs/parallels.log`; per-VM log in `~/Parallels/win-devvm.pvm/parallels.log`.
- Guest log: `./vm.sh ssh 'Get-Content C:\setup-tools.log -Tail 50'`.
- Domain state: `virsh -c qemu:///session domstate win-devvm`.

## Troubleshooting
| Symptom | Cause / fix |
|---|---|
| `missing: <iso>` | Set `WIN_ISO` / `VIRTIO_ISO` |
| `/dev/kvm not accessible` | Add your user to the `kvm` group; re-login |
| `VM ... exists` | Use `--force` or `./vm.sh destroy` |
| Stuck at "Press any key" | Tap a key in `view` within the first seconds, or `--force` and retry |
| Install stalls at Setup's Cancel dialog | Key taps ran too long; press Enter |
| Setup says no image / edition error | `WIN_EDITION` doesn't match the ISO's image names |
| No disk found in Setup | virtio ISO missing/unreadable; driver paths are `E:`, `F:`, `D:` `\amd64\w11` |
| `ssh: not reachable yet` | Install or tool setup still running; sshd is installed by `setup-tools.ps1` |
| `tools: installing` forever / `.failed` exists | Read `C:\setup-tools.log`; no network (script waits 5 min), winget unavailable, or a package failed |
| Autologon stops working | It is limited to 10 logons by design (enough for setup's reboots) |
| Parallels: VM registered but not started | Something ran `prlctl register` first, or a Parallels dialog is open; dismiss it and `./vm.sh start` |
| Parallels: `no DHCP lease for win-devvm yet` | Windows still installing, or the virtio-net driver didn't load (check `\drivers` on the media) |
| Parallels: `missing Parallels payload` | Parallels Desktop not in `PRL_APP`, or a Parallels release moved `Contents/Resources/Tools` |
| Answer file rejected | Password or edition contains `<`, `>`, or `&amp;`-sensitive XML characters |
| Port already in use | Change `SSH_PORT` / `RDP_PORT` |
