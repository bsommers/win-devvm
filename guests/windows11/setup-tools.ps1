# Runs inside the guest at first logon (FirstLogonCommands, from the config media) and again at every logon
# (scheduled task) until it succeeds, so reboots during setup (e.g. by Parallels Tools) are survived.
# Idempotent; logs to C:\setup-tools.log. Installs guest tools, OpenSSH, RDP, and a Rust/MSVC dev toolchain
# for the guest's native architecture (x64 or ARM64) plus the other Windows target for cross builds.
$ErrorActionPreference = 'Continue'
$self = 'C:\win-devvm\setup-tools.ps1'
New-Item C:\win-devvm -ItemType Directory -Force | Out-Null
if ($PSCommandPath -and $PSCommandPath -ne $self) { Copy-Item $PSCommandPath $self -Force }
if (Test-Path C:\setup-tools.done) { exit 0 }
Remove-Item C:\setup-tools.failed, C:\setup-tools.warn -ErrorAction SilentlyContinue
$script:failed = @(); $script:warned = @()
Start-Transcript -Path C:\setup-tools.log -Append
function Step($m) { Write-Host "`n=== $m === $(Get-Date -Format s)" }

Step 'resume-at-logon task'
if (-not (Get-ScheduledTask -TaskName win-devvm-setup -ErrorAction SilentlyContinue)) {
  $a = New-ScheduledTaskAction -Execute powershell.exe -Argument "-NoProfile -ExecutionPolicy Bypass -File $self"
  $t = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
  $p = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest
  Register-ScheduledTask -TaskName win-devvm-setup -Action $a -Trigger $t -Principal $p -Force | Out-Null
}

# Native arch from the registry: $env:PROCESSOR_ARCHITECTURE lies inside an x64-emulated process on ARM64.
$arch = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment').PROCESSOR_ARCHITECTURE
$arm64 = $arch -eq 'ARM64'
# Payload dir: C:\win-devvm (staged in specialize; Parallels detaches the media) or the config media itself.
$media = @('C:\win-devvm\') + (Get-PSDrive -PSProvider FileSystem | ForEach-Object Root) |
         Where-Object { Test-Path (Join-Path $_ 'authorized_keys') } | Select-Object -First 1
Write-Host "arch=$arch config-media=$media"

Step 'wait for network'
for ($i=0; $i -lt 60; $i++) { if (Test-NetConnection 1.1.1.1 -Port 443 -WarningAction SilentlyContinue -InformationLevel Quiet) { break }; Start-Sleep 5 }

Step 'guest tools'
foreach ($d in 'D','E','F','G') {   # libvirt: virtio guest tools (drivers, qemu-ga, spice agent)
  $p = "${d}:\virtio-win-guest-tools.exe"
  if (Test-Path $p) { Start-Process $p -ArgumentList '/install','/quiet','/norestart' -Wait; break }
}
if (Get-Service prl_tools -ErrorAction SilentlyContinue) { Write-Host 'Parallels Tools: installed' }   # installed in specialize

Step 'OpenSSH server'
if (-not (Get-Service sshd -ErrorAction SilentlyContinue)) { Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0 | Out-Null }
Set-Service sshd -StartupType Automatic; Start-Service sshd
New-ItemProperty HKLM:\SOFTWARE\OpenSSH -Name DefaultShell -Value 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -PropertyType String -Force | Out-Null
if (-not (Get-NetFirewallRule -Name sshd -ErrorAction SilentlyContinue)) {
  New-NetFirewallRule -Name sshd -DisplayName 'OpenSSH' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 | Out-Null }
# authorized_keys for admin users lives in ProgramData; provision.sh puts the host key on the config media
if ($media) {
  Copy-Item (Join-Path $media 'authorized_keys') C:\ProgramData\ssh\administrators_authorized_keys -Force
  icacls C:\ProgramData\ssh\administrators_authorized_keys /inheritance:r /grant 'Administrators:F' 'SYSTEM:F' | Out-Null
}

Step 'Remote Desktop'
Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' fDenyTSConnections 0
Enable-NetFirewallRule -DisplayGroup 'Remote Desktop'

Step 'power: never sleep'
powercfg /change standby-timeout-ac 0; powercfg /change monitor-timeout-ac 0

Step 'Defender: exclude the dev profile (lab VM; large speedup for cargo builds)'
Add-MpPreference -ExclusionPath $env:USERPROFILE -ErrorAction SilentlyContinue

Step 'winget'
$winget = Get-Command winget -ErrorAction SilentlyContinue
for ($i=0; -not $winget -and $i -lt 30; $i++) {
  # A fresh install registers App Installer lazily; nudge it, then poll.
  if ($i -eq 0) { Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe -ErrorAction SilentlyContinue }
  Start-Sleep 10; $winget = Get-Command winget -ErrorAction SilentlyContinue
}
if ($winget) {
  # Required packages gate C:\setup-tools.done; optional ones only warn (not every package ships ARM64 builds).
  $required = 'Git.Git','Microsoft.VisualStudio.2022.BuildTools'
  $optional = 'Microsoft.PowerShell','Python.Python.3.12','OpenJS.NodeJS.LTS','Microsoft.WindowsTerminal',
              '7zip.7zip','GitHub.cli','Kitware.CMake','Neovim.Neovim'
  foreach ($p in $required + $optional) {
    Step "winget $p"
    $extra = @()
    if ($p -like '*BuildTools') {   # ARM64 + x64 MSVC toolsets so either Windows target builds on either host
      $extra = '--override','--quiet --wait --norestart --add Microsoft.VisualStudio.Workload.VCTools --add Microsoft.VisualStudio.Component.VC.Tools.ARM64 --add Microsoft.VisualStudio.Component.VC.Tools.x86.x64 --includeRecommended' }
    # --source winget: a failing msstore source (e.g. 0x8a15005e cert mismatch on fresh installs) otherwise aborts every install
    winget install -e --id $p --source winget --silent --accept-package-agreements --accept-source-agreements @extra
    $rc = $LASTEXITCODE
    if ($rc -ne 0 -and $rc -ne -1978335189) {   # -1978335189: already installed
      # Some installers report success with a non-zero code (e.g. restart required): trust what is installed.
      winget list -e --id $p --source winget --accept-source-agreements | Out-Null
      if ($LASTEXITCODE -eq 0) { Write-Host "winget exit $rc for $p, but it is installed" }
      elseif ($required -contains $p) { $script:failed += $p } else { $script:warned += $p } }
  }
} else { Write-Warning 'winget unavailable'; $script:failed += 'winget' }

Step 'rust toolchain'
$cargoBin = "$env:USERPROFILE\.cargo\bin"
$env:Path += ";$cargoBin"
$hostTriple  = if ($arm64) { 'aarch64-pc-windows-msvc' } else { 'x86_64-pc-windows-msvc' }
$otherTriple = if ($arm64) { 'x86_64-pc-windows-msvc' } else { 'aarch64-pc-windows-msvc' }
if (-not (Get-Command rustup -ErrorAction SilentlyContinue)) {
  $init = "$env:TEMP\rustup-init.exe"
  Invoke-WebRequest "https://static.rust-lang.org/rustup/dist/$hostTriple/rustup-init.exe" -OutFile $init -UseBasicParsing
  & $init -y --default-host $hostTriple --default-toolchain stable --profile minimal -c rustfmt -c clippy
}
if (Get-Command rustup -ErrorAction SilentlyContinue) { rustup target add $otherTriple }

if (-not (Get-Service sshd -ErrorAction SilentlyContinue)) { $script:failed += 'sshd' }
if (-not (Get-Command rustc -ErrorAction SilentlyContinue)) { $script:failed += 'rustc' }
if ($script:warned) { Write-Warning "optional packages failed: $($script:warned -join ', ')"; Set-Content C:\setup-tools.warn ($script:warned -join ',') }
if ($script:failed) { Write-Warning "FAILED: $($script:failed -join ', ')"; Set-Content C:\setup-tools.failed ($script:failed -join ',') }
else {
  Unregister-ScheduledTask -TaskName win-devvm-setup -Confirm:$false -ErrorAction SilentlyContinue
  New-Item C:\setup-tools.done -ItemType File -Force | Out-Null
}
Stop-Transcript
# New SSH sessions must pick up the PATH entries added by Git / rustup. Restarting sshd kills the
# session we may be running in, so do it last, and from a detached process when inside SSH.
if (-not $script:failed) {
  if ($env:SSH_CONNECTION) { Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-Command','Start-Sleep 5; Restart-Service sshd' }
  else { Restart-Service sshd }
}
