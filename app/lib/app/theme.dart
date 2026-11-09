import 'package:flutter/material.dart';

abstract final class AggregateTheme {
  static ThemeData light = _build(
    const Color(0xFFF5F7F8),
    const Color(0xFFFFFFFF),
    const Color(0xFF1B2833),
    const Color(0xFF245F89),
    Brightness.light,
  );
  static ThemeData dark = _build(
    const Color(0xFF151B20),
    const Color(0xFF1C252B),
    const Color(0xFFE8F0F3),
    const Color(0xFF78B7DF),
    Brightness.dark,
  );

  static ThemeData _build(
    Color background,
    Color surface,
    Color foreground,
    Color accent,
    Brightness brightness,
  ) {
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: brightness,
      surface: surface,
      onSurface: foreground,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      appBarTheme: AppBarTheme(backgroundColor: background),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 12),
      ),
    );
  }
}
