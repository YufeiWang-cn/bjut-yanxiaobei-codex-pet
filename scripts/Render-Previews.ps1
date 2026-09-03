param([string]$OutputDirectory)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
$repoRoot = Split-Path -Parent $PSScriptRoot
$appRoot = Join-Path $repoRoot 'windows-companion'
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $repoRoot 'docs\images' }
$null = New-Item -ItemType Directory -Path $OutputDirectory -Force
$tokens = $null; $parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $appRoot 'CodexQuotaPet.ps1'), [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw ($parseErrors | Out-String) }
foreach ($name in @('Brush','Get-TaskVisual','Update-TaskList','Apply-PetSnapshot','Format-TaskCount','Update-TaskSummary','Update-PetLayout','Set-TaskTrayExpanded','Set-QuotaVisible','Set-QuotaBar','RemainingColor')) {
    $definition = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name }, $true)
    if (-not $definition) { throw "Missing preview function: $name" }
    . ([scriptblock]::Create($definition.Extent.Text))
}
function Set-WindowPositionClamped { }
function Save-UiSettings { }
function Set-PetState([string]$name) {
    $script:petImage.Source = [Windows.Media.Imaging.BitmapImage]::new([uri](Join-Path $appRoot ('frames\' + $name + '\00.png')))
}
function Render-Element($element, [double]$width, [double]$height, [string]$name) {
    $element.Measure([Windows.Size]::new($width, $height))
    $element.Arrange([Windows.Rect]::new(0, 0, $width, $height))
    $element.UpdateLayout()
    $bitmap = [Windows.Media.Imaging.RenderTargetBitmap]::new([int]($width*2), [int]($height*2), 192, 192, [Windows.Media.PixelFormats]::Pbgra32)
    $bitmap.Render($element)
    $encoder = [Windows.Media.Imaging.PngBitmapEncoder]::new()
    $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
    $stream = [IO.File]::Create((Join-Path $OutputDirectory $name))
    try { $encoder.Save($stream) } finally { $stream.Dispose() }
    $bitmap.Freeze()
    return $bitmap
}

[xml]$xaml = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $appRoot 'MainWindow.xaml')
$window = [Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new($xaml))
foreach ($name in @('TaskListPanel','TaskTrayCount','TaskTrayEmpty','TaskTray','TaskToggleButton','TaskSummary','StateLabel','StateDot','PetCaption','PetImage','QuotaBubble')) {
    Set-Variable -Name $name -Value $window.FindName($name)
}
$collapsedWindowHeight = 180.0; $expandedWindowHeight = 344.0
$script:isQuotaVisible = $true
$script:isTaskTrayExpanded = $true
$script:isDragging = $false
$items = @(
    [pscustomobject]@{ id='00000000-0000-4000-8000-000000000001'; title='确认下一步修改'; state='waiting'; label='需要确认'; updatedAt=1 },
    [pscustomobject]@{ id='00000000-0000-4000-8000-000000000002'; title='检查构建结果'; state='failed'; label='出错'; updatedAt=1 },
    [pscustomobject]@{ id='00000000-0000-4000-8000-000000000003'; title='README 整理完成'; state='ready'; label='已完成'; updatedAt=1 },
    [pscustomobject]@{ id='00000000-0000-4000-8000-000000000004'; title='完善桌宠交互'; state='active'; label='执行中'; updatedAt=1 }
)
Apply-PetSnapshot ([pscustomobject]@{
    petState='waiting'; label='需要确认'
    counts=[pscustomobject]@{ total=4; active=2; running=1; waiting=1; ready=1; failed=1 }
    tasks=$items
})
Set-TaskTrayExpanded $true
$root = $window.Content
$root.Measure([Windows.Size]::new(344,344)); $root.Arrange([Windows.Rect]::new(0,0,344,344)); $root.UpdateLayout()
Set-QuotaBar ($window.FindName('FiveHourValue')) ($window.FindName('FiveHourBar')) 82
Set-QuotaBar ($window.FindName('WeeklyValue')) ($window.FindName('WeeklyBar')) 64
$window.FindName('FiveHourReset').Text = '3小时42分'
$window.FindName('WeeklyReset').Text = '4天12小时'
$window.FindName('ResetCreditValue').Text = '重置 ×2'
$window.FindName('StatusText').Text = '示例数据 · 非账号实况'
$expanded = Render-Element $root 344 344 'windows-expanded.png'

Set-TaskTrayExpanded $false
$null = Render-Element $root 344 180 'windows-compact.png'
Set-QuotaVisible $false
$null = Render-Element $root 128 180 'windows-pet-only.png'

# Layout-native artwork: compose the actual UI render with text, not a fake screenshot.
[xml]$heroXaml = @'
<Grid xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
      xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Width="1040" Height="560"
      TextOptions.TextFormattingMode="Display" TextOptions.TextRenderingMode="Grayscale"
      TextElement.FontFamily="Microsoft YaHei UI">
  <Grid.Background>
    <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
      <GradientStop Color="#0B1725" Offset="0"/>
      <GradientStop Color="#142F41" Offset="1"/>
    </LinearGradientBrush>
  </Grid.Background>
  <Border Margin="28" BorderBrush="#244662" BorderThickness="1" CornerRadius="24"/>
  <StackPanel Margin="66,76,0,0" Width="455" HorizontalAlignment="Left" VerticalAlignment="Top">
    <TextBlock Text="A LITTLE COMPANION FOR YOUR WORK" Foreground="#70DAD2" FontSize="12" FontWeight="SemiBold"/>
    <TextBlock Text="BJUT 燕小北" Foreground="#F4FAFF" FontSize="45" FontWeight="Bold" Margin="0,19,0,0"/>
    <TextBlock Text="把任务进度，留在桌面一角。" Foreground="#C9D8E5" FontSize="23" Margin="0,14,0,0"/>
    <TextBlock Text="一起思考，等待确认，迎接完成。" Foreground="#95AFC4" FontSize="16" Margin="0,22,0,0"/>
    <StackPanel Orientation="Horizontal" Margin="0,32,0,0">
      <Border CornerRadius="9" Background="#214256" Padding="14,9"><TextBlock Text="原生素材版" Foreground="#E1F4FF" FontSize="14"/></Border>
      <Border CornerRadius="9" Background="#164F55" Padding="12,9" Margin="10,0,0,0"><TextBlock Text="Windows 增强版" Foreground="#A7EBDD" FontSize="14"/></Border>
      <Border CornerRadius="9" Background="#343758" Padding="12,9" Margin="10,0,0,0"><TextBlock Text="macOS 实验版" Foreground="#D1C9FA" FontSize="14"/></Border>
    </StackPanel>
    <TextBlock Text="5 小时 / 每周额度 · 任务活动 · 一键收起" Foreground="#9BB6CC" FontSize="14" Margin="0,28,0,0"/>
    <TextBlock Text="个人制作  /  非官方产品" Foreground="#67849B" FontSize="12" Margin="0,46,0,0"/>
  </StackPanel>
  <Border Width="418" Height="454" HorizontalAlignment="Right" VerticalAlignment="Center" Margin="0,0,50,0"
          CornerRadius="22" Background="#0D1D2E" BorderBrush="#284153" BorderThickness="1">
    <Grid>
      <TextBlock Text="WINDOWS COMPANION" Foreground="#7196AC" FontSize="10" Margin="24,19,0,0" VerticalAlignment="Top"/>
      <Image x:Name="Preview" Width="378.4" Height="378.4" Stretch="Uniform" VerticalAlignment="Center" RenderOptions.BitmapScalingMode="HighQuality"/>
      <TextBlock Text="实际界面渲染 · 示例数据" Foreground="#7695AA" FontSize="11" Margin="0,0,0,16" VerticalAlignment="Bottom" HorizontalAlignment="Center"/>
    </Grid>
  </Border>
</Grid>
'@
$hero = [Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new($heroXaml))
$hero.FindName('Preview').Source = $expanded
$null = Render-Element $hero 1040 560 'hero.png'
Write-Output "Rendered 4 previews using fictional data: $OutputDirectory"
