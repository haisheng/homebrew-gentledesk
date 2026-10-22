$ErrorActionPreference = 'Stop'
$key = 'HKCU:\Software\Google\Chrome\NativeMessagingHosts\com.deskassit.desktop'
if (Test-Path $key) { Remove-Item -Path $key -Recurse }
$dest = Join-Path $env:LOCALAPPDATA 'DeskAssit'
foreach ($name in @('host.ps1','host.cmd','selection.json','search-folders.json','allowed-extension.txt','com.deskassit.desktop.json')) {
    $path = Join-Path $dest $name
    if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path }
}
if ((Test-Path -LiteralPath $dest) -and @(Get-ChildItem -LiteralPath $dest -Force).Count -eq 0) { Remove-Item -LiteralPath $dest }
Write-Output 'GentleDesk 本机连接和目录记录已移除。桌面原文件未被改动。'
