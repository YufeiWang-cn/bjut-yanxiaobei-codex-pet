[CmdletBinding(SupportsShouldProcess)]
param([string]$CodexHome, [switch]$Force)
$ErrorActionPreference = 'Stop'
if (-not $CodexHome) {
    $CodexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' }
}
$source = Join-Path $PSScriptRoot '..\codex-native\bjut-yanxiaobei'
$target = Join-Path $CodexHome 'pets\bjut-yanxiaobei'
foreach ($file in @('pet.json', 'spritesheet.webp')) {
    if (-not (Test-Path -LiteralPath (Join-Path $source $file) -PathType Leaf)) { throw "Missing source: $file" }
}
if ((Test-Path -LiteralPath $target) -and -not $Force) {
    throw "Target already exists: $target. Use -Force to back up and update."
}
if ($PSCmdlet.ShouldProcess($target, 'Install BJUT YanXiaoBei native pet')) {
    if (Test-Path -LiteralPath $target) {
        $backup = $target + '.backup-' + [DateTime]::Now.ToString('yyyyMMdd-HHmmss-fff')
        Copy-Item -LiteralPath $target -Destination $backup -Recurse
        Write-Output "Backup: $backup"
    }
    $null = New-Item -ItemType Directory -Path $target -Force
    foreach ($file in @('pet.json', 'spritesheet.webp')) {
        Copy-Item -LiteralPath (Join-Path $source $file) -Destination (Join-Path $target $file) -Force
    }
    Write-Output "Installed: $target"
    Write-Output 'Refresh custom pets in Codex Settings > Pets, then select BJUT YanXiaoBei.'
}
