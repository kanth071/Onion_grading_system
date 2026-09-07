import 'package:flutter/material.dart';

class AppColors {
  static const green = Color(0xFF22B14C);
  static const greenDark = Color(0xFF1C8F3D);
  static const orange = Color(0xFFFF8C00);
  static const red = Color(0xFFDC1414);
  static const purple = Color(0xFFA020F0);
  static const bg = Color(0xFFF7F4EE);
  static const border = Color(0xFFE7E2D6);
  static const muted = Color(0xFF6B6F63);
  static const ink = Color(0xFF24261F);

  static Color forClass(String key) {
    switch (key) {
      case 'healthy':
        return green;
      case 'damaged':
        return orange;
      case 'rotten':
        return red;
      case 'sprouted':
        return purple;
      default:
        return muted;
    }
  }

  static Color forGrade(String grade) {
    if (grade == 'Grade 1') return green;
    if (grade == 'Grade 2') return orange;
    return red;
  }
}

ThemeData buildAppTheme() {
  return ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: AppColors.bg,
    colorScheme: ColorScheme.fromSeed(seedColor: AppColors.green),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.green,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.border),
      ),
      margin: const EdgeInsets.only(bottom: 14),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.green,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.ink,
        side: const BorderSide(color: AppColors.border),
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    ),
  );
}
