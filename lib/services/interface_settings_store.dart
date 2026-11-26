// 接口通信偏好持久化（决策 Q14）
//
// 上次选中的接口 + 各协议各自的参数，存于应用支持目录 interface_settings.json
// （与协议库 library.json 同目录习惯）。写盘防抖，损坏时回退默认值。

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../src/io/interface_params.dart';

class InterfaceSettingsStore {
  InterfaceSettingsStore({this.file, Future<Directory> Function()? directoryProvider})
      : _directoryProvider = directoryProvider ?? getApplicationSupportDirectory;

  /// 显式指定文件时优先；否则按应用支持目录解析
  File? file;
  final Future<Directory> Function() _directoryProvider;

  static const _debounce = Duration(milliseconds: 500);

  Timer? _debounceTimer;
  InterfacePrefs? _pending;
  bool _loaded = false;
  InterfacePrefs _cached = InterfacePrefs();

  InterfacePrefs get current => _cached;

  Future<InterfacePrefs> load() async {
    if (!_loaded) {
      _loaded = true;
      try {
        final target = await _resolveFile();
        if (await target.exists()) {
          final json = jsonDecode(await target.readAsString());
          if (json is Map<String, dynamic>) {
            _cached = InterfacePrefs.fromJson(json);
          }
        }
      } catch (error) {
        debugPrint('接口设置载入失败，使用默认值：$error');
        _cached = InterfacePrefs();
      }
    }
    return _cached;
  }

  /// 防抖保存；进程退出前应调用 flush()
  void save(InterfacePrefs prefs) {
    _cached = prefs;
    _pending = prefs;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounce, _writePending);
  }

  Future<void> flush() async {
    _debounceTimer?.cancel();
    await _writePending();
  }

  Future<void> _writePending() async {
    final prefs = _pending;
    if (prefs == null) return;
    _pending = null;
    try {
      final target = await _resolveFile();
      await target.create(recursive: true);
      const encoder = JsonEncoder.withIndent('  ');
      await target.writeAsString(encoder.convert(prefs.toJson()));
    } catch (error) {
      debugPrint('接口设置保存失败：$error');
    }
  }

  Future<File> _resolveFile() async {
    final explicit = file;
    if (explicit != null) return explicit;
    final dir = await _directoryProvider();
    final target = File('${dir.path}/interface_settings.json');
    file = target;
    return target;
  }

  void dispose() {
    _debounceTimer?.cancel();
  }
}
