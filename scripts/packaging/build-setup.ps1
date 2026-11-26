#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$PayloadDirectory,
    [Parameter(Mandatory)][string]$OutputFile,
    [Parameter(Mandatory)][string]$Version,
    [Parameter(Mandatory)][string]$NsisPath,
    [Parameter(Mandatory)][string]$IconPath,
    [string]$ProductName = 'CloveCOM',
    [string]$RegistryKey = 'Software\CloveCOM\Setup',
    [string]$DataSubdirectory,
    [string]$LauncherDataSubdirectory = 'CloveCOM'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$payload = (Resolve-Path -LiteralPath $PayloadDirectory).Path
if (-not $DataSubdirectory) {
    # 与 path_provider_windows 一致，从应用版本资源读取用户数据目录。
    $info = [Diagnostics.FileVersionInfo]::GetVersionInfo((Join-Path $payload 'clovecom.exe'))
    if (-not $info.CompanyName -or -not $info.ProductName) { throw '应用缺少 CompanyName 或 ProductName，无法确定用户数据目录。' }
    $DataSubdirectory = "$($info.CompanyName)\$($info.ProductName)"
}
foreach ($relativePath in @($DataSubdirectory, $LauncherDataSubdirectory)) {
    if ($relativePath -notmatch '^[A-Za-z0-9_ .-]+(\\[A-Za-z0-9_ .-]+)*$' -or @($relativePath.Split('\') | Where-Object { $_ -in @('.', '..') -or $_.EndsWith('.') -or $_.EndsWith(' ') }).Count) {
        throw '用户数据目录必须是 AppData 内的有效相对路径。'
    }
}
if (Test-Path -LiteralPath (Join-Path $payload 'Uninstall.exe')) { throw '分发资源不能包含 Uninstall.exe。' }
$include = Join-Path ([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($OutputFile))) ('remove-' + [Guid]::NewGuid().ToString('N') + '.nsh')
function Escape-Nsis([string]$Value) { $Value.Replace('$', '$$').Replace('"', '$\"') }
try {
    $lines = @(
        Get-ChildItem -LiteralPath $payload -File -Recurse | ForEach-Object {
            'Delete "$INSTDIR\' + (Escape-Nsis $_.FullName.Substring($payload.Length + 1)) + '"'
        }
        '${If} ${Errors}'
        'MessageBox MB_ICONSTOP "部分程序文件无法删除。请先退出应用后重试。" /SD IDOK'
        'SetErrorLevel 1'
        'Abort'
        '${EndIf}'
        # 非空目录保留，其中可能存在用户后来保存的文件。
        Get-ChildItem -LiteralPath $payload -Directory -Recurse | Sort-Object { $_.FullName.Length } -Descending | ForEach-Object {
            'RMDir "$INSTDIR\' + (Escape-Nsis $_.FullName.Substring($payload.Length + 1)) + '"'
            'ClearErrors'
        }
    )
    [IO.File]::WriteAllLines($include, [string[]]$lines, [Text.UTF8Encoding]::new($false))
    & $NsisPath '/V2' '/INPUTCHARSET' 'UTF8' "/DPAYLOAD_DIR=$payload" "/DOUTPUT_FILE=$OutputFile" "/DAPP_VERSION=$Version" "/DAPP_ICON=$IconPath" "/DREMOVE_INCLUDE=$include" "/DPRODUCT_NAME=$ProductName" "/DREG_KEY=$RegistryKey" "/DUNINSTALL_KEY=Software\Microsoft\Windows\CurrentVersion\Uninstall\$ProductName" "/DDATA_SUBDIR=$DataSubdirectory" "/DLAUNCHER_DATA_SUBDIR=$LauncherDataSubdirectory" (Join-Path $PSScriptRoot 'setup.nsi')
    if ($LASTEXITCODE -ne 0) { throw "安装程序编译失败：$LASTEXITCODE" }
} finally {
    if (Test-Path -LiteralPath $include) { Remove-Item -LiteralPath $include }
}
