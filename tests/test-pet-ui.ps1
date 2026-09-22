param([string]$AppRoot = (Join-Path $PSScriptRoot '..\windows-companion'))
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase,System.Windows.Forms
$AppRoot = (Resolve-Path -LiteralPath $AppRoot).Path
$outputRoot = Join-Path $PSScriptRoot '..\.test-output'
$null = New-Item -ItemType Directory -Path $outputRoot -Force
$dataRoot = $outputRoot
$tokens=$null; $parseErrors=$null
$ast=[System.Management.Automation.Language.Parser]::ParseFile((Join-Path $AppRoot 'CodexQuotaPet.ps1'),[ref]$tokens,[ref]$parseErrors)
if($parseErrors.Count){throw ($parseErrors | Out-String)}
$functions=@('Brush','Get-TaskVisual','Update-TaskList','Apply-PetSnapshot','Test-PetSnapshotFresh','Set-ActivityOffline','Format-TaskCount','Update-TaskSummary','Set-WindowPositionClamped','Set-TaskTrayExpanded','Update-PetLayout','Set-QuotaVisible','Save-UiSettings','Get-CodexThreadUri','Initialize-PetMenu','Initialize-PanelActions','Is-ButtonOrigin')
foreach($name in $functions){
    $definition=$ast.Find({param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name},$true)
    if(!$definition){throw "Missing function: $name"}
    . ([scriptblock]::Create($definition.Extent.Text))
}
function Assert($condition,[string]$message){if(!$condition){throw $message}}
[xml]$xaml=Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $AppRoot 'MainWindow.xaml')
$window=[Windows.Markup.XamlReader]::Load([System.Xml.XmlNodeReader]::new($xaml))
$realWindow=$window
foreach($name in @('TaskListPanel','TaskTrayCount','TaskTrayEmpty','TaskTray','TaskToggleButton','TaskSummary','StateLabel','StateDot','PetCaption','PetImage','QuotaBubble','RefreshButton','ClearReadyButton','TaskTrayCollapseButton','CloseButton','StatusText')){
    Set-Variable -Name $name -Value $window.FindName($name)
}
function Set-PetState([string]$name){$script:testPetState=$name}
function Open-Codex([string]$threadId=''){$script:openedThread=$threadId; $script:openCount++}
$settingsPath=Join-Path $outputRoot 'test-ui-settings.json'
$script:isQuotaVisible=$true
$script:isTaskTrayExpanded=$false
$script:testArea=[pscustomobject]@{Left=0;Top=0;Right=1536;Bottom=832}
function Get-WorkAreaInDip([bool]$followCursor){return $script:testArea}
$caseCount=0
foreach($area in @(
    @{Left=0;Top=0;Right=1536;Bottom=832},
    @{Left=-1920;Top=-120;Right=0;Bottom=920},
    @{Left=1920;Top=0;Right=3840;Bottom=1040}
)){
    $script:testArea=[pscustomobject]$area
    foreach($height in @(180,344)){
        foreach($point in @(@(-100000,-100000),@(100000,100000),@(-100000,100000),@(100000,-100000),@(800,200))){
            $window=[pscustomobject]@{Left=0;Top=0;Width=344;Height=$height;ActualWidth=344;ActualHeight=$height}
            Set-WindowPositionClamped $point[0] $point[1] $false
            Assert ($window.Left -ge $area.Left -and $window.Top -ge $area.Top) 'Top/left escaped work area'
            Assert ($window.Left+344 -le $area.Right -and $window.Top+$height -le $area.Bottom) 'Bottom/right escaped work area'
            $caseCount++
        }
    }
}
$window=$realWindow
$collapsedWindowHeight=180.0; $expandedWindowHeight=344.0
$script:testArea=[pscustomobject]@{Left=0;Top=0;Right=1536;Bottom=832}
$window.Left=1200; $window.Top=650
Set-TaskTrayExpanded $true
Assert ($window.Height -eq 344 -and $taskTray.Visibility -eq 'Visible') 'Expansion failed'
Assert ($window.Top + $window.Height -le 832) 'Expanded tray escaped bottom edge'
Set-TaskTrayExpanded $false
Assert ($window.Height -eq 180 -and $taskTray.Visibility -eq 'Collapsed') 'Collapse failed'
Set-QuotaVisible $false
Assert ($window.Width -eq 128 -and $quotaBubble.Visibility -eq 'Collapsed') 'Pet-only layout failed'
Set-TaskTrayExpanded $true
Assert ($window.Width -eq 344 -and $quotaBubble.Visibility -eq 'Collapsed' -and $taskTray.Visibility -eq 'Visible') 'Queue must work without quota bubble'
Initialize-PanelActions
Set-QuotaVisible $true
$closeButton.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
Assert (!$script:isQuotaVisible -and $script:isTaskTrayExpanded) 'Bubble close changed task visibility'
$saved=Get-Content -Raw -Encoding UTF8 -LiteralPath $settingsPath | ConvertFrom-Json
Assert (!$saved.quotaVisible -and $saved.tasksVisible) 'Visibility preferences not persisted'
Initialize-PetMenu
Assert (@($window.ContextMenu.Items | Where-Object { $_ -is [Windows.Controls.MenuItem] -and $_.Header -eq '使用说明' }).Count -eq 1) 'Usage guide menu item missing'
$window.ContextMenu.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.ContextMenu]::OpenedEvent))
Assert ($quotaMenuItem.Header -eq '显示额度气泡') 'Hidden quota menu label incorrect'
$quotaMenuItem.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.MenuItem]::ClickEvent))
Assert $script:isQuotaVisible 'Context menu did not restore quota'
$taskMenuItem.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.MenuItem]::ClickEvent))
Assert (!$script:isTaskTrayExpanded) 'Context menu did not hide queue'
$threadId='00000000-0000-4000-8000-000000000001'
Assert ((Get-CodexThreadUri $threadId) -eq ('codex://threads/'+$threadId)) 'Incorrect official deep link'
foreach($badId in @('', 'x;calc.exe', '../settings', 'codex://settings', 'bad-id')){
    $rejected=$false
    try { $null=Get-CodexThreadUri $badId } catch { $rejected=$true }
    Assert $rejected 'Unsafe task ID accepted'
}
$dragAssignment=$ast.Find({param($node) $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and $node.Left.Extent.Text -eq '$beginDrag'},$true)
. ([scriptblock]::Create($dragAssignment.Extent.Text))
$clickArgs=[pscustomobject]@{ChangedButton=[Windows.Input.MouseButton]::Left;ClickCount=2;OriginalSource=$petImage;Handled=$false}
& $beginDrag $petImage $clickArgs
Assert ($script:openCount -eq 1 -and $clickArgs.Handled) 'Double-click did not open Codex'
$items=@(
    [pscustomobject]@{id=$threadId;title='等待你的确认';state='waiting';label='需要确认';kind='codex';kindLabel='Codex';updatedAt=1},
    [pscustomobject]@{id='failed';title='出现错误的任务';state='failed';label='出错';kind='codex';kindLabel='Codex';updatedAt=1},
    [pscustomobject]@{id='ready';title='桌宠界面检查已完成';state='ready';label='已完成';kind='codex';kindLabel='Codex';updatedAt=1},
    [pscustomobject]@{id='active';title='很长的中文任务名称会显示省略号且不挤压状态';state='active';label='执行中';kind='codex';kindLabel='Codex';updatedAt=1}
)
Update-TaskList $items
Assert ($taskListPanel.Children.Count -eq 4) 'Task count incorrect'
$firstRow=$taskListPanel.Children[0]
Assert ($firstRow.Content.Children[1].Text -eq 'Codex · 等待你的确认') 'Codex task kind is not visible'
$firstRow.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
Assert ($script:openedThread -eq $threadId) 'Task row did not navigate to its own thread'
$items[0].updatedAt=2
Update-TaskList $items
Assert ([object]::ReferenceEquals($firstRow,$taskListPanel.Children[0])) 'Unchanged list was rebuilt'
$items[0].state='active'; $items[0].label='执行中'
Update-TaskList $items
Assert (![object]::ReferenceEquals($firstRow,$taskListPanel.Children[0])) 'Changed state was not refreshed'
Update-TaskList @()
Assert ($taskListPanel.Children.Count -eq 0 -and $taskTrayEmpty.Visibility -eq 'Visible') 'Empty state failed'
$items[0].state='waiting'; $items[0].label='需要确认'
$snapshot=[pscustomobject]@{petState='waiting';label='需要确认';counts=[pscustomobject]@{total=4;active=2;running=1;waiting=1;ready=1;failed=1};tasks=$items}
Apply-PetSnapshot $snapshot
Assert ($script:testPetState -eq 'waiting' -and $taskSummary.ToolTip -match '任务 4' -and $window.FindName('TaskTotalValue').Text -eq '4') 'State summary failed'
Assert (Test-PetSnapshotFresh ([pscustomobject]@{fetchedAt=100}) $false 110) 'Fresh heartbeat rejected'
Assert (!(Test-PetSnapshotFresh ([pscustomobject]@{fetchedAt=100}) $false 116)) 'Stale heartbeat accepted'
Assert (!(Test-PetSnapshotFresh ([pscustomobject]@{fetchedAt=100}) $true 100)) 'Exited bridge still treated as live'
Assert (!(Test-PetSnapshotFresh $null $false 100)) 'Missing snapshot treated as live'
Set-ActivityOffline
Assert ($script:testPetState -eq 'idle' -and $petCaption.Text -eq '状态离线') 'Disconnected animation still thinking'
Assert ($window.FindName('TaskRunningValue').Text -eq '--' -and $taskListPanel.Children.Count -eq 0) 'Stale task counts/list still shown'
$script:isDragging=$true; $script:testPetState='running-left'
Set-ActivityOffline
Assert ($script:testPetState -eq 'running-left' -and $script:basePetState -eq 'idle') 'Offline check interrupted drag'
$script:isDragging=$false
Apply-PetSnapshot $snapshot
Assert ($script:testPetState -eq 'waiting' -and $window.FindName('TaskTotalValue').Text -eq '4' -and $taskListPanel.Children.Count -eq 4) 'Reconnection failed to restore current tasks'
Assert ($taskTrayEmpty.Text -eq '暂时没有活动任务') 'Offline placeholder survived reconnection'
Set-TaskTrayExpanded $true
$window.FindName('FiveHourValue').Text='100% 剩余'
$window.FindName('FiveHourReset').Text='4小时59分'
$window.FindName('WeeklyValue').Text='100% 剩余'
$window.FindName('WeeklyReset').Text='6天23小时'
$window.FindName('StatusText').Text='PLUS 额度 · 刚刚更新'
$reset=$window.FindName('ResetCreditValue'); $reset.Text='重置 ×12'
$bitmap=[Windows.Media.Imaging.BitmapImage]::new([uri](Join-Path $AppRoot 'frames\waiting\00.png'))
$petImage.Source=$bitmap
$root=$window.Content
$root.Measure([Windows.Size]::new(344,344))
$root.Arrange([Windows.Rect]::new(0,0,344,344))
$root.UpdateLayout()
$center=$reset.TranslatePoint([Windows.Point]::new($reset.ActualWidth/2,$reset.ActualHeight/2),$reset.Parent)
Assert ([math]::Abs($center.X-$reset.Parent.ActualWidth/2) -le 1) 'Reset badge not horizontally centered'
Assert ([math]::Abs($center.Y-$reset.Parent.ActualHeight/2) -le 1) 'Reset badge not vertically centered'
foreach($textName in @('FiveHourValue','FiveHourReset','WeeklyValue','WeeklyReset','StateLabel','ResetCreditValue')){
    $control=$window.FindName($textName)
    Assert ($control.ActualHeight -ge $control.FontSize*1.3) ('Text row is too short: '+$textName)
    $point=$control.TranslatePoint([Windows.Point]::new(0,0),$quotaBubble)
    Assert ($point.Y+$control.ActualHeight -le $quotaBubble.ActualHeight) ('Text below bubble: '+$textName)
}
foreach($pair in @(@('FiveHourValue','FiveHourReset'),@('WeeklyValue','WeeklyReset'))){
    $left=$window.FindName($pair[0]); $right=$window.FindName($pair[1])
    $edge=$left.TranslatePoint([Windows.Point]::new($left.ActualWidth,0),$quotaBubble)
    $start=$right.TranslatePoint([Windows.Point]::new(0,0),$quotaBubble)
    Assert ($edge.X -le $start.X+1) 'Quota percentage overlaps countdown'
}
$render=[Windows.Media.Imaging.RenderTargetBitmap]::new(344,344,96,96,[Windows.Media.PixelFormats]::Pbgra32)
$render.Render($root)
$encoder=[Windows.Media.Imaging.PngBitmapEncoder]::new()
$encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($render))
$stream=[IO.File]::Create((Join-Path $outputRoot 'pet-ui-regression.png'))
try{$encoder.Save($stream)}finally{$stream.Dispose()}
"PASS: $caseCount boundary cases; independent visibility and persistence; context menu; close only quota; double-click; per-row navigation; ID validation; four states; stable rows; font bounds and reset centering; rendered pet-ui-regression.png"
