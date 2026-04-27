// 应用入口文件
// 
// 该文件是Flutter应用的入口点，负责启动应用并配置Material 3主题。
// 
// 主要功能：
// - 启动Flutter应用
// - 配置Material Design 3主题
// - 设置应用标题和调试选项
// - 指定主页面组件

import 'package:flutter/material.dart';
import 'views/home/home_view.dart';

/// 应用入口函数
void main() {
  runApp(const MyApp());
}

/// 应用根组件
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // 定义Material 3配色方案
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF1A73E8), // Google Blue
      brightness: Brightness.light,
    );

    return MaterialApp(
      title: '通信助手',
      debugShowCheckedModeBanner: false,
      
      // Material 3主题配置
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: colorScheme,
        
        // 字体主题
        fontFamily: 'Roboto',
        
        // 文字主题
        textTheme: const TextTheme(
          displayLarge: TextStyle(fontSize: 57, fontWeight: FontWeight.w400),
          displayMedium: TextStyle(fontSize: 45, fontWeight: FontWeight.w400),
          displaySmall: TextStyle(fontSize: 36, fontWeight: FontWeight.w400),
          headlineLarge: TextStyle(fontSize: 32, fontWeight: FontWeight.w400),
          headlineMedium: TextStyle(fontSize: 28, fontWeight: FontWeight.w400),
          headlineSmall: TextStyle(fontSize: 24, fontWeight: FontWeight.w400),
          titleLarge: TextStyle(fontSize: 22, fontWeight: FontWeight.w500),
          titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, letterSpacing: 0.15),
          titleSmall: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, letterSpacing: 0.1),
          bodyLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w400, letterSpacing: 0.5),
          bodyMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w400, letterSpacing: 0.25),
          bodySmall: TextStyle(fontSize: 12, fontWeight: FontWeight.w400, letterSpacing: 0.4),
          labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, letterSpacing: 0.1),
          labelMedium: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, letterSpacing: 0.5),
          labelSmall: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: 0.5),
        ),
        
        // AppBar主题
        appBarTheme: AppBarTheme(
          centerTitle: false,
          elevation: 0,
          scrolledUnderElevation: 3,
          backgroundColor: colorScheme.surface,
          foregroundColor: colorScheme.onSurface,
          titleTextStyle: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w400,
            color: colorScheme.onSurface,
          ),
        ),
        
        // Card主题
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: colorScheme.outlineVariant,
              width: 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
        ),
        
        // 输入框主题
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: colorScheme.surface,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: colorScheme.outline),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: colorScheme.outline),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: colorScheme.primary, width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: colorScheme.error),
          ),
          labelStyle: TextStyle(
            fontSize: 14,
            color: colorScheme.onSurfaceVariant,
          ),
          hintStyle: TextStyle(
            fontSize: 14,
            color: colorScheme.onSurfaceVariant.withOpacity(0.6),
          ),
        ),
        
        // 下拉框主题
        dropdownMenuTheme: DropdownMenuThemeData(
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: colorScheme.surface,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: colorScheme.outline),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: colorScheme.outline),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: colorScheme.primary, width: 2),
            ),
          ),
        ),
        
        // 按钮主题
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            textStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.1,
            ),
          ),
        ),
        
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            textStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.1,
            ),
          ),
        ),
        
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            textStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.1,
            ),
          ),
        ),
        
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            textStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.1,
            ),
          ),
        ),
        
        // 分段按钮主题
        segmentedButtonTheme: SegmentedButtonThemeData(
          style: ButtonStyle(
            shape: WidgetStateProperty.all(
              RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            textStyle: WidgetStateProperty.all(
              const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
        
        // Divider主题
        dividerTheme: DividerThemeData(
          color: colorScheme.outlineVariant,
          thickness: 1,
          space: 1,
        ),
        
        // Switch主题
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return colorScheme.onPrimary;
            }
            return colorScheme.outline;
          }),
          trackColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return colorScheme.primary;
            }
            return colorScheme.surfaceContainerHighest;
          }),
        ),
        
        // 进度条主题
        progressIndicatorTheme: ProgressIndicatorThemeData(
          color: colorScheme.primary,
          linearTrackColor: colorScheme.surfaceContainerHighest,
        ),
        
        // Tooltip主题
        tooltipTheme: TooltipThemeData(
          decoration: BoxDecoration(
            color: colorScheme.inverseSurface,
            borderRadius: BorderRadius.circular(4),
          ),
          textStyle: TextStyle(
            color: colorScheme.onInverseSurface,
            fontSize: 12,
          ),
        ),
      ),
      
      home: const HomeView(),
    );
  }
}
