class CrcFileEntry {
  final String name;
  final String path;
  final List<int> bytes;
  final int size;
  bool selected;

  CrcFileEntry({
    required this.name,
    required this.path,
    required this.bytes,
    required this.size,
    this.selected = true,
  });
}
