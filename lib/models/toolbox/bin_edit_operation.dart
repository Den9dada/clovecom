enum BinEditOperationType { insert, replace, delete }

class BinEditOperation {
  const BinEditOperation({
    required this.type,
    required this.address,
    required this.length,
    required this.deltaBytes,
  });

  final BinEditOperationType type;
  final int address;
  final int length;
  final List<int> deltaBytes;

  String get label {
    return switch (type) {
      BinEditOperationType.insert => '插入',
      BinEditOperationType.replace => '修改',
      BinEditOperationType.delete => '删除',
    };
  }
}
