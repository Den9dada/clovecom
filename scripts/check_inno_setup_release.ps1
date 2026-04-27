$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$inputDir = Join-Path $repoRoot 'release_package/enigma_input'
$issPath = Join-Path $repoRoot 'installer/clovecom.iss'

function Assert-PathExists {
  param([Parameter(Mandatory = $true)][string]$Path)

  if (-not (Test-Path -LiteralPath $Path)) {
    throw "Required Inno input path is missing: $Path"
  }
}

function Assert-FileContains {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Pattern,
    [Parameter(Mandatory = $true)][string]$Message
  )

  Assert-PathExists -Path $Path
  $content = Get-Content -LiteralPath $Path -Raw
  if ($content -notmatch $Pattern) {
    throw $Message
  }
}

function Find-Iscc {
  $command = Get-Command ISCC.exe -ErrorAction SilentlyContinue
  if ($command) {
    return $command.Source
  }

  $roots = @($env:ProgramFiles, ${env:ProgramFiles(x86)}) |
    Where-Object { $_ -and (Test-Path -LiteralPath $_) }

  foreach ($root in $roots) {
    $found = Get-ChildItem -LiteralPath $root -Directory -Filter 'Inno Setup*' -ErrorAction SilentlyContinue |
      ForEach-Object { Join-Path $_.FullName 'ISCC.exe' } |
      Where-Object { Test-Path -LiteralPath $_ } |
      Select-Object -First 1

    if ($found) {
      return $found
    }
  }

  return $null
}

$requiredInput = @(
  'clovecom.exe',
  'flutter_windows.dll',
  'native_assets.json',
  'data/app.so',
  'data/icudtl.dat',
  'data/flutter_assets',
  'msvcp140.dll',
  'vcruntime140.dll',
  'vcruntime140_1.dll',
  'ucrtbase.dll'
)

foreach ($relativePath in $requiredInput) {
  Assert-PathExists -Path (Join-Path $inputDir $relativePath)
}

Assert-FileContains $issPath 'ArchitecturesInstallIn64BitMode=x64compatible' 'clovecom.iss must install in x64-compatible mode.'
Assert-FileContains $issPath '\[Files\]' 'clovecom.iss must define files to install.'
Assert-FileContains $issPath '\[Icons\]' 'clovecom.iss must define shortcuts.'
Assert-FileContains $issPath '\[Code\]' 'clovecom.iss must define installer checks.'
Assert-FileContains $issPath '不支持当前系统' 'clovecom.iss must warn about unsupported systems in Chinese.'
Assert-FileContains $issPath '请先关闭 CloveCom' 'clovecom.iss must warn when CloveCom is running.'
Assert-FileContains $issPath 'install_check\.log' 'clovecom.iss must write install_check.log on validation failure.'

$iscc = Find-Iscc
if ($iscc) {
  Write-Host "Inno Setup compiler found: $iscc"
} else {
  Write-Warning 'ISCC.exe was not found. Install Inno Setup or add ISCC.exe to PATH before compiling the installer.'
}

Write-Host 'Inno Setup release input checks passed.'
