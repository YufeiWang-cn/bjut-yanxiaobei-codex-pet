$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '..\windows-companion\CodexPetWatcher.ps1') -SmokeTest
function Assert($condition,$message){if(!$condition){throw $message}}
Assert (Test-CodexDesktopIdentity 'ChatGPT' '' 'OpenAI.Codex_2p2nqsd0c76g0!App') 'Packaged Codex/ChatGPT.exe was ignored'
Assert (!(Test-CodexDesktopIdentity 'ChatGPT' '' 'OpenAI.ChatGPT_x!App')) 'Ordinary ChatGPT app was accepted'
Assert (!(Test-CodexDesktopIdentity 'Codex' 'C:\Users\A\AppData\Local\OpenAI\Codex\bin\hash\codex.exe' '')) 'Quota CLI was accepted'
Assert (Test-CodexDesktopIdentity 'Codex' 'C:\Apps\Codex\Codex.exe' '') 'Standalone GUI was ignored'
$d=Get-PetLaunchDecision @() @() @(10,11)
Assert (!$d.Start -and $d.KnownIds.Count -eq 0) 'CLI processes started pet'
$d=Get-PetLaunchDecision @() @(20) @(10,20)
Assert ($d.Start -and $d.KnownIds.Count -eq 1) 'New GUI did not start pet'
$d=Get-PetLaunchDecision @(20) @(20) @(10,20)
Assert (!$d.Start) 'Repeated GUI poll restarted pet'
$d=Get-PetLaunchDecision @(20) @() @(10,20)
Assert (!$d.Start -and $d.KnownIds.Count -eq 1) 'Minimized GUI lost session'
$d=Get-PetLaunchDecision @(20) @() @(10)
Assert (!$d.Start -and $d.KnownIds.Count -eq 0) 'Closed GUI remained active'
$d=Get-PetLaunchDecision @(20) @(21) @(10,21)
Assert $d.Start 'Fast GUI restart not detected'
$d=Get-PetLaunchDecision @(20) @(20,21) @(20,21)
Assert (!$d.Start) 'Second GUI window restarted pet'
$life=Get-PetCloseDecision 0 $true 2
Assert (!$life.Close -and $life.MissingPolls -eq 0) 'Running Codex advanced close countdown'
$life=Get-PetCloseDecision $life.MissingPolls $false 2
Assert (!$life.Close -and $life.MissingPolls -eq 1) 'Pet closed on a single missing poll'
$life=Get-PetCloseDecision $life.MissingPolls $false 2
Assert $life.Close 'Pet did not close after Codex exited'
$life=Get-PetCloseDecision $life.MissingPolls $true 2
Assert (!$life.Close -and $life.MissingPolls -eq 0) 'Codex restart did not cancel close countdown'
'PASS: application identity, watcher launch and pet-close lifecycle cases passed'
