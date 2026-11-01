import 'package:flutter/material.dart';

enum AppBrandVariant {
  iphone,
  android,
}

class AppColors {
  /// Global theme toggle flag. Defaults to false (Clean White Theme).
  static bool isDark = false;

  // Backgrounds: macOS Liquid Glass Luminous White (Default) vs Dark Glass
  static Color get background =>
      isDark ? const Color(0xFF14171F) : const Color(0xFFF3F5F9);
  static Color get backgroundSecondary =>
      isDark ? const Color(0xFF1B202B) : const Color(0xFFFAFBFC);
  static Color get card =>
      isDark ? const Color(0xFF1F2633) : const Color(0xFFFFFFFF);
  static Color get cardElevated =>
      isDark ? const Color(0xFF262E3D) : const Color(0xFFF8FAFD);
  static Color get cardBorder =>
      isDark ? const Color(0x2EFFFFFF) : const Color(0x18000000);
  static Color get cardBorderHover =>
      isDark ? const Color(0x4DFFFFFF) : const Color(0x29000000);

  // Text: Apple Human Interface Guidelines Typography
  static Color get textPrimary =>
      isDark ? const Color(0xFFF5F5F7) : const Color(0xFF1D1D1F);
  static Color get textSecondary =>
      isDark ? const Color(0xFF98989D) : const Color(0xFF6E6E73);
  static Color get textMuted =>
      isDark ? const Color(0xFF636366) : const Color(0xFF86868B);

  // Status
  static const Color success = Color(0xFF34C759);
  static const Color warning = Color(0xFFFF9500);
  static const Color error = Color(0xFFFF3B30);
  static const Color info = Color(0xFF007AFF);

  // Brand Accents - Vibrant Apple Blue (SF System Blue)
  static const Color iphoneBlue = Color(0xFF0071E3);
  static const Color iphoneBlueLight = Color(0xFF3395FF);
  static const Color iphoneBlueDark = Color(0xFF0056B3);
  static const Color iphoneBlueGlow = Color(0x400071E3);

  static const Color androidGreen = Color(0xFF34C759);
  static const Color androidGreenDark = Color(0xFF248A3D);
  static const Color androidGreenGlow = Color(0x3334C759);

  // Liquid Glass Styling Helpers & Specular Depth
  static Color get glassFill =>
      isDark ? const Color(0x24FFFFFF) : const Color(0xE8FFFFFF);
  static Color get glassBorder =>
      isDark ? const Color(0x33FFFFFF) : const Color(0x1F000000);
  static Color get glassShadow =>
      isDark ? const Color(0x55000000) : const Color(0x0F0F172A);

  /// Authentic macOS & iOS 26 Liquid Glass decoration with specular highlight,
  /// translucent frosted gradient, and layered ambient depth shadow.
  static BoxDecoration liquidGlassDecoration({
    double radius = 14,
    Border? border,
    bool elevated = false,
  }) {
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.12)
        : Colors.black.withValues(alpha: 0.08);

    return BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: isDark
            ? (elevated
                ? [const Color(0x402A3446), const Color(0x261B222E)]
                : [const Color(0x33232C3A), const Color(0x1F171D27)])
            : (elevated
                ? [const Color(0xFFFFFFFF), const Color(0xF2F6FAFD)]
                : [const Color(0xF7FFFFFF), const Color(0xECF3F7FC)]),
      ),
      border: border ??
          Border.all(
            color: borderColor,
            width: 1.0,
          ),
      boxShadow: [
        BoxShadow(
          color: isDark
              ? Colors.black.withValues(alpha: 0.45)
              : const Color(0x0C0F172A),
          blurRadius: elevated ? 24 : 16,
          offset: Offset(0, elevated ? 8 : 4),
          spreadRadius: 0,
        ),
        BoxShadow(
          color: isDark
              ? Colors.black.withValues(alpha: 0.25)
              : const Color(0x05000000),
          blurRadius: 4,
          offset: const Offset(0, 1),
        ),
      ],
    );
  }
}

class AppTheme {
  static ThemeData getTheme(AppBrandVariant variant, {bool? darkMode}) {
    final dark = darkMode ?? AppColors.isDark;
    final primaryAccent = variant == AppBrandVariant.iphone
        ? AppColors.iphoneBlue
        : AppColors.androidGreen;

    final baseBrightness = dark ? Brightness.dark : Brightness.light;

    return ThemeData(
      brightness: baseBrightness,
      scaffoldBackgroundColor: AppColors.background,
      fontFamily: 'Segoe UI',
      colorScheme: dark
          ? ColorScheme.dark(
              primary: primaryAccent,
              surface: AppColors.card,
              error: AppColors.error,
              onPrimary: Colors.white,
              onSurface: AppColors.textPrimary,
            )
          : ColorScheme.light(
              primary: primaryAccent,
              surface: AppColors.card,
              error: AppColors.error,
              onPrimary: Colors.white,
              onSurface: AppColors.textPrimary,
            ),
      cardTheme: CardThemeData(
        color: AppColors.card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: AppColors.cardBorder, width: 1),
        ),
      ),
      textTheme: TextTheme(
        headlineLarge: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 32,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.6,
        ),
        headlineMedium: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 24,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.4,
        ),
        titleLarge: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
        ),
        titleMedium: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
        bodyLarge: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.normal,
        ),
        bodyMedium: TextStyle(
          color: AppColors.textSecondary,
          fontSize: 13,
          fontWeight: FontWeight.normal,
        ),
        bodySmall: TextStyle(
          color: AppColors.textMuted,
          fontSize: 12,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.cardElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: AppColors.cardBorder, width: 1),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.cardElevated,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.cardBorder),
          boxShadow: [
            BoxShadow(
              color: AppColors.glassShadow,
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        textStyle: TextStyle(color: AppColors.textPrimary, fontSize: 12),
      ),
    );
  }
}
