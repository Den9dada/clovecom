import 'dart:convert';
import 'dart:io';

import '../application/app_update.dart';

/// 与通信配置分开保存，重启应用后仍沿用用户的自动检查间隔选择。
class AppUpdatePreferences {
  AppUpdatePreferences(this.file);
  final File file;

  Future<AppUpdateInterval> load() async {
    try {
      final json = jsonDecode(await file.readAsString());
      if (json is Map<String, dynamic>) {
        for (final value in AppUpdateInterval.values) {
          if (value.name == json['checkInterval']) return value;
        }
      }
    } on FileSystemException {
      // 首次启动或配置不可读时使用默认间隔，不阻止启动。
    } on FormatException {
      // 配置损坏时恢复默认值，后续选择会重新保存。
    }
    return AppUpdateInterval.sixHours;
  }

  Future<void> save(AppUpdateInterval value) async {
    await file.parent.create(recursive: true);
    final pending = File('${file.path}.tmp');
    await pending.writeAsString(
      jsonEncode({'checkInterval': value.name}),
      flush: true,
    );
    await pending.rename(file.path);
  }
}
