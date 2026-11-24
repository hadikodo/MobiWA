import 'package:flutter/material.dart';

/// App-wide colors and Material 3 theme.
class AppColors {
  AppColors._();

  static const brand = Color(0xFF00A884);
  static const scan = Color(0xFF2F80ED); // Step 1 · Get numbers
  static const ai = Color(0xFF8B5CF6); // Step 2 · AI sort
  static const send = Color(0xFF00A884); // Step 3 · Send
  static const junk = Color(0xFF9AA4B2);
  static const unnamed = Color(0xFFF59E0B);
  static const danger = Color(0xFFE5484D);
  static const success = Color(0xFF16A34A);

  /// Stable color for a customer category, picked from its name.
  static Color forCategory(String name) {
    const palette = [
      Color(0xFF0EA5E9),
      Color(0xFF10B981),
      Color(0xFFF97316),
      Color(0xFFEC4899),
      Color(0xFF6366F1),
      Color(0xFF14B8A6),
      Color(0xFFEAB308),
      Color(0xFFEF4444),
      Color(0xFF8B5CF6),
      Color(0xFF84CC16),
    ];
    var h = 0;
    for (final c in name.toLowerCase().codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return palette[h % palette.length];
  }
}

class AppTheme {
  AppTheme._();

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness b) {
    final dark = b == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.brand,
      brightness: b,
      surface: dark ? const Color(0xFF0F1417) : const Color(0xFFF6F8F7),
    );
    final cardColor = dark ? const Color(0xFF182025) : Colors.white;
    final border = dark ? const Color(0xFF26313A) : const Color(0xFFE6EAE8);

    return ThemeData(
      useMaterial3: true,
      // Bundled fonts (no CDN): Roboto, with Arabic falling back to Noto Naskh.
      fontFamily: 'Roboto',
      fontFamilyFallback: const ['NotoNaskhArabic'],
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        color: cardColor,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: border),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cardColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: border),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: cardColor,
        indicatorColor: AppColors.brand.withValues(alpha: 0.18),
        surfaceTintColor: Colors.transparent,
      ),
      dividerTheme: DividerThemeData(color: border, space: 1),
    );
  }
}
