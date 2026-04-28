import 'package:clovecom/viewmodels/toolbox/bin_editor_viewmodel.dart';
import 'package:clovecom/viewmodels/toolbox/bin_link_viewmodel.dart';
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
}
