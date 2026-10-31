# Provisioning deep-dive

## Answer file (`autounattend.xml.tmpl`)
| Pass | What it does |
|---|---|
| windowsPE | Loads virtio drivers from `E:\amd64\w11`, `F:\...`, `D:\...` (libvirt) and `D:`-`F:\drivers` (Parallels virtio-net); en-US locale; sets `LabConfig` BypassTPM/SecureBoot/RAM checks; wipes disk 0 and creates EFI 300 MB (FAT32), MSR 16 MB, Windows NTFS `C:` (rest); installs image `@@EDITION@@` to partition 3; accepts EULA, no product key |
| specialize | `ComputerName` = `@@VMNAME@@`; copies `setup-tools.ps1` + `authorized_keys` to `C:\win-devvm` (Parallels disconnects the install media once its Tools are installed, so the CD is gone by first logon); disables automatic BitLocker; installs the Parallels toolgate driver (reboot `@@TG_REBOOT@@`: `Always` on Parallels) and runs the Parallels Tools installer — each Parallels step is a no-op when its files are absent |
| oobeSystem | en-US locale (no region/keyboard pages); hides EULA, OEM, online-account and local-account screens (no deprecated `SkipMachineOOBE`/`SkipUserOOBE`: with them OOBE showed the license page anyway); creates local admin `@@USER@@` (plaintext password); autologon for 10 logons; `FirstLogonCommands` runs `C:\win-devvm\setup-tools.ps1`, falling back to the first of D-H that has it |

All components use `processorArchitecture="@@ARCH@@"` (`amd64` / `arm64`).

`DiskConfiguration.WillShowUI` is `OnError`, so a disk problem surfaces in the UI instead of failing silently.

## `setup-tools.ps1`
Runs as `$ADMIN_USER`, transcript to `C:\setup-tools.log`, `ErrorActionPreference=Continue` so one failing step doesn't abort the rest. It copies itself to `C:\win-devvm\` and registers a logon task (`win-devvm-setup`) so a reboot mid-setup resumes it; the task is removed on success. Native architecture comes from the registry (not `$env:PROCESSOR_ARCHITECTURE`, which says AMD64 in emulated processes).

| Step | Detail |
|---|---|
| Network wait | Up to 60 x 5 s for TCP 443 to 1.1.1.1 |
| Guest tools | libvirt: `virtio-win-guest-tools.exe /install /quiet /norestart` from D-G. Parallels: Tools already installed in specialize; only logged |
| OpenSSH | Installs capability, auto-start, default shell = Windows PowerShell, firewall rule for 22, copies `authorized_keys` to `C:\ProgramData\ssh\administrators_authorized_keys` with ACL limited to Administrators/SYSTEM |
| RDP | Enables Terminal Server connections and firewall group |
| Power | Never sleep / blank monitor on AC |
| Defender | Excludes `%USERPROFILE%` from real-time scanning (lab VM; makes cargo builds much faster) |
| winget | Registers App Installer if needed and waits up to 5 min. Required: Git, VS 2022 Build Tools (VCTools workload + `VC.Tools.ARM64` + `VC.Tools.x86.x64`). Optional (warn only, `C:\setup-tools.warn`): PowerShell, Python 3.12, Node LTS, Windows Terminal, 7-Zip, GitHub CLI, CMake, Neovim. Exit `-1978335189` (already installed) is not a failure |
| Rust | `rustup-init.exe` for the native host triple (`aarch64-` or `x86_64-pc-windows-msvc`), stable + rustfmt + clippy; adds the other Windows target |
| Result | Failures collected; `C:\setup-tools.failed` if any, else `C:\setup-tools.done`, the logon task is removed and `sshd` restarted (so SSH sessions see the new PATH). `sshd` and `rustc` presence are always verified |
