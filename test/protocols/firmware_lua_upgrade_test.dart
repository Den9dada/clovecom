import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:clovecom/protocol_editor.dart';
import 'package:clovecom/services/serial/serial_byte_transport.dart';
import 'package:clovecom/services/serial/serial_port_catalog.dart';
import 'package:clovecom/viewmodels/serial_port_viewmodel.dart';
import '../services/serial/serial_port_directory_test.dart' show ports;

class DeviceTransport implements SerialByteTransport {
  final input = StreamController<Uint8List>.broadcast();
  final writes = <List<int>>[];
  bool closed = false;
  bool writeFails = false;
  void Function(Uint8List)? onWrite;
  @override
  Stream<Uint8List> get chunks => input.stream;
  @override
  bool send(Uint8List data, int timeoutMs) {
    if (closed || writeFails) return false;
    writes.add(data.toList());
    if (onWrite != null) {
      onWrite!(data);
    } else {
      input.add(Uint8List.fromList([6]));
    }
    return true;
  }

  @override
  void purge() {}
  @override
  void close() {
    closed = true;
  }
}

String script(String body) => newInteractionSource(
  '测试升级',
  InteractionPurpose.upgrade,
).replaceFirst('  ctx:fail("NotImplemented", "请先编写实际交互步骤和成功判据")', body);

void main() {
  late ProtocolLibrary library;
  late SerialPortViewModel vm;
  late DeviceTransport device;
  late Directory dir;
  setUp(() async {
    library = ProtocolLibrary();
    await library.initialize();
    device = DeviceTransport();
    vm = SerialPortViewModel(
      protocolLibrary: library,
      directory: SerialPortDirectory(
        scan: () async => ports([]),
        changes: const Stream.empty(),
      ),
      openTransport: (_) => device,
    );
    vm.updateConfig(portName: 'COM99');
    dir = await Directory.systemTemp.createTemp('clovecom-firmware-test-');
    final file = File('${dir.path}/test.bin');
    await file.writeAsBytes([1, 2, 3, 4]);
    await vm.loadFirmwareFile(file.path);
  });
  tearDown(() async {
    vm.dispose();
    library.dispose();
    await device.input.close();
    await dir.delete(recursive: true);
  });
  Future<String> loadScript(String body) async {
    final draft = library.createInteraction(
      '测试升级',
      InteractionPurpose.upgrade,
      source: script(body),
    );
    await library.saveInteraction(draft.id);
    await vm.loadFirmwareProtocol(draft.id);
    expect(vm.errorMessage, isNull);
    return draft.id;
  }

  test('真实 Lua 收发握手、固件快照、进度和成功终态对接现有串口', () async {
    await loadScript('''
  local reader = ctx.link:reader()
  local fw = ctx.inputs.firmware
  ctx.link:send(fw:read(0, fw:info().size))
  assert(reader:read_exact(1, {deadline=ctx.time:after(2000)}):u8(0) == 6)
  ctx:progress({completed=4,total=4})
  return {status="success"}
''');
    // 文件载入成功后修改磁盘内容，不应改变本次升级输入。
    await File('${dir.path}/test.bin').writeAsBytes([9]);
    await vm.connect();
    await vm.startFirmwareUpgrade();
    expect(device.writes, [
      [1, 2, 3, 4],
    ]);
    expect(vm.firmwareConfig.progress, 1);
    expect(vm.firmwareConfig.isUpgrading, isFalse);
    expect(vm.isTransferBusy, isFalse);
    expect(vm.state.isConnected, isTrue);
    expect(vm.messages.any((m) => m.data.contains('Lua 协议升级完成')), isTrue);
  });

  test('停止等待应答的 Lua 任务后释放独占会话，串口保持连接', () async {
    await loadScript('''
  local reader = ctx.link:reader()
  reader:read_exact(1, {deadline=ctx.time:after(30000)})
  return {status="success"}
''');
    await vm.connect();
    final upgrade = vm.startFirmwareUpgrade();
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(vm.isTransferBusy, isTrue);
    vm.stopFirmwareUpgrade();
    await upgrade.timeout(const Duration(seconds: 5));
    expect(vm.isTransferBusy, isFalse);
    expect(vm.state.isConnected, isTrue);
    expect(vm.firmwareConfig.progress, isNot(1));
    expect(device.writes, isEmpty);
  });

  test('Lua 写入失败必须报告失败，不能误报完成', () async {
    await loadScript('''
  ctx.link:reader()
  ctx.link:send(bytes.from_hex("0102"))
  return {status="success"}
''');
    device.writeFails = true;
    await vm.connect();
    await vm.startFirmwareUpgrade();
    expect(vm.errorMessage, contains('固件升级失败'));
    expect(vm.isTransferBusy, isFalse);
    expect(vm.messages.any((m) => m.data.contains('Lua 协议升级完成')), isFalse);
  });

  test('预置点表 Lua 在模拟设备取数后应答正确固件并按静默判据完成', () async {
    final preset = library.interactionDrafts.first;
    final draft = library.createInteraction(
      '点表模拟',
      InteractionPurpose.upgrade,
      source: preset.source.replaceAll('= 10000', '= 150'),
    );
    await library.saveInteraction(draft.id);
    await vm.loadFirmwareProtocol(draft.id);
    expect(vm.errorMessage, isNull);
    final firmware = File('${dir.path}/point-table.bin');
    await firmware.writeAsBytes([0x42, 0x4c, 0, 2, 0, 0x63, 1, 2, 3, 4]);
    await vm.loadFirmwareFile(firmware.path);
    Uint8List request(int address, int count) {
      final body = [1, address >> 8, address & 255, count >> 8, count & 255];
      final crc = computeChecksum(ChecksumKind.crc16Modbus, body);
      return Uint8List.fromList([
        0x42,
        0x4c,
        3,
        0,
        2,
        0,
        0,
        7,
        ...body,
        crc & 255,
        crc >> 8,
      ]);
    }

    device.onWrite = (_) {
      if (device.writes.length == 1) device.input.add(request(0, 2));
      if (device.writes.length == 2) device.input.add(request(2, 2));
    };
    await vm.connect();
    await vm.startFirmwareUpgrade().timeout(const Duration(seconds: 5));
    expect(device.writes, hasLength(3));
    expect(device.writes[0][8], 4);
    expect(device.writes[1].sublist(13, 17), [0, 0, 0, 4]);
    expect(device.writes[2].sublist(13, 17), [1, 2, 3, 4]);
    expect(vm.errorMessage, isNull);
    expect(vm.firmwareConfig.progress, 1);
    expect(vm.state.isConnected, isTrue);
  });

  test('未载入或卸载协议后拒绝升级，不执行无应答分包发送', () async {
    await vm.connect();
    await vm.startFirmwareUpgrade();
    expect(vm.errorMessage, contains('请先选择并载入升级协议'));
    expect(device.writes, isEmpty);
    expect(vm.isTransferBusy, isFalse);
    final id = library.savedInteractions.first.id;
    await vm.loadFirmwareProtocol(id);
    expect(vm.firmwareProtocols!.loaded?.id, id);
    vm.unloadFirmwareProtocol();
    await library.deleteInteraction(id);
    await vm.startFirmwareUpgrade();
    expect(device.writes, isEmpty);
    expect(vm.isTransferBusy, isFalse);
  });
  test('固件载入失败保留上一次完整输入', () async {
    await expectLater(
      vm.loadFirmwareFile('${dir.path}/missing.bin'),
      throwsA(isA<FileSystemException>()),
    );
    expect(vm.firmwareConfig.firmwareName, 'test.bin');
    expect(vm.firmwareConfig.firmwareSize, 4);
  });
}
