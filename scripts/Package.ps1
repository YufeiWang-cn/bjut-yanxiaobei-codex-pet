param([string]$OutputDirectory, [string]$NodeExecutable)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression,System.IO.Compression.FileSystem
$repoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $repoRoot 'windows-companion/Runtime.ps1')
if (-not $NodeExecutable) { $NodeExecutable = Get-CompanionNode }
& $NodeExecutable (Join-Path $repoRoot 'scripts/Audit-Source.cjs')
if ($LASTEXITCODE -ne 0) { throw 'Source audit failed; no release was created' }
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $repoRoot 'dist' }
$null = New-Item -ItemType Directory -Path $OutputDirectory -Force
$OutputDirectory = (Resolve-Path -LiteralPath $OutputDirectory).Path
$version = (Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'VERSION.txt')).Trim()
$macPackage = Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'macos-companion/package.json') | ConvertFrom-Json
if ($version -ne $macPackage.version) { throw 'VERSION.txt and Mac package version differ' }
if (-not (Test-Path -LiteralPath (Join-Path $repoRoot 'START-HERE.html'))) { throw 'Generate START-HERE.html before packaging' }
$archiveChecksums = [Collections.Generic.List[string]]::new()

# Do not publish a Mac runtime that drifted from the canonical source.
$manifestPath = Join-Path $repoRoot 'macos-companion\assets\manifest.json'
$manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
foreach ($entry in $manifest.PSObject.Properties) {
    $resource = Join-Path $repoRoot ('macos-companion/' + $entry.Name)
    if ((Get-FileHash -LiteralPath $resource -Algorithm SHA256).Hash.ToLowerInvariant() -ne $entry.Value) { throw "Mac resource changed; run npm run prepare-assets: $($entry.Name)" }
    $canonicalRelative = if ($entry.Name -like 'runtime/*') { 'windows-companion/' + $entry.Name.Substring(8) }
        elseif ($entry.Name -eq 'assets/LICENSE.md') { 'LICENSE.md' }
        else { 'windows-companion/' + $entry.Name.Substring(7) }
    if ((Get-FileHash -LiteralPath (Join-Path $repoRoot $canonicalRelative)).Hash.ToLowerInvariant() -ne $entry.Value) { throw "Canonical resource changed; run npm run prepare-assets: $canonicalRelative" }
}
foreach ($name in @('quota-bridge.js','activity-state.js','platform-paths.js')) {
    if ((Get-FileHash (Join-Path $repoRoot "windows-companion/$name")).Hash -ne (Get-FileHash (Join-Path $repoRoot "macos-companion/runtime/$name")).Hash) { throw "Mac runtime drift: $name" }
}

function Get-SourceFiles([string[]]$directories, [string[]]$files) {
    $items = @()
    foreach ($file in $files) {
        $source = Join-Path $repoRoot $file
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Missing release file: $file" }
        $items += [pscustomobject]@{ Source=$source; Relative=$file.Replace('\','/') }
    }
    foreach ($directory in $directories) {
        $sourceRoot = Join-Path $repoRoot $directory
        foreach ($file in Get-ChildItem -LiteralPath $sourceRoot -File -Recurse -Force) {
            if ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Symlink not allowed in release: $($file.FullName)" }
            $relative = $file.FullName.Substring($repoRoot.Length+1).Replace('\','/')
            # A positive directory list plus a runtime-data deny list, independent of git status.
            if ($relative -match '(^|/)(\.git|\.codex|\.test-output|node_modules|dist|logs|sessions|__pycache__|\.release-backups)(/|$)' -or
                $file.Name -match '^(auth\.json|bridge-state\.json|badge-position\.json|ui-settings\.json|mac-settings\.json|autostart-.*\.flag|\.env.*)$' -or
                $file.Name -match '(\.(log|zip|dmg|db|sqlite|lnk|p12|pfx|pem|key|pyc)|\.(db|sqlite)-[^.]+)$|^(Thumbs\.db|Desktop\.ini|\.DS_Store)$') { continue }
            $items += [pscustomobject]@{ Source=$file.FullName; Relative=$relative }
        }
    }
    return $items
}

function Write-ReleaseZip([string]$name, $entries) {
    $destination = Join-Path $OutputDirectory ($name + '.zip')
    if (Test-Path -LiteralPath $destination) { throw "Archive exists; choose another -OutputDirectory: $destination" }
    $zip = [IO.Compression.ZipFile]::Open($destination, [IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($entry in ($entries | Sort-Object Relative -Unique)) {
            $entryName = $name + '/' + $entry.Relative
            $null = [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $entry.Source, $entryName, [IO.Compression.CompressionLevel]::Optimal)
        }
    } finally { $zip.Dispose() }
    $archive = [IO.Compression.ZipFile]::OpenRead($destination)
    try {
        if (-not ($archive.Entries.FullName -contains ($name + '/README.md'))) { throw "README missing: $destination" }
        $hash = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash
        $archiveChecksums.Add($hash + '  ' + $name + '.zip')
        Write-Output ("{0}: {1} files, SHA256 {2}" -f $destination, $archive.Entries.Count, $hash)
    } finally { $archive.Dispose() }
}

$repository = Get-SourceFiles @('codex-native','windows-companion','macos-companion','.github','docs','scripts','tests') @('README.md','CHANGELOG.md','LICENSE.md','.gitignore','.gitattributes','VERSION.txt','START-HERE.html')
Write-ReleaseZip 'bjut-yanxiaobei-codex-pet' $repository

$native = @(Get-SourceFiles @('codex-native','docs') @('LICENSE.md','scripts/Install-CodexPet.ps1','VERSION.txt','START-HERE.html')) | Where-Object { $_.Relative -notlike 'docs/releases/*' }
$native += [pscustomobject]@{ Source=(Join-Path $repoRoot 'docs\releases\native.md'); Relative='README.md' }
Write-ReleaseZip 'bjut-yanxiaobei-native' $native

$windows = @(Get-SourceFiles @('windows-companion','docs') @('LICENSE.md','CHANGELOG.md','VERSION.txt','START-HERE.html')) | Where-Object { $_.Relative -notlike 'docs/releases/*' }
$windows += [pscustomobject]@{ Source=(Join-Path $repoRoot 'docs\releases\windows.md'); Relative='README.md' }
Write-ReleaseZip 'bjut-yanxiaobei-windows' $windows

$macos = @(Get-SourceFiles @('macos-companion','docs') @('LICENSE.md','CHANGELOG.md','VERSION.txt','START-HERE.html')) | Where-Object { $_.Relative -notlike 'docs/releases/*' }
$macos += [pscustomobject]@{ Source=(Join-Path $repoRoot 'docs\releases\macos.md'); Relative='README.md' }
Write-ReleaseZip 'bjut-yanxiaobei-macos' $macos
[IO.File]::WriteAllLines((Join-Path $OutputDirectory 'SHA256SUMS.txt'), $archiveChecksums, [Text.UTF8Encoding]::new($false))
