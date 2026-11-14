enum ToolboxFileStatus { idle, parsed, failed, exported }

class ToolboxFileEntry {
  const ToolboxFileEntry({
    required this.name,
    required this.path,
    required this.extension,
    required this.size,
    required this.status,
    this.bytes,
    this.baseAddress = 0,
    this.error,
  });

  final String name;
  final String path;
  final String extension;
  final int size;
  final ToolboxFileStatus status;
  final List<int>? bytes;
  final int baseAddress;
  final String? error;

  bool get isHex => extension.toLowerCase() == 'hex';
  bool get isBin => extension.toLowerCase() == 'bin';
  /// HEX 文件是否可导出为 BIN
  bool get canExportBin => isHex && status == ToolboxFileStatus.parsed && bytes != null;
  /// BIN 文件是否可导出为 HEX
  bool get canExportHex => isBin && bytes != null;
  /// 是否可导出（BIN→HEX 或 HEX→BIN）
  bool get canExport => canExportBin || canExportHex;

  ToolboxFileEntry copyWith({
    String? name,
    String? path,
    String? extension,
    int? size,
    ToolboxFileStatus? status,
    List<int>? bytes,
    int? baseAddress,
    String? error,
  }) {
    return ToolboxFileEntry(
      name: name ?? this.name,
      path: path ?? this.path,
      extension: extension ?? this.extension,
      size: size ?? this.size,
      status: status ?? this.status,
      bytes: bytes ?? this.bytes,
      baseAddress: baseAddress ?? this.baseAddress,
      error: error,
    );
  }
}
