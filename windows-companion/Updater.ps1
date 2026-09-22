[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$InstallRoot,
    [string]$TargetVersion,
    [string]$DownloadUrl,
    [int]$ParentProcessId = 0,
    [switch]$TestExtractOnly,
    [switch]$NonInteractive,
    [switch]$NoRestart,
    [string]$PackagePath,
    [string]$ChecksumPath
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms,System.IO.Compression,System.IO.Compression.FileSystem

function Show-Info([string]$text, [string]$title='燕小北更新程序') {
    [Windows.Forms.MessageBox]::Show($text, $title, [Windows.Forms.MessageBoxButtons]::OK, [Windows.Forms.MessageBoxIcon]::Information) | Out-Null
}
function Get-TrustedRoot([string]$value) {
    $root = [IO.Path]::GetFullPath($value).TrimEnd('\','/')
    if (-not (Test-Path -LiteralPath (Join-Path $root 'VERSION.txt') -PathType Leaf) -or
        -not (Test-Path -LiteralPath (Join-Path $root 'windows-companion\CodexQuotaPet.ps1') -PathType Leaf)) {
        throw '安装目录不是完整的燕小北 Windows 版本。请完整解压后再更新。'
    }
    return $root
}
function Receive-File([string]$url, [string]$destination, [int]$seconds=45) {
    if ($url -notmatch '^https://github\.com/YufeiWang-cn/bjut-yanxiaobei-codex-pet/releases/download/v\d+\.\d+\.\d+/(?:bjut-yanxiaobei-windows\.zip|SHA256SUMS\.txt)$') {
        throw '下载地址未通过安全检查。'
    }
    Add-Type -AssemblyName System.Net.Http
    $handler = [Net.Http.HttpClientHandler]::new()
    $handler.UseProxy = $true
    $handler.Proxy = [Net.WebRequest]::DefaultWebProxy
    if ($null -ne $handler.Proxy) { $handler.Proxy.Credentials = [Net.CredentialCache]::DefaultCredentials }
    foreach ($name in @('HTTPS_PROXY','https_proxy','ALL_PROXY','all_proxy')) {
        $candidate = [Environment]::GetEnvironmentVariable($name)
        if ($candidate) { try { $handler.Proxy = [Net.WebProxy]::new([Uri]$candidate); break } catch {} }
    }
    $client = [Net.Http.HttpClient]::new($handler)
    $client.Timeout = [TimeSpan]::FromSeconds($seconds)
    $client.DefaultRequestHeaders.UserAgent.ParseAdd('BJUT-YanXiaoBei-Updater/0.2.6')
    try {
        $response = $client.GetAsync($url).GetAwaiter().GetResult()
        if (-not $response.IsSuccessStatusCode) { throw ('下载失败：HTTP ' + [int]$response.StatusCode) }
        $bytes = $response.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult()
        [IO.File]::WriteAllBytes($destination, $bytes)
    } finally { $client.Dispose(); $handler.Dispose() }
}
function Expand-TrustedArchive([string]$archivePath, [string]$destination, [string]$expectedVersion) {
    $archive = [IO.Compression.ZipFile]::OpenRead($archivePath)
    try {
        foreach ($entry in $archive.Entries) {
            $target = [IO.Path]::GetFullPath((Join-Path $destination $entry.FullName))
            if (-not $target.StartsWith(([IO.Path]::GetFullPath($destination).TrimEnd('\') + '\'), [StringComparison]::OrdinalIgnoreCase)) {
                throw '更新包包含越界路径，已停止安装。'
            }
        }
    } finally { $archive.Dispose() }
    [IO.Compression.ZipFile]::ExtractToDirectory($archivePath, $destination)
    $roots = @(Get-ChildItem -LiteralPath $destination -Directory)
    if ($roots.Count -ne 1 -or $roots[0].Name -ne 'bjut-yanxiaobei-windows') { throw '更新包目录结构无效。' }
    $root = $roots[0].FullName
    $version = (Get-Content -Raw -LiteralPath (Join-Path $root 'VERSION.txt')).Trim()
    if ($version -ne $expectedVersion) { throw "更新包版本不一致：期望 $expectedVersion，实际 $version。" }
    if (-not (Test-Path -LiteralPath (Join-Path $root 'windows-companion\CodexQuotaPet.ps1') -PathType Leaf)) { throw '更新包缺少桌宠核心文件。' }
    return $root
}
function Stop-InstalledPet([string]$root, [int]$parentId) {
    if ($parentId -gt 0) { try { Wait-Process -Id $parentId -Timeout 10 -ErrorAction SilentlyContinue } catch {} }
    $escaped = [Regex]::Escape((Join-Path $root 'windows-companion'))
    foreach ($process in @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
        $_.ProcessId -ne $PID -and $_.CommandLine -match $escaped -and $_.CommandLine -match '(?:CodexQuotaPet|Launch)\.ps1'
    })) { try { Stop-Process -Id $process.ProcessId -Force -ErrorAction Stop } catch {} }
}

$temporary = Join-Path ([IO.Path]::GetTempPath()) ('YanXiaoBei-Update-' + [Guid]::NewGuid().ToString('N'))
try {
    $InstallRoot = Get-TrustedRoot $InstallRoot
    if (-not $TargetVersion -or -not $DownloadUrl) {
        $runtime = Join-Path $InstallRoot 'windows-companion\Runtime.ps1'; . $runtime
        $node = Get-CompanionNode
        $info = [Diagnostics.ProcessStartInfo]::new($node, '"' + (Join-Path $InstallRoot 'windows-companion\update-check.js') + '"')
        $info.UseShellExecute=$false; $info.CreateNoWindow=$true; $info.RedirectStandardOutput=$true; $info.StandardOutputEncoding=[Text.Encoding]::UTF8
        $process=[Diagnostics.Process]::Start($info); $json=$process.StandardOutput.ReadToEnd(); $process.WaitForExit(); $process.Dispose()
        $result=$json|ConvertFrom-Json
        if ($result.status -ne 'update') { Show-Info '当前已经是最新版本。'; return }
        $TargetVersion=[string]$result.latest; $DownloadUrl=[string]$result.downloads.windows
    }
    if ($TargetVersion -notmatch '^\d+\.\d+\.\d+$') { throw '目标版本号无效。' }
    $expected = "https://github.com/YufeiWang-cn/bjut-yanxiaobei-codex-pet/releases/download/v$TargetVersion/bjut-yanxiaobei-windows.zip"
    if ($DownloadUrl -ne $expected) { throw '更新下载地址与目标版本不匹配。' }
    if (-not $TestExtractOnly -and -not $NonInteractive) {
        $answer=[Windows.Forms.MessageBox]::Show("将燕小北更新到 v$TargetVersion。`n`n程序会保留设置和缓存，在当前目录覆盖核心文件。是否继续？",'燕小北更新程序',[Windows.Forms.MessageBoxButtons]::YesNo,[Windows.Forms.MessageBoxIcon]::Question)
        if ($answer -ne [Windows.Forms.DialogResult]::Yes) { return }
    }
    $null=New-Item -ItemType Directory -Path $temporary -Force
    $zip=Join-Path $temporary 'bjut-yanxiaobei-windows.zip'; $sums=Join-Path $temporary 'SHA256SUMS.txt'
    if ($PackagePath -or $ChecksumPath) {
        if ((-not $TestExtractOnly -and -not $NonInteractive) -or -not $PackagePath -or -not $ChecksumPath) { throw '本地更新包参数仅供隔离验证使用。' }
        Copy-Item -LiteralPath $PackagePath -Destination $zip
        Copy-Item -LiteralPath $ChecksumPath -Destination $sums
    } else {
        Receive-File $DownloadUrl $zip
        $sumUrl="https://github.com/YufeiWang-cn/bjut-yanxiaobei-codex-pet/releases/download/v$TargetVersion/SHA256SUMS.txt"
        Receive-File $sumUrl $sums
    }
    $expectedHash=(Get-Content -LiteralPath $sums | Where-Object {$_ -match '\s+bjut-yanxiaobei-windows\.zip$'} | Select-Object -First 1) -replace '\s+.*$',''
    if ($expectedHash -notmatch '^[0-9A-Fa-f]{64}$' -or (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash -ne $expectedHash) { throw '更新包 SHA256 校验失败。' }
    $stage=Join-Path $temporary 'stage'; $null=New-Item -ItemType Directory -Path $stage
    $newRoot=Expand-TrustedArchive $zip $stage $TargetVersion
    if ($TestExtractOnly) { Write-Output 'PASS: update archive validated'; return }
    Stop-InstalledPet $InstallRoot $ParentProcessId
    foreach ($directory in @('windows-companion','docs')) {
        $target=Join-Path $InstallRoot $directory
        if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force }
    }
    foreach ($file in @('README.md','CHANGELOG.md','LICENSE.md','VERSION.txt','START-HERE.html','Update.vbs','Uninstall.vbs')) {
        $target=Join-Path $InstallRoot $file
        if (Test-Path -LiteralPath $target -PathType Leaf) { Remove-Item -LiteralPath $target -Force }
    }
    Copy-Item -Path (Join-Path $newRoot '*') -Destination $InstallRoot -Recurse -Force
    $starter=Join-Path $InstallRoot 'windows-companion\Start.vbs'
    if (-not $NoRestart -and (Test-Path -LiteralPath $starter)) { Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\wscript.exe') -ArgumentList ('"'+$starter+'"') -WindowStyle Hidden }
    if ($NonInteractive) { Write-Output "PASS: updated in place to v$TargetVersion" } else { Show-Info "更新完成，当前版本为 v$TargetVersion。" }
} catch {
    if ($NonInteractive) { throw }
    [Windows.Forms.MessageBox]::Show($_.Exception.Message,'燕小北更新失败',[Windows.Forms.MessageBoxButtons]::OK,[Windows.Forms.MessageBoxIcon]::Error) | Out-Null
} finally {
    if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Recurse -Force -ErrorAction SilentlyContinue }
    if ($PSCommandPath -like ([IO.Path]::GetTempPath() + 'YanXiaoBei-Updater-*')) { Remove-Item -LiteralPath $PSCommandPath -Force -ErrorAction SilentlyContinue }
}
