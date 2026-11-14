import 'package:clovecom/models/toolbox/bin_link_segment.dart';
import 'package:clovecom/services/toolbox/bin_link_service.dart';
import 'package:clovecom/viewmodels/toolbox/bin_link_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('规划报告嵌套区间全部冲突并保留可显示布局', () {
    final result = BinLinkService.plan([
      BinLinkSegment(name: 'outer', address: 0, bytes: List.filled(20, 1)),
      const BinLinkSegment(name: 'a', address: 2, bytes: [2]),
      const BinLinkSegment(name: 'b', address: 10, bytes: [3]),
    ], fillByte: 0xFF);
    expect(result.overlappingPairs, [(i: 0, j: 1), (i: 0, j: 2)]);
    expect(result.bytes, isEmpty);
    expect(result.outputCrc32, isNull);
    expect(result.canExport, isFalse);
    expect(result.layoutEndAddress, 20);
    expect(result.paddingBytes, 0);
  });
  test('规划包含对齐尾部并忽略禁用片段', () {
    final result = BinLinkService.plan([
      const BinLinkSegment(name: 'a', address: 1, bytes: [1], alignment: 4),
      const BinLinkSegment(
        name: 'disabled',
        address: 1,
        bytes: [2],
        enabled: false,
      ),
      const BinLinkSegment(name: 'b', address: 4, bytes: [3]),
    ], fillByte: 0xEE);
    expect(result.bytes, [0xEE, 1, 0xEE, 0xEE, 3]);
    expect(result.paddingBytes, 3);
    expect(result.originalSize, 2);
    expect(result.enabledCount, 2);
    expect(result.canExport, isTrue);
  });
  test('对齐填充范围同样产生冲突', () {
    final result = BinLinkService.plan([
      const BinLinkSegment(name: 'a', address: 0, bytes: [1], alignment: 8),
      const BinLinkSegment(name: 'b', address: 7, bytes: [3]),
    ], fillByte: 0xFF);
    expect(result.overlappingPairs, [(i: 0, j: 1)]);
    expect(result.canExport, isFalse);
  });
  test('有效到冲突再恢复时预览统计和导出资格同步', () {
    final vm = BinLinkViewModel();
    addTearDown(vm.dispose);
    vm.addManualHex(addressText: '0', hexText: '01 02');
    vm.addManualHex(addressText: '4', hexText: '03');
    expect(vm.previewBytes, [1, 2, 0xFF, 0xFF, 3]);
    vm.updateSegmentAddress(1, '1');
    expect(vm.previewBytes, isEmpty);
    expect(vm.canExport, isFalse);
    expect(vm.outputCrc32, isNull);
    expect(vm.paddingBytes, 0);
    expect(vm.previewEndAddress, 2);
    vm.clearError();
    expect(vm.canExport, isFalse);
    vm.updateSegmentAddress(1, '2');
    expect(vm.previewBytes, [1, 2, 3]);
    expect(vm.totalPaddedSize, 3);
    expect(vm.hasConflicts, isFalse);
    expect(vm.canExport, isTrue);
  });
}
