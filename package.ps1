#requires -Version 5.1
[CmdletBinding()]
param(
    [ValidateSet('All', 'Zip', 'Nsis', 'Setup', 'Msix')][string]$Target = 'All',
    [switch]$SkipBuild,
    [ValidateSet('Auto', 'Offline', 'Online')][string]$DependencyMode = 'Auto',
    [string]$NsisPath,
    [string]$WindowsSdkBin,
    [string]$VcRuntimePath,
    [string]$CertificatePath,
    [string]$IdentityName = 'CloveCOM.Desktop',
    [string]$TimestampUrl
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$projectRoot = $PSScriptRoot
$dist = Join-Path $projectRoot 'dist'
$workRoot = Join-Path $projectRoot 'build\packaging'
$work = Join-Path $workRoot ([Guid]::NewGuid().ToString('N'))
$utf8 = New-Object System.Text.UTF8Encoding($false)
$certificate = $null
$signingFile = $null

function Invoke-Checked([string]$File, [string[]]$Arguments) {
    & $File @Arguments
    if ($LASTEXITCODE -ne 0) { throw "工具执行失败：$File，退出码 $LASTEXITCODE" }
}

function Build-WindowsRelease([string]$Mode) {
    if (-not (Test-Path -LiteralPath (Join-Path $projectRoot 'pubspec.lock'))) {
        throw '缺少 pubspec.lock，请先执行 flutter pub get 并确认锁定的依赖版本，再打包。'
    }
    # 打包只使用锁定版本；先验证缓存，避免资源声明变化触发不必要的联网。
    if ($Mode -ne 'Online') {
        Write-Host '从本地缓存验证锁定依赖……'
        try {
            Invoke-Checked 'flutter' @('pub', 'get', '--offline', '--enforce-lockfile')
        } catch {
            if ($Mode -eq 'Offline') {
                throw '离线依赖验证失败，未开始构建。请检查上方错误；缓存缺失可用 -DependencyMode Online 获取，依赖声明改变时请先执行 flutter pub get。'
            }
            Write-Warning '本地缓存无法满足锁文件，尝试联网获取锁定依赖；如已修改依赖声明，请先执行 flutter pub get。'
            Invoke-Checked 'flutter' @('pub', 'get', '--enforce-lockfile')
        }
    } else {
        Write-Host '联网验证并获取锁定依赖……'
        Invoke-Checked 'flutter' @('pub', 'get', '--enforce-lockfile')
    }
    # 依赖已验证，构建阶段不再重复运行 pub get。
    Invoke-Checked 'flutter' @('build', 'windows', '--release', '--no-pub')
}

function Find-Nsis {
    if ($NsisPath) { return (Get-Item -LiteralPath $NsisPath).FullName }
    $command = Get-Command makensis.exe -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    foreach ($candidate in @("${env:ProgramFiles(x86)}\NSIS\makensis.exe", "$env:ProgramFiles\NSIS\makensis.exe")) {
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }
    throw '未找到 NSIS；安装后重试，或传入 -NsisPath。'
}

function Find-Sdk {
    if ($WindowsSdkBin) { $candidates = @($WindowsSdkBin) }
    else {
        $sdkRoot = "${env:ProgramFiles(x86)}\Windows Kits\10\bin"
        $candidates = @(Get-ChildItem -LiteralPath $sdkRoot -Directory |
            Where-Object Name -Match '^10\.0\.\d+\.\d+$' |
            Sort-Object { [version]$_.Name } -Descending |
            ForEach-Object { Join-Path $_.FullName 'x64' })
    }
    foreach ($candidate in $candidates) {
        if ((Test-Path "$candidate\makeappx.exe") -and (Test-Path "$candidate\signtool.exe")) { return $candidate }
    }
    throw '未找到 Windows SDK 的 MakeAppx/SignTool，请安装 Windows SDK 或传入 -WindowsSdkBin。'
}

function Find-VcRuntime {
    if ($VcRuntimePath) { return (Get-Item -LiteralPath $VcRuntimePath).FullName }
    $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    $vsRoot = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if ($LASTEXITCODE -ne 0 -or -not $vsRoot) { throw '未找到 Visual C++ 工具链；可用 -VcRuntimePath 指定 x64 CRT 目录。' }
    $redist = Join-Path $vsRoot 'VC\Redist\MSVC'
    foreach ($version in (Get-ChildItem -LiteralPath $redist -Directory | Where-Object Name -Match '^\d+\.' | Sort-Object { [version]$_.Name } -Descending)) {
        $crt = Get-ChildItem -Path (Join-Path $version.FullName 'x64\Microsoft.VC*.CRT') -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($crt) { return $crt.FullName }
    }
    throw '未找到可再分发的 x64 VC++ CRT 文件。'
}

function Get-SigningCertificate {
    Add-Type -AssemblyName System.Security
    $flags = [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::EphemeralKeySet -bor
        [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable
    if ($CertificatePath) {
        # 正式证书密码从环境变量读取，不写入仓库或构建日志。
        $bytes = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $CertificatePath).Path)
        return [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($bytes, $env:CLOVECOM_CERT_PASSWORD, $flags)
    }
    # 私钥仅以当前 Windows 用户的 DPAPI 密文保存，不导入系统证书信任库。
    $keyDir = Join-Path $projectRoot 'build\packaging-keys'
    $keyFile = Join-Path $keyDir 'development.pfx.dpapi'
    $scope = [System.Security.Cryptography.DataProtectionScope]::CurrentUser
    if (Test-Path -LiteralPath $keyFile) {
        $bytes = [System.Security.Cryptography.ProtectedData]::Unprotect([IO.File]::ReadAllBytes($keyFile), $null, $scope)
        return [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($bytes, '', $flags)
    }
    $rsa = [System.Security.Cryptography.RSA]::Create(2048)
    try {
        $request = [System.Security.Cryptography.X509Certificates.CertificateRequest]::new(
            'CN=CloveCOM Development', $rsa, [System.Security.Cryptography.HashAlgorithmName]::SHA256,
            [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)
        $oids = New-Object System.Security.Cryptography.OidCollection
        [void]$oids.Add([System.Security.Cryptography.Oid]::new('1.3.6.1.5.5.7.3.3'))
        $request.CertificateExtensions.Add([System.Security.Cryptography.X509Certificates.X509EnhancedKeyUsageExtension]::new($oids, $true))
        $request.CertificateExtensions.Add([System.Security.Cryptography.X509Certificates.X509KeyUsageExtension]::new(
            [System.Security.Cryptography.X509Certificates.X509KeyUsageFlags]::DigitalSignature, $true))
        $generated = $request.CreateSelfSigned([DateTimeOffset]::Now.AddMinutes(-5), [DateTimeOffset]::Now.AddYears(2))
        try { $bytes = $generated.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Pfx, '') }
        finally { $generated.Dispose() }
        [void][IO.Directory]::CreateDirectory($keyDir)
        [IO.File]::WriteAllBytes($keyFile, [System.Security.Cryptography.ProtectedData]::Protect($bytes, $null, $scope))
        return [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($bytes, '', $flags)
    } finally { $rsa.Dispose() }
}

function Write-Logos([string]$Destination) {
    Add-Type -AssemblyName System.Drawing
    [void][IO.Directory]::CreateDirectory($Destination)
    # 直接从应用 ICO 提取最大帧（兼容内嵌 PNG 帧与传统 BMP 帧），避免维护重复图标文件。
    $icoPath = Join-Path $projectRoot 'windows\runner\resources\app_icon.ico'
    $icoBytes = [IO.File]::ReadAllBytes($icoPath)
    $count = [BitConverter]::ToUInt16($icoBytes, 4)
    $bestSize = -1; $bestOffset = 0; $bestLength = 0
    for ($i = 0; $i -lt $count; $i++) {
        $entry = 6 + $i * 16
        $w = if ($icoBytes[$entry] -eq 0) { 256 } else { [int]$icoBytes[$entry] }
        if ($w -gt $bestSize) {
            $bestSize = $w
            $bestLength = [BitConverter]::ToInt32($icoBytes, $entry + 8)
            $bestOffset = [BitConverter]::ToInt32($icoBytes, $entry + 12)
        }
    }
    $isPng = $bestLength -ge 8 -and $icoBytes[$bestOffset] -eq 0x89 -and $icoBytes[$bestOffset + 1] -eq 0x50
    $source = $null; $stream = $null; $iconObj = $null
    try {
        if ($isPng) {
            $stream = [IO.MemoryStream]::new($icoBytes, $bestOffset, $bestLength)
            $source = [System.Drawing.Image]::FromStream($stream)
        } else {
            $iconObj = [System.Drawing.Icon]::new($icoPath, 256, 256)
            $source = $iconObj.ToBitmap()
        }
        foreach ($item in @(@('StoreLogo', 50), @('Square44x44Logo', 44), @('Square150x150Logo', 150))) {
            $bitmap = [System.Drawing.Bitmap]::new([int]$item[1], [int]$item[1])
            $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
            try {
                $graphics.Clear([System.Drawing.Color]::Transparent)
                $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                $graphics.DrawImage($source, 0, 0, [int]$item[1], [int]$item[1])
                $bitmap.Save((Join-Path $Destination ($item[0] + '.png')), [System.Drawing.Imaging.ImageFormat]::Png)
            } finally { $graphics.Dispose(); $bitmap.Dispose() }
        }
    } finally {
        if ($source) { $source.Dispose() }
        if ($stream) { $stream.Dispose() }
        if ($iconObj) { $iconObj.Dispose() }
    }
}

try {
    Push-Location $projectRoot
    if ($IdentityName -notmatch '^[A-Za-z0-9][A-Za-z0-9.-]{2,49}$') { throw 'IdentityName 必须是 3–50 位字母、数字、点或连字符。' }
    $pubspec = Get-Content -LiteralPath (Join-Path $projectRoot 'pubspec.yaml') -Raw
    if ($pubspec -notmatch '(?m)^version:\s*(\d+)\.(\d+)\.(\d+)(?:\+(\d+))?\s*$') { throw 'pubspec.yaml 需要 major.minor.patch+build 格式版本。' }
    $revision = if ($Matches.ContainsKey(4)) { $Matches[4] } else { '0' }
    $version = "$($Matches[1]).$($Matches[2]).$($Matches[3]).$revision"
    foreach ($part in $version.Split('.')) { if ([long]$part -gt 65535) { throw 'MSIX 版本的每段不能超过 65535。' } }
    $makeNsis = $Target -in @('All', 'Nsis')
    $makeMsix = $Target -in @('All', 'Msix')
    $makeZip = $Target -in @('All', 'Zip')
    $makeSetup = $Target -in @('All', 'Setup')
    if ($makeNsis -or $makeSetup) { $nsis = Find-Nsis }
    if ($makeMsix) { $sdk = Find-Sdk }
    $crt = Find-VcRuntime
    Write-Host "打包版本：$version，目标：$Target，VC++ 运行库：$crt"
    if (-not $SkipBuild) { Build-WindowsRelease $DependencyMode }
    else { Write-Warning '跳过构建：请自行确认 Release 目录与当前源代码一致。' }
    $release = Join-Path $projectRoot 'build\windows\x64\runner\Release'
    foreach ($required in @('clovecom.exe', 'flutter_windows.dll', 'data\app.so', 'data\icudtl.dat', 'data\flutter_assets')) {
        if (-not (Test-Path -LiteralPath (Join-Path $release $required))) { throw "Release 产物缺失：$required" }
    }
    $exeBytes = [IO.File]::ReadAllBytes((Join-Path $release 'clovecom.exe'))
    $peOffset = [BitConverter]::ToInt32($exeBytes, 0x3c)
    if ([BitConverter]::ToUInt16($exeBytes, $peOffset + 4) -ne 0x8664) { throw '当前脚本仅支持 Windows x64 产物。' }
    & (Join-Path $projectRoot 'scripts\packaging\assert-exe-icon.ps1') `
        -ExePath (Join-Path $release 'clovecom.exe') `
        -IconPath (Join-Path $projectRoot 'windows\runner\resources\app_icon.ico')
    $payload = Join-Path $work 'payload'
    $artifacts = Join-Path $work 'artifacts'
    [void][IO.Directory]::CreateDirectory($payload)
    [void][IO.Directory]::CreateDirectory($artifacts)
    & (Join-Path $projectRoot 'scripts\packaging\copy-clean-payload.ps1') -ReleaseDirectory $release -DestinationDirectory $payload
    foreach ($required in @('clovecom.exe', 'flutter_windows.dll', 'data\app.so', 'data\icudtl.dat', 'data\flutter_assets')) {
        if (-not (Test-Path -LiteralPath (Join-Path $payload $required))) { throw "分发资源复制不完整：$required" }
    }
    Get-ChildItem -LiteralPath $crt -Filter '*.dll' | Copy-Item -Destination $payload
    foreach ($required in @('msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll')) {
        if (-not (Test-Path -LiteralPath (Join-Path $payload $required))) { throw "VC++ 运行库缺失：$required" }
    }
    $stem = "CloveCOM-$version-windows-x64"
    if ($makeZip) {
        Write-Host '生成 ZIP 免安装包（完整解压后运行 clovecom.exe）……'
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [IO.Compression.ZipFile]::CreateFromDirectory($payload,
            (Join-Path $artifacts "$stem-portable.zip"),
            [IO.Compression.CompressionLevel]::Optimal, $false)
    }
    if ($makeNsis) {
        Write-Host '生成 NSIS 单 EXE 自解压运行包……'
        Invoke-Checked $nsis @('/V2', '/INPUTCHARSET', 'UTF8', "/DPAYLOAD_DIR=$payload",
            "/DOUTPUT_FILE=$artifacts\$stem-portable.exe", "/DAPP_VERSION=$version",
            "/DAPP_ICON=$projectRoot\windows\runner\resources\app_icon.ico", "$projectRoot\scripts\packaging\portable.nsi")
    }
    if ($makeSetup) {
        & (Join-Path $projectRoot 'scripts\packaging\build-setup.ps1') -PayloadDirectory $payload `
            -OutputFile "$artifacts\$stem-setup.exe" -Version $version -NsisPath $nsis `
            -IconPath "$projectRoot\windows\runner\resources\app_icon.ico"
    }
    if ($makeMsix) {
        Write-Host '生成 MSIX 安装包……'
        $certificate = Get-SigningCertificate
        if (-not $certificate.HasPrivateKey) { throw '签名证书不含私钥。' }
        if ($certificate.NotAfter -le (Get-Date) -or $certificate.NotBefore -gt (Get-Date)) { throw '签名证书不在有效期内。' }
        $msixPayload = Join-Path $work 'msix'
        Copy-Item -LiteralPath $payload -Destination $msixPayload -Recurse
        Write-Logos (Join-Path $msixPayload 'Assets')
        $manifest = [IO.File]::ReadAllText("$projectRoot\scripts\packaging\AppxManifest.xml.template")
        $manifest = $manifest.Replace('@IDENTITY@', $IdentityName).Replace('@VERSION@', $version).Replace(
            '@PUBLISHER@', [System.Security.SecurityElement]::Escape($certificate.Subject))
        [IO.File]::WriteAllText((Join-Path $msixPayload 'AppxManifest.xml'), $manifest, $utf8)
        $suffix = if ($CertificatePath) { '' } else { '-dev' }
        $msixFile = Join-Path $artifacts "$stem$suffix.msix"
        Invoke-Checked "$sdk\makeappx.exe" @('pack', '/d', $msixPayload, '/p', $msixFile, '/o')
        $signingPassword = [Guid]::NewGuid().ToString('N')
        $signingFile = Join-Path $work 'signing.pfx'
        [IO.File]::WriteAllBytes($signingFile, $certificate.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Pfx, $signingPassword))
        $signArgs = @('sign', '/fd', 'SHA256', '/f', $signingFile, '/p', $signingPassword)
        if ($TimestampUrl) { $signArgs += @('/tr', $TimestampUrl, '/td', 'SHA256') }
        Invoke-Checked "$sdk\signtool.exe" ($signArgs + @($msixFile))
        if (-not $CertificatePath) {
            [IO.File]::WriteAllBytes((Join-Path $artifacts 'CloveCOM-development.cer'), $certificate.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert))
            Write-Warning 'MSIX 已使用测试证书签名；未导入信任。目标机器须手动信任附带的公开 CER 后安装。'
        }
    }
    # 所有目标成功后才发布结果，避免将半成品当作本轮成功产物。
    $hashes = @(Get-ChildItem -LiteralPath $artifacts -File | ForEach-Object {
        '{0}  {1}' -f (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant(), $_.Name
    })
    [IO.File]::WriteAllLines((Join-Path $artifacts "$stem-$Target-SHA256SUMS.txt"), $hashes, $utf8)
    [void][IO.Directory]::CreateDirectory($dist)
    Get-ChildItem -LiteralPath $artifacts -File | Copy-Item -Destination $dist -Force
    Write-Host "打包成功，输出目录：$dist"
    Get-ChildItem -LiteralPath $artifacts -File | ForEach-Object { Write-Host "  $($_.Name)" }
} catch {
    Write-Error $_ -ErrorAction Continue
    exit 1
} finally {
    if ($certificate) { $certificate.Dispose() }
    # 仅清理本次唯一工作目录，解析绝对路径并确认仍在预期 build/packaging 下。
    $absoluteWork = [IO.Path]::GetFullPath($work)
    $expectedParent = [IO.Path]::GetFullPath($workRoot).TrimEnd('\') + '\'
    if ($absoluteWork.StartsWith($expectedParent, [StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $absoluteWork)) {
        Remove-Item -LiteralPath $absoluteWork -Recurse -Force
    }
    Pop-Location
}
