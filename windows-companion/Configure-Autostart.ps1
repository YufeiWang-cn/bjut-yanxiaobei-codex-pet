param(
    [switch]$Enable,
    [switch]$Disable,
    [string]$DataDirectory,
    [string]$StartupDirectory,
    [switch]$NoStart
)
$ErrorActionPreference = 'Stop'
if ($Enable -eq $Disable) { throw 'Specify exactly one of -Enable or -Disable.' }
. (Join-Path $PSScriptRoot 'Runtime.ps1')
if (-not $DataDirectory) { $DataDirectory = Get-CompanionDataRoot }
if (-not $StartupDirectory) { $StartupDirectory = [Environment]::GetFolderPath('Startup') }
$flag = Join-Path $DataDirectory 'autostart-enabled.flag'
$shortcutPath = Join-Path $StartupDirectory 'BJUT-YanXiaoBei-Codex.lnk'
if ($Disable) {
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
