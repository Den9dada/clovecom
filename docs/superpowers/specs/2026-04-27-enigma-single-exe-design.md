# Enigma Single-EXE Release Compatibility Design

## Goal

Package CloveCom as a single Windows x64 executable with Enigma Virtual Box so
users can open it directly on target machines without installing Flutter, Dart,
or the Microsoft Visual C++ Redistributable.

The packaging flow must also address two observed failure modes:

- Some target computers cannot open the packed EXE at all.
- Some target computers show `Cannot load library MSVCP140.dll`.

## Root Cause

The Flutter Windows release bundle is not a single-file application. The runner
EXE loads files next to it, including `flutter_windows.dll`, `data/`, and
generated native asset metadata.

The current `clovecom.exe` also imports Microsoft Visual C++ runtime DLLs:

- `MSVCP140.dll`
- `VCRUNTIME140.dll`
- `VCRUNTIME140_1.dll`
- related `api-ms-win-crt-*` Universal CRT DLLs supplied by supported Windows
  systems

Development machines often already have these runtime DLLs installed, so the
app works locally. Clean user machines may not, which produces the
`MSVCP140.dll` error or a silent startup failure.

## Chosen Approach

Use app-local runtime deployment before Enigma packing:

1. Build the standard Flutter Windows release output.
2. Copy the complete release output into a stable Enigma input directory.
3. Copy required x64 Visual C++ runtime DLLs into the same directory as
   `clovecom.exe`.
4. Generate an Enigma `.evb` project that virtualizes the Flutter DLL, VC++
   runtime DLLs, `native_assets.json`, and `data/`.
5. Use Enigma Virtual Box to produce a single output EXE.

This preserves Flutter's expected release layout while allowing Enigma to embed
the non-system files needed at runtime.

## Non-Goals

- Do not require users to install `vc_redist.x64.exe`.
- Do not change Flutter engine or plugin internals.
- Do not promise bundled hardware drivers. Serial USB adapter drivers remain
  device-vendor dependencies.
- Do not target 32-bit Windows. The project builds and packages Windows x64.

## Runner Compatibility

The Windows runner should set the process working directory to the directory
that contains the executable before creating the Flutter project.

This protects startup when users launch the app from a shortcut, a different
current directory, or Enigma's packed executable context. The Flutter project
can still be created with `data` as its relative asset path.

## Packaging Script

Add a PowerShell script at `scripts/prepare_enigma_release.ps1`.

The script will:

- Run `flutter build windows --release`.
- Recreate `release_package/enigma_input/`.
- Copy everything from `build/windows/x64/runner/Release/` into
  `release_package/enigma_input/`.
- Copy required x64 VC++ runtime DLLs from the current machine into
  `release_package/enigma_input/`.
- Generate `release_package/clovecom.evb`.
- Print a short checklist of included files and any missing optional runtime
  files.

Required runtime DLLs:

- `msvcp140.dll`
- `vcruntime140.dll`
- `vcruntime140_1.dll`

Optional runtime DLLs, copied when available:

- `msvcp140_1.dll`
- `msvcp140_2.dll`
- `msvcp140_atomic_wait.dll`
- `msvcp140_codecvt_ids.dll`
- `concrt140.dll`

The script should prefer x64 DLLs from Visual Studio redist directories when
available, and fall back to `C:\Windows\System32` for the current machine's x64
runtime files.

## Dependency Check

Add a PowerShell script at `scripts/check_windows_release_dependencies.ps1`.

The script will:

- Locate `dumpbin.exe` when available.
- Run `dumpbin /DEPENDENTS` on `clovecom.exe`.
- Classify expected Windows system DLLs separately from app-local DLLs.
- Fail if a non-system dependency required by the runner is missing from the
  Enigma input directory.

The dependency check should be conservative. It is acceptable to warn when
`dumpbin.exe` is not installed, but CI or local release validation should use it
when available.

## Enigma Project

The generated `.evb` should use paths under `release_package/enigma_input/` as
input files and write a packed executable under `release_package/`.

Virtualized items:

- `flutter_windows.dll`
- `native_assets.json`
- `data/`
- VC++ runtime DLLs copied by the script

The app executable itself remains the Enigma input executable.

## Documentation

Document the release workflow:

1. Run `scripts/prepare_enigma_release.ps1`.
2. Open `release_package/clovecom.evb` in Enigma Virtual Box.
3. Build the packed output.
4. Test the packed EXE on a clean Windows x64 machine or Windows Sandbox.

The documentation should call out that Windows 10/11 x64 is the supported user
target. It should also mention that very old Windows systems may fail because
Flutter and the Universal CRT rely on OS-level components.

## Verification

Before considering the work complete, run:

- `flutter analyze`
- `flutter test test/widget_test.dart`
- `flutter build windows --release`
- `scripts/prepare_enigma_release.ps1`
- `scripts/check_windows_release_dependencies.ps1`

Manual release verification:

- Open the generated `.evb` in Enigma Virtual Box.
- Build the single EXE.
- Run it on a clean target machine or Windows Sandbox that does not have Visual
  Studio or Flutter installed.

