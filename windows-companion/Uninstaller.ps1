[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$InstallRoot,[int]$ParentProcessId=0,[ValidateSet('Ask','Keep','Clear')][string]$Mode='Ask',[switch]$NonInteractive,[string]$DataDirectory,[string]$StartupDirectory)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
function Fail([string]$text){[Windows.Forms.MessageBox]::Show($text,'燕小北卸载程序',[Windows.Forms.MessageBoxButtons]::OK,[Windows.Forms.MessageBoxIcon]::Error)|Out-Null}
try {
    $InstallRoot=[IO.Path]::GetFullPath($InstallRoot).TrimEnd('\','/')
    if (-not (Test-Path -LiteralPath (Join-Path $InstallRoot 'VERSION.txt') -PathType Leaf) -or
        -not (Test-Path -LiteralPath (Join-Path $InstallRoot 'windows-companion\CodexQuotaPet.ps1') -PathType Leaf)) { throw '安装目录不是完整的燕小北 Windows 版本。' }
    if ($Mode -eq 'Ask') {
        $answer=[Windows.Forms.MessageBox]::Show("是否保留燕小北的设置和缓存？`n`n是：保留习惯和数据，只删除核心文件。`n否：删除核心文件、设置和缓存。`n取消：不卸载。",'卸载燕小北',[Windows.Forms.MessageBoxButtons]::YesNoCancel,[Windows.Forms.MessageBoxIcon]::Question)
        if ($answer -eq [Windows.Forms.DialogResult]::Cancel) { return }
        $Mode=if($answer -eq [Windows.Forms.DialogResult]::Yes){'Keep'}else{'Clear'}
    }
    if ($ParentProcessId -gt 0) { try { Wait-Process -Id $ParentProcessId -Timeout 10 -ErrorAction SilentlyContinue } catch {} }
    $escaped=[Regex]::Escape((Join-Path $InstallRoot 'windows-companion'))
    foreach($process in @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue|Where-Object{$_.ProcessId -ne $PID -and $_.CommandLine -match $escaped -and $_.CommandLine -match '(?:CodexQuotaPet|Launch|CodexPetWatcher)\.ps1'})){
        try{Stop-Process -Id $process.ProcessId -Force -ErrorAction Stop}catch{}
    }
    $startup=if($StartupDirectory){[IO.Path]::GetFullPath($StartupDirectory)}else{[Environment]::GetFolderPath('Startup')};$shortcut=Join-Path $startup 'BJUT-YanXiaoBei-Codex.lnk'
    if(Test-Path -LiteralPath $shortcut){Remove-Item -LiteralPath $shortcut -Force}
    $data=if($DataDirectory){[IO.Path]::GetFullPath($DataDirectory)}elseif($env:YANXIAOBEI_DATA_DIR){[IO.Path]::GetFullPath($env:YANXIAOBEI_DATA_DIR)}else{Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'BJUT-YanXiaoBei'}
    if($Mode -eq 'Clear' -and (Test-Path -LiteralPath $data)){
        if((Split-Path -Leaf $data)-ne'BJUT-YanXiaoBei'-or((Get-Item -LiteralPath $data -Force).Attributes-band[IO.FileAttributes]::ReparsePoint)){throw '本地数据目录路径异常，未执行删除。'}
        Remove-Item -LiteralPath $data -Recurse -Force
    }
    foreach($directory in @('windows-companion','docs')){$target=Join-Path $InstallRoot $directory;if(Test-Path -LiteralPath $target){Remove-Item -LiteralPath $target -Recurse -Force}}
    foreach($file in @('README.md','CHANGELOG.md','LICENSE.md','VERSION.txt','START-HERE.html','Update.vbs','Uninstall.vbs')){$target=Join-Path $InstallRoot $file;if(Test-Path -LiteralPath $target -PathType Leaf){Remove-Item -LiteralPath $target -Force}}
    try{if(-not(Get-ChildItem -LiteralPath $InstallRoot -Force|Select-Object -First 1)){Remove-Item -LiteralPath $InstallRoot -Force}}catch{}
    $detail=if($Mode -eq 'Keep'){'核心文件已删除；设置和缓存已保留，下次安装会继续使用。'}else{'核心文件、设置和缓存均已删除。'}
    if($NonInteractive){Write-Output $detail}else{[Windows.Forms.MessageBox]::Show($detail,'燕小北卸载完成',[Windows.Forms.MessageBoxButtons]::OK,[Windows.Forms.MessageBoxIcon]::Information)|Out-Null}
}catch{Fail $_.Exception.Message}
finally{if($PSCommandPath -like([IO.Path]::GetTempPath()+'YanXiaoBei-Uninstaller-*')){Remove-Item -LiteralPath $PSCommandPath -Force -ErrorAction SilentlyContinue}}
