import 'package:flutter/material.dart';

/// 桌面语义令牌；透明叠加色保持参考规范的 ARGB 顺序。
abstract final class DesktopTokens {
  static const brand = Color(0xFF4B3FE3);
  static const brandHover = Color(0xFF6A6FFF);
  static const brandPressed = Color(0xFF3F31C6);
  static const selected = Color(0x5CAAB7FF);
  static const background = Color(0xFFFFFFFF);
  static const secondary = Color(0xFFF5F5F5);
  static const text = Color(0xFF171717);
  static const muted = Color(0xFF737373);
  static const disabled = Color(0xFFA1A1A1);
  static const border = Color(0x1F737373);
  static const floatingBorder = Color(0x2E737373);
  static const controlBorder = Color(0xFFB3B3B3);
  static const success = Color(0xFF15A877);
  static const warning = Color(0xFFE27900);
  static const error = Color(0xFFE8463A);
  static const monoFamily = 'Consolas';
  static const monoFallback = ['Menlo', 'Courier New', 'MiSans'];
}

enum DesktopActionKind { primary, secondary, icon, text, danger }

/// 所有动作共用状态优先级，危险动作选中仍保持危险语义。
ButtonStyle desktopActionStyle(
  DesktopActionKind kind, {
  bool inline = false,
  bool selected = false,
}) {
  final primary = kind == DesktopActionKind.primary;
  final danger = kind == DesktopActionKind.danger;
  final ghost =
      kind == DesktopActionKind.icon || kind == DesktopActionKind.text;
  final height = inline ? 24.0 : 28.0;
  return ButtonStyle(
    visualDensity: VisualDensity.standard,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    minimumSize: WidgetStatePropertyAll(Size(0, height)),
    maximumSize: WidgetStatePropertyAll(Size(double.infinity, height)),
    padding: WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: inline ? 8 : 12),
    ),
    textStyle: WidgetStatePropertyAll(
      TextStyle(
        fontFamily: 'MiSans',
        fontSize: inline ? 11 : 12,
        fontWeight: FontWeight.w500,
      ),
    ),
    iconSize: const WidgetStatePropertyAll(14),
    elevation: const WidgetStatePropertyAll(0),
    surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
    animationDuration: const Duration(milliseconds: 120),
    shape: const WidgetStatePropertyAll(
      RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(6)),
      ),
    ),
    foregroundColor: WidgetStateProperty.resolveWith((states) {
      states = {...states, if (selected) WidgetState.selected};
      if (states.contains(WidgetState.disabled)) return DesktopTokens.disabled;
      if (primary) return Colors.white;
      if (danger) return DesktopTokens.error;
      if (states.contains(WidgetState.selected) ||
          kind == DesktopActionKind.text) {
        return DesktopTokens.brand;
      }
      return const Color(0xFF404040);
    }),
    backgroundColor: WidgetStateProperty.resolveWith((states) {
      states = {...states, if (selected) WidgetState.selected};
      if (states.contains(WidgetState.disabled)) {
        return ghost ? Colors.transparent : DesktopTokens.secondary;
      }
      if (primary) {
        if (states.contains(WidgetState.pressed) ||
            states.contains(WidgetState.selected)) {
          return DesktopTokens.brandPressed;
        }
        if (states.contains(WidgetState.hovered)) {
          return DesktopTokens.brandHover;
        }
        return DesktopTokens.brand;
      }
      if (danger) {
        return DesktopTokens.error.withValues(
          alpha: states.contains(WidgetState.pressed)
              ? .16
              : states.contains(WidgetState.hovered)
              ? .08
              : .06,
        );
      }
      final base = states.contains(WidgetState.selected)
          ? DesktopTokens.selected
          : ghost
          ? Colors.transparent
          : Colors.white;
      if (states.contains(WidgetState.pressed)) {
        return Color.alphaBlend(const Color(0x29737373), base);
      }
      if (states.contains(WidgetState.hovered)) {
        return Color.alphaBlend(const Color(0x1F737373), base);
      }
      return base;
    }),
    overlayColor: const WidgetStatePropertyAll(Colors.transparent),
    side: WidgetStateProperty.resolveWith((states) {
      states = {...states, if (selected) WidgetState.selected};
      if (states.contains(WidgetState.disabled)) {
        return BorderSide(
          color: ghost ? Colors.transparent : DesktopTokens.border,
        );
      }
      if (states.contains(WidgetState.focused)) {
        return const BorderSide(color: DesktopTokens.brand, width: 1.5);
      }
      if (danger) return const BorderSide(color: DesktopTokens.error);
      if (states.contains(WidgetState.selected)) {
        return const BorderSide(color: DesktopTokens.brand);
      }
      if (primary || ghost) return const BorderSide(color: Colors.transparent);
      return BorderSide(
        color:
            states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.pressed)
            ? const Color(0xFF858585)
            : DesktopTokens.controlBorder,
      );
    }),
  );
}

ThemeData buildDesktopTheme() {
  final scheme =
      ColorScheme.fromSeed(
        seedColor: DesktopTokens.brand,
        brightness: Brightness.light,
      ).copyWith(
        primary: DesktopTokens.brand,
        secondary: DesktopTokens.brand,
        tertiary: DesktopTokens.success,
        error: DesktopTokens.error,
        primaryContainer: DesktopTokens.selected,
        onPrimaryContainer: DesktopTokens.brand,
        secondaryContainer: DesktopTokens.selected,
        onSecondaryContainer: DesktopTokens.brand,
        surface: Colors.white,
        surfaceContainerLowest: Colors.white,
        surfaceContainerLow: DesktopTokens.secondary,
        surfaceContainer: DesktopTokens.secondary,
        surfaceContainerHigh: DesktopTokens.secondary,
        surfaceContainerHighest: const Color(0xFFE5E5E5),
        onSurface: DesktopTokens.text,
        onSurfaceVariant: DesktopTokens.muted,
        outline: DesktopTokens.controlBorder,
        outlineVariant: DesktopTokens.border,
      );
  OutlineInputBorder border(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: color, width: width),
      );
  final input = InputDecorationTheme(
    filled: true,
    fillColor: WidgetStateColor.resolveWith(
      (states) => states.contains(WidgetState.disabled)
          ? DesktopTokens.secondary
          : Colors.white,
    ),
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    border: border(DesktopTokens.controlBorder),
    enabledBorder: border(DesktopTokens.controlBorder),
    focusedBorder: border(DesktopTokens.brand, 1.5),
    disabledBorder: border(DesktopTokens.border),
    errorBorder: border(DesktopTokens.error),
    focusedErrorBorder: border(DesktopTokens.error, 1.5),
    hintStyle: const TextStyle(fontSize: 14, color: DesktopTokens.muted),
    labelStyle: const TextStyle(fontSize: 12, color: DesktopTokens.muted),
    errorStyle: const TextStyle(fontSize: 11, color: DesktopTokens.error),
    errorMaxLines: 3,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: scheme,
    fontFamily: 'MiSans',
    fontFamilyFallback: const ['Microsoft YaHei', 'Segoe UI'],
    visualDensity: VisualDensity.compact,
    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    scaffoldBackgroundColor: Colors.white,
    splashFactory: NoSplash.splashFactory,
    textTheme: const TextTheme(
      bodyLarge: TextStyle(fontSize: 14),
      bodyMedium: TextStyle(fontSize: 12),
      bodySmall: TextStyle(fontSize: 11),
      titleLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      titleMedium: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      titleSmall: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      labelLarge: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
    ),
    iconTheme: const IconThemeData(size: 16, color: Color(0xFF404040)),
    inputDecorationTheme: input,
    dropdownMenuTheme: DropdownMenuThemeData(inputDecorationTheme: input),
    filledButtonTheme: FilledButtonThemeData(
      style: desktopActionStyle(DesktopActionKind.primary),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: desktopActionStyle(DesktopActionKind.primary),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: desktopActionStyle(DesktopActionKind.secondary),
    ),
    textButtonTheme: TextButtonThemeData(
      style: desktopActionStyle(DesktopActionKind.text),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: desktopActionStyle(DesktopActionKind.icon).copyWith(
        minimumSize: const WidgetStatePropertyAll(Size(28, 28)),
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: desktopActionStyle(DesktopActionKind.secondary),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: DesktopTokens.border),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: DesktopTokens.floatingBorder),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 4,
      textStyle: const TextStyle(
        fontFamily: 'MiSans',
        fontSize: 14,
        color: DesktopTokens.text,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: DesktopTokens.floatingBorder),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: DesktopTokens.border,
      thickness: 1,
      space: 1,
    ),
    switchTheme: SwitchThemeData(
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled)
            ? const Color(0xFFE5E5E5)
            : states.contains(WidgetState.selected)
            ? DesktopTokens.brand
            : DesktopTokens.controlBorder,
      ),
      thumbColor: const WidgetStatePropertyAll(Colors.white),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: DesktopTokens.brand,
    ),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: DesktopTokens.brand,
      selectionColor: DesktopTokens.selected,
    ),
    dataTableTheme: const DataTableThemeData(
      headingRowHeight: 36,
      dataRowMinHeight: 36,
      dataRowMaxHeight: 36,
      dividerThickness: 1,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    tooltipTheme: const TooltipThemeData(
      textStyle: TextStyle(
        fontFamily: 'MiSans',
        fontSize: 11,
        color: Colors.white,
      ),
    ),
  );
}

/// 图标动作必须提供名称；忙碌时替代图标并阻止重复提交。
class DesktopAction extends StatelessWidget {
  const DesktopAction({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.kind = DesktopActionKind.secondary,
    this.inline = false,
    this.busy = false,
    this.selected = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final DesktopActionKind kind;
  final bool inline, busy, selected;
  @override
  Widget build(BuildContext context) {
    final height = inline ? 24.0 : 28.0;
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (busy)
          const SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 1.5),
          )
        else if (icon != null)
          Icon(icon, size: 14),
        if (kind != DesktopActionKind.icon) ...[
          if (icon != null || busy) const SizedBox(width: 6),
          Text(label),
        ],
      ],
    );
    return Semantics(
      label: label,
      button: true,
      selected: selected,
      enabled: !busy && onPressed != null,
      child: Tooltip(
        message: busy ? '$label：正在处理' : label,
        child: SizedBox(
          height: height,
          width: kind == DesktopActionKind.icon ? height : null,
          child: TextButton(
            onPressed: busy ? null : onPressed,
            statesController: null,
            style: desktopActionStyle(kind, inline: inline, selected: selected),
            child: content,
          ),
        ),
      ),
    );
  }
}
