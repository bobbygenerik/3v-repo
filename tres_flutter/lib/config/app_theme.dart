import 'package:flutter/material.dart';

/// Custom color scheme matching the Android app's AppColors.kt
/// Based on the Très³ logo and brand identity
class AppColors {
  // Primary dark blue from nightfall
  static const Color primaryDark = Color(0xFF2F3448); // #2F3448

  // Bright blue accent - matches logo
  static const Color primaryBlue = Color(0xFF6B7FB8); // #6B7FB8 - Main brand color

  // Dark gray background
  static const Color backgroundDark = Color(0xFF1b1c1e); // #1b1c1e

  // Medium gray
  static const Color surfaceGray = Color(0xFF515664); // #515664

  // Light gray text
  static const Color textLight = Color(0xFFA0A2A6); // #A0A2A6

  // Near white
  static const Color textWhite = Color(0xFFF4F4F5); // #F4F4F5

  // Secondary blue - lighter version of logo color
  static const Color accentBlue = Color(0xFF7589C4); // #7589C4 - Lighter variant

  // Gray for secondary elements
  static const Color gray = Color(0xFF7E8183); // #7E8183
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
        surface: AppColors.primaryDark,
        onPrimary: AppColors.textWhite,
        onSecondary: AppColors.textWhite,
        onSurface: AppColors.textWhite,
        surfaceContainerHighest: AppColors.surfaceGray,
      ),
      
      // Scaffold background
      scaffoldBackgroundColor: AppColors.backgroundDark,
      
      // AppBar theme
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.primaryDark,
        foregroundColor: AppColors.textWhite,
        elevation: 0,
        centerTitle: false,
      ),
      
      // Card theme
      cardTheme: const CardThemeData(
        color: AppColors.primaryDark,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
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
          foregroundColor: AppColors.textWhite,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
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
        fillColor: AppColors.primaryDark,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppColors.surfaceGray),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppColors.surfaceGray),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppColors.primaryBlue, width: 2),
        ),
        labelStyle: TextStyle(color: AppColors.textLight),
        hintStyle: TextStyle(color: AppColors.gray),
      ),
    );
  }
}
