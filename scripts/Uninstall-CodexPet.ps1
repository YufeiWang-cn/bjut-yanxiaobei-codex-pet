[CmdletBinding(SupportsShouldProcess, ConfirmImpact='High')]
param([string]$CodexHome, [switch]$RemoveBackups)
$ErrorActionPreference = 'Stop'
if (-not $CodexHome) { $CodexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' } }
$root = [IO.Path]::GetFullPath($CodexHome)
$pets = Join-Path $root 'pets'
$target = Join-Path $pets 'bjut-yanxiaobei'
if ((Split-Path -Leaf $target) -ne 'bjut-yanxiaobei') { throw 'Unexpected pet path' }
if (Test-Path -LiteralPath $target) {
    if ((Get-Item -LiteralPath $target -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Refusing to follow a linked pet directory' }
    if ($PSCmdlet.ShouldProcess($target, 'Remove YanXiaoBei native pet')) { Remove-Item -LiteralPath $target -Recurse -Force }
}
if ($RemoveBackups -and (Test-Path -LiteralPath $pets)) {
    foreach ($backup in Get-ChildItem -LiteralPath $pets -Directory -Filter 'bjut-yanxiaobei.backup-*') {
        if ($backup.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
        if ($backup.Name -notmatch '^bjut-yanxiaobei\.backup-\d{8}-\d{6}-\d{3}$') { continue }
        if ($PSCmdlet.ShouldProcess($backup.FullName, 'Remove YanXiaoBei installer backup')) { Remove-Item -LiteralPath $backup.FullName -Recurse -Force }
    }
}
Write-Output 'Native pet removed. Switch away from YanXiaoBei in Codex Pets and refresh the list; Codex account preferences are untouched.'
