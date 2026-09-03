param([string]$NodeExecutable)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $repoRoot 'windows-companion\Runtime.ps1')
if (-not $NodeExecutable) { $NodeExecutable = Get-CompanionNode }
$hostExecutable = (Get-Process -Id $PID).Path
$cases = @(
    'tests\test-pet-ui.ps1',
    'tests\test-pet-summary.ps1',
    'tests\test-pet-animation.ps1',
    'tests\test-pet-window-restore.ps1',
    'tests\test-pet-watcher.ps1',
    'tests\test-package.ps1'
)
& $hostExecutable -NoProfile -ExecutionPolicy Bypass -STA -File (Join-Path $repoRoot 'windows-companion\CodexQuotaPet.ps1') -SmokeTest
if ($LASTEXITCODE -ne 0) { throw 'Smoke test failed' }
foreach ($test in $cases) {
    & $hostExecutable -NoProfile -ExecutionPolicy Bypass -STA -File (Join-Path $repoRoot $test)
    if ($LASTEXITCODE -ne 0) { throw "Failed: $test" }
}
& $NodeExecutable --check (Join-Path $repoRoot 'windows-companion\quota-bridge.js')
if ($LASTEXITCODE -ne 0) { throw 'JavaScript syntax check failed' }
& $NodeExecutable (Join-Path $repoRoot 'tests\test-pet-bridge.js')
if ($LASTEXITCODE -ne 0) { throw 'Bridge unit tests failed' }
& $NodeExecutable (Join-Path $repoRoot 'tests\test-activity-state.js')
if ($LASTEXITCODE -ne 0) { throw 'Activity lifecycle tests failed' }
& $NodeExecutable (Join-Path $repoRoot 'tests\test-task-scope.js')
if ($LASTEXITCODE -ne 0) { throw 'Root task scope regression tests failed' }
& $NodeExecutable (Join-Path $repoRoot 'scripts\Render-StartHere.cjs') --check
if ($LASTEXITCODE -ne 0) { throw 'Offline installation guide is stale' }
& $NodeExecutable --test (Join-Path $repoRoot 'macos-companion\tests\model.test.cjs') (Join-Path $repoRoot 'macos-companion\tests\source-quality.test.cjs')
if ($LASTEXITCODE -ne 0) { throw 'Mac/shared release tests failed' }
& $NodeExecutable --test (Join-Path $repoRoot 'tests\test-source-audit.cjs')
if ($LASTEXITCODE -ne 0) { throw 'Source audit regression tests failed' }
& $NodeExecutable (Join-Path $repoRoot 'scripts\Audit-Source.cjs') --report (Join-Path $repoRoot '.test-output\source-audit.json')
if ($LASTEXITCODE -ne 0) { throw 'Per-file source audit failed' }
'All tests passed. Test artifacts are in .test-output/; no login or real task is needed.'
