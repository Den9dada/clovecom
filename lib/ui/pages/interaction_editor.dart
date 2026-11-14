import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../protocol_editor.dart';
import '../widgets/ds_toast.dart';
import '../widgets/ds_widgets.dart';
import '../widgets/list_delete_menu.dart';
import '../widgets/lua_api_panel.dart';
import '../theme/traework_theme.dart';
import '../layout/responsive.dart';

/// 与解析协议共用入口，脚本草稿和已载入快照分别管理。
class InteractionEditor extends StatefulWidget {
  const InteractionEditor({super.key, required this.application, this.header});
  final ProtocolLibrary application;
  final Widget? header;
  @override
  State<InteractionEditor> createState() => _InteractionEditorState();
}

class _InteractionEditorState extends State<InteractionEditor> {
  String? _selected;
  final _code = _LuaCodeController();
  final _undo = UndoHistoryController();
  final _find = TextEditingController(), _replace = TextEditingController();
  final _focus = FocusNode();
  final _vertical = ScrollController(), _gutter = ScrollController();
  Timer? _validation;
  bool _changing = false, _busy = false;
  bool _showApi = false;
  double _apiHeightRatio = 0.5;
  bool _showFind = true;
  static const double _minFindWidth = 280;
  double _findWidth = _minFindWidth;
  int _activeLine = 1;
  double? _hoverY;
  InteractionDraft? get draft => widget.application.interactionDrafts
      .where((d) => d.id == _selected)
      .firstOrNull;
  static const fileType = XTypeGroup(label: 'Lua 协议脚本', extensions: ['lua']);

  @override
  void initState() {
    super.initState();
    _code.addListener(_edited);
    _vertical.addListener(() {
      if (_gutter.hasClients) {
        _gutter.jumpTo(
          _vertical.offset.clamp(0, _gutter.position.maxScrollExtent),
        );
      }
      if (_hoverY != null) setState(() {});
    });
  }

  void _edited() {
    if (_changing || draft == null) return;
    final offset = _code.selection.extentOffset.clamp(0, _code.text.length);
    final activeLine =
        '\n'.allMatches(_code.text.substring(0, offset)).length + 1;
    final lineChanged = activeLine != _activeLine;
    _activeLine = activeLine;
    if (draft!.source == _code.text) {
      if (lineChanged) setState(() {});
      return;
    }
    draft!.setSource(_code.text);
    _validation?.cancel();
    _validation = Timer(const Duration(milliseconds: 500), () {
      if (mounted && draft != null) {
        unawaited(widget.application.validateInteraction(draft!.id));
      }
    });
    setState(() {});
  }

  void select(String id) {
    _validation?.cancel();
    _selected = id;
    _activeLine = 1;
    _changing = true;
    _code.value = TextEditingValue(text: draft!.source);
    _changing = false;
    unawaited(widget.application.validateInteraction(id));
    setState(() {});
  }

  Future<void> perform(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      showDsToast('$error', kind: DsToastKind.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> validateCurrent(InteractionDraft current) async {
    _validation?.cancel();
    try {
      final result = await widget.application.validateInteraction(current.id);
      if (!mounted || _selected != current.id) return;
      switch (result.status) {
        case InteractionValidationStatus.superseded:
          showDsToast('本次校验已失效，请查看当前脚本的校验状态', kind: DsToastKind.warning);
        case InteractionValidationStatus.passed:
          showDsToast('校验通过：Lua 语法和脚本头部配置检查通过', kind: DsToastKind.success);
        case InteractionValidationStatus.failed:
          showDsToast(
            '校验未通过：发现 ${result.diagnostics.length} 项问题，详见编辑器下方',
            kind: DsToastKind.error,
          );
      }
    } catch (error) {
      if (mounted) showDsToast('无法校验脚本：$error', kind: DsToastKind.error);
    }
  }

  Future<void> importScript() => perform(() async {
    final file = await openFile(acceptedTypeGroups: [fileType]);
    if (file == null || !mounted) return;
    final source = await file.readAsString();
    final name = file.name.replaceFirst(
      RegExp(r'\.lua$', caseSensitive: false),
      '',
    );
    final created = widget.application.createInteraction(
      name,
      InteractionPurpose.control,
      source: source,
    );
    select(created.id);
  });
  Future<void> exportScript() => perform(() async {
    final value = draft!.build();
    final name = value.name.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_');
    final target = await getSaveLocation(
      suggestedName: '$name.lua',
      acceptedTypeGroups: [fileType],
    );
    if (target != null) {
      await XFile.fromData(utf8.encode(value.source)).saveTo(target.path);
    }
  });
  void findNext() {
    if (_find.text.isEmpty) return;
    var at = _code.text.indexOf(
      _find.text,
      _code.selection.isValid ? _code.selection.end : 0,
    );
    if (at < 0) at = _code.text.indexOf(_find.text);
    if (at >= 0) {
      _code.selection = TextSelection(
        baseOffset: at,
        extentOffset: at + _find.text.length,
      );
      _focus.requestFocus();
    }
  }

  void indent() {
    final selection = _code.selection;
    if (!selection.isValid) return;
    final start = _code.text.lastIndexOf('\n', selection.start - 1) + 1;
    final end = selection.end;
    final text = _code.text.substring(start, end);
    final replacement = '  ${text.replaceAll('\n', '\n  ')}';
    _code.value = TextEditingValue(
      text: _code.text.replaceRange(start, end, replacement),
      selection: TextSelection.collapsed(offset: start + replacement.length),
    );
  }

  void rename([InteractionDraft? target]) {
    final current = target ?? draft;
    if (current == null) return;
    showDialog<void>(
      context: context,
      builder: (_) => DsNameDialog(
        title: '交互协议名称',
        initialName: current.name,
        onConfirm: current.rename,
      ),
    );
  }

  @override
  void dispose() {
    _validation?.cancel();
    _code.dispose();
    _undo.dispose();
    _find.dispose();
    _replace.dispose();
    _focus.dispose();
    _vertical.dispose();
    _gutter.dispose();
    super.dispose();
  }

  Widget _library(
    BuildContext context,
    List<InteractionDraft> scripts,
    InteractionDraft? current,
  ) {
    final width = Responsive.densityOf(context) == AppLayoutDensity.compact
        ? 220.0
        : 260.0;
    return Container(
      width: width,
      decoration: const BoxDecoration(
        color: TraeWorkColors.bgBaseSecondary,
        border: Border(
          right: BorderSide(color: TraeWorkColors.borderNeutralL1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(child: Text('交互协议', style: traeworkText(size: 13))),
                DsMenuButton<InteractionPurpose>(
                  enabled: !_busy,
                  tooltip: '新建脚本',
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: SizedBox(
                      height: 24,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.add, size: 14),
                          const SizedBox(width: 4),
                          Text('新建脚本', style: traeworkText(size: 12)),
                        ],
                      ),
                    ),
                  ),
                  itemBuilder: (_) => [
                    for (final p in InteractionPurpose.values)
                      PopupMenuItem(value: p, child: Text(p.label)),
                  ],
                  onSelected: (p) => select(
                    widget.application.createInteraction('新建${p.label}', p).id,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: DsButton(
                    label: '导入脚本',
                    tooltip: '导入 Lua',
                    icon: Icons.file_upload_outlined,
                    size: DsButtonSize.sm,
                    onPressed: _busy ? null : importScript,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DsButton(
                    label: '导出脚本',
                    tooltip: '导出当前内容',
                    icon: Icons.file_download_outlined,
                    size: DsButtonSize.sm,
                    onPressed: _busy || current == null ? null : exportScript,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                if (scripts.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text('暂无交互协议', style: traeworkText(size: 12)),
                  ),
                for (final d in scripts)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: ListDeleteMenu(
                      onDelete: () => perform(() async {
                        await widget.application.deleteInteraction(d.id);
                        if (_selected == d.id) _selected = null;
                      }),
                      child: DsInteraction(
                        key: ValueKey('interaction-node-${d.id}'),
                        selected: d.id == _selected,
                        onTap: () => select(d.id),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              d.runnable ? Icons.code : Icons.warning_amber,
                              size: 16,
                              color: d.runnable
                                  ? TraeWorkColors.iconTertiary
                                  : TraeWorkColors.statusWarning,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${d.name}${d.isDirty ? ' *' : ''}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: traeworkText(
                                      size: 13,
                                      weight: FontWeight.w500,
                                      color: d.id == _selected
                                          ? TraeWorkColors.textBrand
                                          : TraeWorkColors.textDefault,
                                    ),
                                  ),
                                  Text(
                                    d.validating
                                        ? '校验中'
                                        : d.runnable
                                        ? '可运行'
                                        : '待校验 / 不可运行',
                                    style: traeworkText(
                                      size: 11,
                                      color: TraeWorkColors.textTertiary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            DsButton.icon(
                              icon: Icons.edit_outlined,
                              tooltip: '重命名',
                              size: DsButtonSize.sm,
                              onPressed: _busy ? null : () => rename(d),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _toolbar(InteractionDraft current) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      DsButton(
        label: '保存',
        size: DsButtonSize.sm,
        icon: Icons.save_outlined,
        variant: DsButtonVariant.brand,
        onPressed: _busy
            ? null
            : () =>
                  perform(() => widget.application.saveInteraction(current.id)),
      ),
      const SizedBox(width: 6),
      Tooltip(
        message: '检查 Lua 语法和脚本头部配置，不执行协议流程',
        child: SizedBox(
          key: const ValueKey('interaction-validate-button'),
          width: 72,
          child: DsButton(
            label: '校验',
            icon: Icons.fact_check_outlined,
            busy: current.validating,
            expand: true,
            size: DsButtonSize.sm,
            onPressed: current.validating || _busy
                ? null
                : () => validateCurrent(current),
          ),
        ),
      ),
      const SizedBox(width: 6),
      DsButton(label: '撤销', size: DsButtonSize.sm, onPressed: _undo.undo),
      const SizedBox(width: 6),
      DsButton(label: '重做', size: DsButtonSize.sm, onPressed: _undo.redo),
      const SizedBox(width: 6),
      DsButton.icon(
        icon: Icons.find_replace,
        tooltip: '查找/替换',
        size: DsButtonSize.sm,
        active: _showFind,
        onPressed: () => setState(() => _showFind = !_showFind),
      ),
      const SizedBox(width: 6),
      DsButton(
        label: '接口说明',
        icon: Icons.menu_book_outlined,
        size: DsButtonSize.sm,
        active: _showApi,
        onPressed: () => setState(() => _showApi = !_showApi),
      ),
      const SizedBox(width: 6),
      Text(
        'UTF-8 · Lua 5.4 · 保存后需在使用页重新载入',
        style: traeworkText(size: 11, color: TraeWorkColors.textTertiary),
      ),
    ],
  );

  Widget _findPanel(double maxWidth) => Container(
    key: const ValueKey('interaction-find-panel'),
    decoration: BoxDecoration(
      color: TraeWorkColors.bgBaseDefault.withValues(alpha: 0.97),
      border: Border.all(color: TraeWorkColors.borderNeutralL2),
      borderRadius: BorderRadius.circular(6),
      boxShadow: const [
        BoxShadow(
          color: Color(0x1F000000),
          blurRadius: 12,
          offset: Offset(0, 3),
        ),
      ],
    ),
    child: Stack(
      children: [
        Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: DsInput(
                      controller: _find,
                      placeholder: '查找',
                      expand: true,
                    ),
                  ),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 76,
                    child: DsButton(
                      label: '下一处',
                      size: DsButtonSize.sm,
                      onPressed: findNext,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: DsInput(
                      controller: _replace,
                      placeholder: '替换为',
                      expand: true,
                    ),
                  ),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 76,
                    child: DsButton(
                      label: '全部替换',
                      size: DsButtonSize.sm,
                      onPressed: () {
                        if (_find.text.isNotEmpty) {
                          _code.text = _code.text.replaceAll(
                            _find.text,
                            _replace.text,
                          );
                        }
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: 8,
          child: MouseRegion(
            cursor: SystemMouseCursors.resizeLeftRight,
            child: GestureDetector(
              key: const ValueKey('interaction-find-resize'),
              behavior: HitTestBehavior.opaque,
              onHorizontalDragUpdate: (details) => setState(() {
                final width = _findWidth.clamp(
                  math.min(_minFindWidth, maxWidth),
                  maxWidth,
                );
                _findWidth = (width - details.delta.dx).clamp(
                  math.min(_minFindWidth, maxWidth),
                  maxWidth,
                );
              }),
              child: const Tooltip(
                message: '左右拖动调整宽度',
                child: SizedBox.expand(),
              ),
            ),
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Row(
        children: [
          if (widget.header != null) widget.header!,
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Align(
                alignment: Alignment.centerRight,
                child: draft == null
                    ? const SizedBox(height: 40)
                    : SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: _toolbar(draft!),
                      ),
              ),
            ),
          ),
        ],
      ),
      Expanded(
        child: LayoutBuilder(
          builder: (context, bounds) => Stack(
            key: const ValueKey('interaction-workspace'),
            children: [
              Positioned.fill(child: _workspace(context)),
              if (_showApi)
                Positioned(
                  top: 12,
                  left: 16,
                  right: 16,
                  height: _apiPanelHeight(bounds.maxHeight),
                  child: LuaApiPanel(
                    onClose: () => setState(() => _showApi = false),
                    onResize: (delta) {
                      final available = math.max(0.0, bounds.maxHeight - 28);
                      final maximum = math.max(0.0, available - 80);
                      if (available == 0) return;
                      final height = (_apiPanelHeight(bounds.maxHeight) + delta)
                          .clamp(math.min(200.0, maximum), maximum);
                      setState(() => _apiHeightRatio = height / available);
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    ],
  );
  double _apiPanelHeight(double workspaceHeight) {
    final available = math.max(0.0, workspaceHeight - 28);
    final maximum = math.max(0.0, available - 80);
    return (available * _apiHeightRatio).clamp(
      math.min(200.0, maximum),
      maximum,
    );
  }

  Widget _editorViewport(InteractionDraft current) {
    final lineCount = '\n'.allMatches(_code.text).length + 1;
    final noScrollbars = ScrollConfiguration.of(
      context,
    ).copyWith(scrollbars: false);
    return Padding(
      padding: const EdgeInsets.all(8),
      child: ListenableBuilder(
        listenable: _focus,
        builder: (context, child) => DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(
              color: _focus.hasFocus
                  ? TraeWorkColors.borderBrand
                  : TraeWorkColors.borderControl,
            ),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Padding(padding: const EdgeInsets.all(1), child: child),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: math.max(45, '$lineCount'.length * 8.5 + 16),
              decoration: const BoxDecoration(
                border: Border(
                  right: BorderSide(color: TraeWorkColors.borderNeutralL1),
                ),
              ),
              child: ScrollConfiguration(
                behavior: noScrollbars,
                child: SingleChildScrollView(
                  controller: _gutter,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                  child: Text.rich(
                    TextSpan(
                      children: List.generate(
                        lineCount,
                        (i) => TextSpan(
                          text: '${i + 1}${i < lineCount - 1 ? '\n' : ''}',
                          style: i + 1 == _activeLine
                              ? const TextStyle(
                                  color: TraeWorkColors.textBrand,
                                  fontWeight: FontWeight.w600,
                                  backgroundColor: TraeWorkColors.bgBrandPopup,
                                )
                              : null,
                        ),
                      ),
                    ),
                    key: const ValueKey('interaction-line-numbers'),
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontFamily: 'Consolas',
                      fontSize: 14,
                      height: 1.5,
                      color: TraeWorkColors.textTertiary,
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: Scrollbar(
                controller: _vertical,
                thumbVisibility: true,
                scrollbarOrientation: ScrollbarOrientation.right,
                notificationPredicate: (notification) =>
                    notification.metrics.axis == Axis.vertical,
                child: Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: LayoutBuilder(
                    builder: (context, constraints) => SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: math.max(
                          constraints.maxWidth,
                          _code.text
                                      .split('\n')
                                      .fold<int>(
                                        0,
                                        (a, b) => math.max(a, b.length),
                                      ) *
                                  8.5 +
                              24,
                        ),
                        height: constraints.maxHeight,
                        child: _hoverableCode(
                          CallbackShortcuts(
                            bindings: {
                              const SingleActivator(LogicalKeyboardKey.tab):
                                  indent,
                            },
                            child: ScrollConfiguration(
                              behavior: noScrollbars,
                              child: TextField(
                                key: ValueKey(current.id),
                                controller: _code,
                                undoController: _undo,
                                focusNode: _focus,
                                scrollController: _vertical,
                                inputFormatters: [_LuaIndentFormatter()],
                                expands: true,
                                minLines: null,
                                maxLines: null,
                                keyboardType: TextInputType.multiline,
                                style: const TextStyle(
                                  fontFamily: 'Consolas',
                                  fontSize: 14,
                                  height: 1.5,
                                ),
                                decoration: const InputDecoration(
                                  filled: false,
                                  hoverColor: Colors.transparent,
                                  isCollapsed: true,
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  contentPadding: EdgeInsets.all(8),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _hoverableCode(Widget child) {
    final metrics = TextPainter(
      text: const TextSpan(
        text: ' ',
        style: TextStyle(fontFamily: 'Consolas', fontSize: 14, height: 1.5),
      ),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final lineHeight = metrics.height;
    metrics.dispose();
    final scrollOffset = _vertical.hasClients ? _vertical.offset : 0.0;
    final line = _hoverY == null
        ? -1
        : ((_hoverY! - 8 + scrollOffset) / lineHeight).floor();
    final lineCount = '\n'.allMatches(_code.text).length + 1;
    return MouseRegion(
      key: const ValueKey('interaction-code-hover'),
      onHover: (event) => setState(() => _hoverY = event.localPosition.dy),
      onExit: (_) => setState(() => _hoverY = null),
      child: ClipRect(
        child: Stack(
          children: [
            if (line >= 0 && line < lineCount)
              Positioned(
                top: 8 + line * lineHeight - scrollOffset,
                left: 0,
                right: 0,
                height: lineHeight,
                child: const IgnorePointer(
                  child: ColoredBox(
                    key: ValueKey('interaction-hover-line'),
                    color: TraeWorkColors.bgOverlay1,
                  ),
                ),
              ),
            Positioned.fill(child: child),
          ],
        ),
      ),
    );
  }

  Widget _workspace(BuildContext context) {
    final scripts = widget.application.interactionDrafts;
    final current = draft;
    return Row(
      children: [
        _library(context, scripts, current),
        const VerticalDivider(width: 1),
        Expanded(
          child: current == null
              ? const Center(child: Text('选择、新建或导入交互协议脚本'))
              : Column(
                  children: [
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) => Stack(
                          children: [
                            Positioned.fill(child: _editorViewport(current)),
                            if (_showFind)
                              Positioned(
                                top: 12,
                                right: 12,
                                width: _findWidth.clamp(
                                  math.min(
                                    _minFindWidth,
                                    math.max(0, constraints.maxWidth - 80),
                                  ),
                                  math.max(0, constraints.maxWidth - 80),
                                ),
                                child: _findPanel(
                                  math.max(0, constraints.maxWidth - 80),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    if (current.diagnostics.isNotEmpty)
                      SizedBox(
                        height: 100,
                        child: ListView(
                          children: [
                            for (final error in current.diagnostics)
                              DsInteraction(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                child: Text(
                                  '$error',
                                  style: const TextStyle(
                                    color: TraeWorkColors.statusError,
                                  ),
                                ),
                                onTap: () {
                                  var at = 0;
                                  for (var i = 1; i < (error.line ?? 1); i++) {
                                    final next = _code.text.indexOf('\n', at);
                                    if (next < 0) break;
                                    at = next + 1;
                                  }
                                  _code.selection = TextSelection.collapsed(
                                    offset: at,
                                  );
                                  _focus.requestFocus();
                                },
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _LuaIndentFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final end = newValue.selection.extentOffset;
    if (newValue.text.length != oldValue.text.length + 1 ||
        end < 1 ||
        newValue.text[end - 1] != '\n' ||
        !newValue.composing.isCollapsed) {
      return newValue;
    }
    final previousStart =
        oldValue.text.lastIndexOf('\n', math.max(0, end - 2)) + 1;
    final prefix = oldValue.text.substring(
      previousStart,
      math.min(end - 1, oldValue.text.length),
    );
    var indentation = RegExp(r'^\s*').stringMatch(prefix) ?? '';
    if (RegExp(r'\b(then|do|function.*\))\s*$').hasMatch(prefix)) {
      indentation += '  ';
    }
    return newValue.copyWith(
      text: newValue.text.replaceRange(end, end, indentation),
      selection: TextSelection.collapsed(offset: end + indentation.length),
    );
  }
}

class _LuaCodeController extends TextEditingController {
  static final _tokens = RegExp(
    r'''--\[\[[\s\S]*?\]\]|--[^\n]*|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|\b(?:local|function|end|if|then|else|elseif|for|while|do|return|break|repeat|until|in|and|or|not|nil|true|false)\b|\b\d+(?:\.\d+)?\b''',
  );
  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final spans = <TextSpan>[];
    var offset = 0;
    for (final match in _tokens.allMatches(text)) {
      spans.add(TextSpan(text: text.substring(offset, match.start)));
      final token = match.group(0)!;
      final color = token.startsWith('--')
          ? Colors.green
          : token.startsWith('"') || token.startsWith("'")
          ? Colors.orange
          : Colors.blue;
      spans.add(
        TextSpan(
          text: token,
          style: TextStyle(color: color),
        ),
      );
      offset = match.end;
    }
    spans.add(TextSpan(text: text.substring(offset)));
    return TextSpan(style: style, children: spans);
  }
}
