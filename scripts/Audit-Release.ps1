param([Parameter(Mandatory=$true)][string]$ReleaseDirectory)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$repo = Split-Path -Parent $PSScriptRoot
$release = (Resolve-Path -LiteralPath $ReleaseDirectory).Path
$version = (Get-Content -Raw -LiteralPath (Join-Path $repo 'VERSION.txt')).Trim()
function Public-File($file) {
    $relative = $file.FullName.Substring($repo.Length+1).Replace('\','/')
    return -not ($relative -match '(^|/)(\.git|\.codex|\.test-output|node_modules|dist|logs|sessions|__pycache__|\.release-backups)(/|$)' -or
        $file.Name -match '^(auth\.json|bridge-state\.json|badge-position\.json|ui-settings\.json|mac-settings\.json|update-preferences\.json|autostart-.*\.flag|\.env.*)$' -or
        $file.Name -match '(\.(log|zip|dmg|db|sqlite|lnk|p12|pfx|pem|key|pyc)|\.(db|sqlite)-[^.]+)$|^(Thumbs\.db|Desktop\.ini|\.DS_Store)$')
}
$specs = @(
    @{Name='bjut-yanxiaobei-codex-pet'; Dirs=@('codex-native','windows-companion','macos-companion','.github','docs','scripts','tests'); Files=@('README.md','CHANGELOG.md','LICENSE.md','.gitignore','.gitattributes','VERSION.txt','START-HERE.html'); Template=$null},
    @{Name='bjut-yanxiaobei-native'; Dirs=@('codex-native','docs'); Files=@('LICENSE.md','scripts/Install-CodexPet.ps1','scripts/Uninstall-CodexPet.ps1','scripts/Uninstall-CodexPet.command','VERSION.txt','START-HERE.html'); Template='native'},
    @{Name='bjut-yanxiaobei-windows'; Dirs=@('windows-companion','docs'); Files=@('LICENSE.md','CHANGELOG.md','VERSION.txt','START-HERE.html'); Template='windows'},
    @{Name='bjut-yanxiaobei-macos'; Dirs=@('macos-companion','docs'); Files=@('LICENSE.md','CHANGELOG.md','VERSION.txt','START-HERE.html'); Template='macos'}
)
$checksums = Get-Content -LiteralPath (Join-Path $release 'SHA256SUMS.txt')
foreach ($spec in $specs) {
    $expected = @{}
    foreach ($name in $spec.Files) { $expected[$name] = Join-Path $repo $name }
    foreach ($dir in $spec.Dirs) {
        foreach ($file in Get-ChildItem -LiteralPath (Join-Path $repo $dir) -File -Recurse -Force) {
            if (-not (Public-File $file)) { continue }
            $relative = $file.FullName.Substring($repo.Length+1).Replace('\','/')
            if ($spec.Template -and $relative -like 'docs/releases/*') { continue }
            $expected[$relative] = $file.FullName
        }
    }
    if ($spec.Template) { $expected['README.md'] = Join-Path $repo ('docs/releases/' + $spec.Template + '.md') }
    $archive = Join-Path $release ($spec.Name + '.zip')
    $sha = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash
    if (-not ($checksums -contains ($sha + '  ' + $spec.Name + '.zip'))) { throw "SHA256SUMS mismatch: $archive" }
    $zip = [IO.Compression.ZipFile]::OpenRead($archive)
    $seen = @{}
    try {
        foreach ($entry in $zip.Entries) {
            $prefix = $spec.Name + '/'
            if (-not $entry.FullName.StartsWith($prefix) -or $entry.FullName.Contains('../')) { throw "Unsafe ZIP path: $($entry.FullName)" }
            $relative = $entry.FullName.Substring($prefix.Length)
            if ($seen.ContainsKey($relative) -or -not $expected.ContainsKey($relative)) { throw "Duplicate or unexpected entry: $relative" }
            $seen[$relative] = $true
            $stream=$entry.Open(); $hash=[Security.Cryptography.SHA256]::Create()
            try { $actual=[BitConverter]::ToString($hash.ComputeHash($stream)).Replace('-','') } finally { $stream.Dispose();$hash.Dispose() }
            if ($actual -ne (Get-FileHash -LiteralPath $expected[$relative]).Hash) { throw "Stale archive entry: $relative" }
        }
        foreach ($name in $expected.Keys) { if (-not $seen.ContainsKey($name)) { throw "Missing archive entry: $name" } }
        Write-Output "PASS v${version}: $($spec.Name), $($seen.Count) entries, full source match and SHA256 verified"
    } finally { $zip.Dispose() }
}
Write-Output 'Read-only audit complete. This checks release files, not running processes or Mac hardware.'
