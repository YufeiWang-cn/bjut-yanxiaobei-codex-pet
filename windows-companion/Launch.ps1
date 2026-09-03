param([switch]$Watch)
$ErrorActionPreference = 'Stop'
try {
    if ($Watch) { & (Join-Path $PSScriptRoot 'CodexPetWatcher.ps1') }
    else { & (Join-Path $PSScriptRoot 'CodexQuotaPet.ps1') }
} catch {
    Add-Type -AssemblyName PresentationFramework
    $null = [Windows.MessageBox]::Show($_.Exception.Message + "`n`nSee docs/INSTALL.md or run Start-Debug.cmd.", 'BJUT YanXiaoBei - Startup error')
    exit 1
}
