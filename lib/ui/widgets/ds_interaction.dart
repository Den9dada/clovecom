import 'package:flutter/material.dart';

import '../theme/traework_theme.dart';

/// 同类动作共用状态优先级：禁用 > 按下 > 悬停；焦点与选中独立保留。
enum DsInteractionVariant { ghost, secondary, brand, text, danger }

/// 集中绘制交互底色和焦点边框，避免 InkWell 的反馈被不透明内容遮住。
class DsInteraction extends StatefulWidget {
  const DsInteraction({
    super.key,
    required this.child,
    this.onTap,
    this.onTapDown,
    this.onTapCancel,
    this.selected = false,
    this.selectionBorderOnly = false,
    this.variant = DsInteractionVariant.ghost,
    this.borderRadius = const BorderRadius.all(Radius.circular(6)),
    this.padding = EdgeInsets.zero,
    this.focusNode,
  });

  final Widget child;
  final VoidCallback? onTap;
  final GestureTapDownCallback? onTapDown;
  final VoidCallback? onTapCancel;
  final bool selected;

  /// 选中时仅绘制边框，不改变底色和文字色。
  final bool selectionBorderOnly;
  final DsInteractionVariant variant;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry padding;
  final FocusNode? focusNode;

  @override
  State<DsInteraction> createState() => _DsInteractionState();
}

class _DsInteractionState extends State<DsInteraction> {
  bool _hover = false;
  bool _pressed = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final brand = widget.variant == DsInteractionVariant.brand;
    final danger = widget.variant == DsInteractionVariant.danger;
    final secondary = widget.variant == DsInteractionVariant.secondary;
    final foreground = !enabled
        ? TraeWorkColors.textDisabled
        : brand
        ? TraeWorkColors.textOnBrand
        : danger
        ? TraeWorkColors.statusError
        : (widget.selected && !widget.selectionBorderOnly) ||
              widget.variant == DsInteractionVariant.text
        ? TraeWorkColors.textBrand
        : TraeWorkColors.textSecondary;
    final base = brand
        ? (widget.selected
              ? TraeWorkColors.bgBrandActive
              : TraeWorkColors.bgBrand)
        : widget.selected
        ? TraeWorkColors.bgBrandPopup
        : danger
        ? TraeWorkColors.statusError.withValues(alpha: 0.06)
        : secondary
        ? TraeWorkColors.bgBaseDefault
        : Colors.transparent;
    final background = !enabled
        ? (brand || secondary || danger
              ? TraeWorkColors.bgBaseSecondary
              : Colors.transparent)
        : brand
        ? (_pressed
              ? TraeWorkColors.bgBrandActive
              : _hover
              ? TraeWorkColors.bgBrandHover
              : base)
        : Color.alphaBlend(
            _pressed
                ? (danger
                      ? TraeWorkColors.statusError.withValues(alpha: 0.16)
                      : TraeWorkColors.bgOverlay3)
                : _hover
                ? (danger
                      ? TraeWorkColors.statusError.withValues(alpha: 0.08)
                      : TraeWorkColors.bgOverlay2)
                : Colors.transparent,
            base,
          );
    final border = enabled && (_focused || widget.selected)
        ? TraeWorkColors.borderBrand
        : danger && enabled
        ? TraeWorkColors.statusError
        : (secondary || danger) && !enabled
        ? TraeWorkColors.borderNeutralL2
        : secondary
        ? (_hover || _pressed
              ? TraeWorkColors.borderControlHover
              : TraeWorkColors.borderControl)
        : Colors.transparent;
    return Semantics(
      enabled: enabled,
      selected: widget.selected ? true : null,
      // 装饰不占布局尺寸，表格定宽列和紧凑按钮不会被边框挤窄。
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: widget.selected && widget.selectionBorderOnly
              ? Colors.transparent
              : background,
          borderRadius: widget.borderRadius,
          border: Border.all(color: border),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            focusNode: widget.focusNode,
            onTap: widget.onTap,
            onTapDown: enabled ? widget.onTapDown : null,
            onTapCancel: widget.onTapCancel,
            canRequestFocus: enabled,
            mouseCursor: enabled
                ? SystemMouseCursors.click
                : SystemMouseCursors.basic,
            onHover: (value) => setState(() => _hover = value),
            onHighlightChanged: (value) => setState(() => _pressed = value),
            onFocusChange: (value) => setState(() => _focused = value),
            borderRadius: widget.borderRadius,
            overlayColor: const WidgetStatePropertyAll(Colors.transparent),
            child: Padding(
              padding: widget.padding,
              child: IconTheme.merge(
                data: IconThemeData(color: foreground, size: 14),
                child: DefaultTextStyle.merge(
                  style: TextStyle(color: foreground),
                  child: widget.child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 表单布尔选择：整行与文字均可点击，键盘操作与禁用语义共用一处。
class DsSwitch extends StatelessWidget {
  const DsSwitch({
    super.key,
    required this.value,
    this.onChanged,
    this.label,
    this.description,
  });
  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? label;
  final String? description;

  @override
  Widget build(BuildContext context) => Semantics(
    toggled: value,
    child: DsInteraction(
      onTap: onChanged == null ? null : () => onChanged!(!value),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 20,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: onChanged == null
                  ? TraeWorkColors.bgBaseTertiary
                  : value
                  ? TraeWorkColors.bgBrand
                  : TraeWorkColors.borderNeutralL3,
            ),
            child: AnimatedAlign(
              duration: const Duration(milliseconds: 120),
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                margin: const EdgeInsets.all(2),
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: onChanged == null
                      ? TraeWorkColors.bgBaseSecondary
                      : Colors.white,
                ),
              ),
            ),
          ),
          if (label != null) ...[
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label!),
                  if (description != null)
                    Text(description!, style: const TextStyle(fontSize: 11)),
                ],
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

class DsRadioChoice extends StatelessWidget {
  const DsRadioChoice({
    super.key,
    required this.label,
    required this.selected,
    this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    checked: selected,
    inMutuallyExclusiveGroup: true,
    child: DsInteraction(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            selected ? Icons.radio_button_checked : Icons.radio_button_off,
            color: onTap == null
                ? TraeWorkColors.iconDisabled
                : selected
                ? TraeWorkColors.iconBrand
                : TraeWorkColors.iconTertiary,
          ),
          const SizedBox(width: 6),
          Text(label),
        ],
      ),
    ),
  );
}

/// 色点共用选中标记、命中区域和焦点反馈。
class DsColorSwatch extends StatelessWidget {
  const DsColorSwatch({
    super.key,
    required this.argb,
    required this.selected,
    this.onTap,
  });
  final int argb;
  final bool selected;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    label:
        '颜色 #${(argb & 0xffffff).toRadixString(16).padLeft(6, '0').toUpperCase()}',
    button: true,
    child: DsInteraction(
      selected: selected,
      onTap: onTap,
      padding: const EdgeInsets.all(2),
      child: Opacity(
        opacity: onTap == null ? 0.5 : 1,
        child: Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: Color(argb),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: TraeWorkColors.borderNeutralL3),
          ),
          child: selected
              ? Center(
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                )
              : null,
        ),
      ),
    ),
  );
}
