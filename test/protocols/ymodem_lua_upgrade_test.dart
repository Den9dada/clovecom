import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:clovecom/protocol_editor.dart';
import 'package:clovecom/services/serial/serial_port_catalog.dart';
import 'package:clovecom/src/application/ymodem_lua_source.dart';
import 'package:clovecom/viewmodels/serial_port_viewmodel.dart';
import '../services/serial/serial_port_directory_test.dart' show ports;
import 'firmware_lua_upgrade_test.dart' show DeviceTransport;

int crc16(List<int> data) {
  var crc = 0;
  for (final byte in data) {
    crc ^= byte << 8;
    for (var bit = 0; bit < 8; bit++) {
      crc = ((crc << 1) ^ ((crc & 0x8000) != 0 ? 0x1021 : 0)) & 0xffff;
    }
  }
  return crc;
}

void main() {
  late ProtocolLibrary library;
  late SerialPortViewModel vm;
  late DeviceTransport device;
  late Directory dir;
  Timer? requests;
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
    dir = await Directory.systemTemp.createTemp('clovecom-ymodem-');
  });
  tearDown(() async {
    requests?.cancel();
    vm.dispose();
    library.dispose();
    await device.input.close();
    await dir.delete(recursive: true);
  });

  Future<void> prepare(List<int> firmware) async {
    final file = File('${dir.path}/Firmware.bin');
    await file.writeAsBytes(firmware);
    await vm.loadFirmwareFile(file.path);
    final preset = library.interactionDrafts.singleWhere(
      (p) => p.source == ymodemLuaSource,
    );
    preset.setSource(
      preset.source
          .replaceFirst('ACK_TIMEOUT_MS = 10000', 'ACK_TIMEOUT_MS = 100')
          .replaceFirst('START_TIMEOUT_MS = 60000', 'START_TIMEOUT_MS = 1000'),
    );
    await library.saveInteraction(preset.id);
    await vm.loadFirmwareProtocol(preset.id);
    expect(vm.errorMessage, isNull);
    await vm.connect();
  }

  void startRequests(int byte) {
    requests = Timer.periodic(const Duration(milliseconds: 10), (timer) {
      if (vm.messages.any((m) => m.data.contains('等待接收端请求 YMODEM 传输'))) {
        device.input.add(Uint8List.fromList([byte]));
        timer.cancel();
      }
    });
  }

  test('预置 Lua 示例与协议库源码一致，CRC 已知向量正确', () async {
    expect(
      await File('assets/protocols/ymodem.lua').readAsString(),
      ymodemLuaSource,
    );
    expect(crc16(ascii.encode('123456789')), 0x31c3);
    expect(
      library.savedInteractions.where((p) => p.source == ymodemLuaSource),
      hasLength(1),
    );
  });

  for (final checksum in [false, true]) {
    test(
      checksum ? '标准 YMODEM 支持 NAK 协商校验和' : '标准 YMODEM 数据块仅需 ACK，支持重传和两次 EOT',
      () async {
        final firmware = List.generate(2051, (i) => i & 255);
        await prepare(firmware);
        var header = false, rejected = false, eot = 0, finished = false;
        final data = <int>[], sequences = <int>[];
        List<int>? firstAttempt;
        void reply(List<int> values) =>
            device.input.add(Uint8List.fromList(values));
        final mode = checksum ? 0x15 : 0x43;
        device.onWrite = (packet) {
          if (packet.length == 1 && packet[0] == 4) {
            eot++;
            reply(eot == 1 ? [0x15] : [6, mode]);
            return;
          }
          final size = packet[0] == 1 ? 128 : 1024;
          expect(packet.length, 3 + size + (checksum ? 1 : 2));
          expect(packet[1] ^ packet[2], 255);
          final body = packet.sublist(3, 3 + size);
          if (checksum) {
            expect(packet.last, body.fold<int>(0, (s, b) => (s + b) & 255));
          } else {
            expect(packet[3 + size] * 256 + packet[4 + size], crc16(body));
          }
          if (!header ||
              (packet[0] == 1 && packet[1] == 0 && body.first != 0)) {
            expect(packet[0], 1);
            expect(packet[1], 0);
            final nameEnd = body.indexOf(0);
            expect(ascii.decode(body.sublist(0, nameEnd)), 'firmware.bin');
            expect(
              ascii.decode(
                body.sublist(nameEnd + 1, body.indexOf(0, nameEnd + 1)),
              ),
              '2051',
            );
            expect(
              body.skip(body.indexOf(0, nameEnd + 1)).every((b) => b == 0),
              isTrue,
            );
            header = true;
            reply([6, mode]); // ACK 与 C/NAK 粘在同一个读取块。
          } else if (packet[0] == 1 &&
              packet[1] == 0 &&
              body.every((b) => b == 0)) {
            finished = true;
            reply([6]);
          } else {
            if (!checksum && packet[1] == 2 && !rejected) {
              firstAttempt = packet.toList();
              rejected = true;
              reply([0x15]);
              return;
            }
            if (firstAttempt != null && packet[1] == 2) {
              expect(packet, firstAttempt);
            }
            expect(packet[1], sequences.length + 1);
            sequences.add(packet[1]);
            final remaining = firmware.length - data.length;
            data.addAll(body.take(remaining < size ? remaining : size));
            if (remaining < size) {
              expect(body.skip(remaining).every((b) => b == 0x1a), isTrue);
            }
            reply([6]); // 数据包后不发送 C。
          }
        };
        startRequests(mode);
        await vm.startFirmwareUpgrade().timeout(const Duration(seconds: 10));
        expect(vm.errorMessage, isNull);
        expect(data, firmware);
        expect(sequences, [1, 2, 3]);
        expect(eot, 2);
        expect(finished, isTrue);
        expect(vm.firmwareConfig.progress, 1);
        expect(vm.isTransferBusy, isFalse);
        expect(vm.state.isConnected, isTrue);
      },
    );
  }

  test('标准 YMODEM 序号跨 255 回绕，接受 EOT 直接 ACK', () async {
    final firmware = List.generate(256 * 1024 + 1, (i) => i & 255);
    await prepare(firmware);
    var dataBlocks = 0, eot = false, finished = false;
    device.onWrite = (packet) {
      if (packet.length == 1 && packet[0] == 4) {
        eot = true;
        device.input.add(Uint8List.fromList([6, 0x43]));
      } else if (packet[0] == 2) {
        dataBlocks++;
        expect(packet[1], dataBlocks & 255);
        device.input.add(Uint8List.fromList([6]));
      } else {
        finished = eot;
        device.input.add(Uint8List.fromList(eot ? [6] : [6, 0x43]));
      }
    };
    startRequests(0x43);
    await vm.startFirmwareUpgrade().timeout(const Duration(seconds: 20));
    expect(dataBlocks, 257);
    expect(finished, isTrue);
    expect(vm.errorMessage, isNull);
  });

  test('空文件名结束块缺少 ACK 时失败并发送取消，不误报成功', () async {
    await prepare([1, 2, 3]);
    var eot = false, emptyAttempts = 0;
    device.onWrite = (packet) {
      if (packet.length == 2 && packet.every((b) => b == 0x18)) return;
      if (packet.length == 1) {
        eot = true;
        device.input.add(Uint8List.fromList([6, 0x43]));
      } else if (eot) {
        emptyAttempts++;
      } else {
        device.input.add(Uint8List.fromList(packet[0] == 1 ? [6, 0x43] : [6]));
      }
    };
    startRequests(0x43);
    await vm.startFirmwareUpgrade().timeout(const Duration(seconds: 10));
    expect(emptyAttempts, 10);
    expect(vm.errorMessage, contains('重传次数耗尽'));
    expect(device.writes.last, [0x18, 0x18]);
    expect(vm.messages.any((m) => m.data.contains('Lua 协议升级完成')), isFalse);
    expect(vm.isTransferBusy, isFalse);
  });

  test('数据块丢失 ACK 后原样重传，不推进偏移', () async {
    await prepare([1, 2, 3]);
    List<int>? first;
    var attempts = 0, eot = false;
    device.onWrite = (packet) {
      if (packet.length == 1) {
        eot = true;
        device.input.add(Uint8List.fromList([6, 0x43]));
      } else if (packet[0] == 2) {
        attempts++;
        if (first == null) {
          first = packet.toList();
          return;
        }
        expect(packet, first);
        device.input.add(Uint8List.fromList([6]));
      } else {
        device.input.add(Uint8List.fromList(eot ? [6] : [6, 0x43]));
      }
    };
    startRequests(0x43);
    await vm.startFirmwareUpgrade().timeout(const Duration(seconds: 5));
    expect(attempts, 2);
    expect(vm.errorMessage, isNull);
  });

  test('等待接收端时可停止，停止后不再重传且保持串口连接', () async {
    await prepare([1, 2, 3]);
    final dataSent = Completer<void>();
    device.onWrite = (packet) {
      if (packet[0] == 1) device.input.add(Uint8List.fromList([6, 0x43]));
      if (packet[0] == 2 && !dataSent.isCompleted) dataSent.complete();
    };
    startRequests(0x43);
    final upgrade = vm.startFirmwareUpgrade();
    await dataSent.future.timeout(const Duration(seconds: 3));
    vm.stopFirmwareUpgrade();
    await upgrade.timeout(const Duration(seconds: 3));
    final written = device.writes.length;
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(device.writes, hasLength(written));
    expect(vm.isTransferBusy, isFalse);
    expect(vm.state.isConnected, isTrue);
    expect(vm.messages.any((m) => m.data.contains('Lua 协议升级完成')), isFalse);
  });

  test('接收端连续 CAN 取消后不得发送固件', () async {
    await prepare([1, 2, 3]);
    device.onWrite = (_) {};
    requests = Timer.periodic(const Duration(milliseconds: 15), (_) {
      device.input.add(Uint8List.fromList([0x18, 0x18]));
    });
    await vm.startFirmwareUpgrade().timeout(const Duration(seconds: 5));
    requests!.cancel();
    expect(vm.errorMessage, contains('RemoteCancelled'));
    expect(
      device.writes.every((b) => b.length == 2 && b.every((n) => n == 0x18)),
      isTrue,
    );
    expect(vm.state.isConnected, isTrue);
  });
}
