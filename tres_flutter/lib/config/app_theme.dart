import 'package:flutter/material.dart';

import 'ui_tokens.dart';

/// Custom color scheme matching the Android app's AppColors.kt
/// Based on the Très³ logo and brand identity
class AppColors {
  // Sitch/Modern Color Palette
  static const Color backgroundBlack = Color(0xFF15171D); // #15171D
  static const Color surfaceDark = Color(0xFF1F2128);     // #1F2128
  static const Color primaryBlue = Color(0xFF6B7FB8);     // #6B7FB8
  static const Color bgGradientStart = Color(0xFF15171D); // #15171D
  static const Color bgGradientMid = Color(0xFF1F2128);   // #1F2128
  
  // Legacy/Other colors
  static const Color backgroundDark = Color(0xFF1b1c1e); // #1b1c1e
  static const Color primaryDark = Color(0xFF2F3448);    // #2F3448
  static const Color surfaceGray = Color(0xFF515664);    // #515664
  static const Color textLight = Color(0xFFA0A2A6);      // #A0A2A6
  static const Color textWhite = Color(0xFFF4F4F5);      // #F4F4F5
  static const Color accentBlue = Color(0xFF7589C4);     // #7589C4
  static const Color gray = Color(0xFF7E8183);           // #7E8183
}

/// Custom theme matching the Android app design
class AppTheme {
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      
      // Color scheme based on brand colors
      colorScheme: ColorScheme.dark(
        primary: AppColors.primaryBlue,
        secondary: AppColors.accentBlue,
        surface: AppColors.surfaceDark,
        onPrimary: AppColors.textWhite,
        onSecondary: AppColors.textWhite,
        onSurface: AppColors.textWhite,
        surfaceContainerHighest: AppColors.surfaceGray,
      ),
      
      // Scaffold background
      scaffoldBackgroundColor: AppColors.backgroundBlack,
      
      // AppBar theme
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.primaryDark,
        foregroundColor: AppColors.textWhite,
        elevation: 0,
        centerTitle: false,
      ),
      
      // Card theme
      cardTheme: const CardThemeData(
        color: AppColors.surfaceDark,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: UiRadius.lg,
          side: BorderSide(color: Colors.white12),
        ),
      ),
      
      // Text theme
      textTheme: const TextTheme(
        displayLarge: TextStyle(color: AppColors.textWhite),
        displayMedium: TextStyle(color: AppColors.textWhite),
        displaySmall: TextStyle(color: AppColors.textWhite),
        headlineLarge: TextStyle(color: AppColors.textWhite),
        headlineMedium: TextStyle(color: AppColors.textWhite),
        headlineSmall: TextStyle(color: AppColors.textWhite),
        titleLarge: TextStyle(color: AppColors.textWhite),
        titleMedium: TextStyle(color: AppColors.textWhite),
        titleSmall: TextStyle(color: AppColors.textLight),
        bodyLarge: TextStyle(color: AppColors.textWhite),
        bodyMedium: TextStyle(color: AppColors.textLight),
        bodySmall: TextStyle(color: AppColors.textLight),
        labelLarge: TextStyle(color: AppColors.textWhite),
        labelMedium: TextStyle(color: AppColors.textLight),
        labelSmall: TextStyle(color: AppColors.textLight),
      ),
      
      // Icon theme
      iconTheme: const IconThemeData(
        color: AppColors.textLight,
      ),
      
      // FloatingActionButton theme
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.primaryBlue,
        foregroundColor: AppColors.textWhite,
      ),
      
      // ElevatedButton theme
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryBlue,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(
            vertical: UiSpacing.md,
            horizontal: UiSpacing.xl,
          ),
          textStyle: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w500,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: UiRadius.lg,
          ),
        ),
      ),
      
      // TabBar theme
      tabBarTheme: const TabBarThemeData(
        labelColor: AppColors.primaryBlue,
        unselectedLabelColor: AppColors.textLight,
        indicatorColor: AppColors.primaryBlue,
      ),
      
      // Input decoration theme
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceDark,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: UiSpacing.lg,
          vertical: 18,
        ),
        border: OutlineInputBorder(
          borderRadius: UiRadius.lg,
          borderSide: const BorderSide(color: Colors.white12),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: UiRadius.lg,
          borderSide: const BorderSide(color: Colors.white12),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: UiRadius.lg,
          borderSide: const BorderSide(color: AppColors.primaryBlue, width: 2),
        ),
        labelStyle: const TextStyle(color: Colors.white70),
        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
        prefixIconColor: Colors.white70,
        suffixIconColor: Colors.white70,
      ),
      
      // SnackBar theme
      snackBarTheme: SnackBarThemeData(
        backgroundColor: const Color(0xFF6B7FB8),
        contentTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: UiRadius.md,
        ),
        elevation: 4,
      ),
    );
  }
}
