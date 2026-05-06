import 'package:clovecom/models/toolbox/crc_params.dart';
import 'package:clovecom/viewmodels/toolbox/bin_editor_viewmodel.dart';
import 'package:clovecom/viewmodels/toolbox/bin_link_viewmodel.dart';
import 'package:clovecom/viewmodels/toolbox/crc_viewmodel.dart';
import 'package:clovecom/viewmodels/toolbox/hex_to_bin_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('hex to bin view model parses hex content for preview', () {
    final viewModel = HexToBinViewModel();

    viewModel.loadHexContent(
      name: 'app.hex',
      path: r'C:\temp\app.hex',
      content: ':020000000102FB\n:00000001FF',
    );

    expect(viewModel.entries.single.name, 'app.hex');
    expect(viewModel.selectedBytes, [0x01, 0x02]);
    expect(viewModel.selectedBaseAddress, 0);
    expect(viewModel.lastError, isNull);
  });

  test(
    'hex to bin view model rejects duplicate imports and removes entries',
    () {
      final viewModel = HexToBinViewModel();

      viewModel.loadHexContent(
        name: 'app.hex',
        path: r'C:\temp\app.hex',
        content: ':020000000102FB\n:00000001FF',
      );
      viewModel.loadHexContent(
        name: 'app.hex',
        path: r'C:\temp\app.hex',
        content: ':020000000102FB\n:00000001FF',
      );

      expect(viewModel.entries, hasLength(1));
      expect(viewModel.lastError, contains('已导入'));

      viewModel.clearError();
      expect(viewModel.lastError, isNull);

      viewModel.removeEntry(0);
      expect(viewModel.entries, isEmpty);
      expect(viewModel.selectedBytes, isEmpty);
    },
  );

  test('bin editor applies insert and undo', () {
    final viewModel = BinEditorViewModel();

    viewModel.loadBinBytes(
      name: 'app.bin',
      path: r'C:\temp\app.bin',
      bytes: [0x01, 0x04],
    );
    viewModel.applyInsert('1', '02 03');

    expect(viewModel.bytes, [0x01, 0x02, 0x03, 0x04]);
    expect(viewModel.hasUnsavedChanges, isTrue);

    viewModel.undoLast();

    expect(viewModel.bytes, [0x01, 0x04]);
    expect(viewModel.hasUnsavedChanges, isFalse);
  });

  test('bin editor replaces a single preview byte and supports undo', () {
    final viewModel = BinEditorViewModel();

    viewModel.loadBinBytes(
      name: 'app.bin',
      path: r'C:\temp\app.bin',
      bytes: [0x01, 0x02, 0x03],
    );
    viewModel.replaceByte(1, 'AA');

    expect(viewModel.bytes, [0x01, 0xAA, 0x03]);
    expect(viewModel.hasUnsavedChanges, isTrue);

    viewModel.undoLast();

    expect(viewModel.bytes, [0x01, 0x02, 0x03]);
  });

  test('bin link view model previews manual hex segments with fill byte', () {
    final viewModel = BinLinkViewModel();

    viewModel.addManualHex(addressText: '0x1000', hexText: '01 02');
    viewModel.addManualHex(addressText: '0x1004', hexText: 'AA');

    expect(viewModel.previewBaseAddress, 0x1000);
    expect(viewModel.previewBytes, [0x01, 0x02, 0xFF, 0xFF, 0xAA]);
    expect(viewModel.lastError, isNull);
  });

  test(
    'bin link view model replaces existing bytes for overlapping manual hex',
    () {
      final viewModel = BinLinkViewModel();

      viewModel.addManualHex(addressText: '0x1000', hexText: '01 02 03 04');
      viewModel.addManualHex(addressText: '0x1001', hexText: 'AA BB');

      expect(viewModel.segments, hasLength(1));
      expect(viewModel.previewBaseAddress, 0x1000);
      expect(viewModel.previewBytes, [0x01, 0xAA, 0xBB, 0x04]);
      expect(viewModel.lastError, isNull);
    },
  );

  group('CRC ViewModel', () {
    test('default preset is CRC-16/MODBUS', () {
      final vm = CrcViewModel();
      expect(vm.selectedPreset, 'CRC-16/MODBUS');
      expect(vm.isCustomMode, false);
    });

    test('setHexText triggers recalculation', () {
      final vm = CrcViewModel();
      vm.setHexText('31 32 33 34');
      expect(vm.result, 0x30BA);
    });

    test('setAsciiText triggers recalculation', () {
      final vm = CrcViewModel();
      vm.setInputMode(DataInputMode.ascii);
      vm.setAsciiText('1234');
      expect(vm.result, 0x30BA);
    });

    test('empty hex text gives null result', () {
      final vm = CrcViewModel();
      vm.setHexText('');
      expect(vm.result, isNull);
    });

    test('invalid hex text gives null result', () {
      final vm = CrcViewModel();
      vm.setHexText('GG HH');
      expect(vm.result, isNull);
    });

    test('switching input modes preserves data', () {
      final vm = CrcViewModel();
      vm.setHexText('31 32');
      vm.setInputMode(DataInputMode.ascii);
      vm.setAsciiText('AB');
      expect(vm.hexText, '31 32');
      expect(vm.asciiText, 'AB');
    });

    test('switch to custom mode shows custom params', () {
      final vm = CrcViewModel();
      vm.selectPreset(null);
      expect(vm.isCustomMode, true);
    });

    test('custom params recalculate correctly', () {
      final vm = CrcViewModel();
      vm.selectPreset(null);
      vm.setCustomWidth(16);
      vm.setCustomPoly('8005');
      vm.setCustomInit('FFFF');
      vm.setCustomXorout('0000');
      vm.setCustomRefin(true);
      vm.setCustomRefout(true);
      vm.setHexText('31 32 33 34');
      expect(vm.result, 0x30BA);
    });

    test('formatHex pads correctly', () {
      final vm = CrcViewModel();
      vm.setHexText('31 32 33 34');
      expect(vm.formatHex(vm.result!), '0x30BA');
    });

    test('about popup toggles', () {
      final vm = CrcViewModel();
      expect(vm.showAboutPopup, false);
      vm.setAboutHovered(true);
      expect(vm.showAboutPopup, true);
      vm.setAboutHovered(false);
      expect(vm.showAboutPopup, false);
      vm.toggleAboutPinned();
      expect(vm.showAboutPopup, true);
      vm.setAboutHovered(false);
      expect(vm.showAboutPopup, true);
      vm.dismissAbout();
      expect(vm.showAboutPopup, false);
    });
  });
}
