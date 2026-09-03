$ErrorActionPreference='Stop'
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
$outputRoot = Join-Path $PSScriptRoot '..\.test-output'
$null = New-Item -ItemType Directory -Path $outputRoot -Force
$appRoot=Join-Path $PSScriptRoot '..\windows-companion'
$parseTokens=$null; $parseErrors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $appRoot 'CodexQuotaPet.ps1'),[ref]$parseTokens,[ref]$parseErrors)
if($parseErrors.Count){throw ($parseErrors | Out-String)}
foreach($name in @('Format-TaskCount','Update-TaskSummary')){
    $definition=$ast.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name},$true)
    . ([scriptblock]::Create($definition.Extent.Text))
}
function Assert($condition,$message){if(!$condition){throw $message}}
[xml]$xaml=Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $appRoot 'MainWindow.xaml')
$window=[Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new($xaml))
$taskSummary=$window.FindName('TaskSummary')
$root=$window.Content
$cells=@('TaskTotalCell','TaskRunningCell','TaskWaitingCell','TaskReadyCell')
$caseCount=0
foreach($count in @(0,1,9,12,99,100,999,[int]::MaxValue)){
    Update-TaskSummary $count $count $count $count 3
    $root.Measure([Windows.Size]::new(344,180))
    $root.Arrange([Windows.Rect]::new(0,0,344,180))
    $root.UpdateLayout()
    Assert ($taskSummary.ToolTip -match ('任务 '+$count+' ·')) 'Exact total missing from tooltip'
    Assert ($taskSummary.ToolTip -match '出错 3') 'Error count missing from full summary'
    $expected=if($count -gt 99){'99+'}else{[string]$count}
    Assert ($window.FindName('TaskTotalValue').Text -eq $expected) 'Compact count incorrect'
    $previousRight=-1.0
    foreach($cellName in $cells){
        $cell=$window.FindName($cellName)
        Assert ($cell.TextTrimming -eq 'None') 'Summary unexpectedly uses ellipsis'
        $point=$cell.TranslatePoint([Windows.Point]::new(0,0),$taskSummary)
        Assert ($point.X -ge $previousRight-1) 'Summary columns overlap beyond pixel rounding'
        Assert ($point.Y -ge 0 -and $point.Y+$cell.ActualHeight -le $taskSummary.ActualHeight) 'Summary text is vertically clipped'
        $previousRight=$point.X+$cell.ActualWidth
        foreach($scale in @(1.0,1.25,1.5,2.0)){
            $textWidth=0.0
            foreach($run in $cell.Inlines){
                $face=[Windows.Media.Typeface]::new($run.FontFamily,$run.FontStyle,$run.FontWeight,$run.FontStretch)
                $formatted=[Windows.Media.FormattedText]::new($run.Text,[Globalization.CultureInfo]::GetCultureInfo('zh-CN'),[Windows.FlowDirection]::LeftToRight,$face,$run.FontSize,$run.Foreground,$scale)
                $textWidth+=$formatted.WidthIncludingTrailingWhitespace
            }
            Assert ($textWidth -le $cell.ActualWidth) ('Count text does not fit: '+$cellName+', '+$count+', scale '+$scale)
            $caseCount++
        }
    }
    $toggle=$window.FindName('TaskToggleButton')
    $summaryRight=$taskSummary.TranslatePoint([Windows.Point]::new($taskSummary.ActualWidth,0),$taskSummary.Parent)
    $toggleLeft=$toggle.TranslatePoint([Windows.Point]::new(0,0),$taskSummary.Parent)
    Assert ($summaryRight.X -le $toggleLeft.X) 'Summary overlaps dropdown button'
}

# Render at common desktop output densities without changing the user's DPI.
$window.FindName('PetImage').Source=[Windows.Media.Imaging.BitmapImage]::new([uri](Join-Path (Resolve-Path -LiteralPath $appRoot).Path 'frames\running\00.png'))
foreach($example in @('normal','large')){
    if($example -eq 'normal'){Update-TaskSummary 1 1 0 0 0}else{Update-TaskSummary 512 123 245 99 45}
    $root.UpdateLayout()
    foreach($dpi in @(96,120,144,192)){
        $render=[Windows.Media.Imaging.RenderTargetBitmap]::new([int](344*$dpi/96),[int](180*$dpi/96),$dpi,$dpi,[Windows.Media.PixelFormats]::Pbgra32)
        $render.Render($root)
        $encoder=[Windows.Media.Imaging.PngBitmapEncoder]::new()
        $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($render))
        $stream=[IO.File]::Create((Join-Path $outputRoot ('pet-summary-'+$example+'-'+$dpi+'.png')))
        try{$encoder.Save($stream)}finally{$stream.Dispose()}
    }
}
"PASS: $caseCount text-width cases, 8 count sizes, label/number alignment, vertical bounds, independent dropdown, exact tooltips, 8 density renders"
