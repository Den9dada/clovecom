// 公开具名参数映射到私有字段，不能使用初始化形参。
// ignore_for_file: prefer_initializing_formals
import '../core/interaction_protocol.dart';

enum InteractionValidationStatus { passed, failed, superseded }

/// 单次校验的完成事实；失效请求不向调用者交付旧诊断。
class InteractionValidationResult {
  InteractionValidationResult(
    this.status, {
    List<ScriptDiagnostic> diagnostics = const [],
  }) : diagnostics = List.unmodifiable(diagnostics);

  final InteractionValidationStatus status;
  final List<ScriptDiagnostic> diagnostics;
}

/// 草稿可持久化错误代码，校验状态与内容版本分别管理。
class InteractionDraft {
  InteractionDraft(
    InteractionProtocol protocol, {
    this.onChanged,
    bool isNew = false,
  }) : _saved = protocol,
       _source = protocol.source,
       _name = protocol.name,
       _isNew = isNew;

  final void Function()? onChanged;
  InteractionProtocol _saved;
  String _source;
  String _name;
  bool _isNew;
  int _revision = 0;
  String? _validatedSource;
  Object? _validationRequest;
  bool _validating = false;
  List<ScriptDiagnostic> _diagnostics = const [];
  bool get validating => _validating;
  List<ScriptDiagnostic> get diagnostics => _diagnostics;
  String get id => _saved.id;
  String get name => _name;
  String get source => _source;
  int get revision => _revision;
  bool get isDirty =>
      _isNew || _source != _saved.source || _name != _saved.name;
  bool get runnable =>
      _validatedSource == source && !validating && diagnostics.isEmpty;

  void setSource(String value) {
    if (value == _source) return;
    _source = value;
    _revision++;
    _invalidateValidation();
    onChanged?.call();
  }

  void rename(String value) {
    if (value.trim().isEmpty) throw const FormatException('名称不能为空');
    _name = value.trim();
    _revision++;
    onChanged?.call();
  }

  InteractionProtocol build() =>
      InteractionProtocol(id: id, name: name, source: source);

  void acceptSaved(InteractionProtocol value, int revision) {
    _saved = value;
    _isNew = false;
    if (_revision == revision) {
      if (_source != value.source) _invalidateValidation();
      _source = value.source;
      _name = value.name;
    }
    onChanged?.call();
  }

  void discard() {
    _source = _saved.source;
    _name = _saved.name;
    _revision++;
    _invalidateValidation();
    onChanged?.call();
  }

  /// 每次调用都是新请求；即使文本相同，较早请求也不能覆盖后发请求。
  Future<InteractionValidationResult> validate(
    Future<List<ScriptDiagnostic>> Function(InteractionProtocol) check,
  ) async {
    final request = Object();
    final checkedSource = source, checkedName = name;
    _validationRequest = request;
    _validating = true;
    _validatedSource = null;
    _diagnostics = const [];
    onChanged?.call();
    List<ScriptDiagnostic> result;
    try {
      result = await check(
        InteractionProtocol(id: id, name: checkedName, source: checkedSource),
      );
    } catch (error) {
      result = [ScriptDiagnostic('$error')];
    }
    if (!identical(_validationRequest, request)) {
      return InteractionValidationResult(
        InteractionValidationStatus.superseded,
      );
    }
    _validatedSource = checkedSource;
    _diagnostics = List.unmodifiable(result);
    _validating = false;
    onChanged?.call();
    return InteractionValidationResult(
      result.isEmpty
          ? InteractionValidationStatus.passed
          : InteractionValidationStatus.failed,
      diagnostics: result,
    );
  }

  /// 草稿被删除或应用关闭后，迟到结果不得再发布状态。
  void invalidateValidation() {
    _invalidateValidation();
    onChanged?.call();
  }

  void _invalidateValidation() {
    _validationRequest = null;
    _validating = false;
    _validatedSource = null;
    _diagnostics = const [];
  }
}
