$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$inputDir = Join-Path $repoRoot 'release_package/enigma_input'
$exePath = Join-Path $inputDir 'clovecom.exe'

if (-not (Test-Path -LiteralPath $exePath)) {
  throw "Release input executable not found. Run scripts/prepare_enigma_release.ps1 first: $exePath"
}

function Find-Dumpbin {
  $command = Get-Command dumpbin.exe -ErrorAction SilentlyContinue
  if ($command) {
    return $command.Source
  }

  $programFilesX86 = ${env:ProgramFiles(x86)}
  if (-not $programFilesX86 -or -not (Test-Path -LiteralPath $programFilesX86)) {
    return $null
  }

  $found = Get-ChildItem -LiteralPath $programFilesX86 -Recurse -Filter dumpbin.exe -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -match '\\VC\\Tools\\MSVC\\.*\\bin\\Hostx64\\x64\\dumpbin\.exe$' } |
    Select-Object -First 1

  if ($found) {
    return $found.FullName
  }

  return $null
}

$dumpbin = Find-Dumpbin
if (-not $dumpbin) {
  Write-Warning 'dumpbin.exe was not found. Skipping native dependency inspection.'
  exit 0
}

$output = & $dumpbin /DEPENDENTS $exePath
if ($LASTEXITCODE -ne 0) {
  throw "dumpbin failed with exit code $LASTEXITCODE"
}

$dependencies = $output |
  Where-Object { $_ -match '^\s+[A-Za-z0-9_.-]+\.dll\s*$' } |
  ForEach-Object { $_.Trim() }

$systemDlls = @(
  'ADVAPI32.dll',
  'dwmapi.dll',
  'KERNEL32.dll',
  'ole32.dll',
  'SHELL32.dll',
  'USER32.dll'
)

$appLocalDlls = @(
  'flutter_windows.dll',
  'MSVCP140.dll',
  'VCRUNTIME140.dll',
  'VCRUNTIME140_1.dll',
  'ucrtbase.dll'
)

$missing = New-Object System.Collections.Generic.List[string]

foreach ($dependency in $dependencies) {
  if ($dependency -like 'api-ms-win-crt-*.dll') {
    $path = Join-Path $inputDir $dependency
    if (-not (Test-Path -LiteralPath $path)) {
      $missing.Add($dependency)
    }
    continue
  }

  $isSystem = $systemDlls | Where-Object {
    $_.Equals($dependency, [System.StringComparison]::OrdinalIgnoreCase)
  }
  if ($isSystem) {
    continue
  }

  $isAppLocal = $appLocalDlls | Where-Object {
    $_.Equals($dependency, [System.StringComparison]::OrdinalIgnoreCase)
  }
  if ($isAppLocal) {
    $path = Join-Path $inputDir $dependency
    if (-not (Test-Path -LiteralPath $path)) {
      $missing.Add($dependency)
    }
    continue
  }

  Write-Warning "Unclassified dependency from clovecom.exe: $dependency"
}

if ($missing.Count -gt 0) {
  throw "Missing app-local dependencies: $($missing -join ', ')"
}

Write-Host 'Windows release dependency checks passed.'
