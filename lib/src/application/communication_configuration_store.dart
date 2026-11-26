import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// 应用配置的文件系统边界；纯内核默认不接触用户配置。
abstract interface class CommunicationConfigurationStore {
  Future<String?> read();
  Future<void> write(String contents);
}

class FileCommunicationConfigurationStore
    implements CommunicationConfigurationStore {
  FileCommunicationConfigurationStore({
    this.file,
    this.filename = 'communication_connections.json',
    Future<Directory> Function()? directoryProvider,
  }) : _directoryProvider = directoryProvider ?? getApplicationSupportDirectory;
  File? file;
  final String filename;
  final Future<Directory> Function() _directoryProvider;
  Future<File> _resolve() async =>
      file ??= File('${(await _directoryProvider()).path}/$filename');
  @override
  Future<String?> read() async {
    final target = await _resolve();
    return await target.exists() ? target.readAsString() : null;
  }

  @override
  Future<void> write(String contents) async {
    final target = await _resolve();
    await target.parent.create(recursive: true);
    final pending = File('${target.path}.tmp');
    await pending.writeAsString(contents, flush: true);
    // 同目录替换：失败时保留上一份完整文件，绝不先删旧配置。
    await pending.rename(target.path);
  }
}
