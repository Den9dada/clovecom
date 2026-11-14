; CloveCom NSIS 便携自解压脚本
; 打包为单 EXE，运行时自动解压到临时目录并启动，退出后清理

; ═══════════════════════════════════════════════════════════════
; 基础定义
; ═══════════════════════════════════════════════════════════════
!define PRODUCT_NAME "CloveCom"
!define PRODUCT_EXE "clovecom.exe"
!define PRODUCT_VERSION "1.0.0"

; 压缩配置
SetCompressor /SOLID lzma
SetCompressorDictSize 64
SetDatablockOptimize ON

; 静默解压（SilentInstall 和 SilentUninstall 都为 silent）
SilentInstall silent

; 图标
!define MUI_ICON "..\windows\runner\resources\app_icon.ico"

; ═══════════════════════════════════════════════════════════════
; 界面 — 仅显示解压进度
; ═══════════════════════════════════════════════════════════════
!include "MUI2.nsh"
!include "FileFunc.nsh"

!define MUI_ABORTWARNING
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_LANGUAGE "SimpChinese"

Name "${PRODUCT_NAME} Portable"
OutFile "..\release_package\nsis_output\CloveCom_portable.exe"
RequestExecutionLevel user
ShowInstDetails show
BrandingText "${PRODUCT_NAME}"

; ═══════════════════════════════════════════════════════════════
; 安装区段 — 解压到 %TEMP% 并启动
; ═══════════════════════════════════════════════════════════════
Section
  ; 创建临时工作目录
  GetTempFileName $R0
  Delete $R0
  CreateDirectory $R0

  ; 设置输出路径并解压全部文件
  SetOutPath $R0
  File /r "..\release_package\enigma_input\*"

  ; 启动主程序并等待退出
  ; ExecWait 会阻塞直到目标进程退出
  DetailPrint "启动 ${PRODUCT_NAME} ..."
  ExecWait '"$R0\${PRODUCT_EXE}"' $1

  ; 清理临时文件
  DetailPrint "清理临时文件..."
  SetOutPath "$TEMP"
  RMDir /r $R0

  DetailPrint "${PRODUCT_NAME} 已退出，临时文件已清理。"
SectionEnd
