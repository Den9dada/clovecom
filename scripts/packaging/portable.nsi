# -*- coding: utf-8 -*-
Unicode true
!include "LogicLib.nsh"
!include "x64.nsh"

Name "CloveCOM"
OutFile "${OUTPUT_FILE}"
Icon "${APP_ICON}"
RequestExecutionLevel user
SilentInstall silent
AutoCloseWindow true
SetCompressor /SOLID lzma
VIProductVersion "${APP_VERSION}"
VIAddVersionKey /LANG=1033 "ProductName" "CloveCOM"
VIAddVersionKey /LANG=1033 "FileDescription" "CloveCOM self-extracting launcher"
VIAddVersionKey /LANG=1033 "FileVersion" "${APP_VERSION}"
VIAddVersionKey /LANG=1033 "LegalCopyright" "CloveCOM contributors"

Var LaunchLog
Var LogLine

; 持久日志放在临时解压目录之外，退出清理后仍可取回。
Function WriteLaunchLog
  Push $R0
  ClearErrors
  FileOpen $R0 "$LaunchLog" a
  ${IfNot} ${Errors}
    FileSeek $R0 0 END
    FileWriteUTF16LE $R0 "$LogLine$\r$\n"
    FileClose $R0
  ${EndIf}
  Pop $R0
FunctionEnd

; 直接捕获 CreateProcess 的 GetLastError，避免 ExecWait 只留下错误标志。
; 输出：$0 为退出码，$2 为 Win32 错误；创建失败时设置错误标志。
Function LaunchApplication
  Push $R0
  Push $R1
  Push $R2
  Push $R3
  Push $R4
  !if ${NSIS_PTR_SIZE} <= 4
    !define STARTUP_SIZE 68
    !define PROCESS_SIZE 16
  !else
    !define STARTUP_SIZE 104
    !define PROCESS_SIZE 24
  !endif
  System::Alloc ${STARTUP_SIZE}
  Pop $R0
  System::Alloc ${PROCESS_SIZE}
  Pop $R1
  StrCpy $2 8
  StrCpy $R2 0
  ${If} $R0 != 0
  ${AndIf} $R1 != 0
    System::Call 'kernel32::RtlZeroMemory(p R0, p ${STARTUP_SIZE})'
    System::Call '*$R0(i ${STARTUP_SIZE})'
    StrCpy $R4 '"$PLUGINSDIR\app\clovecom.exe"'
    System::Call 'kernel32::CreateProcessW(w "$PLUGINSDIR\app\clovecom.exe", w R4, p 0, p 0, i 0, i 0, p 0, w "$PLUGINSDIR\app", p R0, p R1) i.R2 ?e'
    Pop $2
    ${If} $R2 != 0
      System::Call '*$R1(p.R3, p.R4)'
      System::Call 'kernel32::CloseHandle(p R4)'
      System::Call 'kernel32::WaitForSingleObject(p R3, i -1)'
      System::Call 'kernel32::GetExitCodeProcess(p R3, *i.r0)'
      System::Call 'kernel32::CloseHandle(p R3)'
      StrCpy $2 0
    ${EndIf}
  ${EndIf}
  System::Free $R0
  System::Free $R1
  ${If} $R2 = 0
    SetErrors
  ${Else}
    ClearErrors
  ${EndIf}
  Pop $R4
  Pop $R3
  Pop $R2
  Pop $R1
  Pop $R0
FunctionEnd

Section
  CreateDirectory "$LOCALAPPDATA\CloveCOM\logs"
  StrCpy $LaunchLog "$LOCALAPPDATA\CloveCOM\logs\portable-launcher.log"
  StrCpy $LogLine "----- launcher ${APP_VERSION}: $EXEPATH -----"
  Call WriteLaunchLog
  ${IfNot} ${RunningX64}
    MessageBox MB_OK|MB_ICONSTOP "CloveCOM requires 64-bit Windows."
    SetErrorLevel 1
    Quit
  ${EndIf}
  ; 每次启动独享临时目录，避免多实例覆盖或删除彼此的文件。
  InitPluginsDir
  SetOutPath "$PLUGINSDIR\app"
  ClearErrors
  File /r "${PAYLOAD_DIR}\*.*"
  ${If} ${Errors}
    MessageBox MB_OK|MB_ICONSTOP "Unable to extract CloveCOM. Check free disk space and permissions."
    SetErrorLevel 1
    Quit
  ${EndIf}
  StrCpy $LogLine "extracted: $PLUGINSDIR\app\clovecom.exe"
  Call WriteLaunchLog
  System::Call 'kernel32::SetErrorMode(i 1) i .r3'
  StrCpy $1 0
launch_retry:
  IntOp $1 $1 + 1
  ClearErrors
  Call LaunchApplication
  ${If} ${Errors}
    StrCpy $LogLine "attempt=$1 CreateProcess failed; Win32=$2"
    Call WriteLaunchLog
    ${If} $1 < 10
      Sleep 500
      Goto launch_retry
    ${EndIf}
    System::Call 'kernel32::SetErrorMode(i r3)'
    MessageBox MB_OK|MB_ICONSTOP "CloveCOM 无法启动（已尝试 10 次）。$\r$\nWindows 错误码：$2$\r$\n程序：$PLUGINSDIR\app\clovecom.exe$\r$\n诊断日志：$LaunchLog"
    SetErrorLevel 1
  ${Else}
    StrCpy $LogLine "attempt=$1 child exit=$0"
    Call WriteLaunchLog
    ${If} $0 = 0xC0000043
      ${If} $1 < 10
        Sleep 500
        Goto launch_retry
      ${EndIf}
      MessageBox MB_OK|MB_ICONSTOP "CloveCOM files are still in use after 10 attempts (0xC0000043).$\r$\nPlease wait a moment and try again."
    ${EndIf}
    System::Call 'kernel32::SetErrorMode(i r3)'
    SetErrorLevel $0
  ${EndIf}
  SetOutPath "$TEMP"
SectionEnd
