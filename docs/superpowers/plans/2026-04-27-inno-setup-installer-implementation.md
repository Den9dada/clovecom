# Inno Setup Installer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an Inno Setup installer workflow that installs CloveCom with a wizard, shortcuts, uninstall support, runtime DLLs, and visible Chinese install-time warnings.

**Architecture:** Reuse `release_package/enigma_input/` as the canonical staged Flutter bundle with VC++ and UCRT DLLs. Add an Inno `.iss` project and PowerShell scripts that validate input, compile with `ISCC.exe`, and test script/project contents without invoking Flutter build.

**Tech Stack:** Inno Setup 7, PowerShell 5+, Flutter Windows release bundle.

---

## Files

- Create: `installer/clovecom.iss`
- Create: `scripts/check_inno_setup_release.ps1`
- Create: `scripts/prepare_inno_setup_release.ps1`
- Create: `test/inno_setup_release_test.ps1`
- Modify: `README.md`

## Task 1: Add Inno Static Test

- [ ] Create `test/inno_setup_release_test.ps1` to assert the Inno project and scripts contain required install behavior.
- [ ] Run it and confirm it fails because `installer/clovecom.iss` does not exist.

## Task 2: Add Inno Project

- [ ] Create `installer/clovecom.iss`.
- [ ] Include x64 install mode, Program Files destination, Start Menu shortcut, optional desktop shortcut, uninstall icon, recursive file copy from `release_package\enigma_input`, Chinese x64/running-app warnings, and post-install file checks.
- [ ] Run `test/inno_setup_release_test.ps1` and confirm it now fails on missing scripts.

## Task 3: Add Inno Check Script

- [ ] Create `scripts/check_inno_setup_release.ps1`.
- [ ] Validate required staged files, `.iss` sections, Chinese warning strings, and optional `ISCC.exe` availability.
- [ ] Run `test/inno_setup_release_test.ps1` and confirm it now fails on the missing prepare script.

## Task 4: Add Inno Prepare Script

- [ ] Create `scripts/prepare_inno_setup_release.ps1`.
- [ ] Support `-PrepareInput` to run Enigma staging first and `-SkipCompile` to only validate input.
- [ ] Locate `ISCC.exe` from PATH or `C:\Program Files\Inno Setup *\ISCC.exe`.
- [ ] Compile `installer/clovecom.iss` by default.
- [ ] Run `test/inno_setup_release_test.ps1` and confirm it passes.

## Task 5: Document Workflow

- [ ] Update `README.md` with Windows installer instructions after the Enigma section.
- [ ] Include commands for staging, checking, compiling, and clean-machine testing.

## Task 6: Verify

- [ ] Run `flutter analyze`.
- [ ] Run `flutter test test/widget_test.dart`.
- [ ] Run `powershell -ExecutionPolicy Bypass -File test/release_packaging_test.ps1`.
- [ ] Run `powershell -ExecutionPolicy Bypass -File test/inno_setup_release_test.ps1`.
- [ ] Run `powershell -ExecutionPolicy Bypass -File scripts/prepare_enigma_release.ps1`.
- [ ] Run `powershell -ExecutionPolicy Bypass -File scripts/check_windows_release_dependencies.ps1`.
- [ ] Run `powershell -ExecutionPolicy Bypass -File scripts/check_inno_setup_release.ps1`.
- [ ] Run `powershell -ExecutionPolicy Bypass -File scripts/prepare_inno_setup_release.ps1`.

Do not run `flutter build windows --release`; the user runs that command manually.

