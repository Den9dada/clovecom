part of 'session_history.dart';

/// 连续的小页读取复用会话 isolate。大页由独立 isolate 移交结果所有权。
class _HistoryPageReader {
  static const _maxSharedBytes = 64 * 1024;

  ReceivePort? _replies;
  StreamIterator<Object?>? _messages;
  Isolate? _worker;
  SendPort? _commands;
  bool _busy = false, _closed = false;

  Future<List<SessionRecord>> read(List<_PageRead> reads) async {
    if (_closed ||
        _busy ||
        reads.fold<int>(0, (bytes, read) => bytes + read.length) >
            _maxSharedBytes) {
      return Isolate.run(() => _readPageFromFiles(reads));
    }

    _busy = true;
    Object? response;
    try {
      if (_commands == null) {
        final replies = _replies = ReceivePort();
        final messages = _messages = StreamIterator<Object?>(replies);
        _worker = await Isolate.spawn(
          _runHistoryReader,
          replies.sendPort,
          onExit: replies.sendPort,
          debugName: '会话历史读取',
        );
        if (await messages.moveNext() && messages.current is SendPort) {
          _commands = messages.current as SendPort;
        }
      }
      if (_commands case final commands?) {
        commands.send(reads);
        if (await _messages!.moveNext()) response = _messages!.current;
      }
    } catch (_) {
      _stop();
      rethrow;
    } finally {
      _busy = false;
      if (_closed || response == null) _stop();
    }
    if (response case (final Object error, final String stack)) {
      Error.throwWithStackTrace(error, StackTrace.fromString(stack));
    }
    if (response is List<SessionRecord>) return response;
    return Isolate.run(() => _readPageFromFiles(reads));
  }

  void close() {
    _closed = true;
    if (!_busy) _stop();
  }

  void _stop() {
    _commands = null;
    _worker?.kill(priority: Isolate.immediate);
    _worker = null;
    if (_messages case final messages?) unawaited(messages.cancel());
    _replies?.close();
    _replies = null;
    _messages = null;
  }
}

void _runHistoryReader(SendPort replies) {
  final commands = ReceivePort();
  replies.send(commands.sendPort);
  commands.listen((request) {
    try {
      replies.send(_readPageFromFiles(request as List<_PageRead>));
    } catch (error, stack) {
      replies.send((error, stack.toString()));
    }
  });
}
