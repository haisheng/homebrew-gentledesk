param([string]$Origin = '', [switch]$SelfTest)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$InstallDir = Join-Path $env:LOCALAPPDATA 'DeskAssit'
$SelectionFile = Join-Path $InstallDir 'selection.json'
$SearchSelectionFile = Join-Path $InstallDir 'search-folders.json'
$Utf8 = New-Object System.Text.UTF8Encoding($false)

function Get-ItemId([string]$Path) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Utf8.GetBytes([IO.Path]::GetFullPath($Path).ToLowerInvariant())))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}
function Get-Children([string]$Root) {
    if (-not [IO.Directory]::Exists($Root)) { throw '已选择的桌面不可访问，请重新选择。' }
    return @(Get-ChildItem -LiteralPath $Root -ErrorAction Stop | Where-Object { -not ($_.Attributes -band [IO.FileAttributes]::Hidden) } | Sort-Object Name | Select-Object -First 250)
}
function Get-IconData([string]$Path) {
    try {
        if ([IO.Directory]::Exists($Path)) { return '' }
        Add-Type -AssemblyName System.Drawing
        $ico = [Drawing.Icon]::ExtractAssociatedIcon($Path)
        if ($null -eq $ico) { return '' }
        $bitmap = $ico.ToBitmap()
        $stream = New-Object IO.MemoryStream
        try {
            $bitmap.Save($stream, [Drawing.Imaging.ImageFormat]::Png)
            $bytes = $stream.ToArray()
            if ($bytes.Length -gt 6000) { return '' }
            return 'data:image/png;base64,' + [Convert]::ToBase64String($bytes)
        } finally { $stream.Dispose(); $bitmap.Dispose(); $ico.Dispose() }
    } catch { return '' }
}
function Get-Inventory([string]$Root, [bool]$IncludeIcons = $true) {
    $items = @()
    foreach ($file in @(Get-Children $Root)) {
        $name = $file.Name
        $kind = 'file'
        if ($file.PSIsContainer) { $kind = 'folder' }
        elseif ($file.Extension -in @('.lnk', '.exe')) { $kind = 'app'; $name = [IO.Path]::GetFileNameWithoutExtension($name) }
        elseif ($file.Extension -eq '.url') { $name = [IO.Path]::GetFileNameWithoutExtension($name) }
        $image = ''
        if ($IncludeIcons) { $image = Get-IconData $file.FullName }
        $items += @{ id = Get-ItemId $file.FullName; name = $name; kind = $kind; icon = $image }
    }
    if ($Utf8.GetByteCount((ConvertTo-Json -InputObject @($items) -Depth 6 -Compress)) -gt 850000) { foreach ($item in $items) { $item.icon = '' } }
    return $items
}
function Resolve-Item([string]$Id, [string]$Root) {
    if ($Id -notmatch '^[a-f0-9]{64}$') { throw '无效的本地入口。' }
    foreach ($file in @(Get-Children $Root)) { if ((Get-ItemId $file.FullName) -eq $Id) { return $file.FullName } }
    throw '项目已移动或删除，请重新同步。'
}
function Read-Selection {
    if (-not [IO.File]::Exists($SelectionFile)) { throw '尚未选择桌面，请在连接向导中重新选择。' }
    $config = [IO.File]::ReadAllText($SelectionFile, $Utf8) | ConvertFrom-Json
    if (-not [IO.Path]::IsPathRooted([string]$config.path)) { throw '桌面配置无效。' }
    return [string]$config.path
}
function Get-SearchRoots {
    $roots = @()
    foreach ($menu in @([Environment]::GetFolderPath('Programs'), [Environment]::GetFolderPath('CommonPrograms'))) {
        if ([IO.Directory]::Exists($menu)) { $roots += @{path = [IO.Path]::GetFullPath($menu); apps = $true} }
    }
    if ([IO.File]::Exists($SearchSelectionFile)) {
        foreach ($entry in @([IO.File]::ReadAllText($SearchSelectionFile, $Utf8) | ConvertFrom-Json) | Select-Object -First 5) {
            if ([IO.Path]::IsPathRooted([string]$entry.path)) { $roots += @{path = [IO.Path]::GetFullPath([string]$entry.path); apps = $false} }
        }
    }
    return $roots
}
function Test-InSearchRoot([string]$Path, [string]$Root) {
    $full = [IO.Path]::GetFullPath($Path)
    $base = [IO.Path]::GetFullPath($Root).TrimEnd('\')
    return $full.Equals($base, [StringComparison]::OrdinalIgnoreCase) -or $full.StartsWith($base + '\', [StringComparison]::OrdinalIgnoreCase)
}
function Test-SafeSearchPath([string]$Path) {
    # Reject junctions/symlinks in the entire ancestor chain, including a replaced selection root.
    $cursor = [IO.Path]::GetFullPath($Path)
    while ($cursor) {
        $attributes = [IO.File]::GetAttributes($cursor)
        if (($attributes -band [IO.FileAttributes]::ReparsePoint)) { return $false }
        $parent = [IO.Path]::GetDirectoryName($cursor)
        if ($parent -eq $cursor) { break }; $cursor = $parent
    }
    return $true
}
function Find-LocalItems([string]$Query, $Roots) {
    if ($Query.Length -gt 100 -or [string]::IsNullOrWhiteSpace($Query)) { return @() }
    $words = @($Query.Trim() -split '\s+')
    $items = @(); $seen = @{}; $visited = 0
    $clock = [Diagnostics.Stopwatch]::StartNew()
    foreach ($root in $Roots) {
        if (-not [IO.Directory]::Exists($root.path) -or -not (Test-SafeSearchPath $root.path)) { continue }
        $pending = New-Object 'Collections.Generic.Stack[string]'
        $pending.Push($root.path)
        while ($pending.Count -gt 0) {
            $directory = $pending.Pop()
            foreach ($file in @(Get-ChildItem -LiteralPath $directory -ErrorAction SilentlyContinue | Select-Object -First 12001)) {
                $visited++
                if ($visited -gt 12000 -or $clock.ElapsedMilliseconds -gt 1500) { return $items }
                if (($file.Attributes -band [IO.FileAttributes]::Hidden) -or ($file.Attributes -band [IO.FileAttributes]::ReparsePoint)) { continue }
                if (-not (Test-InSearchRoot $file.FullName $root.path)) { continue }
                if ($file.PSIsContainer) { $pending.Push($file.FullName) }
                $isApp = -not $file.PSIsContainer -and $file.Extension.ToLowerInvariant() -in @('.lnk', '.exe', '.appref-ms')
                if ($root.apps -and -not $isApp) { continue }
                $name = $file.Name
                if ($isApp) { $name = [IO.Path]::GetFileNameWithoutExtension($name) }
                $matches = $true
                foreach ($word in $words) { if ($name.IndexOf($word, [StringComparison]::CurrentCultureIgnoreCase) -lt 0) { $matches = $false; break } }
                if (-not $matches -or $seen.ContainsKey($file.FullName)) { continue }
                $seen[$file.FullName] = $true
                $kind = 'file'; if ($isApp) { $kind = 'app' } elseif ($file.PSIsContainer) { $kind = 'folder' }
                $items += @{id = Get-ItemId $file.FullName; name = $name; kind = $kind; path = $file.FullName}
                if ($items.Count -ge 30) { return $items }
            }
        }
    }
    return $items
}
function Open-SearchItem($Request) {
    $path = [string]$Request.path
    if ($path.Length -gt 4096 -or -not [IO.Path]::IsPathRooted($path) -or (Get-ItemId $path) -cne [string]$Request.id) { throw 'Invalid search item' }
    $path = [IO.Path]::GetFullPath($path)
    if (-not (Test-SafeSearchPath $path)) { throw 'Unsafe search path' }
    $extension = [IO.Path]::GetExtension($path).ToLowerInvariant()
    $allowed = $false
    foreach ($root in @(Get-SearchRoots)) {
        if ((Test-InSearchRoot $path $root.path) -and (-not $root.apps -or $extension -in @('.lnk', '.exe', '.appref-ms'))) { $allowed = $true; break }
    }
    if (-not $allowed) { throw 'Outside search scope' }
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = $path; $start.UseShellExecute = $true
    [Diagnostics.Process]::Start($start) | Out-Null
    return @{ok = $true}
}
function Invoke-HostRequest($Request) {
    switch ([string]$Request.action) {
        'status' { return @{ok = $true; version = '1.3.0'; capabilities = @{search = $true; fill = $false; biometric = $false}} }
        'search.configure' {
            Add-Type -AssemblyName System.Windows.Forms
            $dialog = New-Object Windows.Forms.FolderBrowserDialog
            $dialog.Description = 'GentleDesk：搜索所选文件夹及子文件夹的名称和位置，以及开始菜单中的应用。不读正文，不上传结果。'
            $dialog.SelectedPath = [Environment]::GetFolderPath('DesktopDirectory'); $dialog.ShowNewFolderButton = $false
            try {
                if ($dialog.ShowDialog() -ne [Windows.Forms.DialogResult]::OK) { throw 'Cancelled' }
                $path = [IO.Path]::GetFullPath($dialog.SelectedPath)
                if (-not (Test-SafeSearchPath $path)) { throw 'Unsafe directory' }
                [IO.Directory]::CreateDirectory($InstallDir) | Out-Null
                [IO.File]::WriteAllText($SearchSelectionFile, (ConvertTo-Json -InputObject @(@{path = $path})), $Utf8)
                return @{ok = $true; folders = 1}
            } finally { $dialog.Dispose() }
        }
        'search' { return @{ok = $true; items = @(Find-LocalItems ([string]$Request.query) @(Get-SearchRoots))} }
        'search.open' { return Open-SearchItem $Request }
        'search.forget' { if ([IO.File]::Exists($SearchSelectionFile)) { [IO.File]::Delete($SearchSelectionFile) }; return @{ok = $true} }
        'configure' {
            Add-Type -AssemblyName System.Windows.Forms
            $dialog = New-Object Windows.Forms.FolderBrowserDialog
            $dialog.Description = 'GentleDesk：选择桌面文件夹。仅读取项目名称、类型、图标，不读取文档内容，不修改或删除文件。'
            $dialog.SelectedPath = [Environment]::GetFolderPath('DesktopDirectory')
            $dialog.ShowNewFolderButton = $false
            try {
                if ($dialog.ShowDialog() -ne [Windows.Forms.DialogResult]::OK) { throw '已取消选择，没有读取桌面。' }
                $root = [IO.Path]::GetFullPath($dialog.SelectedPath)
                $items = @(Get-Inventory $root)
                [IO.Directory]::CreateDirectory($InstallDir) | Out-Null
                [IO.File]::WriteAllText($SelectionFile, (ConvertTo-Json @{path = $root}), $Utf8)
                return @{ok = $true; items = $items}
            } finally { $dialog.Dispose() }
        }
        'scan' { return @{ok = $true; items = @(Get-Inventory (Read-Selection))} }
        'open' {
            $path = Resolve-Item ([string]$Request.id) (Read-Selection)
            # Use the system shell without constructing/interpreting a command string.
            $start = New-Object Diagnostics.ProcessStartInfo
            $start.FileName = $path
            $start.UseShellExecute = $true
            [Diagnostics.Process]::Start($start) | Out-Null
            return @{ok = $true}
        }
        'forget' { if ([IO.File]::Exists($SearchSelectionFile)) { [IO.File]::Delete($SearchSelectionFile) }; if ([IO.File]::Exists($SelectionFile)) { [IO.File]::Delete($SelectionFile) }; return @{ok = $true} }
        default { throw '不支持的操作。' }
    }
}
function Read-Exact([IO.Stream]$Stream, [int]$Count) {
    $bytes = New-Object byte[] $Count
    $offset = 0
    while ($offset -lt $Count) {
        $read = $Stream.Read($bytes, $offset, $Count - $offset)
        if ($read -eq 0) { if ($offset -eq 0) { return $null }; throw '消息被截断。' }
        $offset += $read
    }
    return ,$bytes
}
function Write-Message([IO.Stream]$Stream, $Message) {
    $bytes = $Utf8.GetBytes((ConvertTo-Json -InputObject $Message -Depth 8 -Compress))
    if ($bytes.Length -gt 1000000) { throw '结果过大。' }
    $header = [BitConverter]::GetBytes([uint32]$bytes.Length)
    $Stream.Write($header, 0, 4); $Stream.Write($bytes, 0, $bytes.Length); $Stream.Flush()
}
if ($SelfTest) {
    $root = Join-Path ([IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString())
    [IO.Directory]::CreateDirectory($root) | Out-Null
    try {
        [IO.File]::WriteAllText((Join-Path $root '测试 file.txt'), 'fixture')
        [IO.Directory]::CreateDirectory((Join-Path $root 'Folder')) | Out-Null
        $items = @(Get-Inventory $root $false)
        if ($items.Count -ne 2 -or $items[0].id.Length -ne 64) { throw 'Inventory test failed' }
        if ((ConvertTo-Json -InputObject $items).Contains($root)) { throw 'Path disclosure test failed' }
        $resolved = Resolve-Item $items[0].id $root
        if ([IO.Path]::GetDirectoryName($resolved) -ne $root) { throw 'Path isolation test failed' }
        $rejected = $false
        try { Resolve-Item ('0' * 64) $root | Out-Null } catch { $rejected = $true }
        if (-not $rejected) { throw 'Unknown ID accepted' }
        [IO.File]::WriteAllText((Join-Path $root 'Folder/needle.txt'), 'fixture')
        $found = @(Find-LocalItems 'needle' @(@{path=$root; apps=$false}))
        if ($found.Count -ne 1 -or @(Find-LocalItems 'needle' @(@{path=$root; apps=$true})).Count -ne 0) { throw 'Search scope test failed' }
        if (Test-InSearchRoot ($root + '-sibling/file.txt') $root) { throw 'Prefix escape accepted' }
        for ($n = 0; $n -lt 40; $n++) { [IO.File]::WriteAllText((Join-Path $root "limit-$n.txt"), '') }
        if (@(Find-LocalItems 'limit' @(@{path=$root; apps=$false})).Count -ne 30) { throw 'Search bound test failed' }
        $stream = New-Object IO.MemoryStream
        Write-Message $stream @{ok=$true; text='中文'}
        $stream.Position = 0
        $length = [BitConverter]::ToUInt32((Read-Exact $stream 4), 0)
        $body = $Utf8.GetString((Read-Exact $stream $length)) | ConvertFrom-Json
        if ($body.text -ne '中文') { throw 'Framing test failed' }
        $stream.Dispose()
        Write-Output 'PASS: Windows inventory, scoped recursive search, bounds, Unicode, ID isolation and native messaging framing'
    } finally { [IO.Directory]::Delete($root, $true) }
    exit 0
}
$allowedFile = Join-Path $PSScriptRoot 'allowed-extension.txt'
if (-not [IO.File]::Exists($allowedFile)) { exit 1 }
$allowed = [IO.File]::ReadAllText($allowedFile).Trim()
if ($allowed -notmatch '^[a-p]{32}$' -or $Origin -cne "chrome-extension://$allowed/") { exit 1 }
$stdin = [Console]::OpenStandardInput(); $stdout = [Console]::OpenStandardOutput()
try {
    while ($true) {
        $header = Read-Exact $stdin 4
        if ($null -eq $header) { break }
        $length = [BitConverter]::ToUInt32($header, 0)
        if ($length -eq 0 -or $length -gt 65536) { break }
        $body = Read-Exact $stdin $length
        if ($null -eq $body) { break }
        try { $request = $Utf8.GetString($body) | ConvertFrom-Json; $result = Invoke-HostRequest $request }
        catch { $result = @{ok=$false; error='操作未完成。请确认选择了可访问的桌面目录、项目仍存在，或重新连接。'} }
        Write-Message $stdout $result
    }
} catch { exit 1 }
