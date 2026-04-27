# Inno Setup Installer Design

## Goal

Add an Inno Setup based Windows installer for CloveCom while keeping the
existing Enigma Virtual Box single-EXE workflow.

The installer should install the normal Flutter Windows release bundle onto the
user's computer, create shortcuts, support uninstall, and show clear Chinese
messages when installation checks fail.

## Distribution Modes

CloveCom supports two Windows distribution modes:

- Inno Setup installer: recommended for most users. Installs the normal Flutter
  release directory and runtime DLLs to Program Files.
- Enigma single EXE: kept for portable single-file distribution.

The Inno installer does not install the Enigma-packed EXE by default. It
installs the staged Flutter bundle because that is more stable for desktop
installation.

## Source Files

The installer input should come from `release_package/enigma_input/`. That
directory already contains:

- `clovecom.exe`
- `flutter_windows.dll`
- `native_assets.json`
- `data/`
- VC++ runtime DLLs
- UCRT/API-MS CRT DLLs when available

This avoids duplicating runtime discovery logic. The Inno preparation script
will validate that this input directory exists and is complete before invoking
Inno Setup.

## Inno Project

Add `installer/clovecom.iss`.

Installer behavior:

- Install to `{autopf}\CloveCom`.
- Use x64 install mode.
- Create a Start Menu shortcut.
- Offer a desktop shortcut task.
- Uninstall cleanly through Windows Apps and Features.
- Output installer files under `release_package/inno_output/`.
- Use `CloveComSetup` as the installer base filename.

Installed files:

- Copy every file under `release_package/enigma_input/` into `{app}`.
- Preserve the `data/` directory structure.
- Install runtime DLLs next to `clovecom.exe`.

## Wizard Warnings and Checks

The installer must provide visible Chinese reminders when problems are detected.

Before installation:

- Block non-x64 systems with a Chinese error message.
- Warn if CloveCom appears to be running, based on the main window title. The
  user can close the app and run the installer again.

After installation:

- Verify required files exist under `{app}`:
  - `clovecom.exe`
  - `flutter_windows.dll`
  - `native_assets.json`
  - `data\app.so`
  - `data\icudtl.dat`
  - `data\flutter_assets`
  - `msvcp140.dll`
  - `vcruntime140.dll`
  - `vcruntime140_1.dll`
  - `ucrtbase.dll`
- If any required file is missing, show a Chinese error message and write
  `{app}\install_check.log` listing missing files.

The app's own startup diagnostics remain in place. If the installed app starts
but cannot see Flutter runtime files, it shows a startup message and writes
`%TEMP%\clovecom_startup_error.log`.

## Scripts

Add `scripts/prepare_inno_setup_release.ps1`.

The script will:

- Optionally run `scripts/prepare_enigma_release.ps1` when `-PrepareInput` is
  supplied.
- Validate `release_package/enigma_input/`.
- Locate `ISCC.exe` from PATH or common Inno Setup install directories.
- Compile `installer/clovecom.iss` unless `-SkipCompile` is supplied.

Add `scripts/check_inno_setup_release.ps1`.

The script will:

- Validate required Inno input files.
- Validate that `installer/clovecom.iss` contains the required install sections
  and Chinese error handling code.
- Report whether `ISCC.exe` is available.

## Documentation

Update `README.md` with a Windows installer section:

1. Run `flutter build windows --release`.
2. Run `scripts/prepare_enigma_release.ps1`.
3. Run `scripts/check_windows_release_dependencies.ps1`.
4. Run `scripts/check_inno_setup_release.ps1`.
5. Run `scripts/prepare_inno_setup_release.ps1`.
6. Test `release_package/inno_output/CloveComSetup.exe` on a clean Windows
   10/11 x64 machine or Windows Sandbox.

## Verification

Do not run Flutter build automatically during verification. The user runs
`flutter build windows --release` manually and reports the result.

Run:

- `flutter analyze`
- `flutter test test/widget_test.dart`
- `powershell -ExecutionPolicy Bypass -File test/release_packaging_test.ps1`
- `powershell -ExecutionPolicy Bypass -File scripts/prepare_enigma_release.ps1`
- `powershell -ExecutionPolicy Bypass -File scripts/check_windows_release_dependencies.ps1`
- `powershell -ExecutionPolicy Bypass -File scripts/check_inno_setup_release.ps1`
- `powershell -ExecutionPolicy Bypass -File scripts/prepare_inno_setup_release.ps1`

