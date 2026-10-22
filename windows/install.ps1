param([ValidatePattern('^[a-p]{32}$')][string]$ExtensionId, [string]$FromFile)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($FromFile) {
    if ($ExtensionId) { throw 'Choose an extension ID or an ID file, not both.' }
    $ExtensionId = [IO.File]::ReadAllText([IO.Path]::GetFullPath($FromFile)).Trim()
}
if ($ExtensionId -cnotmatch '^[a-p]{32}$') { throw 'A valid 32-letter Chrome extension ID is required.' }
$dest = Join-Path $env:LOCALAPPDATA 'DeskAssit'
New-Item -ItemType Directory -Path $dest -Force | Out-Null
# Restrict connector configuration to the current user and SYSTEM.
$acl = New-Object Security.AccessControl.DirectorySecurity
$acl.SetAccessRuleProtection($true, $false)
$user = [Security.Principal.WindowsIdentity]::GetCurrent().User
$rule = New-Object Security.AccessControl.FileSystemAccessRule($user, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
$acl.AddAccessRule($rule)
$system = New-Object Security.Principal.SecurityIdentifier('S-1-5-18')
$acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($system, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')))
Set-Acl -LiteralPath $dest -AclObject $acl
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'host.ps1') -Destination (Join-Path $dest 'host.ps1') -Force
[IO.File]::WriteAllText((Join-Path $dest 'allowed-extension.txt'), $ExtensionId)
$launcher = '@echo off' + "`r`n" + '"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File "%~dp0host.ps1" -Origin %1' + "`r`n"
[IO.File]::WriteAllText((Join-Path $dest 'host.cmd'), $launcher, [Text.Encoding]::Default)
$manifestPath = Join-Path $dest 'com.deskassit.desktop.json'
$manifest = @{name='com.deskassit.desktop';description='GentleDesk optional desktop connector';path=(Join-Path $dest 'host.cmd');type='stdio';allowed_origins=@("chrome-extension://$ExtensionId/")}
$utf8 = New-Object Text.UTF8Encoding($false)
[IO.File]::WriteAllText($manifestPath, (ConvertTo-Json $manifest), $utf8)
$key = 'HKCU:\Software\Google\Chrome\NativeMessagingHosts\com.deskassit.desktop'
New-Item -Path $key -Force | Out-Null
Set-Item -Path $key -Value $manifestPath
Write-Output 'GentleDesk 本机辅助程序已安装。返回扩展，点击“授权并选择桌面”。'
