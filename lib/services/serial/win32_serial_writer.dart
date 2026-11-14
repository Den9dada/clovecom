import 'dart:ffi';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// Win32 字节写入适配：等待完成后才释放缓冲区，短写也视为失败。
class Win32SerialWriter {
  const Win32SerialWriter();
  bool write(HANDLE handle, Uint8List data, int timeoutMs) {
    if (data.isEmpty) return true;
    final over = calloc<OVERLAPPED>();
    final buffer = calloc<Uint8>(data.length);
    final written = calloc<DWORD>();
    over.ref.hEvent = CreateEvent(null, true, false, null).value;
    if (over.ref.hEvent.address == 0) {
      free(over);
      free(buffer);
      free(written);
      return false;
    }
    try {
      buffer.asTypedList(data.length).setAll(0, data);
      final result = WriteFile(handle, buffer, data.length, written, over);
      if (result.value) return written.value == data.length;
      if (result.error != ERROR_IO_PENDING) return false;
      if (WaitForSingleObject(over.ref.hEvent, timeoutMs).value ==
          WAIT_OBJECT_0) {
        return GetOverlappedResult(handle, over, written, false).value &&
            written.value == data.length;
      }
      // 即使超时，内核也可能还持有缓冲区，取消后等待取消完成。
      CancelIoEx(handle, over);
      GetOverlappedResult(handle, over, written, true);
      return false;
    } finally {
      CloseHandle(over.ref.hEvent);
      free(over);
      free(buffer);
      free(written);
    }
  }
}
