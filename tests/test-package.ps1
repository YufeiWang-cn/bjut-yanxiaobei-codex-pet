$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path $repoRoot ('.test-output\package-' + [Guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $testRoot -Force
$data = Join-Path $testRoot 'data'
$startup = Join-Path $testRoot 'startup'
function Assert($condition, $message) { if (-not $condition) { throw $message } }
$freshData = Join-Path $testRoot 'fresh-data'
& (Join-Path $repoRoot 'windows-companion\Configure-Autostart.ps1') -InitializeDefault -DataDirectory $freshData -StartupDirectory $startup -NoStart
Assert (Test-Path -LiteralPath (Join-Path $freshData 'autostart-enabled.flag')) 'Fresh install did not enable follow by default'
Assert (Test-Path -LiteralPath (Join-Path $freshData 'autostart-configured.flag')) 'Default choice was not persisted'
& (Join-Path $repoRoot 'windows-companion\Configure-Autostart.ps1') -Disable -DataDirectory $freshData -StartupDirectory $startup -NoStart
& (Join-Path $repoRoot 'windows-companion\Configure-Autostart.ps1') -InitializeDefault -DataDirectory $freshData -StartupDirectory $startup -NoStart
Assert (-not (Test-Path -LiteralPath (Join-Path $freshData 'autostart-enabled.flag'))) 'Default setup reversed an explicit disable'
Assert (-not (Test-Path -LiteralPath (Join-Path $startup 'BJUT-YanXiaoBei-Codex.lnk'))) 'Disable left a startup shortcut'
& (Join-Path $repoRoot 'windows-companion\Configure-Autostart.ps1') -Enable -DataDirectory $freshData -StartupDirectory $startup -NoStart
Assert (Test-Path -LiteralPath (Join-Path $freshData 'autostart-enabled.flag')) 'Follow could not be re-enabled'
& (Join-Path $repoRoot 'windows-companion\Configure-Autostart.ps1') -Disable -DataDirectory $freshData -StartupDirectory $startup -NoStart
$legacyData = Join-Path $testRoot 'legacy-data'
$null = New-Item -ItemType Directory -Path $legacyData -Force
$null = New-Item -ItemType File -Path (Join-Path $legacyData 'ui-settings.json') -Force
& (Join-Path $repoRoot 'windows-companion\Configure-Autostart.ps1') -InitializeDefault -DataDirectory $legacyData -StartupDirectory $startup -NoStart
Assert (-not (Test-Path -LiteralPath (Join-Path $legacyData 'autostart-enabled.flag'))) 'Existing installation preference was overwritten'
& (Join-Path $repoRoot 'windows-companion\Configure-Autostart.ps1') -Enable -DataDirectory $data -StartupDirectory $startup -NoStart
Assert (Test-Path -LiteralPath (Join-Path $data 'autostart-enabled.flag')) 'Enable flag missing'
Assert (Test-Path -LiteralPath (Join-Path $data 'autostart-configured.flag')) 'Enable choice missing'
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
& (Join-Path $repoRoot 'scripts\Uninstall-CodexPet.ps1') -CodexHome $fakeCodex -RemoveBackups -Confirm:$false
Assert (-not (Test-Path -LiteralPath $pet)) 'Native uninstaller left pet'
Assert (@(Get-ChildItem -LiteralPath (Join-Path $fakeCodex 'pets') -Directory -Filter 'bjut-yanxiaobei.backup-*').Count -eq 0) 'Native uninstaller left backups'
$uninstallData = Join-Path $testRoot 'BJUT-YanXiaoBei'
$null = New-Item -ItemType Directory -Path $uninstallData -Force
$null = New-Item -ItemType File -Path (Join-Path $uninstallData 'ui-settings.json') -Force
& (Join-Path $repoRoot 'windows-companion\Uninstall.ps1') -DataDirectory $uninstallData -StartupDirectory $startup -Confirm:$false
Assert (-not (Test-Path -LiteralPath $uninstallData)) 'Windows uninstaller left settings'
'PASS: isolated default-on, disable persistence, re-enable, native install and uninstall; no real Startup or Codex home modified'
