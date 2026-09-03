$ErrorActionPreference = 'Stop'
$appRoot = Join-Path $PSScriptRoot '..\windows-companion'
$parseTokens=$null; $parseErrors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $appRoot 'CodexQuotaPet.ps1'),[ref]$parseTokens,[ref]$parseErrors)
if ($parseErrors.Count) { throw ($parseErrors | Out-String) }
foreach ($name in @('Read-AnimationTiming','Render-PetFrame','Set-PetState')) {
    $functionAst = $ast.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name},$true)
    . ([scriptblock]::Create($functionAst.Extent.Text))
}
function Assert($condition,$message) { if (-not $condition) { throw $message } }
$frameSets = @{}
foreach ($state in @('idle','running-right','running-left','waving','jumping','failed','waiting','running','review')) {
    $frameSets[$state] = @(Get-ChildItem -LiteralPath (Join-Path $appRoot ('frames\' + $state)) -Filter '*.png' | Sort-Object Name | ForEach-Object FullName)
}
$timingPath = Join-Path $appRoot 'animation-timing.json'
$frameDurations = Read-AnimationTiming $timingPath $frameSets
Assert (($frameDurations.failed | Measure-Object -Sum).Sum -eq 3600) 'Failed loop must be 3.6 seconds'
Assert (($frameDurations.failed | Measure-Object -Minimum).Minimum -ge 320) 'Failed frame is too fast'
$unchanged = @{
    idle='420,180,180,220,220,520'; running='170,170,170,170,170,260'; waiting='230,230,230,230,230,340'
    review='230,230,230,230,230,380'; 'running-left'='150,150,150,150,150,150,150,240'
    'running-right'='150,150,150,150,150,150,150,240'; waving='220,220,220,340'; jumping='200,200,200,200,360'
}
foreach ($state in $unchanged.Keys) { Assert (($frameDurations[$state] -join ',') -eq $unchanged[$state]) ('Unrelated timing changed: ' + $state) }
function Get-Bitmap([string]$path) { return $path }
$petImage = [pscustomobject]@{ Source=$null }
$animationTimer = [pscustomobject]@{ Interval=[TimeSpan]::Zero }
$script:displayPetState='idle'; $script:frameIndex=0
Set-PetState 'failed'
$elapsed = 0
for ($index=0; $index -lt 8; $index++) {
    $script:frameIndex=$index
    Render-PetFrame
    $elapsed += $animationTimer.Interval.TotalMilliseconds
    Set-PetState 'failed'
    Assert ($script:frameIndex -eq $index) 'Repeated failed snapshot reset the animation'
    Assert ($petImage.Source -eq $frameSets.failed[$index]) 'Wrong failed frame selected'
}
Assert ($elapsed -eq 3600) 'Rendered duration differs from profile'
Set-PetState 'running'
Assert ($script:displayPetState -eq 'running' -and $script:frameIndex -eq 0) 'State exit failed'
$badFrames=@{ failed=@('only-one') }; $rejected=$false
try { $null=Read-AnimationTiming $timingPath $badFrames } catch { $rejected=$true }
Assert $rejected 'Bad frame count accepted'
'PASS: failed 3.6s cadence, no same-state resets, correct frames, state exit, profile validation, other 8 timings unchanged'
