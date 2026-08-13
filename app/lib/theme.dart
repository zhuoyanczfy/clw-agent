import 'package:flutter/material.dart';

import 'widgets/cute_widgets.dart';

/// 温馨粉暖色主题：整体暖色调 + 圆角卡片风格
class AppTheme {
  static const Color primary = Color(0xFFFF8C9E); // 温暖粉
  static const Color primaryDark = Color(0xFFF26B8A);
  static const Color accent = Color(0xFFFFB74D); // 暖橙
  static const Color bg = Color(0xFFFFF7F3); // 米白底
  static const Color card = Colors.white;
  static const Color textDark = Color(0xFF4A3F35);
  static const Color textLight = Color(0xFF9B8F85);

  static ThemeData get light => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: primary,
      primary: primary,
      secondary: accent,
      surface: bg,
    ),
    scaffoldBackgroundColor: bg,
    fontFamilyFallback: const ['PingFang SC', 'Microsoft YaHei'],
    // Q 版页面转场：所有 MaterialPageRoute 推开新页时缩放 + 淡入
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: CutePageTransitionsBuilder(),
        TargetPlatform.iOS: CutePageTransitionsBuilder(),
        TargetPlatform.windows: CutePageTransitionsBuilder(),
        TargetPlatform.macOS: CutePageTransitionsBuilder(),
        TargetPlatform.linux: CutePageTransitionsBuilder(),
      },
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      foregroundColor: textDark,
    ),
    cardTheme: CardThemeData(
      color: card,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      margin: EdgeInsets.zero,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      backgroundColor: textDark,
    ),
  );
}
