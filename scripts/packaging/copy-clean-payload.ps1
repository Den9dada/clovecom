#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ReleaseDirectory,
    [Parameter(Mandatory = $true)][string]$DestinationDirectory
)
$ErrorActionPreference = 'Stop'
[void][IO.Directory]::CreateDirectory($DestinationDirectory)
# 仅交付程序与 Flutter 必需资源，不复制本地配置、导入文件或历史记录。
Get-ChildItem -LiteralPath $ReleaseDirectory -File |
    Where-Object { $_.Name -eq 'clovecom.exe' -or $_.Extension -eq '.dll' } |
    Copy-Item -Destination $DestinationDirectory
$payloadData = Join-Path $DestinationDirectory 'data'
[void][IO.Directory]::CreateDirectory($payloadData)
foreach ($resource in @('app.so', 'icudtl.dat', 'flutter_assets')) {
    Copy-Item -LiteralPath (Join-Path $ReleaseDirectory "data\$resource") -Destination $payloadData -Recurse
}
# Lua 是应用必需运行资源；仅复制固定文件，避免带入用户脚本或日志。
$payloadLua = Join-Path $DestinationDirectory 'lua'
[void][IO.Directory]::CreateDirectory((Join-Path $payloadLua 'examples'))
foreach ($resource in @('clovertls_lua_runner.exe', 'host_sdk.lua', 'README', 'LICENSE', 'examples\point_table.lua', 'examples\ymodem.lua')) {
    $target = if ($resource.StartsWith('examples\')) { Join-Path $payloadLua 'examples' } else { $payloadLua }
    Copy-Item -LiteralPath (Join-Path $ReleaseDirectory "lua\$resource") -Destination $target
}
