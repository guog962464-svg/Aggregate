import 'package:flutter/material.dart';

import '../widgets/glass/glass_design_tokens.dart';

abstract final class AggregateTheme {
  static final ThemeData light = _build(
    const Color(0xFFF5F7F8),
    const Color(0xFFFFFFFF),
    const Color(0xFF1B2833),
    const Color(0xFF546270),
    const Color(0xFF245F89),
    const Color(0xFF2F7EA9),
    Brightness.light,
  );
  static final ThemeData dark = _build(
    const Color(0xFF151B20),
    const Color(0xFF1C252B),
    const Color(0xFFE8F0F3),
    const Color(0xFFA8B8C1),
    const Color(0xFF78B7DF),
    const Color(0xFF88C8EA),
    Brightness.dark,
  );

  static ThemeData forPlatform(ThemeData theme, TargetPlatform platform) {
    if (platform == TargetPlatform.macOS) {
      return _macOS(theme);
    }
    if (platform != TargetPlatform.android &&
        platform != TargetPlatform.iOS &&
        platform != TargetPlatform.fuchsia) {
      return theme;
    }
    const mobileButtonStyle = ButtonStyle(
      minimumSize: WidgetStatePropertyAll(Size(64, 48)),
      tapTargetSize: MaterialTapTargetSize.padded,
    );
    return theme.copyWith(
      platform: platform,
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      filledButtonTheme: const FilledButtonThemeData(style: mobileButtonStyle),
      outlinedButtonTheme: const OutlinedButtonThemeData(
        style: mobileButtonStyle,
      ),
      textButtonTheme: const TextButtonThemeData(style: mobileButtonStyle),
    );
  }

  static ThemeData _macOS(ThemeData theme) {
    final glass = GlassDesignTokens.forBrightness(theme.brightness);
    final scheme = theme.colorScheme.copyWith(
      primary: glass.glow,
      onPrimary: glass.ink,
      primaryContainer: glass.glow.withValues(alpha: 0.18),
      onPrimaryContainer: glass.text,
      surface: glass.surface,
      onSurface: glass.text,
      onSurfaceVariant: glass.muted,
      outline: glass.line.withValues(alpha: 0.72),
      outlineVariant: glass.line.withValues(alpha: 0.48),
      error: glass.danger,
      onError: glass.inset,
    );
    return theme.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: Colors.transparent,
      canvasColor: Colors.transparent,
      dividerColor: glass.line.withValues(alpha: 0.62),
      appBarTheme: theme.appBarTheme.copyWith(
        backgroundColor: Colors.transparent,
        foregroundColor: glass.text,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      textTheme: theme.textTheme.apply(
        bodyColor: glass.text,
        displayColor: glass.text,
      ),
      iconTheme: IconThemeData(color: glass.muted),
      inputDecorationTheme: theme.inputDecorationTheme.copyWith(
        filled: true,
        fillColor: glass.inset.withValues(alpha: 0.62),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: glass.line.withValues(alpha: 0.72)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: glass.glow, width: 1.5),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: glass.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      extensions: <ThemeExtension<dynamic>>[glass],
    );
  }

  static ThemeData _build(
    Color background,
    Color surface,
    Color foreground,
    Color secondary,
    Color accent,
    Color focus,
    Brightness brightness,
  ) {
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: brightness,
      surface: surface,
      onSurface: foreground,
      onSurfaceVariant: secondary,
      primary: accent,
      outline: secondary.withValues(alpha: 0.42),
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      visualDensity: VisualDensity.compact,
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: foreground,
        scrolledUnderElevation: 0,
        elevation: 0,
        centerTitle: false,
      ),
      textTheme: TextTheme(
        headlineMedium: TextStyle(
          color: foreground,
          fontSize: 24,
          fontWeight: FontWeight.w600,
          height: 1.25,
        ),
        titleMedium: TextStyle(
          color: foreground,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
        bodyMedium: TextStyle(color: foreground, fontSize: 14, height: 1.45),
        bodySmall: TextStyle(color: secondary, fontSize: 12, height: 1.4),
      ),
      dividerColor: secondary.withValues(alpha: 0.18),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: scheme.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: focus, width: 2),
        ),
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        iconColor: secondary,
        titleTextStyle: TextStyle(color: foreground, fontSize: 14),
        subtitleTextStyle: TextStyle(color: secondary, fontSize: 12),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surface,
        side: BorderSide(color: scheme.outline),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}
