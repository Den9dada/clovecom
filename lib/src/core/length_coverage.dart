part of 'protocol.dart';

/// 覆盖分析只读取这些字段事实；半成品数值无需先构造有效协议。
class CoverageFieldFacts {
  const CoverageFieldFacts({
    required this.name,
    required this.role,
    required this.type,
    required this.size,
    required this.fixed,
    required this.fromEnd,
  });
  factory CoverageFieldFacts.fromField(ProtocolField field) =>
      CoverageFieldFacts(
        name: field.name,
        role: field.role.name,
        type: field.type.name,
        size: field.size,
        fixed: field.fixed != null,
        fromEnd: field.fromEnd,
      );
  factory CoverageFieldFacts.fromDraft(Map<String, dynamic> field) =>
      CoverageFieldFacts(
        name: '${field['name'] ?? ''}',
        role: '${field['role'] ?? ''}',
        type: '${field['type'] ?? ''}',
        size: int.tryParse('${field['size']}'),
        fixed: field['fixed'] != null,
        fromEnd: field['fromEnd'] == true,
      );
  final String name;
  final String role;
  final String type;
  final int? size;
  final bool fixed;
  final bool fromEnd;
  bool get canDerive => (role == 'data' || role == 'skip') && !fixed;
}

class CoverageIssue {
  const CoverageIssue(
    this.lengthField,
    this.code,
    this.message, {
    this.fieldName,
  });
  final String lengthField;
  final String code;
  final String message;
  final String? fieldName;
}

class CoverageOption {
  const CoverageOption(this.name, {this.reason});
  final String name;
  final String? reason;
  String get label => reason == null ? name : '$name（$reason）';
}

class CoverageEditorState {
  CoverageEditorState({
    required this.rule,
    required List<CoverageOption> startOptions,
    required List<CoverageOption> endOptions,
    required List<CoverageOption> derivedOptions,
    required List<int> indices,
    required this.formula,
    required List<CoverageIssue> issues,
  }) : startOptions = List.unmodifiable(startOptions),
       endOptions = List.unmodifiable(endOptions),
       derivedOptions = List.unmodifiable(derivedOptions),
       indices = List.unmodifiable(indices),
       issues = List.unmodifiable(issues);
  final LengthCoverage rule;
  final List<CoverageOption> startOptions;
  final List<CoverageOption> endOptions;
  final List<CoverageOption> derivedOptions;
  final List<int> indices;
  final String formula;
  final List<CoverageIssue> issues;
}

/// 校验、字段归属与页面解释使用同一份覆盖分析。
class LengthCoverageAnalysis {
  LengthCoverageAnalysis({
    required List<CoverageFieldFacts> fields,
    required List<LengthCoverage> rules,
    required this.enabled,
  }) : fields = List.unmodifiable(fields),
       rules = List.unmodifiable(rules) {
    _inspect();
  }
  final List<CoverageFieldFacts> fields;
  final List<LengthCoverage> rules;
  final bool enabled;
  final List<CoverageIssue> _issues = [];
  List<CoverageIssue> get issues => List.unmodifiable(_issues);
  int _index(String name) =>
      name.isEmpty ? -1 : fields.indexWhere((field) => field.name == name);

  void _inspect() {
    if (!enabled) return;
    if (rules.isEmpty) {
      _issues.add(const CoverageIssue('', 'missingRules', '请为长度字段配置覆盖范围'));
    }
    final sources = <String>{};
    for (final rule in rules) {
      void issue(String code, String message, [String? field]) => _issues.add(
        CoverageIssue(
          rule.lengthField,
          code,
          '长度规则 ${rule.lengthField}：$message',
          fieldName: field,
        ),
      );
      final source = _index(rule.lengthField);
      final first = _index(rule.startField);
      final last = _index(rule.endField);
      final derived = _index(rule.derivedField);
      final hasDerived = rule.derivedField.isNotEmpty;
      for (final name in <String>{
        rule.lengthField,
        rule.startField,
        rule.endField,
        if (hasDerived) rule.derivedField,
      }) {
        if (_index(name) < 0) {
          issue(
            'missingReference',
            '引用字段不存在：${name.isEmpty ? '尚未选择' : name}',
            name,
          );
        }
      }
      if (first >= 0 &&
          last >= 0 &&
          (first > last ||
              (hasDerived &&
                  derived >= 0 &&
                  (derived < first || derived > last)))) {
        issue('range', '起止范围或自动字段无效', rule.derivedField);
      }
      if (!sources.add(rule.lengthField)) {
        issue('duplicateSource', '同一个长度字段只能配置一个范围');
      }
      if (hasDerived && source >= 0 && derived >= 0 && source >= derived) {
        issue('dependency', '长度字段必须位于自动字段之前', rule.derivedField);
      }
      if (source >= 0) {
        final field = fields[source];
        if (field.role != 'length' ||
            field.type != 'uint' ||
            field.fromEnd ||
            field.size == null ||
            field.size! <= 0 ||
            field.size! > 4 ||
            field.fixed) {
          issue('source', '长度来源必须是最多 4 字节的无符号整数字段', field.name);
        }
      }
      if (hasDerived && derived >= 0) {
        final field = fields[derived];
        if (field.type != 'bytes' || !field.canDerive) {
          issue(
            'derived',
            '自动长度字段 ${field.name} 必须为 bytes 类型的数据或跳过字段；uint/sint/float 是固定宽度数值，请改为 bytes 或取消自动长度',
            field.name,
          );
        }
      }
      if (first >= 0 && last >= first) {
        for (final field in fields.sublist(first, last + 1)) {
          if (field.name != rule.derivedField &&
              (field.size == null || field.size! <= 0)) {
            issue('size', '${field.name} 字节数无效', field.name);
          }
        }
      }
    }
    for (var i = 0; i < rules.length; i++) {
      final a = rules[i];
      final aStart = _index(a.startField), aEnd = _index(a.endField);
      if (aStart < 0 || aEnd < aStart) continue;
      for (var j = i + 1; j < rules.length; j++) {
        final b = rules[j];
        final bStart = _index(b.startField), bEnd = _index(b.endField);
        if (bStart < 0 || bEnd < bStart || aStart > bEnd || bStart > aEnd) {
          continue;
        }
        for (final rule in [a, b]) {
          _issues.add(
            CoverageIssue(
              rule.lengthField,
              'overlap',
              '长度规则 ${rule.lengthField}：覆盖范围重叠',
            ),
          );
        }
      }
    }
  }

  CoverageEditorState editor(String source) {
    final rule =
        rules.where((rule) => rule.lengthField == source).firstOrNull ??
        LengthCoverage(lengthField: source, startField: '', endField: '');
    final first = _index(rule.startField),
        last = _index(rule.endField),
        sourceIndex = _index(source);
    List<CoverageOption> options(List<String> candidates, String selected) {
      final result = [for (final name in candidates) CoverageOption(name)];
      if (selected.isNotEmpty && !candidates.contains(selected)) {
        result.add(
          CoverageOption(
            selected,
            reason: _index(selected) < 0 ? '已删除' : '不适用',
          ),
        );
      }
      return result;
    }

    final names = fields
        .map((field) => field.name)
        .where((name) => name.isNotEmpty)
        .toList();
    final candidates = [
      for (var i = 0; i < fields.length; i++)
        if (first >= 0 &&
            i >= first &&
            i <= last &&
            sourceIndex >= 0 &&
            i > sourceIndex &&
            fields[i].name.isNotEmpty &&
            fields[i].canDerive)
          fields[i].name,
    ];
    final indices = [
      if (first >= 0 && last >= first)
        for (var i = first; i <= last; i++) i,
    ];
    final others = [
      for (final i in indices)
        if (fields[i].name != rule.derivedField)
          '${fields[i].name}(${fields[i].size ?? '?'}B)',
    ];
    final formula = first < 0 || last < first
        ? '${rule.derivedField} = $source − 范围待修正'
        : rule.derivedField.isEmpty
        ? '$source = ${others.join(' + ')}（全部定长，无需自动计算）'
        : '${rule.derivedField} = $source${others.isEmpty ? '' : ' − ${others.join(' − ')}'}';
    return CoverageEditorState(
      rule: rule,
      startOptions: options(names, rule.startField),
      endOptions: options(names, rule.endField),
      derivedOptions: options(candidates, rule.derivedField),
      indices: indices,
      formula: formula,
      issues: _issues.where((issue) => issue.lengthField == source).toList(),
    );
  }

  List<LengthCoverage> covering(int index) => enabled
      ? rules
            .where(
              (rule) =>
                  editor(rule.lengthField).indices.contains(index) ||
                  [
                    rule.startField,
                    rule.endField,
                    rule.derivedField,
                  ].contains(fields[index].name),
            )
            .toList()
      : const [];
}
