import 'dart:io';

import 'package:clovecom/models/serial_port_model.dart';
import 'package:clovecom/services/serial/serial_port_catalog.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

PortDetailInfo _port(String name, String description) => PortDetailInfo(
  portName: name,
  friendlyName: description,
  hardwareID: '',
  manufactureName: '',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Windows 串口扫描', () {
    test('原生枚举结果去重、自然排序并保留友好名称', () async {
      final catalog = SerialPortCatalog(
        scanNative: () async => [
          _port('COM10', '虚拟端口'),
          _port('COM2', 'USB 串口'),
          _port('COM2', 'USB 串口'),
        ],
        scanBackup: () async => throw StateError('不应调用备用枚举'),
      );

      final scan = await catalog.scan();
      expect(scan.devices.map((p) => p.portName), ['COM2', 'COM10']);
      expect(scan.devices.first.friendlyName, 'USB 串口');
      expect(scan.warning, isNull);
    });

    test('原生成功返回空列表时不触发备用枚举', () async {
      final catalog = SerialPortCatalog(
        scanNative: () async => [],
        scanBackup: () async => throw StateError('不应调用备用枚举'),
      );

      final scan = await catalog.scan();
      expect(scan.devices, isEmpty);
      expect(scan.warning, isNull);
    });

    test('原生失败时返回备用结果和警告', () async {
      final catalog = SerialPortCatalog(
        scanNative: () async => throw StateError('主枚举异常'),
        scanBackup: () async => [_port('COM4', '备用端口')],
      );

      final scan = await catalog.scan();
      expect(scan.devices.single.portName, 'COM4');
      expect(scan.warning, contains('主枚举异常'));
    });

    test('两路枚举失败时报告两处错误', () async {
      final catalog = SerialPortCatalog(
        scanNative: () async => throw StateError('主枚举异常'),
        scanBackup: () async => throw StateError('备用枚举异常'),
      );

      await expectLater(
        catalog.scan(),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            allOf(contains('主枚举异常'), contains('备用枚举异常')),
          ),
        ),
      );
    });

    test('继续接收 Windows runner 的热插拔通知', () async {
      final changes = const SerialPortCatalog().watchChanges().first;
      const codec = StandardMethodCodec();
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            'clovecom/serial_ports',
            codec.encodeMethodCall(const MethodCall('portsChanged')),
            (_) {},
          );
      await changes;
    });

    test('真实 Win32 枚举在后台 isolate 成功返回', () async {
      final scan = await SerialPortCatalog().scan();
      expect(scan.warning, isNull);
      expect(
        scan.devices.map((port) => port.portName),
        everyElement(matches(r'^COM[0-9]+$')),
      );
    });
  }, skip: !Platform.isWindows);
}
