param(
  [switch]$PrepareInput,
  [switch]$SkipCompile
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$issPath = Join-Path $repoRoot 'installer/clovecom.iss'
$checkScript = Join-Path $PSScriptRoot 'check_inno_setup_release.ps1'
$prepareEnigmaScript = Join-Path $PSScriptRoot 'prepare_enigma_release.ps1'

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

if ($PrepareInput) {
  Write-Host 'Preparing shared release input...'
  $prepareFailed = $false
  try {
    & $prepareEnigmaScript
  } catch {
    $prepareFailed = $true
    throw
  } finally {
    if ($prepareFailed) {
      Write-Error 'prepare_enigma_release.ps1 failed.'
    }
  }
}

$checkFailed = $false
try {
  & $checkScript
} catch {
  $checkFailed = $true
  throw
} finally {
  if ($checkFailed) {
    Write-Error 'check_inno_setup_release.ps1 failed.'
  }
}

if ($SkipCompile) {
  Write-Host 'Skipping Inno Setup compilation because -SkipCompile was supplied.'
  exit 0
}

$iscc = Find-Iscc
if (-not $iscc) {
  throw 'ISCC.exe was not found. Install Inno Setup or add ISCC.exe to PATH.'
}

Write-Host "Compiling installer with: $iscc"
& $iscc $issPath
if ($LASTEXITCODE -ne 0) {
  throw "ISCC.exe failed with exit code $LASTEXITCODE"
}

Write-Host 'Inno Setup installer build completed.'
