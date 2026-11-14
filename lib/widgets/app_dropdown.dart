import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 全局菜单锚点：优先紧贴控件下沿，空间不足时由框架翻转和避让。
class AppPopupMenuButton<T> extends StatefulWidget {
  const AppPopupMenuButton({
    super.key,
    required this.itemBuilder,
    this.onSelected,
    this.initialValue,
    this.child,
    this.icon,
    this.tooltip,
    this.enabled = true,
    this.menuMaxHeight = 320,
    this.menuWidth,
    this.color,
    this.borderRadius,
    this.anchorBuilder,
  });

  final PopupMenuItemBuilder<T> itemBuilder;
  final ValueChanged<T>? onSelected;
  final T? initialValue;
  final Widget? child;
  final Widget? icon;
  final String? tooltip;
  final bool enabled;
  final double menuMaxHeight;
  final double? menuWidth;
  final Color? color;
  final BorderRadius? borderRadius;
  final Widget Function(BuildContext, VoidCallback, FocusNode)? anchorBuilder;

  @override
  State<AppPopupMenuButton<T>> createState() => _AppPopupMenuButtonState<T>();
}

class _AppPopupMenuButtonState<T> extends State<AppPopupMenuButton<T>> {
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final itemBuilder = widget.itemBuilder;
    final onSelected = widget.onSelected;
    final initialValue = widget.initialValue;
    final child = widget.child;
    final icon = widget.icon;
    final tooltip = widget.tooltip;
    final enabled = widget.enabled;
    final menuMaxHeight = widget.menuMaxHeight;
    final menuWidth = widget.menuWidth;
    final color = widget.color;
    final borderRadius = widget.borderRadius;
    final theme = Theme.of(context);
    // 固定选择框的语义边界，避免弹出层开关时重用父级合并的语义节点。
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: MenuAnchor(
        childFocusNode: _focusNode,
        consumeOutsideTap: true,
        style: MenuStyle(
          alignment: AlignmentDirectional.bottomStart,
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(vertical: 8),
          ),
          maximumSize: WidgetStatePropertyAll(
            Size(menuWidth ?? double.infinity, menuMaxHeight),
          ),
          minimumSize: WidgetStatePropertyAll(Size(menuWidth ?? 0, 0)),
          backgroundColor: WidgetStatePropertyAll(
            color ?? theme.popupMenuTheme.color,
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: borderRadius ?? BorderRadius.circular(8),
            ),
          ),
        ),
        menuChildren: itemBuilder(context).map((entry) {
          if (entry is PopupMenuDivider) return const Divider(height: 16);
          final item = entry as PopupMenuItem<T>;
          return MenuItemButton(
            style: ButtonStyle(
              minimumSize: WidgetStatePropertyAll(
                Size(menuWidth ?? 0, item.height),
              ),
              backgroundColor: item.value == initialValue
                  ? WidgetStatePropertyAll(theme.colorScheme.primaryContainer)
                  : null,
            ),
            onPressed: item.enabled
                ? () {
                    item.onTap?.call();
                    final value = item.value;
                    if (value != null) onSelected?.call(value);
                  }
                : null,
            child: item.child ?? const SizedBox.shrink(),
          );
        }).toList(),
        builder: (context, controller, _) {
          void toggle() {
            _focusNode.requestFocus();
            controller.isOpen ? controller.close() : controller.open();
          }

          final Widget button;
          if (widget.anchorBuilder != null) {
            button = widget.anchorBuilder!(context, toggle, _focusNode);
          } else if (child == null) {
            button = IconButton(
              focusNode: _focusNode,
              tooltip: tooltip,
              onPressed: enabled ? toggle : null,
              icon: icon ?? const Icon(Icons.more_vert),
            );
          } else {
            button = Tooltip(
              message: tooltip ?? '',
              child: TextButton(
                focusNode: _focusNode,
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  maximumSize: const Size(double.infinity, double.infinity),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                onPressed: enabled ? toggle : null,
                child: child,
              ),
            );
          }
          return CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.escape):
                  controller.close,
            },
            child: button,
          );
        },
      ),
    );
  }
}

/// 保留输入框装饰与受控选择值，弹出层统一使用菜单锚点。
class AppDropdownFormField<T> extends StatelessWidget {
  const AppDropdownFormField({
    super.key,
    this.value,
    this.initialValue,
    required this.items,
    required this.onChanged,
    this.decoration = const InputDecoration(),
    this.style,
    this.dropdownColor,
    this.borderRadius,
    this.menuMaxHeight = 320,
    this.iconEnabledColor,
    this.isExpanded = true,
  });

  final T? value;
  final T? initialValue;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final InputDecoration decoration;
  final TextStyle? style;
  final Color? dropdownColor;
  final BorderRadius? borderRadius;
  final double menuMaxHeight;
  final Color? iconEnabledColor;
  final bool isExpanded;

  @override
  Widget build(BuildContext context) {
    final selected = value ?? initialValue;
    final matches = items.where((item) => item.value == selected);
    final label = matches.isEmpty
        ? const SizedBox.shrink()
        : matches.first.child;
    return LayoutBuilder(
      builder: (context, constraints) {
        return AppPopupMenuButton<T>(
          enabled: onChanged != null && items.isNotEmpty,
          initialValue: selected,
          onSelected: onChanged,
          menuWidth: constraints.hasBoundedWidth ? constraints.maxWidth : null,
          menuMaxHeight: menuMaxHeight,
          color: dropdownColor,
          borderRadius: borderRadius,
          itemBuilder: (_) => items
              .map(
                (item) => PopupMenuItem<T>(
                  value: item.value,
                  enabled: item.enabled,
                  onTap: item.onTap,
                  child: DefaultTextStyle.merge(
                    style: style,
                    child: item.child,
                  ),
                ),
              )
              .toList(),
          // 选择框自行绘制唯一边框，避免操作按钮的焦点边框套在输入框外侧。
          anchorBuilder: (context, toggle, focusNode) {
            final enabled = onChanged != null && items.isNotEmpty;
            final configuredHeight = decoration.constraints?.maxHeight;
            final height = configuredHeight != null && configuredHeight.isFinite
                ? configuredHeight
                : 32.0;
            return SizedBox(
              height: constraints.hasBoundedHeight
                  ? height.clamp(0.0, constraints.maxHeight)
                  : height,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  focusNode: focusNode,
                  canRequestFocus: enabled,
                  onTap: enabled ? toggle : null,
                  borderRadius: BorderRadius.circular(6),
                  focusColor: Colors.transparent,
                  child: ListenableBuilder(
                    listenable: focusNode,
                    builder: (context, _) => InputDecorator(
                      expands: true,
                      isFocused: focusNode.hasFocus,
                      decoration: decoration.copyWith(
                        enabled: enabled,
                        visualDensity:
                            decoration.visualDensity ?? VisualDensity.standard,
                      ),
                      isEmpty: matches.isEmpty,
                      child: DefaultTextStyle.merge(
                        style: style ?? Theme.of(context).textTheme.bodyMedium,
                        child: Row(
                          children: [
                            Expanded(child: label),
                            Icon(
                              Icons.arrow_drop_down,
                              color: enabled
                                  ? iconEnabledColor
                                  : Theme.of(context).disabledColor,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
