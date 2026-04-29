$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot

function Assert-FileContains {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Pattern,
    [Parameter(Mandatory = $true)][string]$Message
  )

  if (-not (Test-Path -LiteralPath $Path)) {
    throw "Missing file: $Path"
  }

  $content = Get-Content -LiteralPath $Path -Raw
  if ($content -notmatch $Pattern) {
    throw $Message
  }
}

function Assert-FileNotContains {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Pattern,
    [Parameter(Mandatory = $true)][string]$Message
  )

  if (-not (Test-Path -LiteralPath $Path)) {
    throw "Missing file: $Path"
  }

  $content = Get-Content -LiteralPath $Path -Raw
  if ($content -match $Pattern) {
    throw $Message
  }
}

$iss = Join-Path $root 'installer/clovecom.iss'
$checkScript = Join-Path $root 'scripts/check_inno_setup_release.ps1'
$prepareScript = Join-Path $root 'scripts/prepare_inno_setup_release.ps1'
$oneClickScript = Join-Path $root 'scripts/build_installer_once.ps1'
$readme = Join-Path $root 'README.md'

Assert-FileContains $iss 'ArchitecturesInstallIn64BitMode=x64compatible' 'installer must use x64-compatible install mode'
Assert-FileContains $iss 'DefaultDirName=\{autopf\}\\CloveCom' 'installer must install to Program Files'
Assert-FileContains $iss 'Source: "\.\.\\release_package\\enigma_input\\\*"' 'installer must copy staged Flutter bundle'
Assert-FileContains $iss 'Name: "\{autoprograms\}\\CloveCom"' 'installer must create Start Menu shortcut'
Assert-FileContains $iss 'Name: "\{autodesktop\}\\CloveCom"' 'installer must support desktop shortcut'
Assert-FileContains $iss '不支持当前系统' 'installer must warn on unsupported systems in Chinese'
Assert-FileContains $iss '请先关闭 CloveCom' 'installer must warn when app appears to be running'
Assert-FileContains $iss 'install_check\.log' 'installer must write post-install check log'
Assert-FileContains $iss 'data\\app\.so' 'installer must verify Flutter app.so'
Assert-FileContains $iss 'vcruntime140_1\.dll' 'installer must verify VC++ runtime files'
Assert-FileNotContains $iss 'ucrtbase\.dll' 'installer must not verify app-local UCRT files'

Assert-FileContains $checkScript 'release_package/enigma_input' 'check script must validate Inno input directory'
Assert-FileContains $checkScript 'ISCC\.exe' 'check script must report Inno compiler availability'
Assert-FileContains $checkScript 'clovecom\.iss' 'check script must inspect the Inno project'
Assert-FileNotContains $checkScript 'ucrtbase\.dll' 'check script must not require app-local UCRT files'

Assert-FileContains $prepareScript 'param\(' 'prepare script must declare parameters'
Assert-FileContains $prepareScript 'PrepareInput' 'prepare script must optionally prepare shared input'
Assert-FileContains $prepareScript 'SkipCompile' 'prepare script must support validation-only mode'
Assert-FileContains $prepareScript 'ISCC\.exe' 'prepare script must invoke Inno compiler'
Assert-FileContains $prepareScript '\$checkFailed' 'prepare script must use PowerShell script error handling instead of raw LASTEXITCODE'

Assert-FileContains $oneClickScript 'param\(' 'one-click script must declare parameters'
Assert-FileContains $oneClickScript '\[switch\]\$Build' 'one-click script must make Flutter build opt-in'
Assert-FileContains $oneClickScript 'prepare_enigma_release\.ps1' 'one-click script must prepare shared release input'
Assert-FileContains $oneClickScript 'check_windows_release_dependencies\.ps1' 'one-click script must check native dependencies'
Assert-FileContains $oneClickScript 'check_inno_setup_release\.ps1' 'one-click script must check Inno installer input'
Assert-FileContains $oneClickScript 'prepare_inno_setup_release\.ps1' 'one-click script must compile the installer'
Assert-FileContains $oneClickScript 'CloveComSetup\.exe' 'one-click script must print the generated installer path'
Assert-FileContains $oneClickScript '一键生成 CloveCom 安装向导' 'one-click script must show Chinese progress text'

Assert-FileContains $readme 'Windows 发布与交付' 'README must document the Windows release workflow'
Assert-FileContains $readme 'build_installer_once\.ps1' 'README must document the one-click installer script'

Write-Host 'Inno Setup release checks passed.'
