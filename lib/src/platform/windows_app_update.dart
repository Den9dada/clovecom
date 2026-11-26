import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../application/app_update.dart';
import '../io/app_update_download.dart';

class WindowsAppUpdateHost implements AppUpdateHost {
  static const channel = MethodChannel('clovecom/app_update');

  @override
  Future<InstalledApp> installedApp() async {
    final info = await channel.invokeMapMethod<String, Object?>('getInfo');
    if (info == null) throw StateError('无法读取当前应用版本。');
    return InstalledApp(
      version: AppVersion.parse(info['version']! as String),
      packaged: info['packaged']! as bool,
      name: info['name']! as String,
      publisher: info['publisher'] as String?,
    );
  }

  @override
  Future<void> openInstaller(String xml) async {
    final temp = await getTemporaryDirectory();
    final directory = await temp.createTemp('clovecom-update-');
    final file = File('${directory.path}/CloveCOM.appinstaller');
    await file.writeAsString(xml, flush: true);
    // 通过文件关联打开，兼容默认禁用 ms-appinstaller 协议的系统。
    await channel.invokeMethod<void>('openInstaller', file.path);
  }

  @override
  Future<AppUpdatePackage> download(
    AppUpdateFeed feed, {
    required bool packaged,
    void Function(AppUpdateProgress)? onProgress,
  }) async {
    return AppUpdateDownloader().download(
      feed,
      await getTemporaryDirectory(),
      packaged: packaged,
      onProgress: onProgress,
    );
  }

  @override
  Future<void> launchInstaller(AppUpdatePackage package) async {
    final path = package.file.path;
    if (!package.packaged) {
      await channel.invokeMethod<void>('runSetup', path);
      return;
    }
    // MSIX 由系统部署到其受保护目录；独立进程等待本应用退出后更新并激活新版。
    String literal(String value) => "'${value.replaceAll("'", "''")}'";
    final script =
        '''
\$ErrorActionPreference = 'Stop'
\$log = ${literal('$path.update.log')}
try {
  \$old = Get-Process -Id $pid -ErrorAction SilentlyContinue
  if (\$old -and -not \$old.WaitForExit(60000)) { throw '等待应用退出超时。' }
  Add-AppxPackage -Path ${literal(path)} -ErrorAction Stop
  \$package = Get-AppxPackage -Name 'CloveCOM.Desktop' -ErrorAction Stop
  if (-not \$package) { throw '更新后的应用包不存在。' }
  Start-Process explorer.exe -ArgumentList ('shell:AppsFolder\\' + \$package.PackageFamilyName + '!CloveCOM')
} catch {
  \$_ | Out-File -LiteralPath \$log -Encoding utf8
  Add-Type -AssemblyName System.Windows.Forms
  [System.Windows.Forms.MessageBox]::Show('更新失败，请重新启动应用后重试。日志：' + \$log, 'CloveCOM 更新')
  exit 1
}
''';
    final bytes = <int>[];
    for (final unit in script.codeUnits) {
      bytes.addAll([unit & 255, unit >> 8]);
    }
    await Process.start(
      '${Platform.environment['SystemRoot']}\\System32\\WindowsPowerShell\\v1.0\\powershell.exe',
      [
        '-NoProfile',
        '-NonInteractive',
        '-WindowStyle',
        'Hidden',
        '-EncodedCommand',
        base64.encode(bytes),
      ],
      mode: ProcessStartMode.detached,
    );
  }
}
