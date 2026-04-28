class BinLinkSegment {
  const BinLinkSegment({
    required this.name,
    required this.address,
    required this.bytes,
    this.isManual = false,
  });

  final String name;
  final int address;
  final List<int> bytes;
  final bool isManual;

  int get endAddress => address + bytes.length;
}
