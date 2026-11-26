import 'package:material_ui/material_ui.dart';

import 'theme/terminal_color_schemes.dart';

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
  ColorScheme? colors,
}) {
  final primary = kind == DesktopActionKind.primary;
  final danger = kind == DesktopActionKind.danger;
  final ghost =
      kind == DesktopActionKind.icon || kind == DesktopActionKind.text;
  final height = inline ? 24.0 : 28.0;
  final isDark = colors?.brightness == Brightness.dark;
  final brand = colors?.primary ?? DesktopTokens.brand;
  final onBrand = colors?.onPrimary ?? Colors.white;
  final brandHover = colors != null
      ? Color.lerp(brand, Colors.white, isDark ? 0.14 : 0.12)!
      : DesktopTokens.brandHover;
  final brandPressed = colors != null
      ? Color.lerp(brand, Colors.black, isDark ? 0.16 : 0.14)!
      : DesktopTokens.brandPressed;
  final error = colors?.error ?? DesktopTokens.error;
  final disabledFg = colors != null
      ? colors.onSurface.withValues(alpha: 0.38)
      : DesktopTokens.disabled;
  final disabledBg = colors?.surfaceContainerHigh ?? DesktopTokens.secondary;
  final neutralFg = colors?.onSurface ?? const Color(0xFF404040);
  final selectedBg = colors?.primaryContainer ?? DesktopTokens.selected;
  final selectedFg = colors?.onPrimaryContainer ?? brand;
  final secondaryBg = colors?.surfaceContainerLowest ?? Colors.white;
  final controlBorder = colors?.outline ?? DesktopTokens.controlBorder;
  final subtleBorder = colors?.outlineVariant ?? DesktopTokens.border;
  final hoverOverlay = (colors?.onSurface ?? const Color(0xFF737373))
      .withValues(alpha: isDark ? 0.10 : 0.08);
  final pressOverlay = (colors?.onSurface ?? const Color(0xFF737373))
      .withValues(alpha: isDark ? 0.16 : 0.14);

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
      if (states.contains(WidgetState.disabled)) return disabledFg;
      if (primary) return onBrand;
      if (danger) return error;
      if (states.contains(WidgetState.selected)) return selectedFg;
      if (kind == DesktopActionKind.text) return brand;
      return neutralFg;
    }),
    backgroundColor: WidgetStateProperty.resolveWith((states) {
      states = {...states, if (selected) WidgetState.selected};
      if (states.contains(WidgetState.disabled)) {
        return ghost ? Colors.transparent : disabledBg;
      }
      if (primary) {
        if (states.contains(WidgetState.pressed) ||
            states.contains(WidgetState.selected)) {
          return brandPressed;
        }
        if (states.contains(WidgetState.hovered)) {
          return brandHover;
        }
        return brand;
      }
      if (danger) {
        return error.withValues(
          alpha: states.contains(WidgetState.pressed)
              ? .16
              : states.contains(WidgetState.hovered)
              ? .08
              : .06,
        );
      }
      final base = states.contains(WidgetState.selected)
          ? selectedBg
          : ghost
          ? Colors.transparent
          : secondaryBg;
      if (states.contains(WidgetState.pressed)) {
        return Color.alphaBlend(pressOverlay, base);
      }
      if (states.contains(WidgetState.hovered)) {
        return Color.alphaBlend(hoverOverlay, base);
      }
      return base;
    }),
    overlayColor: const WidgetStatePropertyAll(Colors.transparent),
    side: WidgetStateProperty.resolveWith((states) {
      states = {...states, if (selected) WidgetState.selected};
      if (states.contains(WidgetState.disabled)) {
        return BorderSide(
          color: ghost ? Colors.transparent : subtleBorder,
        );
      }
      if (states.contains(WidgetState.focused)) {
        return BorderSide(color: brand, width: 1.5);
      }
      if (danger) return BorderSide(color: error);
      if (states.contains(WidgetState.selected)) {
        return BorderSide(color: brand);
      }
      if (primary || ghost) return const BorderSide(color: Colors.transparent);
      return BorderSide(
        color:
            states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.pressed)
            ? Color.lerp(controlBorder, neutralFg, 0.35)!
            : controlBorder,
      );
    }),
  );
}

/// 将当前 `TerminalColorScheme` 挂载到 `ThemeData.extensions`，确保全应用与会话终端同帧切换。
class TerminalThemeExtension extends ThemeExtension<TerminalThemeExtension> {
  const TerminalThemeExtension(this.scheme);

  final TerminalColorScheme scheme;

  @override
  TerminalThemeExtension copyWith({TerminalColorScheme? scheme}) =>
      TerminalThemeExtension(scheme ?? this.scheme);

  @override
  TerminalThemeExtension lerp(
    covariant TerminalThemeExtension? other,
    double t,
  ) => t < 0.5 || other == null ? this : other;
}

final Map<String, ThemeData> _desktopThemeCache = {};

ThemeData buildDesktopTheme({TerminalColorScheme? scheme}) {
  final active = scheme ?? defaultTerminalColorScheme;
  return _desktopThemeCache[active.id] ??= _createDesktopTheme(active);
}

ThemeData _createDesktopTheme(TerminalColorScheme active) {
  final isDark = active.isDark;
  final brightness = isDark ? Brightness.dark : Brightness.light;
  final bg = active.background ?? DesktopTokens.background;
  final fg = active.foreground ?? DesktopTokens.text;
  final muted = Color.lerp(fg, bg, 0.36)!;
  final brand = active.tx;
  final onBrand =
      ThemeData.estimateBrightnessForColor(brand) == Brightness.dark
      ? Colors.white
      : const Color(0xFF171717);
  final selectedContainer = brand.withValues(alpha: isDark ? 0.24 : 0.14);
  final onSelectedContainer = isDark
      ? Color.lerp(brand, Colors.white, 0.35)!
      : Color.lerp(brand, Colors.black, 0.2)!;
  final errorColor = active.notice ?? DesktopTokens.error;
  final surfaceLowest = isDark
      ? Color.lerp(bg, Colors.black, 0.14)!
      : Color.lerp(bg, Colors.white, 0.22)!;
  final surfaceElevated = isDark
      ? Color.lerp(bg, Colors.white, 0.05)!
      : Color.lerp(bg, Colors.white, 0.28)!;
  final surfaceLow =
      active.toolbarBackground ??
      (isDark
          ? Color.lerp(bg, Colors.black, 0.14)!
          : Color.lerp(bg, Colors.black, 0.045)!);
  final surfaceContainer = isDark
      ? Color.lerp(bg, Colors.white, 0.035)!
      : Color.lerp(bg, Colors.black, 0.035)!;
  final surfaceHigh = isDark
      ? Color.lerp(bg, Colors.white, 0.07)!
      : Color.lerp(bg, Colors.black, 0.065)!;
  final surfaceHighest = isDark
      ? Color.lerp(bg, Colors.white, 0.11)!
      : Color.lerp(bg, Colors.black, 0.095)!;
  final borderSubtle = fg.withValues(alpha: isDark ? 0.14 : 0.12);
  final borderFloating = fg.withValues(alpha: isDark ? 0.22 : 0.18);
  final controlBorder = Color.lerp(fg, bg, isDark ? 0.56 : 0.62)!;
  final selectionColor = active.selection ?? selectedContainer;
  final tooltipBg = isDark
      ? Color.lerp(bg, Colors.white, 0.16)!
      : const Color(0xFF262626);
  final tooltipFg = isDark ? fg : Colors.white;

  final colorScheme =
      ColorScheme.fromSeed(
        seedColor: brand,
        brightness: brightness,
      ).copyWith(
        primary: brand,
        onPrimary: onBrand,
        secondary: brand,
        onSecondary: onBrand,
        tertiary: active.rx,
        error: errorColor,
        primaryContainer: selectedContainer,
        onPrimaryContainer: onSelectedContainer,
        secondaryContainer: selectedContainer,
        onSecondaryContainer: onSelectedContainer,
        surface: bg,
        surfaceContainerLowest: surfaceLowest,
        surfaceContainerLow: surfaceLow,
        surfaceContainer: surfaceContainer,
        surfaceContainerHigh: surfaceHigh,
        surfaceContainerHighest: surfaceHighest,
        onSurface: fg,
        onSurfaceVariant: muted,
        outline: controlBorder,
        outlineVariant: borderSubtle,
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
          ? surfaceContainer
          : surfaceLowest,
    ),
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    border: border(controlBorder),
    enabledBorder: border(controlBorder),
    focusedBorder: border(brand, 1.5),
    disabledBorder: border(borderSubtle),
    errorBorder: border(errorColor),
    focusedErrorBorder: border(errorColor, 1.5),
    hintStyle: TextStyle(fontSize: 14, color: muted),
    labelStyle: TextStyle(fontSize: 12, color: muted),
    errorStyle: TextStyle(fontSize: 11, color: errorColor),
    errorMaxLines: 3,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: colorScheme,
    extensions: [TerminalThemeExtension(active)],
    fontFamily: 'MiSans',
    fontFamilyFallback: const ['Microsoft YaHei', 'Segoe UI'],
    visualDensity: VisualDensity.compact,
    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    scaffoldBackgroundColor: bg,
    splashFactory: NoSplash.splashFactory,
    textTheme: TextTheme(
      bodyLarge: TextStyle(fontSize: 14, color: fg),
      bodyMedium: TextStyle(fontSize: 12, color: fg),
      bodySmall: TextStyle(fontSize: 11, color: muted),
      titleLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: fg),
      titleMedium: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: fg),
      titleSmall: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg),
      labelLarge: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: fg),
    ),
    iconTheme: IconThemeData(size: 16, color: muted),
    inputDecorationTheme: input,
    dropdownMenuTheme: DropdownMenuThemeData(inputDecorationTheme: input),
    filledButtonTheme: FilledButtonThemeData(
      style: desktopActionStyle(DesktopActionKind.primary, colors: colorScheme),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: desktopActionStyle(DesktopActionKind.primary, colors: colorScheme),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: desktopActionStyle(
        DesktopActionKind.secondary,
        colors: colorScheme,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: desktopActionStyle(DesktopActionKind.text, colors: colorScheme),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: desktopActionStyle(DesktopActionKind.icon, colors: colorScheme)
          .copyWith(
            minimumSize: const WidgetStatePropertyAll(Size(28, 28)),
            padding: const WidgetStatePropertyAll(EdgeInsets.zero),
          ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: desktopActionStyle(
        DesktopActionKind.secondary,
        colors: colorScheme,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: surfaceElevated,
      surfaceTintColor: Colors.transparent,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: borderSubtle),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: surfaceElevated,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: borderFloating),
      ),
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(surfaceElevated),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        side: WidgetStatePropertyAll(BorderSide(color: borderFloating)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: surfaceElevated,
      surfaceTintColor: Colors.transparent,
      elevation: 4,
      textStyle: TextStyle(fontFamily: 'MiSans', fontSize: 14, color: fg),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: borderFloating),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: borderSubtle,
      thickness: 1,
      space: 1,
    ),
    switchTheme: SwitchThemeData(
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled)
            ? surfaceHighest
            : states.contains(WidgetState.selected)
            ? brand
            : controlBorder,
      ),
      thumbColor: WidgetStatePropertyAll(onBrand),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: brand),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: brand,
      selectionColor: selectionColor,
    ),
    dataTableTheme: const DataTableThemeData(
      headingRowHeight: 36,
      dataRowMinHeight: 36,
      dataRowMaxHeight: 36,
      dividerThickness: 1,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: bg,
      foregroundColor: fg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: tooltipBg,
        borderRadius: BorderRadius.circular(4),
      ),
      textStyle: TextStyle(
        fontFamily: 'MiSans',
        fontSize: 11,
        color: tooltipFg,
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
            style: desktopActionStyle(
              kind,
              inline: inline,
              selected: selected,
              colors: Theme.of(context).colorScheme,
            ),
            child: content,
          ),
        ),
      ),
    );
  }
}
