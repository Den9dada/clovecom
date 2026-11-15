import 'dart:io';

import 'package:clovecom/viewmodels/toolbox/bin_editor_viewmodel.dart';
import 'package:clovecom/viewmodels/toolbox/bin_link_viewmodel.dart';
import 'package:clovecom/viewmodels/toolbox/hex_to_bin_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';

/// C7 通知域细分的契约测试：查看器/规划域 Selector 依赖
/// “内容身份仅在真正变化时改变”这一不变量，此处直接锁定 VM 侧身份语义。
void main() {
  group('BinEditorViewModel 内容域身份', () {
    late BinEditorViewModel vm;
    late Directory tmp;
    late String path;

    setUp(() async {
      vm = BinEditorViewModel();
      tmp = await Directory.systemTemp.createTemp('bin_editor_domain');
      path = '${tmp.path}${Platform.pathSeparator}a.bin';
      await File(path).writeAsBytes([0x00, 0x11]);
    });
    tearDown(() async {
      vm.dispose();
      await tmp.delete(recursive: true);
    });

    test('空态 bytes 为规范化 const 空列表（身份稳定）', () {
      expect(identical(vm.bytes, vm.bytes), isTrue);
      expect(vm.bytes, isEmpty);
    });

    test('相同内容编辑不换 bytes 身份（_commit 早退）', () async {
      await vm.importPaths([path]);
      final before = vm.bytes;
      vm.replaceByte(0, '00'); // 与原值相同，规划上无变化
      expect(identical(vm.bytes, before), isTrue);
    });

    test('真实编辑换 bytes 身份', () async {
      await vm.importPaths([path]);
      final before = vm.bytes;
      vm.replaceByte(0, 'FF');
      expect(identical(vm.bytes, before), isFalse);
    });

    test('清错误不换 bytes 身份', () async {
      await vm.importPaths([path]);
      final before = vm.bytes;
      vm.clearError();
      expect(identical(vm.bytes, before), isTrue);
    });
  });

  group('HexToBinViewModel 内容域身份', () {
    late HexToBinViewModel vm;
    setUp(() => vm = HexToBinViewModel());
    tearDown(() => vm.dispose());

    test('空态 selectedBytes 为规范化 const 空列表（身份稳定）', () {
      expect(identical(vm.selectedBytes, vm.selectedBytes), isTrue);
      expect(vm.selectedBytes, isEmpty);
    });

    test('清错误/重复选中不换 selectedBytes 身份', () {
      vm.loadBinBytes(name: 'a.bin', path: 'a.bin', bytes: [1, 2]);
      final before = vm.selectedBytes;
      vm.clearError();
      expect(identical(vm.selectedBytes, before), isTrue);
      vm.selectEntry(0);
      expect(identical(vm.selectedBytes, before), isTrue);
    });

    test('切换条目换 selectedBytes 身份', () {
      vm.loadBinBytes(name: 'a.bin', path: 'a.bin', bytes: [1, 2]);
      vm.loadBinBytes(name: 'b.bin', path: 'b.bin', bytes: [3, 4]);
      final bBytes = vm.selectedBytes;
      vm.selectEntry(0);
      expect(identical(vm.selectedBytes, bBytes), isFalse);
    });
  });

  group('BinLinkViewModel 规划域身份', () {
    late BinLinkViewModel vm;
    setUp(() => vm = BinLinkViewModel());
    tearDown(() => vm.dispose());

    test('改名/清错误不换 previewBytes 身份且不自增修订号', () {
      vm.addManualHex(addressText: '0', hexText: '01 02');
      final before = vm.previewBytes;
      final rev = vm.layoutRevision;
      vm.updateSegmentName(0, '新名字');
      vm.clearError();
      expect(identical(vm.previewBytes, before), isTrue);
      expect(vm.layoutRevision, rev);
    });

    test('规划变更换 previewBytes 身份', () {
      vm.addManualHex(addressText: '0', hexText: '01 02');
      final before = vm.previewBytes;
      vm.setFillByteValue(0xEE);
      expect(identical(vm.previewBytes, before), isFalse);
    });
  });
}