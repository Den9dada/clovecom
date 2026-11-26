import 'package:clovecom/services/serial/win32_serial_driver.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:win32/win32.dart';

void main() {
  test('FALSE 和错误码 0 不足以证明失败，随后只确认一次真实字节数', () {
    final ambiguous = interpretSerialOverlappedResult(
      Win32Result(value: false, error: ERROR_SUCCESS),
      10,
      10,
    );
    expect(ambiguous.pending, isTrue);
    expect(ambiguous.count, isNull);
    expect(ambiguous.error, isNull);
    final confirmed = interpretSerialOverlappedResult(
      Win32Result(value: true, error: ERROR_SUCCESS),
      10,
      10,
    );
    expect(confirmed.pending, isFalse);
    expect(confirmed.count, 10);
  });

  test('明确的原生错误仍失败，未知资源终态保持屏障', () {
    final failed = interpretSerialOverlappedResult(
      Win32Result(value: false, error: ERROR_OPERATION_ABORTED),
      0,
      10,
    );
    expect(failed.pending, isFalse);
    expect(failed.error, contains('995'));
    expect(
      () => interpretSerialOverlappedResult(
        Win32Result(value: false, error: ERROR_INVALID_HANDLE),
        0,
        10,
      ),
      throwsStateError,
    );
  });
}
