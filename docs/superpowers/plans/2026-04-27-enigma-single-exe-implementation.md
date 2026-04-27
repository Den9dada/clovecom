# Enigma Single-EXE Release Compatibility Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build repeatable Windows x64 Enigma packaging support so the final single EXE includes Flutter assets and VC++ runtime DLLs.

**Architecture:** Keep Flutter's standard Windows release layout intact, then stage it into `release_package/enigma_input/` with app-local runtime DLLs. The runner sets its current directory to the executable directory before loading `data`. PowerShell scripts build, stage, generate `.evb`, and check native dependencies.

**Tech Stack:** Flutter Windows, C++ Win32 runner, PowerShell 5+, Enigma Virtual Box project XML, `dumpbin.exe` when available.

---

## File Structure

- Create: `scripts/prepare_enigma_release.ps1`
  - Builds the Windows release, stages files for Enigma, copies VC++ runtime DLLs, and writes `release_package/clovecom.evb`.
- Create: `scripts/check_windows_release_dependencies.ps1`
  - Uses `dumpbin /DEPENDENTS` to verify app-local dependencies are present in `release_package/enigma_input/`.
- Create: `test/release_packaging_test.ps1`
  - Lightweight PowerShell tests for the packaging scripts and runner source.
- Modify: `windows/runner/utils.h`
  - Declares `SetCurrentDirectoryToExecutablePath()`.
- Modify: `windows/runner/utils.cpp`
  - Implements the Win32 helper that changes the current directory to the executable folder.
- Modify: `windows/runner/main.cpp`
  - Calls the helper before creating `flutter::DartProject project(L"data")`.
- Modify: `README.md`
  - Documents the Enigma single-EXE release workflow and clean-machine validation.

## Task 1: Add Release Packaging Tests

**Files:**
- Create: `test/release_packaging_test.ps1`

- [ ] **Step 1: Write the failing test**

Create `test/release_packaging_test.ps1` with checks that fail until the scripts and runner helper exist:

```powershell
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

$prepareScript = Join-Path $root 'scripts/prepare_enigma_release.ps1'
$checkScript = Join-Path $root 'scripts/check_windows_release_dependencies.ps1'
$mainCpp = Join-Path $root 'windows/runner/main.cpp'
$utilsCpp = Join-Path $root 'windows/runner/utils.cpp'
$utilsH = Join-Path $root 'windows/runner/utils.h'

Assert-FileContains $prepareScript 'flutter build windows --release' 'prepare script must build the Windows release'
Assert-FileContains $prepareScript 'msvcp140\.dll' 'prepare script must copy MSVCP140.dll'
Assert-FileContains $prepareScript 'vcruntime140_1\.dll' 'prepare script must copy VCRUNTIME140_1.dll'
Assert-FileContains $prepareScript 'EnigmaVirtualBox' 'prepare script must generate an Enigma project'
Assert-FileContains $prepareScript 'enigma_input' 'prepare script must stage files in release_package/enigma_input'

Assert-FileContains $checkScript '/DEPENDENTS' 'dependency script must inspect native dependencies'
Assert-FileContains $checkScript 'flutter_windows\.dll' 'dependency script must require flutter_windows.dll'
Assert-FileContains $checkScript 'MSVCP140\.dll' 'dependency script must classify MSVCP140.dll as app-local'

Assert-FileContains $utilsH 'SetCurrentDirectoryToExecutablePath' 'utils.h must declare startup directory helper'
Assert-FileContains $utilsCpp 'SetCurrentDirectoryW' 'utils.cpp must set the current directory'
Assert-FileContains $mainCpp 'SetCurrentDirectoryToExecutablePath\(\);' 'main.cpp must call startup directory helper'

Write-Host 'Release packaging checks passed.'
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File test/release_packaging_test.ps1
```

Expected: FAIL with `Missing file: ...scripts/prepare_enigma_release.ps1`.

## Task 2: Add Runner Startup Directory Helper

**Files:**
- Modify: `windows/runner/utils.h`
- Modify: `windows/runner/utils.cpp`
- Modify: `windows/runner/main.cpp`
- Test: `test/release_packaging_test.ps1`

- [ ] **Step 1: Implement the helper declaration**

Add to `windows/runner/utils.h` before `#endif`:

```cpp
// Sets the current working directory to the directory containing this
// executable. This keeps relative Flutter asset paths stable when launched from
// a shortcut, another working directory, or a packed Enigma executable.
void SetCurrentDirectoryToExecutablePath();
```

- [ ] **Step 2: Implement the helper**

Add this function to `windows/runner/utils.cpp` after `CreateAndAttachConsole()`:

```cpp
void SetCurrentDirectoryToExecutablePath() {
  wchar_t executable_path[MAX_PATH];
  DWORD length = ::GetModuleFileNameW(nullptr, executable_path, MAX_PATH);
  if (length == 0 || length == MAX_PATH) {
    return;
  }

  wchar_t* last_separator = wcsrchr(executable_path, L'\\');
  if (last_separator == nullptr) {
    return;
  }

  *last_separator = L'\0';
  ::SetCurrentDirectoryW(executable_path);
}
```

- [ ] **Step 3: Call the helper before Flutter project creation**

In `windows/runner/main.cpp`, call the helper after COM initialization and before `flutter::DartProject project(L"data");`:

```cpp
  SetCurrentDirectoryToExecutablePath();

  flutter::DartProject project(L"data");
```

- [ ] **Step 4: Run the packaging test**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File test/release_packaging_test.ps1
```

Expected: still FAIL because packaging scripts are not created yet, but runner helper checks should pass once scripts exist.

## Task 3: Add Enigma Release Preparation Script

**Files:**
- Create: `scripts/prepare_enigma_release.ps1`
- Test: `test/release_packaging_test.ps1`

- [ ] **Step 1: Create the script**

Create `scripts/prepare_enigma_release.ps1`:

```powershell
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
  $programFilesX86 = ${env:ProgramFiles(x86)}
  if ($programFilesX86) {
    $candidates += Get-ChildItem -LiteralPath $programFilesX86 -Recurse -Filter $Name -ErrorAction SilentlyContinue |
      Where-Object { $_.FullName -match '\\VC\\Redist\\MSVC\\.*\\x64\\' -or $_.FullName -match '\\VC\\Tools\\MSVC\\.*\\bin\\Hostx64\\x64\\' }
  }

  $system32Path = Join-Path $env:WINDIR "System32\$Name"
  if (Test-Path -LiteralPath $system32Path) {
    $candidates += Get-Item -LiteralPath $system32Path
  }

  return $candidates | Select-Object -First 1
}

Write-Host 'Building Flutter Windows release...'
Push-Location $repoRoot
try {
  flutter build windows --release
} finally {
  Pop-Location
}

if (Test-Path -LiteralPath $inputDir) {
  Remove-Item -LiteralPath $inputDir -Recurse -Force
}
New-Item -ItemType Directory -Path $inputDir | Out-Null

Copy-Item -LiteralPath (Join-Path $buildDir '*') -Destination $inputDir -Recurse -Force

$requiredRuntimeDlls = @(
  'msvcp140.dll',
  'vcruntime140.dll',
  'vcruntime140_1.dll'
)

$optionalRuntimeDlls = @(
  'msvcp140_1.dll',
  'msvcp140_2.dll',
  'msvcp140_atomic_wait.dll',
  'msvcp140_codecvt_ids.dll',
  'concrt140.dll'
)

$copiedRuntimeDlls = New-Object System.Collections.Generic.List[string]

foreach ($dll in $requiredRuntimeDlls) {
  $source = Find-RuntimeDll -Name $dll
  if (-not $source) {
    throw "Required VC++ runtime DLL not found: $dll"
  }
  Copy-RequiredFile -Source $source.FullName -Destination (Join-Path $inputDir $dll)
  $copiedRuntimeDlls.Add($dll)
}

foreach ($dll in $optionalRuntimeDlls) {
  $source = Find-RuntimeDll -Name $dll
  if ($source) {
    Copy-RequiredFile -Source $source.FullName -Destination (Join-Path $inputDir $dll)
    $copiedRuntimeDlls.Add($dll)
  } else {
    Write-Warning "Optional VC++ runtime DLL not found: $dll"
  }
}

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
  $file = $xml.CreateElement('File')
  Add-TextElement -Parent $file -Name 'Path' -Text $Path
  Add-TextElement -Parent $file -Name 'Virtualization' -Text '0'
  $files.AppendChild($file) | Out-Null
}

Add-VirtualFile -Path (Join-Path $inputDir 'flutter_windows.dll')
Add-VirtualFile -Path (Join-Path $inputDir 'native_assets.json')
Add-VirtualFile -Path (Join-Path $inputDir 'data')
foreach ($dll in $copiedRuntimeDlls) {
  Add-VirtualFile -Path (Join-Path $inputDir $dll)
}

$xml.Save($evbPath)

Write-Host "Prepared Enigma input: $inputDir"
Write-Host "Generated Enigma project: $evbPath"
Write-Host "Included VC++ runtime DLLs:"
$copiedRuntimeDlls | ForEach-Object { Write-Host " - $_" }
```

- [ ] **Step 2: Run the packaging test**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File test/release_packaging_test.ps1
```

Expected: still FAIL because dependency check script is not created yet.

## Task 4: Add Windows Dependency Check Script

**Files:**
- Create: `scripts/check_windows_release_dependencies.ps1`
- Test: `test/release_packaging_test.ps1`

- [ ] **Step 1: Create the dependency check script**

Create `scripts/check_windows_release_dependencies.ps1`:

```powershell
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
  if (-not $programFilesX86) {
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
  'api-ms-win-crt-heap-l1-1-0.dll',
  'api-ms-win-crt-locale-l1-1-0.dll',
  'api-ms-win-crt-math-l1-1-0.dll',
  'api-ms-win-crt-runtime-l1-1-0.dll',
  'api-ms-win-crt-stdio-l1-1-0.dll',
  'api-ms-win-crt-string-l1-1-0.dll',
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
  'VCRUNTIME140_1.dll'
)

$missing = New-Object System.Collections.Generic.List[string]

foreach ($dependency in $dependencies) {
  $isSystem = $systemDlls | Where-Object { $_.Equals($dependency, [System.StringComparison]::OrdinalIgnoreCase) }
  if ($isSystem) {
    continue
  }

  $isAppLocal = $appLocalDlls | Where-Object { $_.Equals($dependency, [System.StringComparison]::OrdinalIgnoreCase) }
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
```

- [ ] **Step 2: Run the packaging test**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File test/release_packaging_test.ps1
```

Expected: PASS with `Release packaging checks passed.`

## Task 5: Document the Enigma Release Workflow

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Add release documentation**

Add a `Windows 单文件发布` section to `README.md`:

```markdown
## Windows 单文件发布

项目支持通过 Enigma Virtual Box 打包为单个 Windows x64 可执行文件，用户无需安装 Flutter、Dart 或 Microsoft Visual C++ Redistributable。

### 生成 Enigma 输入目录

```powershell
powershell -ExecutionPolicy Bypass -File scripts/prepare_enigma_release.ps1
```

脚本会生成：

- `release_package/enigma_input/`：Enigma 输入目录
- `release_package/clovecom.evb`：Enigma Virtual Box 项目文件

### 检查本地依赖

```powershell
powershell -ExecutionPolicy Bypass -File scripts/check_windows_release_dependencies.ps1
```

### 使用 Enigma Virtual Box

1. 打开 `release_package/clovecom.evb`。
2. 确认输入文件为 `release_package/enigma_input/clovecom.exe`。
3. 构建输出文件 `release_package/clovecom_packed.exe`。
4. 将 `clovecom_packed.exe` 复制到干净的 Windows 10/11 x64 电脑或 Windows Sandbox 中测试。

串口 USB 转接器驱动属于硬件厂商驱动，不包含在应用打包范围内。
```

- [ ] **Step 2: Run the packaging test**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File test/release_packaging_test.ps1
```

Expected: PASS.

## Task 6: Build and Verify Release Staging

**Files:**
- Generated: `release_package/enigma_input/`
- Generated: `release_package/clovecom.evb`

- [ ] **Step 1: Run Flutter analyzer**

Run:

```powershell
flutter analyze
```

Expected: `No issues found!`

- [ ] **Step 2: Run widget tests**

Run:

```powershell
flutter test test/widget_test.dart
```

Expected: all tests pass.

- [ ] **Step 3: Run release packaging test**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File test/release_packaging_test.ps1
```

Expected: `Release packaging checks passed.`

- [ ] **Step 4: Prepare Enigma release**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/prepare_enigma_release.ps1
```

Expected: script completes and prints included VC++ runtime DLLs.

- [ ] **Step 5: Check native dependencies**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/check_windows_release_dependencies.ps1
```

Expected: `Windows release dependency checks passed.`

- [ ] **Step 6: Inspect staged files**

Run:

```powershell
Get-ChildItem release_package/enigma_input | Select-Object -ExpandProperty Name
```

Expected output includes:

```text
clovecom.exe
flutter_windows.dll
native_assets.json
data
msvcp140.dll
vcruntime140.dll
vcruntime140_1.dll
```

## Task 7: Commit Implementation

**Files:**
- Add/Modify all implementation files.

- [ ] **Step 1: Review Git status**

Run:

```powershell
git status --short
```

Expected: only intentional files are changed.

- [ ] **Step 2: Commit**

Run:

```powershell
git add scripts/prepare_enigma_release.ps1 scripts/check_windows_release_dependencies.ps1 test/release_packaging_test.ps1 windows/runner/main.cpp windows/runner/utils.cpp windows/runner/utils.h README.md docs/superpowers/plans/2026-04-27-enigma-single-exe-implementation.md
git commit -m "build: prepare enigma single exe release"
```

Expected: commit succeeds.

