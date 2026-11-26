import 'dart:async';
import 'dart:typed_data';

import 'package:clovecom/src/application/communication_runtime.dart';
import 'package:clovecom/src/application/communication_transport.dart';
import 'package:clovecom/src/io/connections.dart';

import '../src/application/communication_runtime_test.dart' show FakeTransport;

void add(CommunicationRuntime runtime, String id) {
  runtime.addConnection(
    ConnectionDefinition.serial(
      ConnectionConfig(
        id: id,
        serialPort: id,
        protocolId: '',
        kind: TransportKind.serial,
      ),
    ),
  );
}

class RecordingTransport extends FakeTransport {
  final written = <List<int>>[];
  final settled = Completer<void>();
  bool hold = true, failure = false;
  SerialWriteResult? answer;
  void finish() {
    hold = false;
    if (!settled.isCompleted) settled.complete();
  }

  @override
  Future<SerialWriteResult> write(Uint8List bytes, int timeoutMs) async {
    written.add(List.of(bytes));
    if (answer != null) return answer!;
    return SerialWriteResult(
      succeeded: !failure,
      acceptedBytes: failure ? null : bytes.length,
      settled: hold ? settled.future : null,
    );
  }

  @override
  Future<void> close() async {
    finish();
    await super.close();
  }
}

class DelayedResultTransport extends FakeTransport {
  final pending = Completer<SerialWriteResult>();
  final written = <List<int>>[];
  @override
  Future<SerialWriteResult> write(Uint8List bytes, int timeoutMs) {
    written.add(List.of(bytes));
    return pending.future;
  }
}

class CancelTransport extends RecordingTransport
    implements CancellableCommunicationTransport {
  int cancelled = 0;
  @override
  Future<void> cancelWrite() {
    cancelled++;
    return settled.future;
  }
}
