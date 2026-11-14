import 'package:flutter_test/flutter_test.dart';
import 'package:clovecom/services/serial/serial_config_translation.dart';

/// 翻译缝接口级测试：断言三套词汇对照与往返一致、null/未知归一。
void main() {
  group('SerialConfigTranslation', () {
    test('校验位显示值→索引按表顺序', () {
      expect(SerialConfigTranslation.parityIndexOf('None'), 0);
      expect(SerialConfigTranslation.parityIndexOf('Odd'), 1);
      expect(SerialConfigTranslation.parityIndexOf('Even'), 2);
      expect(SerialConfigTranslation.parityIndexOf('Mark'), 3);
      expect(SerialConfigTranslation.parityIndexOf('Space'), 4);
    });

    test('流控显示值→规范码', () {
      expect(SerialConfigTranslation.flowCodeOf('None'), 'none');
      expect(SerialConfigTranslation.flowCodeOf('RTS/CTS'), 'rts_cts');
      expect(SerialConfigTranslation.flowCodeOf('DTR/DSR'), 'dtr_dsr');
      expect(SerialConfigTranslation.flowCodeOf('XON/XOFF'), 'xon_xoff');
    });

    test('校验位规范码→显示值往返一致', () {
      for (final display in ['None', 'Odd', 'Even', 'Mark', 'Space']) {
        final index = SerialConfigTranslation.parityIndexOf(display);
        final code = const ['none', 'odd', 'even', 'mark', 'space'][index];
        expect(SerialConfigTranslation.parityDisplayOf(code), display);
      }
    });

    test('流控规范码→显示值往返一致', () {
      for (final display in ['None', 'RTS/CTS', 'DTR/DSR', 'XON/XOFF']) {
        final code = SerialConfigTranslation.flowCodeOf(display);
        expect(SerialConfigTranslation.flowDisplayOf(code), display);
      }
    });

    test('null 输入返回 null（供 copyWith 保留原值）', () {
      expect(SerialConfigTranslation.parityDisplayOf(null), isNull);
      expect(SerialConfigTranslation.flowDisplayOf(null), isNull);
    });

    test('未知规范码归一：显示值 null、流控码 none', () {
      expect(SerialConfigTranslation.parityDisplayOf('bogus'), isNull);
      expect(SerialConfigTranslation.flowDisplayOf('bogus'), isNull);
      expect(SerialConfigTranslation.flowCodeOf('bogus'), 'none');
    });
  });
}