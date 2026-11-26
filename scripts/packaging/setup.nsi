Unicode true
!include "MUI2.nsh"
!include "LogicLib.nsh"
!include "x64.nsh"
!include "nsDialogs.nsh"
!include "FileFunc.nsh"

Var KeepUserData
Var KeepDataCheckbox
Var PurgeFailed
Var CreateDesktopShortcut
Var DesktopShortcutCheckbox
Var UpdatePid
Var RestartAfterUpdate
Var InPlaceUpdate
Var PortableUpdate

!macro RemoveUserDirectory Directory
  ${If} ${FileExists} "${Directory}\*.*"
    ClearErrors
    RMDir /r "${Directory}"
    ${If} ${Errors}
      StrCpy $PurgeFailed 1
    ${EndIf}
  ${EndIf}
!macroend

Name "${PRODUCT_NAME}"
OutFile "${OUTPUT_FILE}"
Icon "${APP_ICON}"
UninstallIcon "${APP_ICON}"
RequestExecutionLevel user
InstallDir "$LOCALAPPDATA\Programs\CloveCOM"
InstallDirRegKey HKCU "${REG_KEY}" "InstallLocation"
SetCompressor /SOLID lzma
VIProductVersion "${APP_VERSION}"
VIAddVersionKey "ProductName" "${PRODUCT_NAME}"
VIAddVersionKey "FileVersion" "${APP_VERSION}"
VIAddVersionKey "FileDescription" "CloveCOM 安装程序"
VIAddVersionKey "LegalCopyright" "CloveCOM contributors"

!define MUI_ABORTWARNING
!define MUI_WELCOMEPAGE_TEXT "此向导将安装 CloveCOM。安装前请保存工作并退出正在运行的应用。可在下一页选择安装目录。"
!insertmacro MUI_PAGE_WELCOME
!define MUI_PAGE_CUSTOMFUNCTION_LEAVE ValidateDirectory
!insertmacro MUI_PAGE_DIRECTORY
Page custom ShortcutPage ShortcutPageLeave
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
UninstPage custom un.DataPage un.DataPageLeave
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "SimpChinese"

Function .onInit
  SetShellVarContext current
  StrCpy $UpdatePid 0
  StrCpy $RestartAfterUpdate 0
  StrCpy $InPlaceUpdate 0
  StrCpy $PortableUpdate 0
  ${GetParameters} $0
  ClearErrors
  ${GetOptions} $0 "/RESTART" $1
  ${IfNot} ${Errors}
    StrCpy $RestartAfterUpdate 1
  ${EndIf}
  ClearErrors
  ${GetOptions} $0 "/INPLACE" $1
  ${IfNot} ${Errors}
    StrCpy $InPlaceUpdate 1
    ReadRegStr $1 HKCU "${REG_KEY}" "InstallLocation"
    ${If} $1 == ""
      StrCpy $PortableUpdate 1
    ${EndIf}
  ${EndIf}
  ClearErrors
  ${GetOptions} $0 "/UPDATEPID=" $1
  ${IfNot} ${Errors}
    StrCpy $UpdatePid $1
  ${EndIf}
  ClearErrors
  ; 首次默认创建，更新时沿用上次选择。
  ReadRegDWORD $CreateDesktopShortcut HKCU "${REG_KEY}" "DesktopShortcut"
  ${If} ${Errors}
    StrCpy $CreateDesktopShortcut ${BST_CHECKED}
  ${EndIf}
  ${GetParameters} $0
  ClearErrors
  ${GetOptions} $0 "/DESKTOP=" $1
  ${IfNot} ${Errors}
    ${If} $1 == "0"
      StrCpy $CreateDesktopShortcut ${BST_UNCHECKED}
    ${ElseIf} $1 == "1"
      StrCpy $CreateDesktopShortcut ${BST_CHECKED}
    ${Else}
      MessageBox MB_ICONSTOP "DESKTOP 参数必须为 0 或 1。" /SD IDOK
      SetErrorLevel 1
      Quit
    ${EndIf}
  ${EndIf}
  ${IfNot} ${RunningX64}
    MessageBox MB_ICONSTOP "此安装包仅支持 Windows x64。" /SD IDOK
    SetErrorLevel 1
    Quit
  ${EndIf}
FunctionEnd

Function .onInstSuccess
  ${If} $RestartAfterUpdate == 1
    SetOutPath "$INSTDIR"
    ClearErrors
    Exec '"$INSTDIR\clovecom.exe"'
    ${If} ${Errors}
      ; 安装成功但启动失败必须可见，不能让用户以为应用已重新启动。
      MessageBox MB_ICONSTOP "更新已安装，但无法自动启动。请从原目录手动打开 CloveCOM。"
      SetErrorLevel 2
    ${EndIf}
  ${EndIf}
FunctionEnd

Function .onInstFailed
  ${If} $RestartAfterUpdate == 1
    MessageBox MB_ICONSTOP "CloveCOM 更新失败，未自动重启。请从原目录重新打开应用，或重新下载安装包。"
  ${EndIf}
FunctionEnd

Function ShortcutPage
  !insertmacro MUI_HEADER_TEXT "快捷方式" "选择是否在桌面创建应用快捷方式。"
  nsDialogs::Create 1018
  Pop $0
  ${If} $0 == error
    Abort
  ${EndIf}
  ${NSD_CreateCheckbox} 0 0 100% 20u "创建桌面快捷方式"
  Pop $DesktopShortcutCheckbox
  ${NSD_SetState} $DesktopShortcutCheckbox $CreateDesktopShortcut
  nsDialogs::Show
FunctionEnd

Function ShortcutPageLeave
  ${NSD_GetState} $DesktopShortcutCheckbox $CreateDesktopShortcut
FunctionEnd

Function un.onInit
  SetShellVarContext current
  StrCpy $KeepUserData ${BST_CHECKED}
  ; 静默卸载默认保留，只有显式 /PURGEDATA 才清除数据。
  ${GetParameters} $0
  ClearErrors
  ${GetOptions} $0 "/PURGEDATA" $1
  ${IfNot} ${Errors}
    StrCpy $KeepUserData ${BST_UNCHECKED}
  ${EndIf}
FunctionEnd

Function un.DataPage
  !insertmacro MUI_HEADER_TEXT "用户数据" "选择卸载后是否保留用户数据。"
  nsDialogs::Create 1018
  Pop $0
  ${If} $0 == error
    Abort
  ${EndIf}
  ${NSD_CreateCheckbox} 0 0 100% 20u "保留用户数据（推荐）"
  Pop $KeepDataCheckbox
  ${NSD_SetState} $KeepDataCheckbox $KeepUserData
  ${NSD_CreateLabel} 0 30u 100% 90u "取消勾选将永久删除当前用户的 CloveCOM 配置、协议库、缓存和日志，并清空安装目录内的额外文件。$\r$\n$\r$\n这些数据可能与 ZIP 免安装版共享。导出到安装目录以外的文件不受影响。$\r$\n卸载前请先退出应用。"
  Pop $0
  nsDialogs::Show
FunctionEnd

Function un.DataPageLeave
  ${NSD_GetState} $KeepDataCheckbox $KeepUserData
FunctionEnd

Function ValidateDirectory
  ReadRegStr $0 HKCU "${REG_KEY}" "InstallLocation"
  ${If} $0 != ""
  ${AndIf} $0 != $INSTDIR
    MessageBox MB_ICONSTOP "已安装到 $0。请先卸载旧版，再更换安装目录。" /SD IDOK
    SetErrorLevel 1
    Abort
  ${EndIf}
  ; 新安装只接受空目录，避免覆盖用户已有文件。
  ${If} $0 == ""
    ${If} $InPlaceUpdate == 1
      ; ZIP 版仅允许在完整应用目录更新，不改为固定目录安装版。
      ${IfNot} ${FileExists} "$INSTDIR\clovecom.exe"
      ${OrIfNot} ${FileExists} "$INSTDIR\flutter_windows.dll"
      ${OrIfNot} ${FileExists} "$INSTDIR\data\icudtl.dat"
        MessageBox MB_ICONSTOP "原目录缺少完整的 CloveCOM 文件，已停止更新。" /SD IDOK
        SetErrorLevel 1
        Abort
      ${EndIf}
      Return
    ${EndIf}
    FindFirst $1 $2 "$INSTDIR\*"
    ${DoWhile} $2 != ""
      ${If} $2 != "."
      ${AndIf} $2 != ".."
        FindClose $1
        MessageBox MB_ICONSTOP "请选择空目录或新建 CloveCOM 专用目录。" /SD IDOK
        SetErrorLevel 1
        Abort
      ${EndIf}
      FindNext $1 $2
    ${Loop}
    FindClose $1
  ${EndIf}
FunctionEnd

Section "安装"
  Call ValidateDirectory
  ${If} $UpdatePid != 0
    ; 更新交接期间保留进程句柄，进程退出后才允许覆盖文件。
    System::Call 'kernel32::OpenProcess(i 0x100000, i 0, i $UpdatePid) p.r0'
    ${If} $0 != 0
      System::Call 'kernel32::WaitForSingleObject(p r0, i 60000) i.r1'
      System::Call 'kernel32::CloseHandle(p r0)'
      ${If} $1 != 0
        MessageBox MB_ICONSTOP "旧版应用尚未退出。请保存工作并退出应用后重新运行安装程序。" /SD IDOK
        SetErrorLevel 1
        Abort
      ${EndIf}
    ${EndIf}
  ${EndIf}
  SetOutPath "$INSTDIR"
  SetOverwrite on
  ClearErrors
  File /r "${PAYLOAD_DIR}\*"
  ${If} ${Errors}
    MessageBox MB_ICONSTOP "无法写入安装目录。请确认目录可写，并退出旧版后重试。" /SD IDOK
    SetErrorLevel 1
    Abort
  ${EndIf}
  ${If} $PortableUpdate == 1
    ; ZIP 原位更新保留便携形态，不写注册表、卸载器和快捷方式。
    Goto installComplete
  ${EndIf}
  WriteUninstaller "$INSTDIR\Uninstall.exe"
  WriteRegStr HKCU "${REG_KEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayName" "${PRODUCT_NAME}"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayVersion" "${APP_VERSION}"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "Publisher" "CloveCOM"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "UninstallString" '$\"$INSTDIR\Uninstall.exe$\"'
  WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayIcon" "$INSTDIR\clovecom.exe"
  WriteRegDWORD HKCU "${UNINSTALL_KEY}" "NoModify" 1
  WriteRegDWORD HKCU "${UNINSTALL_KEY}" "NoRepair" 1
  CreateDirectory "$SMPROGRAMS\${PRODUCT_NAME}"
  CreateShortcut "$SMPROGRAMS\${PRODUCT_NAME}\${PRODUCT_NAME}.lnk" "$INSTDIR\clovecom.exe"
  CreateShortcut "$SMPROGRAMS\${PRODUCT_NAME}\卸载.lnk" "$INSTDIR\Uninstall.exe"
  ${If} $CreateDesktopShortcut == ${BST_CHECKED}
    CreateShortcut "$DESKTOP\${PRODUCT_NAME}.lnk" "$INSTDIR\clovecom.exe" "" "$INSTDIR\clovecom.exe" 0
  ${Else}
    Delete "$DESKTOP\${PRODUCT_NAME}.lnk"
  ${EndIf}
  WriteRegDWORD HKCU "${REG_KEY}" "DesktopShortcut" $CreateDesktopShortcut
  installComplete:
SectionEnd

Section "Uninstall"
  SetShellVarContext current
  ; 清理前验证本卸载器仍指向安装时登记的专用目录。
  ReadRegStr $0 HKCU "${REG_KEY}" "InstallLocation"
  ${If} $0 == ""
  ${OrIf} $0 != $INSTDIR
    MessageBox MB_ICONSTOP "安装目录与登记信息不一致，已停止卸载。" /SD IDOK
    SetErrorLevel 1
    Abort
  ${EndIf}
  ; 只删除打包清单中列出的文件，不递归清空用户选择的目录。
  ClearErrors
  !include "${REMOVE_INCLUDE}"
  ${If} ${Errors}
    MessageBox MB_ICONSTOP "部分程序文件无法删除。请先退出 CloveCOM，再重新卸载。" /SD IDOK
    SetErrorLevel 1
    Abort
  ${EndIf}
  ${If} $KeepUserData == ${BST_UNCHECKED}
    StrCpy $PurgeFailed 0
    !insertmacro RemoveUserDirectory "$APPDATA\${DATA_SUBDIR}"
    !insertmacro RemoveUserDirectory "$LOCALAPPDATA\${DATA_SUBDIR}"
    !insertmacro RemoveUserDirectory "$LOCALAPPDATA\${LAUNCHER_DATA_SUBDIR}"
    ; 清除应用留下的更新清单，不删除其他应用的临时文件。
    FindFirst $1 $2 "$TEMP\clovecom-update-*"
    ${DoWhile} $2 != ""
      !insertmacro RemoveUserDirectory "$TEMP\$2"
      FindNext $1 $2
    ${Loop}
    FindClose $1
    ${If} $PurgeFailed == 1
      MessageBox MB_ICONSTOP "部分用户数据无法删除。请关闭应用后重新卸载。" /SD IDOK
      SetErrorLevel 1
      Abort
    ${EndIf}
    ; 用户已明确选择清空安装目录；该目录在新安装时必须为空。
    ClearErrors
    RMDir /r "$INSTDIR"
    ${If} ${Errors}
      MessageBox MB_ICONSTOP "安装目录未能清空，请关闭占用文件的程序后重新卸载。" /SD IDOK
      SetErrorLevel 1
      Abort
    ${EndIf}
  ${EndIf}
  Delete "$INSTDIR\Uninstall.exe"
  RMDir "$INSTDIR"
  Delete "$SMPROGRAMS\${PRODUCT_NAME}\${PRODUCT_NAME}.lnk"
  Delete "$SMPROGRAMS\${PRODUCT_NAME}\卸载.lnk"
  RMDir "$SMPROGRAMS\${PRODUCT_NAME}"
  Delete "$DESKTOP\${PRODUCT_NAME}.lnk"
  DeleteRegKey HKCU "${REG_KEY}"
  DeleteRegKey HKCU "${UNINSTALL_KEY}"
SectionEnd
