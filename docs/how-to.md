# How-to

## Recipes
**Run a command in the guest**
```
./vm.sh ssh 'rustc --version'
```
**Copy files**
```
scp -i ~/.ssh/id_windevvm -P 2222 file dev@127.0.0.1:C:/Users/dev/
```
**Different size / ports**
```
VM_RAM_MB=8192 VM_VCPUS=4 SSH_PORT=2223 RDP_PORT=3391 ./provision.sh
```
(use the same variables with `vm.sh`)

**Rebuild from scratch**: `./provision.sh --force`.

**Re-run tool setup**: in the guest, `powershell -ExecutionPolicy Bypass -File D:\setup-tools.ps1` (adjust drive letter to the CD labelled `WINCONFIG`). The script is idempotent and removes `.done` first.

**Add a package**: append its winget id to `$pkgs` in `setup-tools.ps1`; for new VMs only, or rerun as above.

**Scripted/CI use**: `provision.sh` returns once the VM starts, not when it is ready. Poll:
```
until ./vm.sh status 2>/dev/null | grep -q 'tools: DONE'; do sleep 30; done
```
Also check for `C:\setup-tools.failed` to avoid waiting forever:
`./vm.sh ssh 'Test-Path C:\setup-tools.failed'`.

**Windows release build (Bilterm)**: `ssh` in, clone, `cargo build --release`, then `scripts/build-release-mac-win.sh --windows`.

## Debugging
- Screen: `./vm.sh view` or VNC address from `virsh -c qemu:///session domdisplay win-devvm`.
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
| Autologon stops working | It is limited to 3 logons by design |
| Answer file rejected | Password or edition contains `<`, `>`, or `&amp;`-sensitive XML characters |
| Port already in use | Change `SSH_PORT` / `RDP_PORT` |
