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

$prepareScript = Join-Path $root 'scripts/prepare_enigma_release.ps1'
$checkScript = Join-Path $root 'scripts/check_windows_release_dependencies.ps1'
$mainCpp = Join-Path $root 'windows/runner/main.cpp'
$runnerCMake = Join-Path $root 'windows/runner/CMakeLists.txt'
$utilsCpp = Join-Path $root 'windows/runner/utils.cpp'
$utilsH = Join-Path $root 'windows/runner/utils.h'

Assert-FileContains $prepareScript '\[switch\]\$Build' 'prepare script must make Flutter build opt-in'
Assert-FileContains $prepareScript 'if \(\$Build\)' 'prepare script must not build unless explicitly requested'
Assert-FileContains $prepareScript 'flutter build windows --release' 'prepare script must support an explicit Windows release build'
Assert-FileContains $prepareScript 'msvcp140\.dll' 'prepare script must copy MSVCP140.dll'
Assert-FileContains $prepareScript 'vcruntime140_1\.dll' 'prepare script must copy VCRUNTIME140_1.dll'
Assert-FileNotContains $prepareScript 'optionalRuntimeDlls' 'prepare script must not copy optional VC++ runtime DLLs'
Assert-FileNotContains $prepareScript 'ucrtbase\.dll' 'prepare script must not copy UCRT runtime files'
Assert-FileNotContains $prepareScript 'api-ms-win-crt-\*\.dll' 'prepare script must not copy API-MS CRT forwarder DLLs'
Assert-FileContains $prepareScript 'EnigmaVirtualBox' 'prepare script must generate an Enigma project'
Assert-FileContains $prepareScript 'enigma_input' 'prepare script must stage files in release_package/enigma_input'
Assert-FileContains $prepareScript 'appBundleDlls' 'prepare script must include Flutter plugin DLLs in the Enigma project'

Assert-FileContains $checkScript '/DEPENDENTS' 'dependency script must inspect native dependencies'
Assert-FileContains $checkScript 'flutter_windows\.dll' 'dependency script must require flutter_windows.dll'
Assert-FileContains $checkScript 'desktop_drop_plugin\.dll' 'dependency script must classify Flutter plugin DLLs as app-local'
Assert-FileContains $checkScript 'MSVCP140\.dll' 'dependency script must classify MSVCP140.dll as app-local'
Assert-FileNotContains $checkScript 'ucrtbase\.dll' 'dependency script must not require app-local UCRT files'

Assert-FileContains $utilsH 'SetCurrentDirectoryToExecutablePath' 'utils.h must declare startup directory helper'
Assert-FileContains $utilsH 'LogStartupEvent' 'utils.h must declare startup logging helper'
Assert-FileContains $utilsH 'ValidateFlutterRuntimeFiles' 'utils.h must declare Flutter runtime validation helper'
Assert-FileContains $utilsCpp 'SetCurrentDirectoryW' 'utils.cpp must set the current directory'
Assert-FileContains $utilsCpp 'LogStartupEvent' 'utils.cpp must write startup trace entries'
Assert-FileContains $utilsCpp 'MessageBoxW' 'utils.cpp must show a visible startup error when Flutter files are missing'
Assert-FileContains $utilsCpp 'clovecom_startup_error\.log' 'utils.cpp must write a startup diagnostic log'
Assert-FileContains $utilsCpp 'kernel_blob\.bin' 'utils.cpp must accept Flutter debug runtime kernel_blob.bin when app.so is absent'
Assert-FileContains $mainCpp 'LogStartupEvent\(L"wWinMain entered"\);' 'main.cpp must log as soon as wWinMain starts'
Assert-FileContains $mainCpp 'SetCurrentDirectoryToExecutablePath\(\);' 'main.cpp must call startup directory helper'
Assert-FileContains $mainCpp 'ValidateFlutterRuntimeFiles\(\)' 'main.cpp must validate Flutter runtime files before startup'
Assert-FileContains $runnerCMake 'DELAYLOAD:flutter_windows\.dll' 'runner CMake must delay-load flutter_windows.dll'
Assert-FileContains $runnerCMake 'delayimp\.lib' 'runner CMake must link delay-load helper library'

Write-Host 'Release packaging checks passed.'
