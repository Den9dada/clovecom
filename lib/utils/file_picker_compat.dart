import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// 集中适配 file_picker 13 的静态接口及返回值。
class FilePickerCompat {
  static Future<PickedFiles?> pickFiles({
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    bool allowMultiple = false,
  }) async {
    final List<PlatformFile> files;
    if (allowMultiple) {
      files = await FilePicker.pickFiles(
        type: type,
        allowedExtensions: allowedExtensions,
      );
    } else {
      final file = await FilePicker.pickFile(
        type: type,
        allowedExtensions: allowedExtensions,
      );
      files = file == null ? [] : [file];
    }
    return files.isEmpty ? null : PickedFiles(files);
  }

  static Future<String?> getDirectoryPath({String? dialogTitle}) =>
      FilePicker.getDirectoryPath(dialogTitle: dialogTitle);

  /// 旧调用点负责最终写入；新接口先创建空文件并返回本地路径。
  static Future<String?> saveFile({
    required String fileName,
    String? dialogTitle,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
  }) async {
    final uri = await FilePicker.saveFile(
      fileName: fileName,
      bytes: Uint8List(0),
      dialogTitle: dialogTitle,
      type: type,
      allowedExtensions: allowedExtensions,
    );
    if (uri == null) return null;
    if (uri.scheme != 'file') {
      throw UnsupportedError('当前保存位置不支持直接写入文件路径: $uri');
    }
    return uri.toFilePath();
  }
}

class PickedFiles {
  const PickedFiles(this.files);

  final List<PlatformFile> files;
}
