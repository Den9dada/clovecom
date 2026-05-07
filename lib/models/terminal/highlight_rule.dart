import 'package:flutter/material.dart';

enum HighlightTarget { foreground, background }

class HighlightRule {
  String name;
  String pattern;
  Color color;
  HighlightTarget target;
  bool enabled;

  HighlightRule({
    required this.name,
    required this.pattern,
    required this.color,
    this.target = HighlightTarget.foreground,
    this.enabled = true,
  });

  HighlightRule copy() {
    return HighlightRule(
      name: name,
      pattern: pattern,
      color: color,
      target: target,
      enabled: enabled,
    );
  }

  String get ansiFgCode {
    final r = color.red;
    final g = color.green;
    final b = color.blue;
    return '\x1b[38;2;$r;$g;${b}m';
  }

  String get ansiBgCode {
    final r = color.red;
    final g = color.green;
    final b = color.blue;
    return '\x1b[48;2;$r;$g;${b}m';
  }
}

class HighlightRuleSet {
  final String name;
  final String description;
  final List<HighlightRule> rules;

  const HighlightRuleSet({
    required this.name,
    required this.description,
    required this.rules,
  });
}

class HighlightPresets {
  HighlightPresets._();

  static final HighlightRuleSet serialDebug = HighlightRuleSet(
    name: '串口调试',
    description: 'IP、MAC、帧头、ERROR/OK等串口日志高亮',
    rules: [
      HighlightRule(
        name: 'IPv4 地址',
        pattern: r'\b(?:\d{1,3}\.){3}\d{1,3}\b',
        color: Color(0xFF22B8CF),
      ),
      HighlightRule(
        name: 'MAC 地址',
        pattern: r'\b(?:[0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}\b',
        color: Color(0xFFDA77F2),
      ),
      HighlightRule(
        name: '十六进制帧头',
        pattern: r'\b[Aa]{2}\s?55\b',
        color: Color(0xFFFFD43B),
      ),
      HighlightRule(
        name: 'ERROR',
        pattern: r'\b(ERROR|Error|error|ERR|FAIL|FATAL)\b',
        color: Color(0xFFFF6B6B),
      ),
      HighlightRule(
        name: 'OK/SUCCESS',
        pattern: r'\b(OK|SUCCESS|SUCCESSFUL|DONE|PASS)\b',
        color: Color(0xFF69DB7C),
      ),
      HighlightRule(
        name: 'WARN',
        pattern: r'\b(WARN|WARNING)\b',
        color: Color(0xFFFFD43B),
      ),
      HighlightRule(
        name: '方括号数值',
        pattern: r'\[[\d]+\]',
        color: Color(0xFF4DABF7),
      ),
    ],
  );

  static final HighlightRuleSet networkLog = HighlightRuleSet(
    name: '网络日志',
    description: 'IP:端口、URL、HTTP状态码等高亮',
    rules: [
      HighlightRule(
        name: 'IP:端口',
        pattern: r'\b(?:\d{1,3}\.){3}\d{1,3}:\d+\b',
        color: Color(0xFF22B8CF),
      ),
      HighlightRule(
        name: 'URL',
        pattern: r'\bhttps?://[^\s<>"{}|\\^`\[\]]+',
        color: Color(0xFF4DABF7),
      ),
      HighlightRule(
        name: 'HTTP 2xx',
        pattern: r'\b2\d{2}\b',
        color: Color(0xFF69DB7C),
      ),
      HighlightRule(
        name: 'HTTP 3xx',
        pattern: r'\b3\d{2}\b',
        color: Color(0xFF4DABF7),
      ),
      HighlightRule(
        name: 'HTTP 4xx',
        pattern: r'\b4\d{2}\b',
        color: Color(0xFFFFD43B),
      ),
      HighlightRule(
        name: 'HTTP 5xx',
        pattern: r'\b5\d{2}\b',
        color: Color(0xFFFF6B6B),
      ),
      HighlightRule(
        name: '时间戳 ISO',
        pattern: r'\b\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}\b',
        color: Color(0xFF868E96),
      ),
    ],
  );

  static final HighlightRuleSet generalDev = HighlightRuleSet(
    name: '通用开发',
    description: 'ERROR/WARN/INFO/DEBUG、路径、行号等高亮',
    rules: [
      HighlightRule(
        name: 'ERROR/FATAL',
        pattern: r'\b(ERROR|FATAL|FAILURE|FAILED)\b',
        color: Color(0xFFFF6B6B),
      ),
      HighlightRule(
        name: 'WARN',
        pattern: r'\b(WARN|WARNING)\b',
        color: Color(0xFFFFD43B),
      ),
      HighlightRule(
        name: 'INFO',
        pattern: r'\b(INFO|INFORMATION)\b',
        color: Color(0xFF69DB7C),
      ),
      HighlightRule(
        name: 'DEBUG/TRACE',
        pattern: r'\b(DEBUG|TRACE|VERBOSE)\b',
        color: Color(0xFF868E96),
      ),
      HighlightRule(
        name: '文件路径',
        pattern: r'\b[/\\][\w./\\-]+\b',
        color: Color(0xFF4DABF7),
      ),
      HighlightRule(
        name: '行号:列',
        pattern: r'\b\d+:\d+\b',
        color: Color(0xFFDA77F2),
      ),
    ],
  );

  static final List<HighlightRuleSet> presets = [
    serialDebug,
    networkLog,
    generalDev,
  ];
}

String applyHighlightRules(String data, List<HighlightRule> rules) {
  var result = data;
  for (final rule in rules) {
    if (!rule.enabled) continue;
    try {
      final code = rule.ansiFgCode;
      result = result.replaceAllMapped(
        RegExp(rule.pattern),
        (match) => '$code${match.group(0)}\x1b[0m',
      );
    } catch (_) {}
  }
  return result;
}
