import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:clovecom/models/serial_port_model.dart';
import 'package:clovecom/services/serial/serial_byte_transport.dart';

// 两个串口互连，仅一端发送，另一端无写入可触发接收轮询。
Future<void> main() async {
  final ports = Platform.environment['CLOVECOM_SERIAL_LOOPBACK_PORTS']
      ?.split(',')
      .map((port) => port.trim())
      .toList();
  if (ports == null || ports.length != 2 || ports.toSet().length != 2) {
    throw ArgumentError('请通过 CLOVECOM_SERIAL_LOOPBACK_PORTS 指定一对互连串口');
  }
  final length = int.parse(
    Platform.environment['CLOVECOM_SERIAL_LOOPBACK_PAYLOAD_BYTES'] ?? '10',
  );
  RangeError.checkValueInInterval(
    length,
    1,
    Win32SerialTransport.readBatchBytes,
  );
  final sender = await Win32SerialTransport.open(
    SerialPortConfig(portName: ports.first, baudRate: 115200),
  );
  try {
    final receiver = await Win32SerialTransport.open(
      SerialPortConfig(portName: ports.last, baudRate: 115200),
    );
    try {
      await _measure(sender, receiver, length);
    } finally {
      await receiver.close();
    }
  } finally {
    await sender.close();
  }
}

Future<void> _measure(
  Win32SerialTransport sender,
  Win32SerialTransport receiver,
  int length,
) async {
  final samples = <int>[];
  final clock = Stopwatch();
  int offset = 0, expected = 0, packets = 0, largestChunk = 0;
  Completer<int>? arrived;
  final subscription = receiver.chunks.listen(
    (bytes) {
      packets++;
      if (bytes.length > largestChunk) largestChunk = bytes.length;
      final request = arrived;
      if (request == null ||
          request.isCompleted ||
          offset + bytes.length > length) {
        throw StateError('收到超出本轮发送范围的字节');
      }
      for (final byte in bytes) {
        if (byte != (expected + offset++) % 256) {
          request.completeError(StateError('单向接收字节不一致'));
          return;
        }
      }
      if (offset == length) request.complete(clock.elapsedMicroseconds);
    },
    onError: (Object error, StackTrace stack) {
      final request = arrived;
      if (request == null || request.isCompleted) {
        Error.throwWithStackTrace(error, stack);
      }
      request.completeError(error, stack);
    },
  );
  try {
    for (var i = -24; i < 300; i++) {
      await Future<void>.delayed(Duration(milliseconds: 5 + (i * 7) % 13));
      expected = i % 256;
      offset = 0;
      arrived = Completer<int>();
      final payload = Uint8List.fromList(
        List.generate(length, (index) => (expected + index) % 256),
      );
      clock
        ..reset()
        ..start();
      final sending = sender.send(payload, 1000);
      final elapsed = await arrived.future.timeout(const Duration(seconds: 2));
      final written = await sending;
      await written.settled;
      if (!written.succeeded || written.acceptedBytes != length) {
        throw StateError('单向写入未被确认 ${written.reason}');
      }
      if (i >= 0) samples.add(elapsed);
    }
  } finally {
    await subscription.cancel();
  }
  samples.sort();
  int p(double fraction) => samples[(samples.length * fraction).ceil() - 1];
  stdout.writeln(
    '${samples.length} 轮 × $length B 单向发送至完整接收耗时 P50/P95/P99 '
    '${p(.50)}/${p(.95)}/${p(.99)} µs，共交付 $packets 个接收块，'
    '最大 $largestChunk B，逐字节匹配',
  );
}
