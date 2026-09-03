$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path $repoRoot ('.test-output\package-' + [Guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $testRoot -Force
$data = Join-Path $testRoot 'data'
$startup = Join-Path $testRoot 'startup'
function Assert($condition, $message) { if (-not $condition) { throw $message } }
& (Join-Path $repoRoot 'windows-companion\Configure-Autostart.ps1') -Enable -DataDirectory $data -StartupDirectory $startup -NoStart
Assert (Test-Path -LiteralPath (Join-Path $data 'autostart-enabled.flag')) 'Enable flag missing'
$shortcutPath = Join-Path $startup 'BJUT-YanXiaoBei-Codex.lnk'
Assert (Test-Path -LiteralPath $shortcutPath) 'Startup shortcut missing'
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
Assert ($shortcut.Arguments.EndsWith('Start.vbs" watch')) 'Shortcut does not start watcher'
& (Join-Path $repoRoot 'windows-companion\Configure-Autostart.ps1') -Disable -DataDirectory $data -StartupDirectory $startup -NoStart
Assert (-not (Test-Path -LiteralPath $shortcutPath)) 'Disable left shortcut'
Assert (-not (Test-Path -LiteralPath (Join-Path $data 'autostart-enabled.flag'))) 'Disable left flag'
$fakeCodex = Join-Path $testRoot 'codex-home'
& (Join-Path $repoRoot 'scripts\Install-CodexPet.ps1') -CodexHome $fakeCodex
$pet = Join-Path $fakeCodex 'pets\bjut-yanxiaobei'
$metadata = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $pet 'pet.json') | ConvertFrom-Json
Assert ($metadata.spriteVersionNumber -eq 2 -and $metadata.id -eq 'bjut-yanxiaobei') 'Native manifest invalid'
$rejected = $false
try { & (Join-Path $repoRoot 'scripts\Install-CodexPet.ps1') -CodexHome $fakeCodex } catch { $rejected = $true }
Assert $rejected 'Installer overwrote existing pet without permission'
& (Join-Path $repoRoot 'scripts\Install-CodexPet.ps1') -CodexHome $fakeCodex -Force
Assert (@(Get-ChildItem -LiteralPath (Join-Path $fakeCodex 'pets') -Directory -Filter 'bjut-yanxiaobei.backup-*').Count -eq 1) 'Update backup missing'
$sourceHash = (Get-FileHash -LiteralPath (Join-Path $repoRoot 'codex-native\bjut-yanxiaobei\spritesheet.webp')).Hash
Assert ((Get-FileHash -LiteralPath (Join-Path $pet 'spritesheet.webp')).Hash -eq $sourceHash) 'Installed sprite changed'
'PASS: isolated autostart enable/disable, native install, overwrite protection and backup; no real Startup or Codex home modified'
