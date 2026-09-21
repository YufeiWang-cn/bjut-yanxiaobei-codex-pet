[CmdletBinding(SupportsShouldProcess, ConfirmImpact='High')]
param([string]$DataDirectory, [string]$StartupDirectory)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Runtime.ps1')
if (-not $DataDirectory) { $DataDirectory = Get-CompanionDataRoot }
$data = [IO.Path]::GetFullPath($DataDirectory).TrimEnd('\', '/')
if ((Split-Path -Leaf $data) -ne 'BJUT-YanXiaoBei') { throw 'For safety the data directory must end with BJUT-YanXiaoBei.' }
$startup = if ($StartupDirectory) { [IO.Path]::GetFullPath($StartupDirectory) } else { [Environment]::GetFolderPath('Startup') }
$shortcut = Join-Path $startup 'BJUT-YanXiaoBei-Codex.lnk'
if (Test-Path -LiteralPath $shortcut) {
    $shell = New-Object -ComObject WScript.Shell
    $link = $shell.CreateShortcut($shortcut)
    if ($link.Arguments -notmatch 'Start\.vbs.*watch') { throw 'Startup shortcut is not owned by this pet; leaving it untouched.' }
    if ($PSCmdlet.ShouldProcess($shortcut, 'Remove YanXiaoBei startup shortcut')) { Remove-Item -LiteralPath $shortcut -Force }
}
if (Test-Path -LiteralPath $data) {
    if ((Get-Item -LiteralPath $data -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Refusing to follow a linked data directory.' }
    if ($PSCmdlet.ShouldProcess($data, 'Remove YanXiaoBei settings and cached task/quota data')) { Remove-Item -LiteralPath $data -Recurse -Force }
}
Write-Output 'YanXiaoBei settings and startup shortcut removed. Close the pet first, then delete this extracted application folder. Codex data and other pets were not touched.'
