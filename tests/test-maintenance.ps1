$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.IO.Compression,System.IO.Compression.FileSystem
$repoRoot=Split-Path -Parent $PSScriptRoot
$testRoot=Join-Path $repoRoot ('.test-output\maintenance-'+[Guid]::NewGuid().ToString('N'))
function Assert($condition,$message){if(-not$condition){throw$message}}
function New-FakeInstall([string]$root,[string]$version){
    $null=New-Item -ItemType Directory -Path (Join-Path $root 'windows-companion') -Force
    [IO.File]::WriteAllText((Join-Path $root 'VERSION.txt'),$version)
    [IO.File]::WriteAllText((Join-Path $root 'windows-companion\CodexQuotaPet.ps1'),'# fixture')
    [IO.File]::WriteAllText((Join-Path $root 'README.md'),'fixture')
}
try{
    $install=Join-Path $testRoot 'bjut-yanxiaobei-windows';New-FakeInstall $install '0.2.5'
    [IO.File]::WriteAllText((Join-Path $install 'windows-companion\obsolete-core.txt'),'old')
    $installData=Join-Path $testRoot 'update-data\BJUT-YanXiaoBei';$null=New-Item -ItemType Directory -Path $installData -Force
    [IO.File]::WriteAllText((Join-Path $installData 'ui-settings.json'),'{}')
    $source=Join-Path $testRoot 'source\bjut-yanxiaobei-windows';New-FakeInstall $source '0.2.6'
    [IO.File]::WriteAllText((Join-Path $source 'windows-companion\new-core.txt'),'new')
    $zip=Join-Path $testRoot 'bjut-yanxiaobei-windows.zip';[IO.Compression.ZipFile]::CreateFromDirectory((Split-Path -Parent $source),$zip)
    $sum=Join-Path $testRoot 'SHA256SUMS.txt';[IO.File]::WriteAllText($sum,((Get-FileHash $zip -Algorithm SHA256).Hash+'  bjut-yanxiaobei-windows.zip'))
    $url='https://github.com/YufeiWang-cn/bjut-yanxiaobei-codex-pet/releases/download/v0.2.6/bjut-yanxiaobei-windows.zip'
    $output=& (Join-Path $repoRoot 'windows-companion\Updater.ps1') -InstallRoot $install -TargetVersion 0.2.6 -DownloadUrl $url -TestExtractOnly -PackagePath $zip -ChecksumPath $sum
    Assert ($output -match 'PASS') 'Updater did not validate a clean release archive'
    $output=& (Join-Path $repoRoot 'windows-companion\Updater.ps1') -InstallRoot $install -TargetVersion 0.2.6 -DownloadUrl $url -NonInteractive -NoRestart -PackagePath $zip -ChecksumPath $sum
    Assert ($output -match 'PASS') 'Updater did not finish an in-place update'
    Assert ((Get-Content -Raw -LiteralPath (Join-Path $install 'VERSION.txt')).Trim() -eq '0.2.6') 'Updater did not replace the installed version'
    Assert (Test-Path -LiteralPath (Join-Path $install 'windows-companion\new-core.txt')) 'Updater did not install new core files'
    Assert (-not(Test-Path -LiteralPath (Join-Path $install 'windows-companion\obsolete-core.txt'))) 'Updater left obsolete core files'
    Assert (Test-Path -LiteralPath (Join-Path $installData 'ui-settings.json')) 'Updater changed user data outside the install directory'

    $keep=Join-Path $testRoot 'keep\bjut-yanxiaobei-windows';New-FakeInstall $keep '0.2.5'
    $keepData=Join-Path $testRoot 'keep\BJUT-YanXiaoBei';$null=New-Item -ItemType Directory -Path $keepData -Force
    [IO.File]::WriteAllText((Join-Path $keepData 'ui-settings.json'),'{}')
    & (Join-Path $repoRoot 'windows-companion\Uninstaller.ps1') -InstallRoot $keep -Mode Keep -NonInteractive -DataDirectory $keepData -StartupDirectory (Join-Path $testRoot 'startup') | Out-Null
    Assert (Test-Path -LiteralPath $keepData) 'Keep-data uninstall deleted preferences'
    Assert (-not(Test-Path -LiteralPath (Join-Path $keep 'windows-companion'))) 'Keep-data uninstall left core files'

    $clear=Join-Path $testRoot 'clear\bjut-yanxiaobei-windows';New-FakeInstall $clear '0.2.5'
    $clearData=Join-Path $testRoot 'clear\BJUT-YanXiaoBei';$null=New-Item -ItemType Directory -Path $clearData -Force
    & (Join-Path $repoRoot 'windows-companion\Uninstaller.ps1') -InstallRoot $clear -Mode Clear -NonInteractive -DataDirectory $clearData -StartupDirectory (Join-Path $testRoot 'startup') | Out-Null
    Assert (-not(Test-Path -LiteralPath $clearData)) 'Clear-data uninstall left preferences'
    Assert (-not(Test-Path -LiteralPath (Join-Path $clear 'windows-companion'))) 'Clear-data uninstall left core files'
    'PASS: GUI maintenance backend validates updates and supports keep/clear uninstall modes'
}finally{if(Test-Path -LiteralPath $testRoot){Remove-Item -LiteralPath $testRoot -Recurse -Force}}
