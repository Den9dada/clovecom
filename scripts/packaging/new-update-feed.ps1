#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$MsixPath,
    [Parameter(Mandatory)][string]$Repository,
    [Parameter(Mandatory)][string]$Tag,
    [Parameter(Mandatory)][string]$PagesUrl,
    [Parameter(Mandatory)][string]$OutputDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($Repository -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') { throw 'Repository 必须为 owner/repo。' }
if ($Tag -notmatch '^v\d+\.\d+\.\d+\+\d+$') { throw '发布标签必须为 vmajor.minor.patch+build。' }
$uri = [Uri]$PagesUrl
if (-not $uri.IsAbsoluteUri -or $uri.Scheme -ne 'https' -or $uri.UserInfo -or $uri.Query -or $uri.Fragment) {
    throw 'PagesUrl 必须为不含凭据、查询参数和片段的 HTTPS 地址。'
}
$baseUrl = $PagesUrl.TrimEnd('/')
$msix = Get-Item -LiteralPath $MsixPath
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::OpenRead($msix.FullName)
try {
    if (-not $archive.GetEntry('AppxSignature.p7x')) { throw 'MSIX 未签名，不能生成正式更新清单。' }
    $entry = $archive.GetEntry('AppxManifest.xml')
    if (-not $entry) { throw 'MSIX 缺少 AppxManifest.xml。' }
    $reader = [IO.StreamReader]::new($entry.Open())
    try { [xml]$manifest = $reader.ReadToEnd() } finally { $reader.Dispose() }
} finally { $archive.Dispose() }
$identity = $manifest.Package.Identity
$tagVersion = $Tag.Substring(1).Replace('+', '.')
if ([version]$identity.Version -ne [version]$tagVersion) { throw '标签版本与 MSIX 清单版本不一致。' }
if ($identity.ProcessorArchitecture -ne 'x64') { throw '更新清单仅支持 x64。' }
function Escape-Xml([string]$Value) { [Security.SecurityElement]::Escape($Value) }
$name = Escape-Xml $identity.Name
$publisher = Escape-Xml $identity.Publisher
$version = Escape-Xml $identity.Version
$feedUrl = Escape-Xml "$baseUrl/CloveCOM.appinstaller"
$releaseUrl = "https://github.com/$Repository/releases/download/$([Uri]::EscapeDataString($Tag))"
$packageUrl = Escape-Xml "$releaseUrl/$([Uri]::EscapeDataString($msix.Name))"
$feed = @"
<?xml version="1.0" encoding="utf-8"?>
<AppInstaller xmlns="http://schemas.microsoft.com/appx/appinstaller/2018"
    Version="$version" Uri="$feedUrl">
  <MainPackage Name="$name" Publisher="$publisher" Version="$version"
      ProcessorArchitecture="x64" Uri="$packageUrl" />
  <UpdateSettings>
    <OnLaunch HoursBetweenUpdateChecks="4" ShowPrompt="true" UpdateBlocksActivation="false" />
    <AutomaticBackgroundTask />
  </UpdateSettings>
</AppInstaller>
"@
[void][IO.Directory]::CreateDirectory([IO.Path]::GetFullPath($OutputDirectory))
$utf8 = [Text.UTF8Encoding]::new($false)
[IO.File]::WriteAllText((Join-Path $OutputDirectory 'CloveCOM.appinstaller'), $feed, $utf8)
Write-Output "已生成版本 $version 的更新清单：$baseUrl/CloveCOM.appinstaller"
