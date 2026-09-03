function Get-CompanionDataRoot {
    if ($env:YANXIAOBEI_DATA_DIR) { return [IO.Path]::GetFullPath($env:YANXIAOBEI_DATA_DIR) }
    return Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'BJUT-YanXiaoBei'
}

function Get-CompanionNode {
    if ($env:NODE_EXE -and (Test-Path -LiteralPath $env:NODE_EXE -PathType Leaf)) { return $env:NODE_EXE }
    $command = Get-Command node.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) { return $command.Source }
    throw 'Node.js was not found. Install Node.js 22+ (with PATH enabled), or set NODE_EXE. See docs/INSTALL.md.'
}
