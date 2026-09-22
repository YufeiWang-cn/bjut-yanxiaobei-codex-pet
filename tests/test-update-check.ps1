$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $repoRoot 'windows-companion\Runtime.ps1')
$source = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $repoRoot 'windows-companion\CodexQuotaPet.ps1')
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
$tokens = $null; $errors = $null
$ast = [Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw 'Update dialog source has a PowerShell parse error.' }
$builder = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'New-ReleaseUpdateDialog' }, $true)
if (-not $builder) { throw 'Scrollable update dialog is missing.' }
. ([scriptblock]::Create($builder.Extent.Text))
$window = [Windows.Window]::new()
$dialog = New-ReleaseUpdateDialog ([pscustomobject]@{local='0.2.4';latest='0.2.5';summary=('Fix waiting state' + (' release notes' * 70))})
$notes = @($dialog.Content.Children | Where-Object { $_ -is [Windows.Controls.TextBox] })[0]
if (-not $notes -or $notes.TextWrapping -ne [Windows.TextWrapping]::Wrap -or
    $notes.VerticalScrollBarVisibility -ne [Windows.Controls.ScrollBarVisibility]::Auto -or
    $notes.HorizontalScrollBarVisibility -ne [Windows.Controls.ScrollBarVisibility]::Disabled) {
    throw 'Update notes are not wrapped and vertically scrollable.'
}
$choiceButtons=@($dialog.Content.Children | Where-Object { $_ -is [Windows.Controls.StackPanel] })[0].Children
if ($choiceButtons.Count -ne 3) {
    throw 'Update dialog choices are incomplete.'
}
if (($choiceButtons | ForEach-Object Content) -notcontains '立即更新' -or
    ($choiceButtons | ForEach-Object Content) -notcontains '忽略此版本' -or
    ($choiceButtons | ForEach-Object Content) -notcontains '暂时忽略') { throw 'Update choices changed semantics.' }
$dialog.Content.Measure([Windows.Size]::new(520, 350))
$dialog.Content.Arrange([Windows.Rect]::new(0, 0, 520, 350))
$dialog.Content.UpdateLayout()
if ($notes.ActualWidth -le 0 -or $notes.ActualHeight -le 0 -or
    $notes.ActualWidth -gt 520 -or $notes.ActualHeight -gt 350) { throw 'Update notes overflow dialog bounds.' }
$previewRoot = Join-Path $repoRoot '.test-output'
$null = New-Item -ItemType Directory -Path $previewRoot -Force
$preview = [Windows.Media.Imaging.RenderTargetBitmap]::new(520, 350, 96, 96, [Windows.Media.PixelFormats]::Pbgra32)
$preview.Render($dialog.Content)
$encoder = [Windows.Media.Imaging.PngBitmapEncoder]::new()
$encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($preview))
$stream = [IO.File]::Create((Join-Path $previewRoot 'update-dialog-regression.png'))
try { $encoder.Save($stream) } finally { $stream.Dispose() }
$dialog.Close(); $window.Close()
if ($source -notmatch '\$info\.StandardOutputEncoding\s*=\s*\[Text\.Encoding\]::UTF8') {
    throw 'Windows update process must explicitly decode Node UTF-8 output.'
}
foreach($required in @('Schedule-AutoUpdateCheck 1500','Schedule-AutoUpdateCheck 8000','ignoredVersion','Start-UpdateProgram')){
    if(-not $source.Contains($required)){throw "Automatic update workflow is missing: $required"}
}
$info = [Diagnostics.ProcessStartInfo]::new()
$info.FileName = Get-CompanionNode
$info.Arguments = '"' + (Join-Path $repoRoot 'tests\test-update-check.js') + '" --emit-fixture'
$info.UseShellExecute = $false
$info.CreateNoWindow = $true
$info.RedirectStandardOutput = $true
$info.StandardOutputEncoding = [Text.Encoding]::UTF8
$process = [Diagnostics.Process]::Start($info)
try {
    $json = $process.StandardOutput.ReadToEnd()
    if (-not $process.WaitForExit(5000) -or $process.ExitCode -ne 0) { throw 'Update fixture process failed.' }
    $result = $json | ConvertFrom-Json
    $expectedPrefix = [string][char]0x71d5 + [string][char]0x5c0f + [string][char]0x5317
    if ($result.status -ne 'current' -or -not $result.summary.StartsWith($expectedPrefix) -or $result.summary.Length -lt 12) {
        throw 'Windows update JSON changed while crossing the Node/PowerShell boundary.'
    }
} finally { $process.Dispose() }
'PASS: Windows update dialog wraps and scrolls; PowerShell reads UTF-8 Chinese JSON correctly.'
