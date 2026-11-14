import 'dart:convert';

import 'package:crypto/crypto.dart';

enum InteractionPurpose {
  control('普通交互'),
  upgrade('固件升级');

  const InteractionPurpose(this.label);
  final String label;
}

class ScriptDiagnostic {
  const ScriptDiagnostic(this.message, {this.line});
  final String message;
  final int? line;

  @override
  String toString() => line == null ? message : '第 $line 行：$message';
}

/// 保存原始文本；允许保存错误脚本，只有载入/运行要求完整校验通过。
class InteractionProtocol {
  InteractionProtocol({
    required this.id,
    required this.name,
    required this.source,
  }) {
    if (id.trim().isEmpty || name.trim().isEmpty) {
      throw const FormatException('交互协议标识和名称不能为空');
    }
    if (utf8.encode(source).length > maxSourceBytes) {
      throw const FormatException('脚本超过 1 MiB 上限');
    }
  }

  static const maxSourceBytes = 1024 * 1024;
  final String id;
  final String name;
  final String source;
  late final String digest = sha256.convert(utf8.encode(source)).toString();
  ScriptMetadata get metadata => ScriptMetadata.parse(source);

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'source': source};
  factory InteractionProtocol.fromJson(Map<String, dynamic> json) =>
      InteractionProtocol(
        id: json['id'] as String,
        name: json['name'] as String,
        source: json['source'] as String,
      );
}

/// 只读取前导 JSON 注释，不通过执行 Lua 获取元信息。
class ScriptMetadata {
  ScriptMetadata._(this._json);
  final Map<String, dynamic> _json;
  InteractionPurpose get purpose =>
      InteractionPurpose.values.byName(_json['purpose'] as String);
  String? get displayName => _json['display_name'] as String?;
  Map<String, dynamic> get dataSource =>
      Map<String, dynamic>.from(_json['data_source'] as Map? ?? const {});
  Map<String, dynamic> get upgrade =>
      Map<String, dynamic>.from(_json['upgrade'] as Map? ?? const {});
  Map<String, dynamic> get limits =>
      Map<String, dynamic>.from(_json['limits'] as Map? ?? const {});
  List<String> get requiredCapabilities =>
      List<String>.from(_json['required_capabilities'] as List? ?? const []);
  List<String> get transports => List<String>.from(
    _json['transports'] as List? ?? const ['serial', 'tcp', 'udp'],
  );

  static ScriptMetadata parse(String source) {
    final content = source.startsWith('\ufeff') ? source.substring(1) : source;
    final header = RegExp(
      r'^\s*--\[\[clovertls-config\s*([\s\S]*?)\]\]',
    ).firstMatch(content);
    if (header == null) {
      throw const FormatException('脚本头部缺少 clovertls-config JSON 元信息');
    }
    final value = jsonDecode(header.group(1)!);
    if (value is! Map<String, dynamic>) {
      throw const FormatException('脚本元信息必须是 JSON 对象');
    }
    const allowed = {
      'id',
      'version',
      'display_name',
      'runtime',
      'host_api',
      'purpose',
      'device_kinds',
      'transports',
      'required_capabilities',
      'optional_capabilities',
      'data_source',
      'upgrade',
      'limits',
      'result_schema',
      'inputs',
    };
    for (final key in value.keys) {
      if (!allowed.contains(key)) {
        throw FormatException(
          key == 'parameters' ? '不支持流程参数表单，请直接修改脚本代码' : '未知脚本元信息：$key',
        );
      }
    }
    if (!['control', 'upgrade'].contains(value['purpose'])) {
      throw const FormatException('purpose 必须是 control 或 upgrade');
    }
    if (value['runtime'] != null && value['runtime'] != 'lua54') {
      throw const FormatException('首期只支持 lua54');
    }
    if (value['host_api'] != null &&
        !['1', '1.0', '1.x'].contains(value['host_api'])) {
      throw const FormatException('不支持的宿主接口版本');
    }
    for (final key in ['data_source', 'upgrade', 'limits', 'result_schema']) {
      if (value[key] != null && value[key] is! Map<String, dynamic>) {
        throw FormatException('$key 必须是对象');
      }
    }
    for (final key in [
      'transports',
      'required_capabilities',
      'optional_capabilities',
      'device_kinds',
    ]) {
      if (value[key] != null &&
          (value[key] is! List ||
              (value[key] as List).any((x) => x is! String))) {
        throw FormatException('$key 必须是字符串列表');
      }
    }
    if (value['display_name'] != null &&
        (value['display_name'] is! String ||
            (value['display_name'] as String).trim().isEmpty)) {
      throw const FormatException('display_name 必须是非空文本');
    }
    final metadata = ScriptMetadata._(value);
    if (metadata.transports.isEmpty ||
        metadata.transports.any((t) => !['serial', 'tcp', 'udp'].contains(t))) {
      throw const FormatException('transports 包含无效类型');
    }
    final dataSource = metadata.dataSource;
    for (final key in dataSource.keys) {
      if (!['kind', 'persistent', 'runtime_initial'].contains(key)) {
        throw FormatException('未知数据源元信息：$key');
      }
    }
    if (dataSource['kind'] != null &&
        !['serial', 'tcp', 'udp'].contains(dataSource['kind'])) {
      throw const FormatException('data_source.kind 无效');
    }
    for (final key in ['persistent', 'runtime_initial']) {
      if (dataSource[key] != null && dataSource[key] is! Map<String, dynamic>) {
        throw FormatException('data_source.$key 必须是对象');
      }
    }
    final persistent = dataSource['persistent'] as Map? ?? const {};
    const sourceKeys = {
      'serial_port',
      'baud_rate',
      'data_bits',
      'stop_bits',
      'parity',
      'flow_control',
      'host',
      'port',
      'remote_host',
      'remote_port',
    };
    for (final key in persistent.keys) {
      if (!sourceKeys.contains(key)) {
        throw FormatException('未知接口参数：$key');
      }
    }
    for (final key in ['serial_port', 'host', 'remote_host']) {
      if (persistent[key] != null &&
          (persistent[key] is! String ||
              (persistent[key] as String).trim().isEmpty)) {
        throw FormatException('$key 必须是非空文本');
      }
    }
    for (final key in [
      'baud_rate',
      'port',
      'remote_port',
      'data_bits',
      'stop_bits',
    ]) {
      final v = persistent[key];
      if (v != null &&
          (v is! int ||
              v < (key == 'port' ? 0 : 1) ||
              (key.endsWith('port') && v > 65535) ||
              (key == 'baud_rate' && v > 4000000) ||
              (key == 'data_bits' && ![5, 6, 7, 8].contains(v)) ||
              (key == 'stop_bits' && ![1, 2].contains(v)))) {
        throw FormatException('$key 的接口参数值无效');
      }
    }
    if (persistent['parity'] != null &&
        ![
          'none',
          'odd',
          'even',
          'mark',
          'space',
        ].contains(persistent['parity'])) {
      throw const FormatException('parity 无效');
    }
    if (persistent['flow_control'] != null &&
        ![
          'none',
          'rts_cts',
          'dtr_dsr',
          'xon_xoff',
        ].contains(persistent['flow_control'])) {
      throw const FormatException('flow_control 无效');
    }
    final initial = dataSource['runtime_initial'] as Map? ?? const {};
    if (initial.keys.any((k) => k != 'serial') ||
        (initial['serial'] != null && initial['serial'] is! Map)) {
      throw const FormatException('runtime_initial 仅支持 serial 控制线对象');
    }
    final lines = initial['serial'] as Map? ?? const {};
    if (lines.entries.any(
      (e) => !['rts', 'dtr'].contains(e.key) || e.value is! bool,
    )) {
      throw const FormatException('runtime_initial 只允许布尔型 rts/dtr；输入信号只读');
    }
    for (final key in metadata.limits.keys) {
      final v = metadata.limits[key];
      if (key != 'run_timeout_ms' || v is! int || v < 1 || v > 86400000) {
        throw const FormatException('limits 仅允许 1～86400000 的 run_timeout_ms');
      }
    }
    if (metadata.upgrade.keys.any(
      (k) => !['owns_device_liveness', 'supports_direct'].contains(k),
    )) {
      throw const FormatException('存在不支持的 upgrade 字段');
    }
    for (final key in ['owns_device_liveness', 'supports_direct']) {
      if (metadata.upgrade[key] != null && metadata.upgrade[key] is! bool) {
        throw FormatException('upgrade.$key 必须是布尔值');
      }
    }
    return metadata;
  }
}

String newInteractionSource(String name, InteractionPurpose purpose) =>
    '''--[[clovertls-config
${const JsonEncoder.withIndent('  ').convert({
      'display_name': name,
      'runtime': 'lua54',
      'host_api': '1.0',
      'purpose': purpose.name,
      if (purpose == InteractionPurpose.upgrade) 'upgrade': {'owns_device_liveness': true, 'supports_direct': true},
    })}
]]
-- 调整交互流程请直接修改本脚本，不通过界面生成流程参数。
local function run(ctx)
  ctx:log("info", "开始执行")
  -- 在此使用 ctx.link、ctx.inputs.firmware 等宿主接口。
  ctx:fail("NotImplemented", "请先编写实际交互步骤和成功判据")
end
return {run = run}
''';
