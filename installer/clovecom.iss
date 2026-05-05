#define MyAppName "CloveCom"
#define MyAppExeName "clovecom.exe"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "CloveCom"

[Setup]
AppId={{3B09728C-91E2-45DB-8C5B-7F9418B94A08}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\CloveCom
DefaultGroupName=CloveCom
OutputDir=..\release_package\inno_output
OutputBaseFilename=CloveComSetup
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=admin
DisableProgramGroupPage=yes

[Languages]
Name: "chinesesimp"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; GroupDescription: "附加任务："; Flags: unchecked

[Files]
Source: "..\release_package\enigma_input\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\CloveCom"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"
Name: "{autodesktop}\CloveCom"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "启动 CloveCom"; Flags: nowait postinstall skipifsilent

[Code]
function FindWindowByWindowName(lpClassName: String; lpWindowName: String): Longint;
  external 'FindWindowW@user32.dll stdcall';

function InitializeSetup(): Boolean;
begin
  Result := True;

  if not IsWin64 then
  begin
    MsgBox('不支持当前系统。请在 Windows 10/11 x64 系统上安装 CloveCom。', mbCriticalError, MB_OK);
    Result := False;
    Exit;
  end;

  if FindWindowByWindowName('', 'clovecom') <> 0 then
  begin
    MsgBox('检测到 CloveCom 正在运行。请先关闭 CloveCom，然后重新运行安装向导。', mbCriticalError, MB_OK);
    Result := False;
    Exit;
  end;
end;

procedure AddMissingFile(var Missing: String; RelativePath: String);
begin
  if not FileOrDirExists(ExpandConstant('{app}\' + RelativePath)) then
  begin
    Missing := Missing + RelativePath + #13#10;
  end;
end;

procedure WriteInstallCheckLog(Missing: String);
var
  LogPath: String;
begin
  LogPath := ExpandConstant('{app}\install_check.log');
  SaveStringToFile(LogPath, 'CloveCom 安装后校验失败，缺少以下文件：' + #13#10 + Missing, False);
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  Missing: String;
begin
  if CurStep = ssPostInstall then
  begin
    Missing := '';
    AddMissingFile(Missing, 'clovecom.exe');
    AddMissingFile(Missing, 'flutter_windows.dll');
    AddMissingFile(Missing, 'data\app.so');
    AddMissingFile(Missing, 'data\icudtl.dat');
    AddMissingFile(Missing, 'data\flutter_assets');
    AddMissingFile(Missing, 'msvcp140.dll');
    AddMissingFile(Missing, 'vcruntime140.dll');
    AddMissingFile(Missing, 'vcruntime140_1.dll');

    if Missing <> '' then
    begin
      WriteInstallCheckLog(Missing);
      MsgBox('CloveCom 安装完成，但安装后校验发现关键文件缺失。' + #13#10 +
        '请重新生成发布目录并重新安装。详情请查看：' + #13#10 +
        ExpandConstant('{app}\install_check.log'), mbCriticalError, MB_OK);
    end;
  end;
end;
