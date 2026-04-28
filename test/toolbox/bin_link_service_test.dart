import 'package:clovecom/models/toolbox/bin_link_segment.dart';
import 'package:clovecom/services/toolbox/bin_link_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('links segments by address and fills gaps', () {
    final result = BinLinkService.link([
      BinLinkSegment(name: 'a.bin', address: 0x1000, bytes: [0x01, 0x02]),
      BinLinkSegment(name: 'manual', address: 0x1004, bytes: [0xAA]),
    ], fillByte: 0xFF);

    expect(result.baseAddress, 0x1000);
    expect(result.bytes, [0x01, 0x02, 0xFF, 0xFF, 0xAA]);
  });

  test('rejects overlapping segments', () {
    expect(
      () => BinLinkService.link([
        BinLinkSegment(name: 'a.bin', address: 0, bytes: [0x01, 0x02]),
        BinLinkSegment(name: 'b.bin', address: 1, bytes: [0xAA]),
      ], fillByte: 0xFF),
      throwsA(isA<StateError>()),
    );
  });
}
