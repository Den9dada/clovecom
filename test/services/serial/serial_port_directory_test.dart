import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:clovecom/models/serial_port_model.dart';
import 'package:clovecom/services/serial/serial_port_catalog.dart';

SerialPortScan ports(List<String> names) => SerialPortScan([
  for (final name in names)
    PortDetailInfo(
      portName: name,
      friendlyName: '',
      hardwareID: '',
      manufactureName: '',
    ),
]);

void main() {
  testWidgets('连发事件去抖并从最后一次事件执行补扫', (tester) async {
    final events = StreamController<void>.broadcast(sync: true);
    var scans = 0;
    final directory = SerialPortDirectory(
      scan: () async {
        scans++;
        return ports(['COM2']);
      },
      changes: events.stream,
    );
    events.add(null);
    await tester.pump(const Duration(milliseconds: 200));
    events.add(null);
    await tester.pump(const Duration(milliseconds: 299));
    expect(scans, 0);
    await tester.pump(const Duration(milliseconds: 1));
    expect(scans, 1);
    await tester.pump(const Duration(milliseconds: 700));
    expect(scans, 2);
    directory.dispose();
    await events.close();
  });

  testWidgets('普通扫描期间排入的拔出检查不会丢失', (tester) async {
    final pending = Completer<SerialPortScan>();
    var scans = 0;
    final directory = SerialPortDirectory(
      scan: () {
        scans++;
        if (scans == 1) return Future.value(ports(['COM2']));
        if (scans == 2) return pending.future;
        return Future.value(ports([]));
      },
      changes: const Stream.empty(),
    );
    await directory.refresh();
    final removed = <String>{};
    directory.addListener(() => removed.addAll(directory.removedPorts));
    final scan = directory.refresh();
    await directory.refresh(evictStaleSelection: true);
    pending.complete(ports([]));
    await scan;
    expect(scans, 3);
    expect(removed, {'COM2'});
    directory.dispose();
  });

  test('扫描失败保留上次快照且不报告拔出', () async {
    var fail = false;
    final directory = SerialPortDirectory(
      scan: () async {
        if (fail) throw StateError('枚举失败');
        return ports(['COM5']);
      },
      changes: const Stream.empty(),
    );
    await directory.refresh();
    fail = true;
    await directory.refresh(evictStaleSelection: true);
    expect(directory.snapshot.devices.single.portName, 'COM5');
    expect(directory.removedPorts, isEmpty);
    expect(directory.warning, contains('枚举失败'));
    directory.dispose();
  });

  test('销毁后不通知也不执行排队扫描', () async {
    final pending = Completer<SerialPortScan>();
    var scans = 0;
    final directory = SerialPortDirectory(
      scan: () {
        scans++;
        return pending.future;
      },
      changes: const Stream.empty(),
    );
    var notifications = 0;
    directory.addListener(() => notifications++);
    final scan = directory.refresh();
    await directory.refresh(evictStaleSelection: true);
    directory.dispose();
    pending.complete(ports([]));
    await scan;
    expect(scans, 1);
    expect(notifications, 0);
  });
}
