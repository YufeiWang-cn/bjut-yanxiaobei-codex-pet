param(
    [switch]$Enable,
    [switch]$Disable,
    [switch]$InitializeDefault,
    [string]$DataDirectory,
    [string]$StartupDirectory,
    [switch]$NoStart
)
$ErrorActionPreference = 'Stop'
if (([int][bool]$Enable + [int][bool]$Disable + [int][bool]$InitializeDefault) -ne 1) { throw 'Specify exactly one of -Enable, -Disable or -InitializeDefault.' }
. (Join-Path $PSScriptRoot 'Runtime.ps1')
if (-not $DataDirectory) { $DataDirectory = Get-CompanionDataRoot }
if (-not $StartupDirectory) { $StartupDirectory = [Environment]::GetFolderPath('Startup') }
$flag = Join-Path $DataDirectory 'autostart-enabled.flag'
$choice = Join-Path $DataDirectory 'autostart-configured.flag'
$shortcutPath = Join-Path $StartupDirectory 'BJUT-YanXiaoBei-Codex.lnk'
if ($InitializeDefault) {
    # Existing installations may have deliberately disabled follow before this
    # marker existed. Only an empty/new data directory gets the new default.
    if (Test-Path -LiteralPath $DataDirectory) {
        if (Test-Path -LiteralPath $choice) { return }
        if (Get-ChildItem -LiteralPath $DataDirectory -Force | Select-Object -First 1) { return }
    }
    $Enable = $true
}
if ($Disable) {
    $null = New-Item -ItemType Directory -Path $DataDirectory -Force
    $null = New-Item -ItemType File -Path $choice -Force
    if (Test-Path -LiteralPath $flag) { Remove-Item -LiteralPath $flag }
    if (Test-Path -LiteralPath $shortcutPath) { Remove-Item -LiteralPath $shortcutPath }
    return
}
$null = New-Item -ItemType Directory -Path $DataDirectory -Force
$null = New-Item -ItemType Directory -Path $StartupDirectory -Force
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = Join-Path $env:SystemRoot 'System32\wscript.exe'
$shortcut.Arguments = '"' + (Join-Path $PSScriptRoot 'Start.vbs') + '" watch'
$shortcut.WorkingDirectory = $PSScriptRoot
$shortcut.Description = 'Start BJUT YanXiaoBei when Codex Desktop opens'
$shortcut.WindowStyle = 7
$shortcut.Save()
$null = New-Item -ItemType File -Path $flag -Force
$null = New-Item -ItemType File -Path $choice -Force
if (-not $NoStart) {
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = (Get-Process -Id $PID).Path
    $info.Arguments = '-NoProfile -ExecutionPolicy Bypass -STA -File "' + (Join-Path $PSScriptRoot 'Launch.ps1') + '" -Watch'
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.EnvironmentVariables['YANXIAOBEI_DATA_DIR'] = $DataDirectory
    $started = [Diagnostics.Process]::Start($info)
    $started.Dispose()
}
