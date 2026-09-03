$ErrorActionPreference = 'Stop'
$appRoot = Join-Path $PSScriptRoot '..\windows-companion'
. (Join-Path $appRoot 'CodexDesktop.ps1')
function Assert($condition, [string]$message) { if (-not $condition) { throw $message } }
Initialize-CodexWindowApi
Assert ([YanXiaoBei.WindowActivation]::Find([int[]]@(), [IntPtr]::Zero) -eq [IntPtr]::Zero) 'Empty process IDs matched another app'
Assert (-not [YanXiaoBei.WindowActivation]::Restore([IntPtr]::Zero)) 'Invalid window reported restored'

# Test the action decision independently of the user's desktop and current chat.
function Get-CodexRestoreTarget { return $script:testTarget }
function Restore-CodexWindow([IntPtr]$handle) { $script:restoreCalls++; $script:restoredHandle=$handle; return $script:allowRestore }
function Start-CodexDesktopApplication { $script:launchCalls++ }
$script:restoreCalls=0; $script:launchCalls=0; $script:allowRestore=$true
$script:testTarget=[pscustomobject]@{Handle=[IntPtr]123;IsRunning=$true}
Show-CodexDesktop
Assert ($script:restoreCalls -eq 1 -and $script:restoredHandle -eq [IntPtr]123 -and $script:launchCalls -eq 0) 'Existing window must only be restored'
$script:allowRestore=$false
$blocked=$false
try { Show-CodexDesktop } catch { $blocked=$true }
Assert ($blocked -and $script:launchCalls -eq 0) 'Focus denied must not reopen the app or navigate'
$script:testTarget=[pscustomobject]@{Handle=[IntPtr]::Zero;IsRunning=$true}
$blocked=$false
try { Show-CodexDesktop } catch { $blocked=$true }
Assert ($blocked -and $script:launchCalls -eq 0) 'Missing live window must not trigger cold launch'
$script:testTarget=[pscustomobject]@{Handle=[IntPtr]::Zero;IsRunning=$false}
Show-CodexDesktop
Assert ($script:launchCalls -eq 1) 'Fully exited app should use its normal launcher'

# The real Open-Codex handler, with only OS-bound actions replaced by spies.
$parseTokens=$null; $parseErrors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $appRoot 'CodexQuotaPet.ps1'),[ref]$parseTokens,[ref]$parseErrors)
Assert ($parseErrors.Count -eq 0) 'Main script parse error'
foreach($name in @('Open-Codex','Get-CodexThreadUri')) {
    $definition=$ast.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name},$true)
    . ([scriptblock]::Create($definition.Extent.Text))
}
function Show-CodexDesktop { $script:showCalls++ }
function Start-CodexUri([string]$uri) { $script:uriCalls++; $script:lastUri=$uri }
$script:showCalls=0; $script:uriCalls=0
$script:lastOpenThreadId='00000000-0000-4000-8000-000000000001'
Open-Codex
Assert ($script:showCalls -eq 1 -and $script:uriCalls -eq 0) 'Double-click switched to activity-list task'
$script:lastOpenThreadId=$null
Open-Codex
Assert ($script:showCalls -eq 2 -and $script:uriCalls -eq 0) 'Double-click opened the initial/new-chat page'
Open-Codex '00000000-0000-4000-8000-000000000001'
Assert ($script:showCalls -eq 2 -and $script:uriCalls -eq 1 -and $script:lastUri -eq 'codex://threads/00000000-0000-4000-8000-000000000001') 'Explicit task-row navigation regressed'

# MainWindowHandle=0 is expected for a hidden Electron window. The restore path
# must still examine its real windows; the existing autostart default stays unchanged.
function Get-Process {
    param($Id,$Name,$ErrorAction)
    if($PSBoundParameters.ContainsKey('Id')) { return [pscustomobject]@{SessionId=1} }
    return @(
        [pscustomobject]@{Id=300;SessionId=1;MainWindowHandle=[IntPtr]::Zero;ProcessName='ChatGPT';Path='C:\Program Files\WindowsApps\OpenAI.Codex_version\ChatGPT.exe'},
        [pscustomobject]@{Id=301;SessionId=1;MainWindowHandle=[IntPtr]::Zero;ProcessName='Codex';Path='C:\Users\A\AppData\Local\OpenAI\Codex\bin\hash\codex.exe'}
    )
}
function Get-CodexApplicationId([int]$processId) { return 'OpenAI.Codex_2p2nqsd0c76g0!App' }
Assert (@(Get-CodexDesktopProcesses).Count -eq 0) 'Watcher default unexpectedly changed'
$hidden=@(Get-CodexDesktopProcesses -IncludeHidden)
Assert ($hidden.Count -eq 1 -and $hidden[0].Id -eq 300) 'Hidden GUI was missed or headless CLI was included'
'PASS: native helper compilation, invalid handles, restore-only decision, denied focus, missing window, cold start, zero navigation on double-click, explicit task navigation, hidden GUI detection, watcher compatibility'
