import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:clovecom/services/serial/serial_port_catalog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('clovecom/serial_ports');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('原生枚举结果去重、自然排序并保留友好名称', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => [
        {'port': 'COM10', 'description': '虚拟端口'},
        {'port': 'COM2', 'description': 'USB 串口'},
        {'port': 'COM2', 'description': 'USB 串口'},
      ],
    );
    final scan = await SerialPortCatalog().scan();
    expect(scan.devices.map((p) => p.portName), ['COM2', 'COM10']);
    expect(scan.devices.first.friendlyName, 'USB 串口');
    expect(scan.warning, isNull);
  });

  test('原生成功返回空列表时不触发备用枚举', () async {
    messenger.setMockMethodCallHandler(channel, (call) async => []);
    final scan = await SerialPortCatalog().scan();
    expect(scan.devices, isEmpty);
    expect(scan.warning, isNull);
  });
}
