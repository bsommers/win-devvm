# Provisioning deep-dive

## Answer file (`autounattend.xml.tmpl`)
| Pass | What it does |
|---|---|
| windowsPE | Loads virtio drivers from `E:\amd64\w11`, `F:\...`, `D:\...`; en-US locale; sets `LabConfig` BypassTPM/SecureBoot/RAM checks; wipes disk 0 and creates EFI 300 MB (FAT32), MSR 16 MB, Windows NTFS `C:` (rest); installs image `@@EDITION@@` to partition 3; accepts EULA, no product key |
| specialize | `ComputerName` = `@@VMNAME@@` |
| oobeSystem | Skips OOBE/online account screens; creates local admin `@@USER@@` (plaintext password); autologon for 3 logons; `FirstLogonCommands` runs `setup-tools.ps1` from the first of D-H that has it |

`DiskConfiguration.WillShowUI` is `OnError`, so a disk problem surfaces in the UI instead of failing silently.

## `setup-tools.ps1`
Runs as `$ADMIN_USER`, transcript to `C:\setup-tools.log`, `ErrorActionPreference=Continue` so one failing step doesn't abort the rest.

| Step | Detail |
|---|---|
| Network wait | Up to 60 x 5 s for TCP 443 to 1.1.1.1 |
| virtio guest tools | `virtio-win-guest-tools.exe /install /quiet /norestart` from D-G |
| OpenSSH | Installs capability, auto-start, default shell = Windows PowerShell, firewall rule for 22, copies `authorized_keys` to `C:\ProgramData\ssh\administrators_authorized_keys` with ACL limited to Administrators/SYSTEM |
| RDP | Enables Terminal Server connections and firewall group |
| Power | Never sleep / blank monitor on AC |
| winget | Git, rustup, VS 2022 Build Tools (VCTools workload), PowerShell, Python 3.12, Node LTS, Windows Terminal, 7-Zip, GitHub CLI, CMake, Neovim. Exit `-1978335189` (already installed / no upgrade) is not a failure. Waits 60 s for winget to appear |
| Rust | `stable-x86_64-pc-windows-msvc` default; adds `aarch64-pc-windows-msvc` target |
| Result | Failures collected; `C:\setup-tools.failed` if any, else `C:\setup-tools.done`. `sshd` and `rustc` presence are always verified |
