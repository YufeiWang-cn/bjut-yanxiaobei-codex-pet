param([switch]$Disable, [switch]$Enable, [switch]$SmokeTest)
$ErrorActionPreference = 'Stop'
$appRoot = $PSScriptRoot
. (Join-Path $appRoot 'CodexDesktop.ps1')
. (Join-Path $appRoot 'Runtime.ps1')
$enabledPath = Join-Path (Get-CompanionDataRoot) 'autostart-enabled.flag'

function Get-PetLaunchDecision($knownIds, $visibleIds, $aliveIds) {
    # A remembered GUI may be minimized or hidden. CLI/app-server processes
    # never enter this set, because they have no main window.
    $remaining = @($knownIds | Where-Object { $aliveIds -contains $_ })
    $next = @(@($remaining) + @($visibleIds) | Sort-Object -Unique)
    return [pscustomobject]@{ Start = ($next.Count -gt 0 -and $remaining.Count -eq 0); KnownIds = $next }
}

if ($SmokeTest) { return }
if ($Enable -or $Disable) {
    & (Join-Path $appRoot 'Configure-Autostart.ps1') -Enable:$Enable -Disable:$Disable -NoStart
}
if (-not (Test-Path -LiteralPath $enabledPath)) { return }
$created = $false
$mutex = [Threading.Mutex]::new($true, 'Local\YanXiaoBeiCodexWatcher-4E8F21B3', [ref]$created)
if (-not $created) { $mutex.Dispose(); exit 0 }
$currentProcess = Get-Process -Id $PID
$sessionId = $currentProcess.SessionId
$hostExe = $currentProcess.Path
$knownIds = @()
try {
    while (Test-Path -LiteralPath $enabledPath) {
        try {
            $processes = @(Get-Process -Name Codex,ChatGPT -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -eq $sessionId })
            $aliveIds = @($processes | ForEach-Object Id)
            $visibleIds = @(Get-CodexDesktopProcesses | ForEach-Object Id)
            $decision = Get-PetLaunchDecision $knownIds $visibleIds $aliveIds
            if ($decision.Start) {
                $info = [Diagnostics.ProcessStartInfo]::new()
                $info.FileName = $hostExe
                $info.Arguments = '-NoProfile -ExecutionPolicy Bypass -STA -File "' + (Join-Path $appRoot 'Launch.ps1') + '"'
                $info.WorkingDirectory = $appRoot
                $info.UseShellExecute = $false
                $info.CreateNoWindow = $true
                $started = [Diagnostics.Process]::Start($info)
                $started.Dispose()
            }
            # Do not watch whether the pet exited: closing it is a user choice.
            $knownIds = @($decision.KnownIds)
        } catch {
            # A process may disappear during enumeration. Try again next poll.
        }
        Start-Sleep -Seconds 2
    }
} finally {
    try { $mutex.ReleaseMutex() } catch {}
    $mutex.Dispose()
}
