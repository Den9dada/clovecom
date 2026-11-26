import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import '../../models/serial_port_model.dart';

final _comPort = RegExp(r'^COM[0-9]+$');

/// 合并 DOS 设备名和当前设备信息，在扫描 isolate 内释放原生资源。
List<PortDetailInfo> scanWin32SerialPorts() {
  final ports = _queryDosPorts();
  final opened = SetupDiGetClassDevs(
    null,
    null,
    null,
    DIGCF_PRESENT | DIGCF_ALLCLASSES,
  );
  final devices = opened.value;
  if (!devices.isValid) {
    throw StateError('SetupDiGetClassDevsW 失败：${opened.error}');
  }

  try {
    using((arena) {
      final info = arena<SP_DEVINFO_DATA>();
      info.ref.cbSize = sizeOf<SP_DEVINFO_DATA>();
      final valueName = PCWSTR('PortName'.toNativeUtf16(allocator: arena));
      const portCapacity = 256;
      const descriptionCapacity = 2048;
      final portBuffer = arena<Uint16>(portCapacity);
      final description = arena<Uint16>(descriptionCapacity);
      final bytes = arena<Uint32>();
      final type = arena<Uint32>();

      for (var index = 0; ; index++) {
        final next = SetupDiEnumDeviceInfo(devices, index, info);
        if (!next.value) {
          if (next.error == ERROR_NO_MORE_ITEMS) break;
          throw StateError('SetupDiEnumDeviceInfo 失败：${next.error}');
        }
        final key = SetupDiOpenDevRegKey(
          devices,
          info,
          DICS_FLAG_GLOBAL,
          0,
          DIREG_DEV,
          KEY_QUERY_VALUE,
        ).value;
        if (!key.isValid) continue;

        bytes.value = portCapacity * sizeOf<Uint16>();
        try {
          final status = RegQueryValueEx(
            key,
            valueName,
            type,
            portBuffer.cast(),
            bytes,
          );
          if (status != ERROR_SUCCESS || type.value != REG_SZ) continue;
        } finally {
          key.close();
        }

        final portLength = bytes.value ~/ sizeOf<Uint16>();
        portBuffer[portLength.clamp(0, portCapacity - 1)] = 0;
        final port = portBuffer.cast<Utf16>().toDartString();
        if (!_comPort.hasMatch(port)) continue;

        final friendlyName = SetupDiGetDeviceRegistryProperty(
          devices,
          info,
          SPDRP_FRIENDLYNAME,
          null,
          description.cast(),
          descriptionCapacity * sizeOf<Uint16>(),
          bytes,
        );
        if (friendlyName.value) {
          final length = bytes.value ~/ sizeOf<Uint16>();
          description[length.clamp(0, descriptionCapacity - 1)] = 0;
          ports[port] = description.cast<Utf16>().toDartString();
        } else {
          ports.putIfAbsent(port, () => port);
        }
      }
    });
  } finally {
    devices.close();
  }

  return [
    for (final MapEntry(:key, :value) in ports.entries)
      PortDetailInfo(
        portName: key,
        friendlyName: value,
        hardwareID: '',
        manufactureName: '',
      ),
  ];
}

Map<String, String> _queryDosPorts() {
  const maxCapacity = 1048576;
  for (var capacity = 65536; ; capacity *= 2) {
    final buffer = calloc<Uint16>(capacity);
    try {
      final result = QueryDosDevice(null, PWSTR(buffer.cast()), capacity);
      if (result.value > 0) {
        final names = String.fromCharCodes(buffer.asTypedList(result.value))
            .split('\u0000');
        return {for (final name in names.where(_comPort.hasMatch)) name: name};
      }
      if (result.error != ERROR_INSUFFICIENT_BUFFER ||
          capacity >= maxCapacity) {
        throw StateError('QueryDosDeviceW 失败：${result.error}');
      }
    } finally {
      calloc.free(buffer);
    }
  }
}
