import 'package:clovecom/viewmodels/toolbox/bin_link_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late BinLinkViewModel vm;

  setUp(() {
    vm = BinLinkViewModel();
  });
  tearDown(() => vm.dispose());

  test('初始修订号为 0', () {
    expect(vm.layoutRevision, 0);
  });

  test('影响规划的变更自增修订号', () {
    var rev = vm.layoutRevision;
    vm.addManualHex(addressText: '0', hexText: '01 02');
    expect(vm.layoutRevision, greaterThan(rev));
    rev = vm.layoutRevision;

    vm.updateSegmentAddress(0, '4');
    expect(vm.layoutRevision, greaterThan(rev));
    rev = vm.layoutRevision;

    vm.updateSegmentAlignment(0, 8);
    expect(vm.layoutRevision, greaterThan(rev));
    rev = vm.layoutRevision;

    vm.toggleSegmentEnabled(0);
    expect(vm.layoutRevision, greaterThan(rev));
    rev = vm.layoutRevision;

    vm.setFillByteValue(0xEE);
    expect(vm.layoutRevision, greaterThan(rev));
    rev = vm.layoutRevision;

    vm.addManualHex(addressText: '20', hexText: '03');
    vm.autoArrange();
    expect(vm.layoutRevision, greaterThan(rev));
    rev = vm.layoutRevision;

    vm.checkConflicts();
    expect(vm.layoutRevision, greaterThan(rev));
    rev = vm.layoutRevision;

    vm.removeSegment(0);
    expect(vm.layoutRevision, greaterThan(rev));
  });

  test('改名不自增修订号（布局不渲染名字）', () {
    vm.addManualHex(addressText: '0', hexText: '01 02');
    final rev = vm.layoutRevision;
    vm.updateSegmentName(0, '新名字');
    expect(vm.layoutRevision, rev);
    expect(vm.segments.first.name, '新名字');
  });

  test('清错误不自增修订号', () {
    vm.addManualHex(addressText: '0', hexText: '01');
    vm.addManualHex(addressText: '0', hexText: '02');
    final rev = vm.layoutRevision;
    vm.clearError();
    expect(vm.layoutRevision, rev);
  });

  test('无效地址输入失败时不自增修订号', () {
    vm.addManualHex(addressText: '0', hexText: '01');
    final rev = vm.layoutRevision;
    vm.updateSegmentAddress(0, '不是数字');
    expect(vm.layoutRevision, rev);
    expect(vm.lastError, isNotNull);
  });
}