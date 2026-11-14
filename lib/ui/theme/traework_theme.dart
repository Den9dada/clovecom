/// TraeWork 设计令牌：颜色、间距、字号、圆角。
///
/// 来自 `.design/clovertls-ui/colors_and_type-draft.css` 的 light-only token。
/// 仅在 lib/ui 下使用，避免后端 lib/src 模块依赖 Flutter。
library;

import 'package:flutter/material.dart';



/// TraeWork 颜色常量。所有颜色按设计稿 light-only 令牌取值。
class TraeWorkColors {
  TraeWorkColors._();

  // 背景
  static const Color bgBaseDefault = Color(0xFFFFFFFF);
  static const Color bgBaseSecondary = Color(0xFFF5F5F5);
  static const Color bgBaseTertiary = Color(0xFFE5E5E5);
  static const Color bgOverlay1 = Color(0x14737373); // rgba(115,115,115,0.08)
  static const Color bgOverlay2 = Color(0x1F737373); // rgba(115,115,115,0.12)
  static const Color bgOverlay3 = Color(0x29737373); // rgba(115,115,115,0.16)
  static const Color bgOverlay4 = Color(0x33737373); // rgba(115,115,115,0.20)
  static const Color bgInvert = Color(0xFF262626);
  static const Color bgInvertHover = Color(0xFF404040);
  static const Color bgInvertActive = Color(0xFF171717);

  // 品牌主色
  static const Color bgBrand = Color(0xFF4B3FE3);
  static const Color bgBrandHover = Color(0xFF6A6FFF);
  static const Color bgBrandActive = Color(0xFF3F31C6);
  static const Color bgBrandDisabled = Color(
    0x384B3FE3,
  ); // rgba(75,63,227,0.22)
  static const Color bgBrandPopup = Color(0x5CAAB7FF); // rgba(170,183,255,0.36)

  // 文字
  static const Color textDefault = Color(0xFF171717);
  static const Color textDefaultHover = Color(0xFF262626);
  static const Color textSecondary = Color(0xFF404040);
  static const Color textTertiary = Color(0xFF737373);
  static const Color textDisabled = Color(0xFFA1A1A1);
  static const Color textOnBrand = Color(0xFFFFFFFF);
  static const Color textBrand = Color(0xFF4B3FE3);
  static const Color textBrandHover = Color(0xFF6A6FFF);

  // 图标
  static const Color iconDefault = Color(0xFF262626);
  static const Color iconSecondary = Color(0xFF404040);
  static const Color iconTertiary = Color(0xFF737373);
  static const Color iconDisabled = Color(0xFFA1A1A1);
  static const Color iconOnBrand = Color(0xFFFFFFFF);
  static const Color iconBrand = Color(0xFF4B3FE3);

  // 边框
  static const Color borderNeutralL1 = Color(
    0x1F737373,
  ); // rgba(115,115,115,0.12)
  static const Color borderNeutralL2 = Color(
    0x2E737373,
  ); // rgba(115,115,115,0.18)
  static const Color borderNeutralL3 = Color(
    0x5C737373,
  ); // rgba(115,115,115,0.36)
  static const Color borderBrand = Color(0xFF4B3FE3);
  // 可操作控件使用独立实色边框，避免浅色容器分隔线的透明度削弱命中范围。
  static const Color borderControl = Color(0xFFB3B3B3);
  static const Color borderControlHover = Color(0xFF858585);

  // 状态色
  static const Color statusSuccess = Color(0xFF15A877);
  static const Color statusWarning = Color(0xFFE27900);
  static const Color statusError = Color(0xFFE8463A);
  static const Color statusPrimary = Color(0xFF2F74FF);

  // 业务辅助色（设计稿 index.html 内出现的 brand-{color}-{100..700}）
  static const Color brandYellow100 = Color(0xFFFEF3C7);
  static const Color brandYellow200 = Color(0xFFFDE68A);
  static const Color brandYellow700 = Color(0xFFB45309);
  static const Color brandBlue100 = Color(0xFFDBEAFE);
  static const Color brandBlue300 = Color(0xFF93C5FD);
  static const Color brandPurple100 = Color(0xFFEDE9FE);
  static const Color brandGreen200 = Color(0xFFA7F3D0);
}

/// TraeWork 间距、圆角、字号常量。
class TraeWorkSpacers {
  TraeWorkSpacers._();

  static const double s2 = 2;
  static const double s4 = 4;
  static const double s6 = 6;
  static const double s8 = 8;
  static const double s10 = 10;
  static const double s12 = 12;
  static const double s16 = 16;
  static const double s20 = 20;
  static const double s24 = 24;
  static const double s32 = 32;
}

class TraeWorkRadius {
  TraeWorkRadius._();

  static const double r2 = 2;
  static const double r4 = 4;
  static const double r6 = 6;
  static const double r8 = 8;
  static const double r12 = 12;
  static const double r16 = 16;
  static const double r24 = 24;
  static const double r32 = 32;
  static const double full = 999;
}

/// 字号设计令牌（px 值，line-height 不影响 Flutter 自动布局）。
class TraeWorkFontSizes {
  TraeWorkFontSizes._();

  static const double bodyXs = 10;
  static const double bodySm = 11;
  static const double bodyMd = 12;
  static const double bodyBase = 14;
  static const double bodyLg = 18;
  static const double heading3xs = 11;
  static const double heading2xs = 12;
  static const double headingXs = 13;
  static const double headingSm = 16;
  static const double headingMd = 20;
  static const double headingLg = 22;
  static const double headingXl = 24;
}

/// 字体族：GUI 统一使用随包分发的 MiSans（覆盖中西日韩与常用符号），
/// fallback 仅用于极少数 MiSans 未含字形（如部分 emoji/生僻符号）的兜底。
/// mono 保留 Consolas 等宽，用于坐标、十六进制等需要对齐的数字。
const _kDefaultFontFamily = 'MiSans';
const _kMonoFontFamily = 'Consolas';
const _kFontFallback = ['Microsoft YaHei', 'Segoe UI'];

/// 应用 ThemeData。供 MaterialApp 使用。
ThemeData buildTraeWorkTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: TraeWorkColors.bgBrand,
    primary: TraeWorkColors.bgBrand,
    secondary: TraeWorkColors.bgBrandHover,
    surface: TraeWorkColors.bgBaseDefault,
    onSurface: TraeWorkColors.textDefault,
    error: TraeWorkColors.statusError,
    brightness: Brightness.light,
  );

  return ThemeData(
    useMaterial3: false,
    colorScheme: scheme,
    scaffoldBackgroundColor: TraeWorkColors.bgBaseDefault,
    primaryColor: TraeWorkColors.bgBrand,
    canvasColor: TraeWorkColors.bgBaseSecondary,
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      visualDensity: VisualDensity.standard,
      constraints: const BoxConstraints(minHeight: 28),
      fillColor: TraeWorkColors.bgBaseDefault,
      hoverColor: TraeWorkColors.bgOverlay1,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      hintStyle: traeworkText(size: 14, color: TraeWorkColors.textTertiary),
      labelStyle: traeworkText(size: 12, color: TraeWorkColors.textSecondary),
      errorStyle: traeworkText(size: 11, color: TraeWorkColors.statusError),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: TraeWorkColors.borderControl),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: TraeWorkColors.borderNeutralL1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(
          color: TraeWorkColors.borderBrand,
          width: 1.5,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: TraeWorkColors.statusError),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(
          color: TraeWorkColors.statusError,
          width: 1.5,
        ),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: TraeWorkColors.bgBaseDefault,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(TraeWorkRadius.r12),
        side: const BorderSide(color: TraeWorkColors.borderNeutralL2),
      ),
      titleTextStyle: traeworkText(size: 16, weight: FontWeight.w600),
      contentTextStyle: traeworkText(size: 12),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: TraeWorkColors.bgBaseDefault,
      surfaceTintColor: Colors.transparent,
      elevation: 4,
      textStyle: traeworkText(size: TraeWorkFontSizes.bodyBase),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(TraeWorkRadius.r8),
        side: const BorderSide(color: TraeWorkColors.borderNeutralL2),
      ),
    ),
    dividerColor: TraeWorkColors.borderNeutralL1,
    iconTheme: const IconThemeData(color: TraeWorkColors.iconDefault, size: 16),
    fontFamily: _kDefaultFontFamily,
    fontFamilyFallback: _kFontFallback,
    textTheme: const TextTheme(
      displayLarge: TextStyle(
        fontSize: TraeWorkFontSizes.headingXl,
        fontWeight: FontWeight.w600,
        color: TraeWorkColors.textDefault,
      ),
      titleLarge: TextStyle(
        fontSize: TraeWorkFontSizes.headingSm,
        fontWeight: FontWeight.w600,
        color: TraeWorkColors.textDefault,
      ),
      titleMedium: TextStyle(
        fontSize: TraeWorkFontSizes.headingXs,
        fontWeight: FontWeight.w600,
        color: TraeWorkColors.textDefault,
      ),
      titleSmall: TextStyle(
        fontSize: TraeWorkFontSizes.heading2xs,
        fontWeight: FontWeight.w600,
        color: TraeWorkColors.textDefault,
      ),
      bodyLarge: TextStyle(
        fontSize: TraeWorkFontSizes.bodyBase,
        fontWeight: FontWeight.w400,
        color: TraeWorkColors.textDefault,
        letterSpacing: -0.2,
      ),
      bodyMedium: TextStyle(
        fontSize: TraeWorkFontSizes.bodyMd,
        fontWeight: FontWeight.w400,
        color: TraeWorkColors.textDefault,
      ),
      bodySmall: TextStyle(
        fontSize: TraeWorkFontSizes.bodySm,
        fontWeight: FontWeight.w400,
        color: TraeWorkColors.textSecondary,
      ),
      labelLarge: TextStyle(
        fontSize: TraeWorkFontSizes.bodyBase,
        fontWeight: FontWeight.w500,
        color: TraeWorkColors.textDefault,
      ),
      labelSmall: TextStyle(
        fontSize: TraeWorkFontSizes.bodyXs,
        fontWeight: FontWeight.w400,
        color: TraeWorkColors.textTertiary,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: TraeWorkColors.bgInvert,
      contentTextStyle: const TextStyle(
        color: TraeWorkColors.textOnBrand,
        fontSize: TraeWorkFontSizes.bodyMd,
      ),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(TraeWorkRadius.r8),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: TraeWorkColors.borderNeutralL1,
      thickness: 1,
      space: 1,
    ),
    splashColor: Colors.transparent,
    highlightColor: TraeWorkColors.bgOverlay1,
    hoverColor: TraeWorkColors.bgOverlay2,
    focusColor: TraeWorkColors.bgOverlay2,
    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    visualDensity: VisualDensity.compact,
  );
}

/// 用于 mono 数字的 TextStyle（坐标、十六进制等）。
TextStyle traeworkMono({
  double size = TraeWorkFontSizes.bodyMd,
  Color color = TraeWorkColors.textDefault,
  FontWeight weight = FontWeight.w400,
}) => TextStyle(
  fontFamily: _kMonoFontFamily,
  fontSize: size,
  color: color,
  fontWeight: weight,
  fontFamilyFallback: const [
    'Menlo',
    'Consolas',
    'Courier New',
    'Microsoft YaHei',
  ],
);

/// 用于普通文字的 TextStyle。
TextStyle traeworkText({
  double size = TraeWorkFontSizes.bodyMd,
  Color color = TraeWorkColors.textDefault,
  FontWeight weight = FontWeight.w400,
  double letterSpacing = 0,
}) => TextStyle(
  fontFamily: _kDefaultFontFamily,
  fontSize: size,
  color: color,
  fontWeight: weight,
  letterSpacing: letterSpacing,
  fontFamilyFallback: _kFontFallback,
);

