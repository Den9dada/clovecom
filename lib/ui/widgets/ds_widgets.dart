/// TraeWork 基础组件库：按钮、标签、输入框、卡片等。
///
/// 设计稿中以 `ds-btn`/`ds-tag`/`ds-input`/`ds-table` 等命名，这里以 Flutter
/// 风格重新实现，保持视觉一致性。所有组件颜色、间距、圆角均取自
/// [TraeWorkColors]/[TraeWorkSpacers]/[TraeWorkRadius]。
library;

import 'package:flutter/material.dart';

import '../theme/traework_theme.dart';
import 'ds_dialog.dart';
import 'ds_interaction.dart';
import 'ds_menu_layout.dart';
export 'ds_interaction.dart';
export 'ds_dialog.dart';

/// 命名交互集中管理输入生命周期、空值校验、回车提交和错误反馈。
class DsNameDialog extends StatefulWidget {
  const DsNameDialog({
    super.key,
    required this.title,
    required this.initialName,
    required this.onConfirm,
    this.emptyMessage = '请输入名称',
  });
  final String title;
  final String initialName;
  final ValueChanged<String> onConfirm;
  final String emptyMessage;
  @override
  State<DsNameDialog> createState() => _DsNameDialogState();
}

class _DsNameDialogState extends State<DsNameDialog> {
  late final _controller = TextEditingController(text: widget.initialName);
  String? _error;
  bool _submitted = false;
  void _confirm() {
    if (_submitted) return;
    final name = _controller.text.trim();
    if (name.isEmpty) {
      setState(() => _error = widget.emptyMessage);
      return;
    }
    try {
      widget.onConfirm(name);
      _submitted = true;
      Navigator.of(context).pop();
    } catch (error) {
      setState(() => _error = error.toString());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DsDialog(
    title: Text(widget.title),
    content: DsInput(
      controller: _controller,
      placeholder: '请输入名称',
      expand: true,
      autofocus: true,
      errorText: _error,
      onChanged: (_) {
        if (_error != null) setState(() => _error = null);
      },
      onSubmitted: (_) => _confirm(),
    ),
    actions: [
      DsButton(label: '取消', onPressed: () => Navigator.of(context).pop()),
      DsButton(
        label: '确定',
        variant: DsButtonVariant.brand,
        onPressed: _confirm,
      ),
    ],
  );
}

/// 按钮样式与公共交互状态保持一一对应。
enum DsButtonVariant { brand, secondary, ghost, text, danger }

enum DsButtonSize { sm, md }

class DsButton extends StatelessWidget {
  const DsButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.variant = DsButtonVariant.secondary,
    this.size = DsButtonSize.md,
    this.active = false,
    this.expand = false,
    this.tooltip,
    this.busy = false,
  }) : _iconOnly = false;
  const DsButton.icon({
    super.key,
    required this.icon,
    this.label = '',
    this.onPressed,
    this.variant = DsButtonVariant.ghost,
    this.size = DsButtonSize.md,
    this.active = false,
    this.expand = false,
    this.tooltip,
    this.busy = false,
  }) : _iconOnly = true;
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final DsButtonVariant variant;
  final DsButtonSize size;
  final bool active;
  final bool expand;
  final String? tooltip;
  final bool busy;
  final bool _iconOnly;

  @override
  Widget build(BuildContext context) {
    final height = size == DsButtonSize.sm ? 24.0 : 28.0;
    Widget button = Semantics(
      button: true,
      label: _iconOnly ? (tooltip ?? label) : null,
      child: SizedBox(
        height: height,
        width: expand
            ? double.infinity
            : _iconOnly
            ? height
            : null,
        child: DsInteraction(
          onTap: busy ? null : onPressed,
          selected: active,
          variant: DsInteractionVariant.values.byName(variant.name),
          padding: EdgeInsets.symmetric(
            horizontal: _iconOnly
                ? 0
                : size == DsButtonSize.sm
                ? 8
                : 12,
          ),
          child: Center(
            widthFactor: expand ? null : 1,
            child: Row(
              mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (busy)
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 1.5),
                  )
                else if (icon != null)
                  Icon(icon, size: 14),
                if (!_iconOnly && label.isNotEmpty) ...[
                  if (busy || icon != null) const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: size == DsButtonSize.sm ? 11 : 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    final hint = tooltip ?? (_iconOnly && label.isNotEmpty ? label : null);
    if (hint != null) button = Tooltip(message: hint, child: button);
    return button;
  }
}

/// 标签视觉：与设计稿 `ds-tag--{variant}` 对应。
enum DsTagVariant { neutral, brand, success, warning, error }

/// 设计稿风格的标签徽标。
class DsTag extends StatelessWidget {
  const DsTag({
    super.key,
    required this.label,
    this.variant = DsTagVariant.neutral,
    this.icon,
  });

  final String label;
  final DsTagVariant variant;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final palette = _resolve();
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: TraeWorkSpacers.s6,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: palette.background,
        borderRadius: BorderRadius.circular(TraeWorkRadius.r4),
        border: palette.border ? Border.all(color: Colors.transparent) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 10, color: palette.foreground),
            const SizedBox(width: TraeWorkSpacers.s4),
          ],
          Text(
            label,
            style: traeworkText(
              size: TraeWorkFontSizes.bodyXs,
              color: palette.foreground,
              weight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  _DsTagPalette _resolve() {
    switch (variant) {
      case DsTagVariant.neutral:
        return _DsTagPalette(
          background: TraeWorkColors.bgOverlay2,
          foreground: TraeWorkColors.textSecondary,
          border: false,
        );
      case DsTagVariant.brand:
        return _DsTagPalette(
          background: TraeWorkColors.bgBrandPopup,
          foreground: TraeWorkColors.textBrand,
          border: false,
        );
      case DsTagVariant.success:
        return _DsTagPalette(
          background: const Color(0x1A15A877), // success 10%
          foreground: TraeWorkColors.statusSuccess,
          border: false,
        );
      case DsTagVariant.warning:
        return _DsTagPalette(
          background: const Color(0x1AE27900),
          foreground: TraeWorkColors.statusWarning,
          border: false,
        );
      case DsTagVariant.error:
        return _DsTagPalette(
          background: const Color(0x1AE8463A),
          foreground: TraeWorkColors.statusError,
          border: false,
        );
    }
  }
}

class _DsTagPalette {
  _DsTagPalette({
    required this.background,
    required this.foreground,
    required this.border,
  });
  final Color background;
  final Color foreground;
  final bool border;
}

/// 输入状态由 TextField 与应用 InputDecorationTheme 共同管理。
class DsInput extends StatefulWidget {
  const DsInput({
    super.key,
    this.controller,
    this.initialValue,
    this.placeholder,
    this.keyboardType,
    this.onChanged,
    this.onSubmitted,
    this.enabled = true,
    this.expand = false,
    this.maxLines = 1,
    this.mono = false,
    this.autofocus = false,
    this.suffixIcon,
    this.label,
    this.errorText,
  });
  final TextEditingController? controller;
  final String? initialValue;
  final String? placeholder;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool enabled;
  final bool expand;
  final int? maxLines;
  final bool mono;
  final bool autofocus;
  final Widget? suffixIcon;
  final String? label;
  final String? errorText;
  @override
  State<DsInput> createState() => _DsInputState();
}

class _DsInputState extends State<DsInput> {
  late final TextEditingController _internal = TextEditingController(
    text: widget.initialValue ?? '',
  );
  @override
  void didUpdateWidget(covariant DsInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller == null) {
      if (oldWidget.controller != null) {
        _internal.value = oldWidget.controller!.value;
      } else if (oldWidget.initialValue != widget.initialValue &&
          _internal.text != widget.initialValue) {
        _internal.text = widget.initialValue ?? '';
      }
    }
  }

  @override
  void dispose() {
    _internal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(
      maxWidth: widget.expand ? double.infinity : 240,
      minHeight: 28,
    ),
    child: TextField(
      controller: widget.controller ?? _internal,
      enabled: widget.enabled,
      autofocus: widget.autofocus,
      keyboardType: widget.keyboardType,
      maxLines: widget.maxLines,
      textInputAction: widget.maxLines != 1
          ? TextInputAction.newline
          : TextInputAction.done,
      onSubmitted: widget.onSubmitted,
      onChanged: widget.onChanged,
      style: (widget.mono ? traeworkMono : traeworkText)(
        size: TraeWorkFontSizes.bodyBase,
        color: widget.enabled
            ? TraeWorkColors.textDefault
            : TraeWorkColors.textDisabled,
      ),
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.placeholder,
        errorText: widget.errorText,
        suffixIcon: widget.suffixIcon,
        suffixIconConstraints: const BoxConstraints.tightFor(
          width: 28,
          height: 28,
        ),
        fillColor: widget.enabled
            ? TraeWorkColors.bgBaseDefault
            : TraeWorkColors.bgBaseSecondary,
      ),
      cursorColor: TraeWorkColors.bgBrand,
    ),
  );
}

/// 菜单共用触发器：统一悬停、键盘操作及弹出位置行为。
///
/// 选中框形态（带 [child] 或 [anchorKey]）：菜单在锚点正下方展开且宽度
/// 与锚点一致；纯图标形态同样默认在触发器正下方弹出。
/// 下方空间不足时选择空间更大的一侧，超长菜单限制高度并滚动。
class DsMenuButton<T> extends StatefulWidget {
  const DsMenuButton({
    super.key,
    required this.itemBuilder,
    required this.onSelected,
    this.tooltip,
    this.enabled = true,
    this.constraints,
    this.icon = const Icon(Icons.keyboard_arrow_down_rounded, size: 16),
    this.child,
    this.anchorKey,
  });

  final PopupMenuItemBuilder<T> itemBuilder;
  final ValueChanged<T> onSelected;
  final String? tooltip;
  final bool enabled;

  /// 纯图标触发器的菜单尺寸约束；选中框形态的菜单宽度始终等于锚点宽度。
  final BoxConstraints? constraints;
  final Widget icon;
  final Widget? child;

  /// 外部锚点：触发器本身是附属图标（如输入框右侧下拉箭头）时，用该
  /// key 指向宿主控件（如整个输入框），菜单对齐宿主正下方并等宽。
  final GlobalKey? anchorKey;

  @override
  State<DsMenuButton<T>> createState() => _DsMenuButtonState<T>();
}

class _DsMenuButtonState<T> extends State<DsMenuButton<T>> {
  bool _open = false;

  Future<void> _show() async {
    if (_open || !widget.enabled) return;
    final entries = widget.itemBuilder(context);
    // 菜单打开后页面可能重建；结果仍对应本次构建的条目快照。
    final onSelected = widget.onSelected;
    if (entries.isEmpty) return;
    final overlay =
        Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
    final box = context.findRenderObject()! as RenderBox;
    // 所有菜单锚定触发器或外部宿主，不受鼠标落点影响。
    final anchorObject = widget.anchorKey?.currentContext?.findRenderObject();
    final anchor = anchorObject is RenderBox && anchorObject.hasSize
        ? anchorObject
        : box;
    final selectBox = widget.child != null || widget.anchorKey != null;
    final origin = anchor.localToGlobal(Offset.zero, ancestor: overlay);
    final geometry = DsMenuGeometry(
      anchor: origin & anchor.size,
      bounds: DsMenuGeometry.safeBounds(
        overlay.size,
        MediaQuery.paddingOf(context),
      ),
    );
    var estimate = 16.0;
    for (final entry in entries) {
      estimate += entry.height;
    }
    final menuConstraints =
        (selectBox
                ? BoxConstraints.tightFor(width: anchor.size.width)
                : widget.constraints ?? const BoxConstraints())
            .enforce(
              BoxConstraints(
                maxWidth: geometry.bounds.width,
                maxHeight: geometry.maxHeight,
              ),
            );
    final point = geometry.position(
      Size(
        selectBox
            ? menuConstraints.maxWidth
            : widget.constraints?.hasBoundedWidth == true
            ? menuConstraints.maxWidth
            : 0,
        estimate.clamp(menuConstraints.minHeight, menuConstraints.maxHeight),
      ),
    );
    setState(() => _open = true);
    try {
      final result = await showMenu<T>(
        context: context,
        // 固定优先向右展开，由菜单布局在剩余空间不足时约束到窗口内。
        position: RelativeRect.fromLTRB(
          point.dx,
          point.dy,
          overlay.size.width,
          0,
        ),
        constraints: menuConstraints,
        items: entries,
      );
      if (mounted && widget.enabled && result != null) {
        onSelected(result);
      }
    } finally {
      if (mounted) setState(() => _open = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget button = DsInteraction(
      onTap: widget.enabled ? _show : null,
      variant: widget.child == null
          ? DsInteractionVariant.ghost
          : DsInteractionVariant.secondary,
      selected: _open,
      child:
          widget.child ?? SizedBox(width: 26, height: 26, child: widget.icon),
    );
    if (widget.tooltip != null) {
      button = Tooltip(message: widget.tooltip!, child: button);
    }
    return button;
  }
}

/// 设计稿风格的下拉选择框。
///
/// [groupHeaders] 为 true 时，value 为空串且不可选的项渲染为全宽灰底
/// 分组标题（左侧品牌色竖条 + 加粗小字），用于功能分组的下拉列表。
class DsSelect<T> extends StatelessWidget {
  const DsSelect({
    super.key,
    required this.value,
    required this.items,
    this.onChanged,
    this.enabled = true,
    this.expand = false,
    this.groupHeaders = false,
  });

  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final bool enabled;
  final bool expand;
  final bool groupHeaders;

  @override
  Widget build(BuildContext context) {
    final effectiveEnabled = enabled && onChanged != null;
    return ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: 28,
        maxHeight: 28,
        maxWidth: expand ? double.infinity : 160,
      ),
      child: DsMenuButton<int>(
        enabled: effectiveEnabled,
        itemBuilder: (_) => [
          for (var index = 0; index < items.length; index++)
            if (groupHeaders &&
                items[index].value == '' &&
                !items[index].enabled)
              PopupMenuItem<int>(
                value: index,
                enabled: false,
                padding: EdgeInsets.zero,
                height: 28,
                child: Container(
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    color: TraeWorkColors.bgBaseSecondary,
                    border: Border(
                      left: BorderSide(
                        color: TraeWorkColors.borderBrand,
                        width: 2,
                      ),
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: TraeWorkSpacers.s10,
                    vertical: TraeWorkSpacers.s6,
                  ),
                  child: DefaultTextStyle.merge(
                    style: traeworkText(
                      size: TraeWorkFontSizes.bodySm,
                      color: TraeWorkColors.textSecondary,
                      weight: FontWeight.w600,
                    ),
                    child: items[index].child,
                  ),
                ),
              )
            else
              PopupMenuItem<int>(
                value: index,
                enabled: items[index].enabled,
                child: DefaultTextStyle.merge(
                  style: TextStyle(
                    color: items[index].value == value
                        ? TraeWorkColors.textBrand
                        : null,
                    fontWeight: items[index].value == value
                        ? FontWeight.w600
                        : FontWeight.w400,
                  ),
                  child: items[index].child,
                ),
              ),
        ],
        onSelected: (index) {
          items[index].onTap?.call();
          onChanged?.call(items[index].value);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: TraeWorkSpacers.s10),
          child: Row(
            mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
            children: [
              Flexible(
                fit: expand ? FlexFit.tight : FlexFit.loose,
                child: DefaultTextStyle(
                  style: traeworkText(
                    size: TraeWorkFontSizes.bodyBase,
                    color: effectiveEnabled
                        ? TraeWorkColors.textDefault
                        : TraeWorkColors.textDisabled,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  child:
                      items
                          .where((item) => item.value == value)
                          .firstOrNull
                          ?.child ??
                      const Text('请选择'),
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.keyboard_arrow_down_rounded, size: 16),
            ],
          ),
        ),
      ),
    );
  }
}

/// 卡片容器：浅色背景 + 圆角 + 细边框。
class DsCard extends StatelessWidget {
  const DsCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(TraeWorkSpacers.s12),
    this.background = TraeWorkColors.bgBaseDefault,
    this.border = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color background;
  final bool border;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(TraeWorkRadius.r8),
        border: border
            ? Border.all(color: TraeWorkColors.borderNeutralL1)
            : null,
      ),
      child: child,
    );
  }
}

/// 分隔线：垂直或水平方向。
class DsDivider extends StatelessWidget {
  const DsDivider({super.key, this.vertical = false});
  final bool vertical;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: vertical ? 1 : double.infinity,
      height: vertical ? double.infinity : 1,
      color: TraeWorkColors.borderNeutralL1,
    );
  }
}
