param([switch]$SmokeTest, [switch]$ExpandedTest)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms

$createdNew = $false
$mutexName = if ($SmokeTest) { 'Local\YanXiaoBeiCodexPet-Test-' + $PID } else { 'Local\YanXiaoBeiCodexPet-4E8F21B3' }
$singleInstance = [Threading.Mutex]::new($true, $mutexName, [ref]$createdNew)
if (-not $createdNew) { exit 0 }

$appRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $appRoot 'CodexDesktop.ps1')
. (Join-Path $appRoot 'Runtime.ps1')
$dataRoot = Get-CompanionDataRoot
$xamlPath = Join-Path $appRoot 'MainWindow.xaml'
$bridgePath = Join-Path $appRoot 'quota-bridge.js'
$stateFile = Join-Path $dataRoot 'bridge-state.json'
$frameRoot = Join-Path $appRoot 'frames'

[xml]$xaml = Get-Content -Raw -Encoding UTF8 -LiteralPath $xamlPath
$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)

function Control([string]$name) { $window.FindName($name) }

$fiveHourValue = Control 'FiveHourValue'
$fiveHourBar = Control 'FiveHourBar'
$fiveHourReset = Control 'FiveHourReset'
$weeklyValue = Control 'WeeklyValue'
$weeklyBar = Control 'WeeklyBar'
$weeklyReset = Control 'WeeklyReset'
$resetCreditValue = Control 'ResetCreditValue'
$statusText = Control 'StatusText'
$stateDot = Control 'StateDot'
$stateLabel = Control 'StateLabel'
$taskSummary = Control 'TaskSummary'
$taskToggleButton = Control 'TaskToggleButton'
$taskTray = Control 'TaskTray'
$taskTrayCount = Control 'TaskTrayCount'
$taskTrayEmpty = Control 'TaskTrayEmpty'
$taskTrayCollapseButton = Control 'TaskTrayCollapseButton'
$taskListPanel = Control 'TaskListPanel'
$petCaption = Control 'PetCaption'
$petImage = Control 'PetImage'
$headerDragArea = Control 'HeaderDragArea'
$refreshButton = Control 'RefreshButton'
$clearReadyButton = Control 'ClearReadyButton'
$closeButton = Control 'CloseButton'
$quotaBubble = Control 'QuotaBubble'
$positionPath = Join-Path $dataRoot 'badge-position.json'
$settingsPath = Join-Path $dataRoot 'ui-settings.json'

$requiredStates = @('idle', 'running-right', 'running-left', 'waving', 'jumping', 'failed', 'waiting', 'running', 'review')
$frameSets = @{}
foreach ($name in $requiredStates) {
    $folder = Join-Path $frameRoot $name
    if (Test-Path -LiteralPath $folder) {
        $frameSets[$name] = @(Get-ChildItem -LiteralPath $folder -Filter '*.png' | Sort-Object Name | ForEach-Object FullName)
    }
}

function Read-AnimationTiming([string]$path, $frames) {
    $petTimingProfile = Get-Content -Raw -Encoding UTF8 -LiteralPath $path | ConvertFrom-Json
    if ($petTimingProfile.schemaVersion -ne 1) { throw 'Unsupported animation timing schema' }
    $durationsByState = @{}
    foreach ($state in $frames.Keys) {
        foreach ($profileName in @('companion', 'native')) {
            $durations = @($petTimingProfile.$profileName.$state)
            if ($durations.Count -ne $frames[$state].Count) { throw "Animation frame/timing mismatch: $profileName/$state" }
            foreach ($duration in $durations) {
                if ($null -eq $duration -or [double]$duration -ne [int]$duration -or [int]$duration -lt 40 -or [int]$duration -gt 5000) {
                    throw "Invalid frame duration: $profileName/$state"
                }
            }
        }
        $durationsByState[$state] = @($petTimingProfile.companion.$state | ForEach-Object { [int]$_ })
    }
    return $durationsByState
}
$frameDurations = Read-AnimationTiming (Join-Path $appRoot 'animation-timing.json') $frameSets

if ($SmokeTest) {
    $missing = @($requiredStates | Where-Object { -not $frameSets.ContainsKey($_) -or $frameSets[$_].Count -eq 0 })
    if ($missing.Count -gt 0) { throw ('缺少动画帧: ' + ($missing -join ', ')) }
    'Yan Xiaobei Codex Pet smoke test passed'
    try { $singleInstance.ReleaseMutex() } catch {}
    $singleInstance.Dispose()
    exit 0
}

$null = New-Item -ItemType Directory -Path $dataRoot -Force
$nodeExecutable = Get-CompanionNode
try {
    & (Join-Path $appRoot 'Configure-Autostart.ps1') -InitializeDefault
} catch {
    $null = [Windows.MessageBox]::Show('燕小北已启动，但自动跟随设置失败：' + $_.Exception.Message, '跟随 Codex 启动')
}
$bitmapCache = @{}
function Get-Bitmap([string]$path) {
    if (-not $bitmapCache.ContainsKey($path)) {
        $bitmap = [Windows.Media.Imaging.BitmapImage]::new()
        $bitmap.BeginInit()
        $bitmap.CacheOption = [Windows.Media.Imaging.BitmapCacheOption]::OnLoad
        $bitmap.UriSource = [Uri]::new($path, [UriKind]::Absolute)
        $bitmap.EndInit()
        $bitmap.Freeze()
        $bitmapCache[$path] = $bitmap
    }
    return $bitmapCache[$path]
}

$script:basePetState = 'idle'
$script:displayPetState = 'idle'
$script:frameIndex = 0
$script:isDragging = $false
$script:dragCapture = $null

$animationTimer = [Windows.Threading.DispatcherTimer]::new()
function Render-PetFrame {
    $files = $frameSets[$script:displayPetState]
    if ($null -eq $files -or $files.Count -eq 0) { return }
    if ($script:frameIndex -ge $files.Count) { $script:frameIndex = 0 }
    $petImage.Source = Get-Bitmap $files[$script:frameIndex]
    $durations = $frameDurations[$script:displayPetState]
    $duration = if ($null -ne $durations -and $script:frameIndex -lt $durations.Count) {
        [int]$durations[$script:frameIndex]
    } else { 220 }
    $animationTimer.Interval = [TimeSpan]::FromMilliseconds($duration)
}
function Set-PetState([string]$name) {
    if (-not $frameSets.ContainsKey($name)) { $name = 'idle' }
    if ($script:displayPetState -eq $name -and $null -ne $petImage.Source) { return }
    $script:displayPetState = $name
    $script:frameIndex = 0
    Render-PetFrame
}
$animationTimer.add_Tick({
    $files = $frameSets[$script:displayPetState]
    if ($null -ne $files -and $files.Count -gt 0) {
        $script:frameIndex = ($script:frameIndex + 1) % $files.Count
        Render-PetFrame
    }
})
Set-PetState 'idle'
$animationTimer.Start()

try {
    if (Test-Path -LiteralPath $positionPath) {
        $savedPosition = Get-Content -Raw -LiteralPath $positionPath | ConvertFrom-Json
        $window.Left = [double]$savedPosition.left
        $window.Top = [double]$savedPosition.top
    } else {
        $workArea = [Windows.SystemParameters]::WorkArea
        $window.Left = $workArea.Right - $window.Width - 18
        $window.Top = $workArea.Bottom - $window.Height - 36
    }
} catch {
    $workArea = [Windows.SystemParameters]::WorkArea
    $window.Left = $workArea.Right - $window.Width - 18
    $window.Top = $workArea.Bottom - $window.Height - 36
}

function Save-Position {
    try {
        @{ left = [math]::Round($window.Left, 1); top = [math]::Round($window.Top, 1) } |
            ConvertTo-Json -Compress | Set-Content -LiteralPath $positionPath -Encoding utf8
    } catch {}
}

function Get-ScreenPointInDip([int]$x, [int]$y) {
    $point = [Windows.Point]::new([double]$x, [double]$y)
    $source = [Windows.PresentationSource]::FromVisual($window)
    if ($null -ne $source -and $null -ne $source.CompositionTarget) {
        return $source.CompositionTarget.TransformFromDevice.Transform($point)
    }
    return $point
}
function Get-WorkAreaInDip([bool]$followCursor) {
    if ($followCursor) {
        $cursor = [System.Windows.Forms.Cursor]::Position
        $screen = [System.Windows.Forms.Screen]::FromPoint($cursor)
    } else {
        $helper = [System.Windows.Interop.WindowInteropHelper]::new($window)
        if ($helper.Handle -ne [IntPtr]::Zero) {
            $screen = [System.Windows.Forms.Screen]::FromHandle($helper.Handle)
        } else {
            $screen = [System.Windows.Forms.Screen]::PrimaryScreen
        }
    }
    $topLeft = Get-ScreenPointInDip $screen.WorkingArea.Left $screen.WorkingArea.Top
    $bottomRight = Get-ScreenPointInDip $screen.WorkingArea.Right $screen.WorkingArea.Bottom
    return [pscustomobject]@{
        Left = $topLeft.X; Top = $topLeft.Y
        Right = $bottomRight.X; Bottom = $bottomRight.Y
    }
}
function Set-WindowPositionClamped([double]$left, [double]$top, [bool]$followCursor) {
    $area = Get-WorkAreaInDip $followCursor
    # Explicit target dimensions also work during the resize/layout transition.
    $width = $window.Width
    $height = $window.Height
    $gap = 4.0
    $minimumLeft = $area.Left + $gap
    $minimumTop = $area.Top + $gap
    $maximumLeft = [math]::Max($minimumLeft, $area.Right - $width - $gap)
    $maximumTop = [math]::Max($minimumTop, $area.Bottom - $height - $gap)
    $window.Left = [math]::Round([math]::Max($minimumLeft, [math]::Min($maximumLeft, $left)))
    $window.Top = [math]::Round([math]::Max($minimumTop, [math]::Min($maximumTop, $top)))
}

$script:isTaskTrayExpanded = $false
$script:isQuotaVisible = $true
$collapsedWindowHeight = 180.0
$expandedWindowHeight = 344.0
function Save-UiSettings {
    try {
        @{ quotaVisible = $script:isQuotaVisible; tasksVisible = $script:isTaskTrayExpanded } |
            ConvertTo-Json -Compress | Set-Content -LiteralPath $settingsPath -Encoding utf8
    } catch {}
}
function Update-PetLayout {
    $window.Width = if ($script:isQuotaVisible -or $script:isTaskTrayExpanded) { 344 } else { 128 }
    $window.Height = if ($script:isTaskTrayExpanded) { $expandedWindowHeight } else { $collapsedWindowHeight }
    $window.UpdateLayout()
    Set-WindowPositionClamped $window.Left $window.Top $false
}
function Set-QuotaVisible([bool]$visible) {
    $script:isQuotaVisible = $visible
    $quotaBubble.Visibility = if ($visible) { [Windows.Visibility]::Visible } else { [Windows.Visibility]::Collapsed }
    Update-PetLayout
    if ($visible -and $null -ne $script:lastQuotaSnapshot) { Apply-Snapshot $script:lastQuotaSnapshot }
    Save-UiSettings
}
function Set-TaskTrayExpanded([bool]$expanded) {
    $script:isTaskTrayExpanded = $expanded
    if ($expanded) {
        $taskTray.Visibility = [Windows.Visibility]::Visible
        $taskToggleButton.Content = '▴'
        $taskToggleButton.ToolTip = '收起任务活动'
    } else {
        $taskTray.Visibility = [Windows.Visibility]::Collapsed
        $taskToggleButton.Content = '▾'
        $taskToggleButton.ToolTip = '展开任务活动'
    }
    Update-PetLayout
    Save-UiSettings
}

function Get-CodexThreadUri([string]$threadId) {
    # Never pass task titles or arbitrary log contents to the Windows shell.
    if ($threadId -notmatch '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') {
        throw '该任务没有有效的本机会话 ID，无法跳转。'
    }
    return 'codex://threads/' + [Uri]::EscapeDataString($threadId)
}
function Start-CodexUri([string]$uri) {
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $uri
    $info.UseShellExecute = $true
    $null = [Diagnostics.Process]::Start($info)
}
function Open-Codex([string]$threadId = '') {
    try {
        if (-not [string]::IsNullOrWhiteSpace($threadId)) {
            Start-CodexUri (Get-CodexThreadUri $threadId)
            return
        }
        # Double-click only restores the existing window; task rows alone route.
        Show-CodexDesktop
    } catch {
        [Windows.MessageBox]::Show($window, ('无法打开 Codex：' + $_.Exception.Message), '燕小北 · 打开 Codex') | Out-Null
    }
}

$quotaState = [ordered]@{
    FiveHourResetAt = $null
    WeeklyResetAt = $null
    ResetCreditExpiresAt = $null
}

function Brush([string]$color) {
    return [Windows.Media.BrushConverter]::new().ConvertFromString($color)
}
function Get-TaskVisual([string]$state) {
    switch ($state) {
        'waiting' { return @{ Dot = '#FFFFD166'; Badge = '#30FFD166'; Text = '#FFFFDA80' } }
        'failed'  { return @{ Dot = '#FFFF6B6B'; Badge = '#30FF6B6B'; Text = '#FFFF9292' } }
        'ready'   { return @{ Dot = '#FF9B8CFF'; Badge = '#309B8CFF'; Text = '#FFC4BCFF' } }
        default   { return @{ Dot = '#FF62D6F1'; Badge = '#3062D6F1'; Text = '#FFA8EDF5' } }
    }
}
function Update-TaskList($tasks) {
    $items = @($tasks | Where-Object { $null -ne $_ })
    $listKey = ConvertTo-Json -InputObject @($items | Select-Object id,title,state,label,kindLabel) -Compress
    if ($listKey -eq $script:lastTaskListKey) { return }
    $script:lastTaskListKey = $listKey
    $taskListPanel.Children.Clear()
    $taskTrayCount.Text = ('{0} 项' -f $items.Count)
    $taskTrayEmpty.Visibility = if ($items.Count -eq 0) { [Windows.Visibility]::Visible } else { [Windows.Visibility]::Collapsed }

    foreach ($task in $items) {
        $visual = Get-TaskVisual ([string]$task.state)
        $row = [Windows.Controls.Button]::new()
        $row.Style = $window.FindResource('TaskButton')
        $row.Margin = [Windows.Thickness]::new(0, 0, 0, 4)
        $row.Tag = [string]$task.id
        $kindLabel = if ([string]$task.kindLabel) { [string]$task.kindLabel } else { 'Codex' }
        $row.ToolTip = $kindLabel + ' · ' + [string]$task.title + "`n点击在 Codex 中打开此任务"
        [Windows.Automation.AutomationProperties]::SetName($row, ($kindLabel + '，' + [string]$task.title + '，' + [string]$task.label))
        $row.add_Click({ param($sender, $eventArgs) Open-Codex ([string]$sender.Tag); $eventArgs.Handled = $true })

        $grid = [Windows.Controls.Grid]::new()
        $columnDot = [Windows.Controls.ColumnDefinition]::new()
        $columnDot.Width = [Windows.GridLength]::new(14)
        $columnTitle = [Windows.Controls.ColumnDefinition]::new()
        $columnTitle.Width = [Windows.GridLength]::new(1, [Windows.GridUnitType]::Star)
        $columnBadge = [Windows.Controls.ColumnDefinition]::new()
        $columnBadge.Width = [Windows.GridLength]::new(62)
        $null = $grid.ColumnDefinitions.Add($columnDot)
        $null = $grid.ColumnDefinitions.Add($columnTitle)
        $null = $grid.ColumnDefinitions.Add($columnBadge)

        $dot = [Windows.Shapes.Ellipse]::new()
        $dot.Width = 7; $dot.Height = 7
        $dot.Fill = Brush $visual.Dot
        $dot.HorizontalAlignment = [Windows.HorizontalAlignment]::Left
        $dot.VerticalAlignment = [Windows.VerticalAlignment]::Center
        $null = $grid.Children.Add($dot)

        $title = [Windows.Controls.TextBlock]::new()
        $title.Text = $kindLabel + ' · ' + [string]$task.title
        $title.FontFamily = [Windows.Media.FontFamily]::new('Microsoft YaHei UI')
        $title.FontSize = 10
        $title.Foreground = Brush '#FFF0F3F8'
        $title.VerticalAlignment = [Windows.VerticalAlignment]::Center
        $title.TextTrimming = [Windows.TextTrimming]::CharacterEllipsis
        $title.Margin = [Windows.Thickness]::new(0, 0, 5, 0)
        [Windows.Controls.Grid]::SetColumn($title, 1)
        $null = $grid.Children.Add($title)

        $badge = [Windows.Controls.Border]::new()
        $badge.Width = 60; $badge.Height = 22
        $badge.CornerRadius = [Windows.CornerRadius]::new(7)
        $badge.Background = Brush $visual.Badge
        $badge.HorizontalAlignment = [Windows.HorizontalAlignment]::Right
        $badge.VerticalAlignment = [Windows.VerticalAlignment]::Center
        [Windows.Controls.Grid]::SetColumn($badge, 2)

        $badgeText = [Windows.Controls.TextBlock]::new()
        $badgeText.Text = [string]$task.label
        $badgeText.FontFamily = [Windows.Media.FontFamily]::new('Microsoft YaHei UI')
        $badgeText.FontSize = 10
        $badgeText.FontWeight = [Windows.FontWeights]::SemiBold
        $badgeText.Foreground = Brush $visual.Text
        $badgeText.HorizontalAlignment = [Windows.HorizontalAlignment]::Center
        $badgeText.VerticalAlignment = [Windows.VerticalAlignment]::Center
        $badgeText.TextAlignment = [Windows.TextAlignment]::Center
        $badge.Child = $badgeText
        $null = $grid.Children.Add($badge)

        $row.Content = $grid
        $null = $taskListPanel.Children.Add($row)
    }
}
function RemainingColor([double]$remaining) {
    if ($remaining -le 20) { return '#FFFF6B6B' }
    if ($remaining -le 45) { return '#FFFFD166' }
    return '#FF66D9A7'
}
function Format-Countdown($epoch) {
    if ($null -eq $epoch) { return '时间未知' }
    $target = [DateTimeOffset]::FromUnixTimeSeconds([int64]$epoch).ToLocalTime()
    $span = $target - [DateTimeOffset]::Now
    if ($span.TotalSeconds -le 0) { return '即将重置' }
    if ($span.TotalDays -ge 1) { return ('{0}天{1}小时' -f [math]::Floor($span.TotalDays), $span.Hours) }
    return ('{0}小时{1}分' -f [math]::Floor($span.TotalHours), $span.Minutes)
}
function Set-QuotaBar($valueControl, $barControl, [double]$remaining) {
    $remaining = [math]::Max(0, [math]::Min(100, $remaining))
    $valueControl.Text = ('{0:0}% 剩余' -f $remaining)
    $trackWidth = [double]$barControl.Parent.ActualWidth
    if ($trackWidth -le 0) { $trackWidth = 165 }
    $barControl.Width = $trackWidth * $remaining / 100
    $barControl.Background = Brush (RemainingColor $remaining)
}
function Update-Countdowns {
    $fiveHourReset.Text = Format-Countdown $quotaState.FiveHourResetAt
    $weeklyReset.Text = Format-Countdown $quotaState.WeeklyResetAt
    if ($null -ne $quotaState.FiveHourResetAt) {
        $target = [DateTimeOffset]::FromUnixTimeSeconds([int64]$quotaState.FiveHourResetAt).ToLocalTime()
        $fiveHourReset.ToolTip = ('5 小时额度于 {0:yyyy-MM-dd HH:mm} 重置' -f $target)
    }
    if ($null -ne $quotaState.WeeklyResetAt) {
        $target = [DateTimeOffset]::FromUnixTimeSeconds([int64]$quotaState.WeeklyResetAt).ToLocalTime()
        $weeklyReset.ToolTip = ('每周额度于 {0:yyyy-MM-dd HH:mm} 重置' -f $target)
    }
    if ($null -ne $quotaState.ResetCreditExpiresAt) {
        $expiry = [DateTimeOffset]::FromUnixTimeSeconds([int64]$quotaState.ResetCreditExpiresAt).ToLocalTime()
        $resetCreditValue.ToolTip = ('最近一张 {0:yyyy-MM-dd HH:mm} 到期' -f $expiry)
    }
}
function Apply-Snapshot($data) {
    $script:lastQuotaSnapshot = $data
    if ($null -ne $data.primary) {
        $quotaState.FiveHourResetAt = $data.primary.resetsAt
        Set-QuotaBar $fiveHourValue $fiveHourBar (100 - [double]$data.primary.usedPercent)
    }
    if ($null -ne $data.secondary) {
        $quotaState.WeeklyResetAt = $data.secondary.resetsAt
        Set-QuotaBar $weeklyValue $weeklyBar (100 - [double]$data.secondary.usedPercent)
    }
    if ($null -ne $data.resetCredits) {
        $resetCreditValue.Text = ('重置 ×{0}' -f [int]$data.resetCredits.availableCount)
        $resetCreditValue.ToolTip = '可用重置次数（只读显示，不会执行重置）'
        $quotaState.ResetCreditExpiresAt = $data.resetCredits.expiresAt
    } else {
        $resetCreditValue.Text = '重置 --'
        $resetCreditValue.ToolTip = '当前账号接口未提供可重置次数'
        $quotaState.ResetCreditExpiresAt = $null
    }
    $planName = if ([string]::IsNullOrWhiteSpace([string]$data.planType)) { 'CODEX' } else { $data.planType.ToString().ToUpper() }
    $updatedAt = if ($data.fetchedAtMs) { [DateTimeOffset]::FromUnixTimeMilliseconds([int64]$data.fetchedAtMs) }
        elseif ($data.fetchedAt) { [DateTimeOffset]::FromUnixTimeSeconds([int64]$data.fetchedAt) }
        else { $null }
    $age = if ($null -ne $updatedAt) { [math]::Max(0, [math]::Floor(([DateTimeOffset]::UtcNow - $updatedAt).TotalSeconds)) } else { $null }
    $when = if ($null -eq $age) { '更新时间未知' }
        elseif ($age -lt 10) { '刚刚更新' }
        elseif ($age -lt 60) { ('{0} 秒前更新' -f $age) }
        elseif ($age -lt 3600) { ('{0} 分钟前更新' -f [math]::Floor($age / 60)) }
        else { ('上次更新 {0:MM-dd HH:mm}' -f $updatedAt.ToLocalTime()) }
    $statusText.Text = ('{0} 额度 · {1}' -f $planName, $when)
    Update-Countdowns
}

function Format-TaskCount([int]$count) {
    if ($count -gt 99) { return '99+' }
    return ([math]::Max(0, $count)).ToString([Globalization.CultureInfo]::InvariantCulture)
}
function Update-TaskSummary([int]$total, [int]$running, [int]$waiting, [int]$ready, [int]$failed) {
    # Keep labels stable and each count in its own column; do not ellipsize the
    # whole row. Exact counts remain available in the tooltip and accessibility.
    $values = @{ TaskTotalValue = $total; TaskRunningValue = $running; TaskWaitingValue = $waiting; TaskReadyValue = $ready }
    foreach ($name in $values.Keys) { $window.FindName($name).Text = Format-TaskCount $values[$name] }
    $summary = '任务 {0} · 进行 {1} · 待确认 {2} · 完成 {3} · 出错 {4}' -f $total, $running, $waiting, $ready, $failed
    $taskSummary.ToolTip = $summary
    [Windows.Automation.AutomationProperties]::SetName($taskSummary, $summary)
}
function Apply-PetSnapshot($data) {
    $taskTrayEmpty.Text = '暂时没有活动任务'
    $script:basePetState = [string]$data.petState
    if (-not $script:isDragging) { Set-PetState $script:basePetState }
    $counts = $data.counts
    $stateLabel.Text = ' · ' + [string]$data.label
    $petCaption.Text = [string]$data.label
    $running = if ($null -ne $counts.PSObject.Properties['running']) { [int]$counts.running } else { [math]::Max(0, [int]$counts.active - [int]$counts.waiting) }
    $total = if ($null -ne $counts.PSObject.Properties['total']) { [int]$counts.total } else { $running + [int]$counts.waiting + [int]$counts.ready + [int]$counts.failed }
    Update-TaskSummary $total $running $counts.waiting $counts.ready $counts.failed
    Update-TaskList $data.tasks
    switch ($data.petState) {
        'running' { $stateDot.Fill = Brush '#FF62D6F1'; $stateLabel.Foreground = Brush '#FF8FE7F6' }
        'waiting' { $stateDot.Fill = Brush '#FFFFD166'; $stateLabel.Foreground = Brush '#FFFFDA80' }
        'failed'  { $stateDot.Fill = Brush '#FFFF6B6B'; $stateLabel.Foreground = Brush '#FFFF9292' }
        'review'  { $stateDot.Fill = Brush '#FF9B8CFF'; $stateLabel.Foreground = Brush '#FFB9AEFF' }
        default   { $stateDot.Fill = Brush '#FF72DDB4'; $stateLabel.Foreground = Brush '#FFA1E8CC' }
    }
}

function Test-PetSnapshotFresh($pet, [bool]$bridgeExited, [double]$nowSeconds) {
    if ($bridgeExited -or $null -eq $pet -or $null -eq $pet.fetchedAt) { return $false }
    $age = $nowSeconds - [double]$pet.fetchedAt
    return ($age -ge -5 -and $age -le 15)
}
function Set-ActivityOffline {
    $script:basePetState = 'idle'
    if (-not $script:isDragging) { Set-PetState 'idle' }
    $stateLabel.Text = ' · 状态暂不可用'
    $petCaption.Text = '状态离线'
    $stateDot.Fill = Brush '#FF94A3B8'
    $stateLabel.Foreground = Brush '#FFCBD5E1'
    Update-TaskList @()
    $taskTrayEmpty.Text = '状态暂不可用，恢复连接后更新'
    $taskTrayCount.Text = '-- 项'
    foreach ($name in @('TaskTotalValue','TaskRunningValue','TaskWaitingValue','TaskReadyValue')) {
        $window.FindName($name).Text = '--'
    }
    $taskSummary.ToolTip = '状态暂不可用；不代表任务已停止'
    [Windows.Automation.AutomationProperties]::SetName($taskSummary, '状态暂不可用')
}

$startInfo = [System.Diagnostics.ProcessStartInfo]::new()
$startInfo.FileName = $nodeExecutable
$startInfo.Arguments = '"' + $bridgePath + '"'
$startInfo.WorkingDirectory = $appRoot
$startInfo.UseShellExecute = $false
$startInfo.EnvironmentVariables['YANXIAOBEI_DATA_DIR'] = $dataRoot
$startInfo.CreateNoWindow = $true
$startInfo.RedirectStandardOutput = $false
$startInfo.RedirectStandardError = $false
$startInfo.RedirectStandardInput = $true

$bridge = [System.Diagnostics.Process]::new()
$bridge.StartInfo = $startInfo
$null = $bridge.Start()

$uiTimer = [Windows.Threading.DispatcherTimer]::new()
$uiTimer.Interval = [TimeSpan]::FromMilliseconds(500)
$script:lastStateFileWriteUtc = [datetime]::MinValue
$script:lastPetSnapshot = $null
$script:lastQuotaSnapshotKey = $null
$uiTimer.add_Tick({
    Remember-CodexForegroundWindow
    if (Test-Path -LiteralPath $stateFile) {
        try {
            $stateFileInfo = Get-Item -LiteralPath $stateFile
            if ($stateFileInfo.LastWriteTimeUtc -ne $script:lastStateFileWriteUtc) {
                $data = Get-Content -Raw -Encoding UTF8 -LiteralPath $stateFile | ConvertFrom-Json
                $script:lastPetSnapshot = $data.pet
                $nowSeconds = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
                if (Test-PetSnapshotFresh $data.pet $bridge.HasExited $nowSeconds) { Apply-PetSnapshot $data.pet }
                if ($null -ne $data.quota) {
                    $quotaKey = ConvertTo-Json -InputObject $data.quota -Compress -Depth 8
                    if ($quotaKey -ne $script:lastQuotaSnapshotKey) {
                        Apply-Snapshot $data.quota
                        $script:lastQuotaSnapshotKey = $quotaKey
                    }
                }
                if ($null -ne $data.error) {
                    if ($data.error.scope -eq 'activity') {
                        $script:lastPetSnapshot = $null
                    } else { $statusText.Text = [string]$data.error.message }
                }
                $script:lastStateFileWriteUtc = $stateFileInfo.LastWriteTimeUtc
            }
        } catch {
            # The bridge may be between two small file writes; retry on the next tick.
        }
    }
    if (-not (Test-PetSnapshotFresh $script:lastPetSnapshot $bridge.HasExited ([DateTimeOffset]::UtcNow.ToUnixTimeSeconds()))) {
        Set-ActivityOffline
    }
    if ($bridge.HasExited -and $statusText.Text -notmatch '退出') { $statusText.Text = 'Codex 数据桥已退出' }
})
$uiTimer.Start()

$countdownTimer = [Windows.Threading.DispatcherTimer]::new()
$countdownTimer.Interval = [TimeSpan]::FromSeconds(30)
$countdownTimer.add_Tick({ Update-Countdowns })
$countdownTimer.Start()

function Send-BridgeCommand([string]$command) {
    if (-not $bridge.HasExited) {
        $bridge.StandardInput.WriteLine($command)
        $bridge.StandardInput.Flush()
    }
}
function Initialize-PanelActions {
    $refreshButton.add_Click({ Send-BridgeCommand 'refresh'; $statusText.Text = '正在刷新…' })
    $clearReadyButton.add_Click({ Send-BridgeCommand 'clear-ready' })
    $taskToggleButton.add_Click({ Set-TaskTrayExpanded (-not $script:isTaskTrayExpanded) })
    $taskTrayCollapseButton.add_Click({ Set-TaskTrayExpanded $false })
    $closeButton.add_Click({ Set-QuotaVisible $false })
}
Initialize-PanelActions

function Set-FollowCodex([bool]$enabled) {
    try {
        & (Join-Path $appRoot 'Configure-Autostart.ps1') -Enable:$enabled -Disable:(!$enabled)
    } catch {
        $null = [Windows.MessageBox]::Show($_.Exception.Message, '自启动设置失败')
    }
    $script:followMenuItem.IsChecked = Test-Path -LiteralPath (Join-Path $dataRoot 'autostart-enabled.flag')
}

function Open-UsageGuide {
    $guide = Join-Path (Split-Path -Parent $appRoot) 'START-HERE.html'
    if (-not (Test-Path -LiteralPath $guide -PathType Leaf)) {
        $null = [Windows.MessageBox]::Show('请完整解压下载包，保留根目录的 START-HERE.html 使用说明。', '使用说明')
        return
    }
    $info = [Diagnostics.ProcessStartInfo]::new($guide)
    $info.UseShellExecute = $true
    $null = [Diagnostics.Process]::Start($info)
}

$updatePreferencePath = Join-Path $dataRoot 'update-preferences.json'
$script:updateProcess = $null
$script:updateManual = $false
$updateTimer = [Windows.Threading.DispatcherTimer]::new()
$updateTimer.Interval = [TimeSpan]::FromMilliseconds(250)
function Open-ReleasePage([string]$url) {
    if ($url -notmatch '^https://github\.com/YufeiWang-cn/bjut-yanxiaobei-codex-pet/releases(?:/tag/v\d+\.\d+\.\d+)?$') {
        throw 'Unexpected release URL'
    }
    $browser = [Diagnostics.ProcessStartInfo]::new($url)
    $browser.UseShellExecute = $true
    $null = [Diagnostics.Process]::Start($browser)
}
function New-ReleaseUpdateDialog($result) {
    $dialog = [Windows.Window]::new()
    $dialog.Title = '燕小北发现新版本'
    $dialog.Width = [math]::Min(560, [Windows.SystemParameters]::WorkArea.Width - 32)
    $dialog.Height = [math]::Min(400, [Windows.SystemParameters]::WorkArea.Height - 32)
    $dialog.MinWidth = [math]::Min(390, $dialog.Width)
    $dialog.MinHeight = [math]::Min(285, $dialog.Height)
    $dialog.WindowStartupLocation = [Windows.WindowStartupLocation]::CenterOwner
    if ($window.IsVisible) { $dialog.Owner = $window }
    $dialog.FontFamily = [Windows.Media.FontFamily]::new('Microsoft YaHei UI')
    $dialog.Background = [Windows.Media.Brushes]::White
    $dialog.Tag = 'later'
    $grid = [Windows.Controls.Grid]::new()
    $grid.Margin = [Windows.Thickness]::new(18)
    $grid.Background = [Windows.Media.Brushes]::White
    foreach ($height in @([Windows.GridLength]::Auto, [Windows.GridLength]::new(1, [Windows.GridUnitType]::Star), [Windows.GridLength]::Auto)) {
        $row = [Windows.Controls.RowDefinition]::new(); $row.Height = $height
        $null = $grid.RowDefinitions.Add($row)
    }
    $heading = [Windows.Controls.TextBlock]::new()
    $heading.Text = "当前版本 $($result.local)  →  新版本 $($result.latest)`n更新内容："
    $heading.TextWrapping = [Windows.TextWrapping]::Wrap
    $heading.FontSize = 14
    $heading.Margin = [Windows.Thickness]::new(0, 0, 0, 10)
    [Windows.Controls.Grid]::SetRow($heading, 0); $null = $grid.Children.Add($heading)
    $notes = [Windows.Controls.TextBox]::new()
    $notes.Name = 'ReleaseNotes'
    $notes.Text = [string]$result.summary
    $notes.IsReadOnly = $true
    $notes.TextWrapping = [Windows.TextWrapping]::Wrap
    $notes.VerticalScrollBarVisibility = [Windows.Controls.ScrollBarVisibility]::Auto
    $notes.HorizontalScrollBarVisibility = [Windows.Controls.ScrollBarVisibility]::Disabled
    $notes.Padding = [Windows.Thickness]::new(10)
    $notes.FontSize = 12
    [Windows.Controls.Grid]::SetRow($notes, 1); $null = $grid.Children.Add($notes)
    $buttons = [Windows.Controls.StackPanel]::new()
    $buttons.Orientation = [Windows.Controls.Orientation]::Horizontal
    $buttons.HorizontalAlignment = [Windows.HorizontalAlignment]::Right
    $buttons.Margin = [Windows.Thickness]::new(0, 12, 0, 0)
    foreach ($spec in @(
        @{ Text = '前往更新'; Value = 'open' },
        @{ Text = '忽略此版本'; Value = 'ignore' },
        @{ Text = '暂时忽略'; Value = 'later' }
    )) {
        $button = [Windows.Controls.Button]::new()
        $button.Content = $spec.Text
        $button.Tag = $spec.Value
        $button.MinWidth = 106
        $button.Padding = [Windows.Thickness]::new(8, 6, 8, 6)
        $button.Margin = [Windows.Thickness]::new(6, 0, 0, 0)
        $button.add_Click({ param($sender, $eventArgs) $dialog.Tag = $sender.Tag; $dialog.Close() }.GetNewClosure())
        $null = $buttons.Children.Add($button)
    }
    [Windows.Controls.Grid]::SetRow($buttons, 2); $null = $grid.Children.Add($buttons)
    $dialog.Content = $grid
    return $dialog
}
function Show-ReleaseUpdateDialog($result) {
    $dialog = New-ReleaseUpdateDialog $result
    $null = $dialog.ShowDialog()
    return [string]$dialog.Tag
}
function Start-UpdateCheck([bool]$manual) {
    if ($null -ne $script:updateProcess) {
        if ($manual) { $script:updateManual = $true; $statusText.Text = '正在检查 GitHub 更新…' }
        return
    }
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $nodeExecutable
    $info.Arguments = '"' + (Join-Path $appRoot 'update-check.js') + '"'
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    # Start.vbs uses Windows PowerShell 5.1; its inherited code page may not be UTF-8.
    # Node always writes UTF-8 JSON, including Chinese GitHub release notes.
    $info.StandardOutputEncoding = [Text.Encoding]::UTF8
    try {
        $script:updateProcess = [Diagnostics.Process]::Start($info)
        $script:updateManual = $manual
        if ($manual) { $statusText.Text = '正在检查 GitHub 更新…' }
        $updateTimer.Start()
    } catch {
        if ($manual) { $null = [Windows.MessageBox]::Show($_.Exception.Message, '检查更新失败') }
    }
}
$updateTimer.add_Tick({
    if ($null -eq $script:updateProcess -or -not $script:updateProcess.HasExited) { return }
    $updateTimer.Stop()
    $process = $script:updateProcess
    $script:updateProcess = $null
    try {
        $result = $process.StandardOutput.ReadToEnd() | ConvertFrom-Json
        if ($result.status -eq 'error') {
            if ($script:updateManual) {
                $statusText.Text = '检查更新失败'
                $choice = [Windows.MessageBox]::Show("$($result.message)`n`n是否打开 GitHub 发布页手动查看？", '检查更新失败', [Windows.MessageBoxButton]::YesNo, [Windows.MessageBoxImage]::Warning)
                if ($choice -eq [Windows.MessageBoxResult]::Yes) { Open-ReleasePage 'https://github.com/YufeiWang-cn/bjut-yanxiaobei-codex-pet/releases' }
            }
            return
        }
        if ($script:updateManual) { $statusText.Text = '检查更新完成' }
        if ($result.status -ne 'update') {
            if ($script:updateManual) {
                $message = if ($result.latest) { "当前版本 $($result.local)；GitHub 最新已发布版本 $($result.latest)。没有更高的新版本。" }
                    else { "当前版本 $($result.local)；GitHub 暂无可检查的发布包。" }
                $null = [Windows.MessageBox]::Show($message, '检查更新')
            }
            return
        }
        $ignored = ''
        try { $ignored = (Get-Content -Raw -Encoding UTF8 -LiteralPath $updatePreferencePath | ConvertFrom-Json).ignoredVersion } catch {}
        if (-not $script:updateManual -and $ignored -eq $result.latest) { return }
        $choice = Show-ReleaseUpdateDialog $result
        if ($choice -eq 'open') { Open-ReleasePage $result.link }
        elseif ($choice -eq 'ignore') {
            [IO.File]::WriteAllText($updatePreferencePath, ('{"ignoredVersion":"' + $result.latest + '"}'), [Text.UTF8Encoding]::new($false))
        }
    } catch { if ($script:updateManual) { $null = [Windows.MessageBox]::Show($_.Exception.Message, '检查更新失败') } }
    finally { $script:updateManual = $false; $process.Dispose() }
})

function Initialize-PetMenu {
    $menu = [Windows.Controls.ContextMenu]::new()
    $menu.FontFamily = [Windows.Media.FontFamily]::new('Microsoft YaHei UI')
    $menu.FontSize = 12
    $menu.MinWidth = 185
    $script:quotaMenuItem = [Windows.Controls.MenuItem]::new()
    $script:taskMenuItem = [Windows.Controls.MenuItem]::new()
    $script:followMenuItem = [Windows.Controls.MenuItem]::new()
    $script:followMenuItem.Header = '跟随 Codex 启动'
    $script:followMenuItem.IsCheckable = $true
    $script:followMenuItem.add_Click({ Set-FollowCodex $script:followMenuItem.IsChecked })
    $openItem = [Windows.Controls.MenuItem]::new(); $openItem.Header = '打开 Codex'
    $openItem.add_Click({ Open-Codex })
    $script:quotaMenuItem.add_Click({ Set-QuotaVisible (-not $script:isQuotaVisible) })
    $script:taskMenuItem.add_Click({ Set-TaskTrayExpanded (-not $script:isTaskTrayExpanded) })
    $refreshItem = [Windows.Controls.MenuItem]::new(); $refreshItem.Header = '刷新额度与状态'
    $refreshItem.add_Click({ Send-BridgeCommand 'refresh'; $statusText.Text = '正在刷新…' })
    $updateItem = [Windows.Controls.MenuItem]::new(); $updateItem.Header = '检查更新'
    $updateItem.add_Click({ Start-UpdateCheck $true })
    $helpItem = [Windows.Controls.MenuItem]::new(); $helpItem.Header = '使用说明'
    $helpItem.add_Click({ Open-UsageGuide })
    $clearItem = [Windows.Controls.MenuItem]::new(); $clearItem.Header = '清除完成 / 错误提醒'
    $clearItem.add_Click({ Send-BridgeCommand 'clear-ready' })
    $exitItem = [Windows.Controls.MenuItem]::new(); $exitItem.Header = '关闭桌宠'
    $exitItem.add_Click({ $window.Close() })
    foreach ($item in @($openItem, $script:quotaMenuItem, $script:taskMenuItem, $script:followMenuItem, [Windows.Controls.Separator]::new(), $refreshItem, $updateItem, $helpItem, $clearItem, [Windows.Controls.Separator]::new(), $exitItem)) {
        $null = $menu.Items.Add($item)
    }
    $menu.add_Opened({
        $script:quotaMenuItem.Header = if ($script:isQuotaVisible) { '隐藏额度气泡' } else { '显示额度气泡' }
        $script:taskMenuItem.Header = if ($script:isTaskTrayExpanded) { '隐藏任务队列' } else { '显示任务队列' }
        $script:followMenuItem.IsChecked = Test-Path -LiteralPath (Join-Path $dataRoot 'autostart-enabled.flag')
    })
    $window.ContextMenu = $menu
}
Initialize-PetMenu

function Is-ButtonOrigin($origin, $boundary) {
    $node = $origin
    while ($null -ne $node -and $node -ne $boundary) {
        if ($node -is [Windows.Controls.Button]) { return $true }
        try { $node = [Windows.Media.VisualTreeHelper]::GetParent($node) } catch { break }
    }
    return $false
}
$beginDrag = {
    param($sender, $eventArgs)
    if ($eventArgs.ChangedButton -ne [Windows.Input.MouseButton]::Left) { return }
    if (Is-ButtonOrigin $eventArgs.OriginalSource $sender) { return }
    if ($sender -eq $petImage -and $eventArgs.ClickCount -eq 2) {
        Open-Codex
        $eventArgs.Handled = $true
        return
    }
    $cursor = [System.Windows.Forms.Cursor]::Position
    $dragPoint = Get-ScreenPointInDip $cursor.X $cursor.Y
    $script:dragStartX = $dragPoint.X
    $script:dragStartY = $dragPoint.Y
    $script:windowStartLeft = $window.Left
    $script:windowStartTop = $window.Top
    $script:isDragging = $true
    $script:dragCapture = $sender
    $null = $sender.CaptureMouse()
    $eventArgs.Handled = $true
}
$moveDrag = {
    param($sender, $eventArgs)
    if (-not $script:isDragging) { return }
    $cursor = [System.Windows.Forms.Cursor]::Position
    $dragPoint = Get-ScreenPointInDip $cursor.X $cursor.Y
    $dx = $dragPoint.X - $script:dragStartX
    $dy = $dragPoint.Y - $script:dragStartY
    Set-WindowPositionClamped ($script:windowStartLeft + $dx) ($script:windowStartTop + $dy) $true
    $absX = [math]::Abs($dx)
    $absY = [math]::Abs($dy)
    if ($absX -ge 8 -and $absX -ge ($absY * 0.80)) {
        if ($dx -gt 0) { Set-PetState 'running-right' } else { Set-PetState 'running-left' }
    } else {
        Set-PetState $script:basePetState
    }
    $eventArgs.Handled = $true
}
$endDrag = {
    param($sender, $eventArgs)
    if (-not $script:isDragging) { return }
    $script:isDragging = $false
    if ($null -ne $script:dragCapture) { $script:dragCapture.ReleaseMouseCapture() }
    $script:dragCapture = $null
    Set-PetState $script:basePetState
    Save-Position
    $eventArgs.Handled = $true
}
foreach ($surface in @($petImage, $headerDragArea)) {
    $surface.add_MouseLeftButtonDown($beginDrag)
    $surface.add_MouseMove($moveDrag)
    $surface.add_MouseLeftButtonUp($endDrag)
}

$window.add_Loaded({
    $window.UpdateLayout()
    try {
        if (Test-Path -LiteralPath $settingsPath) {
            $savedUi = Get-Content -Raw -Encoding UTF8 -LiteralPath $settingsPath | ConvertFrom-Json
            # Read both fields before either setter persists them.
            $savedQuotaVisible = $savedUi.quotaVisible -ne $false
            $savedTasksVisible = $savedUi.tasksVisible -eq $true
            Set-QuotaVisible $savedQuotaVisible
            Set-TaskTrayExpanded $savedTasksVisible
        }
    } catch {}
    if ($ExpandedTest) { Set-QuotaVisible $true; Set-TaskTrayExpanded $true }
    Set-WindowPositionClamped $window.Left $window.Top $false
    Start-UpdateCheck $false
})

$window.add_Closed({
    Save-Position
    Save-UiSettings
    $uiTimer.Stop()
    $updateTimer.Stop()
    if ($null -ne $script:updateProcess) { try { if (-not $script:updateProcess.HasExited) { $script:updateProcess.Kill() } } catch {}; $script:updateProcess.Dispose() }
    $countdownTimer.Stop()
    $animationTimer.Stop()
    if (-not $bridge.HasExited) {
        try { $bridge.StandardInput.Close() } catch {}
        if (-not $bridge.WaitForExit(1500)) { try { $bridge.Kill() } catch {} }
    }
    $bridge.Dispose()
    try { $singleInstance.ReleaseMutex() } catch {}
    $singleInstance.Dispose()
})

$null = $window.ShowDialog()
