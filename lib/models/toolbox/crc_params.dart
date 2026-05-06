enum DataInputMode { hex, ascii, file }

class CrcParams {
  const CrcParams({
    required this.width,
    required this.poly,
    required this.init,
    required this.xorout,
    required this.refin,
    required this.refout,
  });

  final int width;
  final int poly;
  final int init;
  final int xorout;
  final bool refin;
  final bool refout;

  CrcParams copyWith({
    int? width,
    int? poly,
    int? init,
    int? xorout,
    bool? refin,
    bool? refout,
  }) {
    return CrcParams(
      width: width ?? this.width,
      poly: poly ?? this.poly,
      init: init ?? this.init,
      xorout: xorout ?? this.xorout,
      refin: refin ?? this.refin,
      refout: refout ?? this.refout,
    );
  }
}

class CrcPreset {
  const CrcPreset({required this.name, required this.params});
  final String name;
  final CrcParams params;
}

class CrcPresets {
  CrcPresets._();

  static const all = <CrcPreset>[
    CrcPreset(name: 'CRC-4/ITU', params: CrcParams(width: 4, poly: 0x03, init: 0x00, xorout: 0x00, refin: true, refout: true)),
    CrcPreset(name: 'CRC-5/EPC', params: CrcParams(width: 5, poly: 0x09, init: 0x09, xorout: 0x00, refin: false, refout: false)),
    CrcPreset(name: 'CRC-5/ITU', params: CrcParams(width: 5, poly: 0x15, init: 0x00, xorout: 0x00, refin: true, refout: true)),
    CrcPreset(name: 'CRC-5/USB', params: CrcParams(width: 5, poly: 0x05, init: 0x1F, xorout: 0x1F, refin: true, refout: true)),
    CrcPreset(name: 'CRC-6/ITU', params: CrcParams(width: 6, poly: 0x03, init: 0x00, xorout: 0x00, refin: true, refout: true)),
    CrcPreset(name: 'CRC-7/MMC', params: CrcParams(width: 7, poly: 0x09, init: 0x00, xorout: 0x00, refin: false, refout: false)),
    CrcPreset(name: 'CRC-8', params: CrcParams(width: 8, poly: 0x07, init: 0x00, xorout: 0x00, refin: false, refout: false)),
    CrcPreset(name: 'CRC-8/ITU', params: CrcParams(width: 8, poly: 0x07, init: 0x00, xorout: 0x55, refin: false, refout: false)),
    CrcPreset(name: 'CRC-8/ROHC', params: CrcParams(width: 8, poly: 0x07, init: 0xFF, xorout: 0x00, refin: true, refout: true)),
    CrcPreset(name: 'CRC-8/MAXIM', params: CrcParams(width: 8, poly: 0x31, init: 0x00, xorout: 0x00, refin: true, refout: true)),
    CrcPreset(name: 'CRC-16/IBM', params: CrcParams(width: 16, poly: 0x8005, init: 0x0000, xorout: 0x0000, refin: true, refout: true)),
    CrcPreset(name: 'CRC-16/MAXIM', params: CrcParams(width: 16, poly: 0x8005, init: 0x0000, xorout: 0xFFFF, refin: true, refout: true)),
    CrcPreset(name: 'CRC-16/USB', params: CrcParams(width: 16, poly: 0x8005, init: 0xFFFF, xorout: 0xFFFF, refin: true, refout: true)),
    CrcPreset(name: 'CRC-16/MODBUS', params: CrcParams(width: 16, poly: 0x8005, init: 0xFFFF, xorout: 0x0000, refin: true, refout: true)),
    CrcPreset(name: 'CRC-16/CCITT', params: CrcParams(width: 16, poly: 0x1021, init: 0x0000, xorout: 0x0000, refin: true, refout: true)),
    CrcPreset(name: 'CRC-16/CCITT-FALSE', params: CrcParams(width: 16, poly: 0x1021, init: 0xFFFF, xorout: 0x0000, refin: false, refout: false)),
    CrcPreset(name: 'CRC-16/X25', params: CrcParams(width: 16, poly: 0x1021, init: 0xFFFF, xorout: 0xFFFF, refin: true, refout: true)),
    CrcPreset(name: 'CRC-16/XMODEM', params: CrcParams(width: 16, poly: 0x1021, init: 0x0000, xorout: 0x0000, refin: false, refout: false)),
    CrcPreset(name: 'CRC-16/DNP', params: CrcParams(width: 16, poly: 0x3D65, init: 0x0000, xorout: 0xFFFF, refin: true, refout: true)),
    CrcPreset(name: 'CRC-32', params: CrcParams(width: 32, poly: 0x04C11DB7, init: 0xFFFFFFFF, xorout: 0xFFFFFFFF, refin: true, refout: true)),
    CrcPreset(name: 'CRC-32/MPEG-2', params: CrcParams(width: 32, poly: 0x04C11DB7, init: 0xFFFFFFFF, xorout: 0x00000000, refin: false, refout: false)),
  ];

  static CrcPreset byName(String name) {
    return all.firstWhere((p) => p.name == name);
  }

  static List<String> get presetNames => ['自定义', ...all.map((p) => p.name)];
}
