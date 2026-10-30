# Runs inside the guest at first logon (run from the config ISO by FirstLogonCommands).
# Idempotent; logs to C:\setup-tools.log. Installs virtio guest tools, OpenSSH, RDP, and a Rust/MSVC dev toolchain.
$ErrorActionPreference = 'Continue'
Remove-Item C:\setup-tools.done -ErrorAction SilentlyContinue
$script:failed = @()
Start-Transcript -Path C:\setup-tools.log -Append
function Step($m) { Write-Host "`n=== $m ===" }

Step 'wait for network'
for ($i=0; $i -lt 60; $i++) { if (Test-NetConnection 1.1.1.1 -Port 443 -WarningAction SilentlyContinue -InformationLevel Quiet) { break }; Start-Sleep 5 }

Step 'virtio guest tools (drivers, qemu-ga, spice agent)'
foreach ($d in 'D','E','F','G') {
  $p = "${d}:\virtio-win-guest-tools.exe"
  if (Test-Path $p) { Start-Process $p -ArgumentList '/install','/quiet','/norestart' -Wait; break }
}

Step 'OpenSSH server'
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0 | Out-Null
Set-Service sshd -StartupType Automatic; Start-Service sshd
New-ItemProperty HKLM:\SOFTWARE\OpenSSH -Name DefaultShell -Value 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -PropertyType String -Force | Out-Null
if (-not (Get-NetFirewallRule -Name sshd -ErrorAction SilentlyContinue)) {
  New-NetFirewallRule -Name sshd -DisplayName 'OpenSSH' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 | Out-Null }
# authorized_keys for admin users lives in ProgramData; host provision.sh drops host key onto the ISO as authorized_keys
foreach ($d in 'D','E','F','G') {
  $k = "${d}:\authorized_keys"
  if (Test-Path $k) {
    Copy-Item $k C:\ProgramData\ssh\administrators_authorized_keys -Force
    icacls C:\ProgramData\ssh\administrators_authorized_keys /inheritance:r /grant 'Administrators:F' 'SYSTEM:F' | Out-Null; break }
}

Step 'Remote Desktop'
Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' fDenyTSConnections 0
Enable-NetFirewallRule -DisplayGroup 'Remote Desktop'

Step 'power: never sleep'
powercfg /change standby-timeout-ac 0; powercfg /change monitor-timeout-ac 0

Step 'winget dev tools'
$winget = (Get-Command winget -ErrorAction SilentlyContinue)
if (-not $winget) { Start-Sleep 60; $winget = Get-Command winget -ErrorAction SilentlyContinue }
if ($winget) {
  $pkgs = 'Git.Git','Rustlang.Rustup','Microsoft.VisualStudio.2022.BuildTools','Microsoft.PowerShell',
          'Python.Python.3.12','OpenJS.NodeJS.LTS','Microsoft.WindowsTerminal','7zip.7zip','GitHub.cli','Kitware.CMake','Neovim.Neovim'
  foreach ($p in $pkgs) {
    Step "winget $p"
    $extra = @()
    if ($p -like '*BuildTools') { $extra = '--override','--quiet --wait --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended' }
    winget install -e --id $p --silent --accept-package-agreements --accept-source-agreements @extra
    if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne -1978335189) { $script:failed += $p }
  }
} else { Write-Warning 'winget unavailable; rerun setup-tools.ps1 from the config CD once networking is up.' }

Step 'rust toolchain'
$env:Path += ";$env:USERPROFILE\.cargo\bin"
if (Get-Command rustup -ErrorAction SilentlyContinue) {
  rustup default stable-x86_64-pc-windows-msvc
  rustup target add aarch64-pc-windows-msvc
}
if (-not (Get-Service sshd -ErrorAction SilentlyContinue)) { $script:failed += 'sshd' }
if (-not (Get-Command rustc -ErrorAction SilentlyContinue)) { $script:failed += 'rustc' }
if ($script:failed) { Write-Warning "FAILED: $($script:failed -join ', ')"; Set-Content C:\setup-tools.failed ($script:failed -join ',') }
else { New-Item C:\setup-tools.done -ItemType File -Force | Out-Null }
Stop-Transcript
