/// 串口配置词汇的唯一翻译缝：显示值（SerialPortConfig 的 parity/flowControl）
/// ↔ 规范码（src/Lua 与持久化 JSON 使用的 snake_case）↔ 校验位索引。
///
/// 深模块：调用方只学四个转换方法；三套词汇的对照表内化于此。
/// 落实 ADR-0001——新增 parity/flowControl 取值只改这一处映射，
/// 不再在 ViewModel 与固件绑定里各维护一份手写表。
library;

class SerialConfigTranslation {
  const SerialConfigTranslation._();

  /// 校验位显示值，顺序即 ConnectionConfig.parity 的索引语义。
  static const _parityDisplay = ['None', 'Odd', 'Even', 'Mark', 'Space'];
  static const _parityCode = ['none', 'odd', 'even', 'mark', 'space'];

  /// 流控显示值 → 规范码。
  static const _flowDisplayToCode = {
    'None': 'none',
    'RTS/CTS': 'rts_cts',
    'DTR/DSR': 'dtr_dsr',
    'XON/XOFF': 'xon_xoff',
  };

  /// 校验位显示值 → 索引（未知返回 -1，与旧 indexOf 行为一致）。
  static int parityIndexOf(String display) => _parityDisplay.indexOf(display);

  /// 流控显示值 → 规范码（未知归一为 none）。
  static String flowCodeOf(String display) =>
      _flowDisplayToCode[display] ?? 'none';

  /// 校验位规范码 → 显示值（null/未知返回 null，供 copyWith 保留原值）。
  static String? parityDisplayOf(String? code) {
    if (code == null) return null;
    final index = _parityCode.indexOf(code);
    return index < 0 ? null : _parityDisplay[index];
  }

  /// 流控规范码 → 显示值（null/未知返回 null，供 copyWith 保留原值）。
  static String? flowDisplayOf(String? code) {
    if (code == null) return null;
    for (final entry in _flowDisplayToCode.entries) {
      if (entry.value == code) return entry.key;
    }
    return null;
  }
}