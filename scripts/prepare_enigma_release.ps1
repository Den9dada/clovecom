param(
  [switch]$Build
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$buildDir = Join-Path $repoRoot 'build/windows/x64/runner/Release'
$releaseDir = Join-Path $repoRoot 'release_package'
$inputDir = Join-Path $releaseDir 'enigma_input'
$evbPath = Join-Path $releaseDir 'clovecom.evb'
$outputExe = Join-Path $releaseDir 'clovecom_packed.exe'

function Copy-RequiredFile {
  param(
    [Parameter(Mandatory = $true)][string]$Source,
    [Parameter(Mandatory = $true)][string]$Destination
  )

  if (-not (Test-Path -LiteralPath $Source)) {
    throw "Required file not found: $Source"
  }

  Copy-Item -LiteralPath $Source -Destination $Destination -Force
}

function Find-RuntimeDll {
  param([Parameter(Mandatory = $true)][string]$Name)

  $candidates = @()
  $programFilesRoots = @($env:ProgramFiles, ${env:ProgramFiles(x86)}) |
    Where-Object { $_ -and (Test-Path -LiteralPath $_) }

  foreach ($root in $programFilesRoots) {
    $vsRoot = Join-Path $root 'Microsoft Visual Studio'
    if (Test-Path -LiteralPath $vsRoot) {
      $candidates += Get-ChildItem -LiteralPath $vsRoot -Recurse -Filter $Name -ErrorAction SilentlyContinue |
        Where-Object {
          $_.FullName -match '\\VC\\Redist\\MSVC\\.*\\x64\\' -or
          $_.FullName -match '\\VC\\Tools\\MSVC\\.*\\bin\\Hostx64\\x64\\'
        }
    }
  }

  $system32Path = Join-Path $env:WINDIR "System32\$Name"
  if (Test-Path -LiteralPath $system32Path) {
    $candidates += Get-Item -LiteralPath $system32Path
  }

  return $candidates | Select-Object -First 1
}

if ($Build) {
  Write-Host 'Building Flutter Windows release...'
  Push-Location $repoRoot
  try {
    flutter build windows --release
  } finally {
    Pop-Location
  }
} else {
  Write-Host 'Using existing Flutter Windows release output. Run flutter build windows --release first if it is stale.'
}

if (-not (Test-Path -LiteralPath $buildDir)) {
  throw "Flutter release output not found: $buildDir"
}

if (Test-Path -LiteralPath $inputDir) {
  Remove-Item -LiteralPath $inputDir -Recurse -Force
}
New-Item -ItemType Directory -Path $inputDir | Out-Null

Get-ChildItem -LiteralPath $buildDir -Force |
  Copy-Item -Destination $inputDir -Recurse -Force

$requiredRuntimeDlls = @(
  'msvcp140.dll',
  'vcruntime140.dll',
  'vcruntime140_1.dll'
)

$copiedRuntimeDlls = New-Object System.Collections.Generic.List[string]
$runtimeDllNames = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
$runtimeDllNames.Add('flutter_windows.dll') | Out-Null

foreach ($dll in $requiredRuntimeDlls) {
  $source = Find-RuntimeDll -Name $dll
  if (-not $source) {
    throw "Required VC++ runtime DLL not found: $dll"
  }

  Copy-RequiredFile -Source $source.FullName -Destination (Join-Path $inputDir $dll)
  $copiedRuntimeDlls.Add($dll)
  $runtimeDllNames.Add($dll) | Out-Null
}

$appBundleDlls = Get-ChildItem -LiteralPath $inputDir -File -Filter '*.dll' |
  Where-Object { -not $runtimeDllNames.Contains($_.Name) } |
  Select-Object -ExpandProperty Name

$xml = New-Object System.Xml.XmlDocument
$declaration = $xml.CreateXmlDeclaration('1.0', 'UTF-8', $null)
$xml.AppendChild($declaration) | Out-Null
$root = $xml.CreateElement('EnigmaVirtualBox')
$xml.AppendChild($root) | Out-Null

function Add-TextElement {
  param(
    [Parameter(Mandatory = $true)][System.Xml.XmlElement]$Parent,
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][string]$Text
  )

  $node = $xml.CreateElement($Name)
  $node.InnerText = $Text
  $Parent.AppendChild($node) | Out-Null
}

Add-TextElement -Parent $root -Name 'InputFile' -Text (Join-Path $inputDir 'clovecom.exe')
Add-TextElement -Parent $root -Name 'OutputFile' -Text $outputExe

$files = $xml.CreateElement('Files')
$root.AppendChild($files) | Out-Null

function Add-VirtualFile {
  param([Parameter(Mandatory = $true)][string]$Path)

  if (-not (Test-Path -LiteralPath $Path)) {
    throw "Enigma input path not found: $Path"
  }

  $file = $xml.CreateElement('File')
  Add-TextElement -Parent $file -Name 'Path' -Text $Path
  Add-TextElement -Parent $file -Name 'Virtualization' -Text '0'
  $files.AppendChild($file) | Out-Null
}

Add-VirtualFile -Path (Join-Path $inputDir 'flutter_windows.dll')
Add-VirtualFile -Path (Join-Path $inputDir 'native_assets.json')
Add-VirtualFile -Path (Join-Path $inputDir 'data')
foreach ($dll in $appBundleDlls) {
  Add-VirtualFile -Path (Join-Path $inputDir $dll)
}
foreach ($dll in $copiedRuntimeDlls) {
  Add-VirtualFile -Path (Join-Path $inputDir $dll)
}

$xml.Save($evbPath)

Write-Host "Prepared Enigma input: $inputDir"
Write-Host "Generated Enigma project: $evbPath"
Write-Host 'Included VC++ runtime DLLs:'
$copiedRuntimeDlls | ForEach-Object { Write-Host " - $_" }
