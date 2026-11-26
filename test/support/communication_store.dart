import 'dart:io';

import 'package:clovecom/src/application/communication_configuration_store.dart';
import 'package:clovecom/src/application/communication_transport.dart';
import 'package:clovecom/src/io/connections.dart';

ConnectionDefinition serialDefinition(String id, {String port = 'COM7'}) =>
    ConnectionDefinition.serial(
      ConnectionConfig(
        id: id,
        kind: TransportKind.serial,
        protocolId: '',
        serialPort: port,
      ),
    );

class MemoryStore implements CommunicationConfigurationStore {
  String? contents;
  @override
  Future<String?> read() async => contents;
  @override
  Future<void> write(String value) async {
    contents = value;
  }
}

class ControlledStore extends MemoryStore {
  ControlledStore({this.readGate, this.writeGate});
  Future<String?>? readGate;
  Future<void>? writeGate;
  int writes = 0, active = 0, peak = 0;
  bool failWrites = false;
  @override
  Future<String?> read() async {
    final gate = readGate;
    readGate = null;
    return gate == null ? contents : await gate;
  }

  @override
  Future<void> write(String value) async {
    writes++;
    active++;
    if (active > peak) peak = active;
    try {
      if (failWrites) throw FileSystemException('受控磁盘错误');
      await writeGate;
      contents = value;
    } finally {
      active--;
    }
  }
}
