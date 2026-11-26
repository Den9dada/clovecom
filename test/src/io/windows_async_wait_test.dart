import 'dart:async';
import 'dart:io';

import 'package:clovecom/src/io/windows_async_wait.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Windows 高分辨率定时器可重复安排，关闭后停止通知', () async {
    var calls = 0;
    var signal = Completer<void>();
    final timer = WindowsHighResolutionTimer(() {
      calls++;
      if (!signal.isCompleted) signal.complete();
    });
    try {
      for (var i = 0; i < 5; i++) {
        signal = Completer<void>();
        timer.arm(800);
        await signal.future.timeout(const Duration(seconds: 1));
      }
      expect(calls, 5);
      timer.arm(25000);
    } finally {
      timer.close();
    }
    timer.close();
    expect(() => timer.arm(800), throwsStateError);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(calls, 5);
  }, skip: !Platform.isWindows);
}
