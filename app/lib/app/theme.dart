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

  /// Keeps macOS foregrounds readable on content surfaces while
  /// [ThemeData.lerp] moves between the light and dark palettes. Existing
  /// colors remain untouched when they meet the target on every surface.
  static ThemeData withMacOSSurfaceTextContrast(ThemeData theme) {
    final glass = theme.extension<GlassDesignTokens>();
    if (glass == null) return theme;

    final surfaces = _macOSContentSurfaces(theme.colorScheme);
    final onSurface = _readableOnSurfaces(
      theme.colorScheme.onSurface,
      surfaces,
    );
    final onSurfaceVariant = _readableOnSurfaces(
      theme.colorScheme.onSurfaceVariant,
      surfaces,
    );
    final safeTextTheme = _withReadableTextColors(theme.textTheme, surfaces);
    final safeGlass = glass.copyWith(
      text: _readableOnSurfaces(glass.text, surfaces),
      muted: _readableOnSurfaces(glass.muted, surfaces),
    );

    return theme.copyWith(
      colorScheme: theme.colorScheme.copyWith(
        onSurface: onSurface,
        onSurfaceVariant: onSurfaceVariant,
      ),
      textTheme: safeTextTheme,
      appBarTheme: theme.appBarTheme.copyWith(
        foregroundColor: _readableOnSurfaces(
          theme.appBarTheme.foregroundColor ?? onSurface,
          surfaces,
        ),
      ),
      iconTheme: theme.iconTheme.copyWith(
        color: _readableOnSurfaces(
          theme.iconTheme.color ?? onSurfaceVariant,
          surfaces,
        ),
      ),
      listTileTheme: theme.listTileTheme.copyWith(
        titleTextStyle: _withReadableTextColor(
          theme.listTileTheme.titleTextStyle,
          surfaces,
          onSurface,
        ),
        subtitleTextStyle: _withReadableTextColor(
          theme.listTileTheme.subtitleTextStyle,
          surfaces,
          onSurfaceVariant,
        ),
        iconColor: _readableOnSurfaces(
          theme.listTileTheme.iconColor ?? onSurfaceVariant,
          surfaces,
        ),
      ),
      extensions: [
        for (final extension in theme.extensions.values)
          if (extension is GlassDesignTokens) safeGlass else extension,
      ],
    );
  }

  /// Aligns text painted directly over the moving macOS glass backdrop with its
  /// current luminance side while preserving surface-safe ColorScheme values.
  /// The caller updates this only when that side changes.
  static ThemeData withMacOSBackdropTextContrast(
    ThemeData theme, {
    required bool usesDarkForeground,
    bool addContrastHalo = false,
  }) {
    final glass = theme.extension<GlassDesignTokens>();
    if (glass == null) return theme;

    final foreground = usesDarkForeground ? Colors.black : Colors.white;
    final safeTextTheme = _withForegroundTextColors(
      theme.textTheme,
      foreground,
      addContrastHalo: addContrastHalo,
    );
    final safeGlass = glass;

    return theme.copyWith(
      // Keep onSurface/onSurfaceVariant from the surface-contrast pass. These
      // semantic colors are also used on Material surfaces, whose brightness
      // can lag the moving backdrop while ThemeData itself is interpolating.
      textTheme: safeTextTheme,
      appBarTheme: theme.appBarTheme.copyWith(
        foregroundColor: foreground,
        titleTextStyle: _withBackdropForeground(
          theme.appBarTheme.titleTextStyle,
          foreground,
          addContrastHalo: addContrastHalo,
        ),
        toolbarTextStyle: _withBackdropForeground(
          theme.appBarTheme.toolbarTextStyle,
          foreground,
          addContrastHalo: addContrastHalo,
        ),
      ),
      iconTheme: theme.iconTheme.copyWith(color: foreground),
      listTileTheme: theme.listTileTheme.copyWith(
        titleTextStyle: _withBackdropForeground(
          theme.listTileTheme.titleTextStyle,
          foreground,
          addContrastHalo: addContrastHalo,
        ),
        subtitleTextStyle: _withBackdropForeground(
          theme.listTileTheme.subtitleTextStyle,
          foreground,
          addContrastHalo: addContrastHalo,
        ),
        iconColor: foreground,
      ),
      extensions: [
        for (final extension in theme.extensions.values)
          if (extension is GlassDesignTokens) safeGlass else extension,
      ],
    );
  }

  static List<Color> _macOSContentSurfaces(ColorScheme scheme) => [
    scheme.surface,
    scheme.surfaceContainerLow,
    scheme.surfaceContainer,
  ];

  static TextTheme _withReadableTextColors(
    TextTheme textTheme,
    List<Color> surfaces,
  ) {
    TextStyle? readable(TextStyle? style, {bool allowHalo = true}) {
      if (style == null || style.color == null) return style;
      return _withReadableTextColor(
        style,
        surfaces,
        style.color!,
        allowHalo: allowHalo,
      );
    }

    return TextTheme(
      displayLarge: readable(textTheme.displayLarge),
      displayMedium: readable(textTheme.displayMedium),
      displaySmall: readable(textTheme.displaySmall),
      headlineLarge: readable(textTheme.headlineLarge),
      headlineMedium: readable(textTheme.headlineMedium),
      headlineSmall: readable(textTheme.headlineSmall),
      titleLarge: readable(textTheme.titleLarge),
      titleMedium: readable(textTheme.titleMedium),
      titleSmall: readable(textTheme.titleSmall),
      bodyLarge: readable(textTheme.bodyLarge),
      bodyMedium: readable(textTheme.bodyMedium),
      bodySmall: readable(textTheme.bodySmall),
      labelLarge: readable(textTheme.labelLarge, allowHalo: false),
      labelMedium: readable(textTheme.labelMedium, allowHalo: false),
      labelSmall: readable(textTheme.labelSmall, allowHalo: false),
    );
  }

  static TextTheme _withForegroundTextColors(
    TextTheme textTheme,
    Color foreground, {
    required bool addContrastHalo,
  }) {
    TextStyle? readable(TextStyle? style, {bool allowHalo = true}) =>
        _withBackdropForeground(
          style,
          foreground,
          addContrastHalo: addContrastHalo && allowHalo,
        );

    return TextTheme(
      displayLarge: readable(textTheme.displayLarge),
      displayMedium: readable(textTheme.displayMedium),
      displaySmall: readable(textTheme.displaySmall),
      headlineLarge: readable(textTheme.headlineLarge),
      headlineMedium: readable(textTheme.headlineMedium),
      headlineSmall: readable(textTheme.headlineSmall),
      titleLarge: readable(textTheme.titleLarge),
      titleMedium: readable(textTheme.titleMedium),
      titleSmall: readable(textTheme.titleSmall),
      bodyLarge: readable(textTheme.bodyLarge),
      bodyMedium: readable(textTheme.bodyMedium),
      bodySmall: readable(textTheme.bodySmall),
      labelLarge: readable(textTheme.labelLarge, allowHalo: false),
      labelMedium: readable(textTheme.labelMedium, allowHalo: false),
      labelSmall: readable(textTheme.labelSmall, allowHalo: false),
    );
  }

  static TextStyle? _withBackdropForeground(
    TextStyle? style,
    Color foreground, {
    required bool addContrastHalo,
  }) {
    if (style == null) return null;
    return style.copyWith(
      color: foreground,
      shadows: addContrastHalo ? _contrastHalo(foreground) : style.shadows,
    );
  }

  static List<Shadow> _contrastHalo(Color foreground) {
    final halo = foreground == Colors.black ? Colors.white : Colors.black;
    const offsets = [
      Offset(-1, -1),
      Offset(0, -1),
      Offset(1, -1),
      Offset(-1, 0),
      Offset(1, 0),
      Offset(-1, 1),
      Offset(0, 1),
      Offset(1, 1),
    ];
    return [
      for (final offset in offsets)
        Shadow(color: halo, offset: offset, blurRadius: 0),
    ];
  }

  static TextStyle? _withReadableTextColor(
    TextStyle? style,
    List<Color> surfaces,
    Color fallback, {
    bool allowHalo = true,
  }) {
    if (style == null) return null;
    final foreground = _readableOnSurfaces(style.color ?? fallback, surfaces);
    final needsHalo =
        allowHalo && !_meetsTextContrastOnSurfaces(foreground, surfaces);
    return style.copyWith(
      color: foreground,
      shadows: needsHalo ? _contrastHalo(foreground) : style.shadows,
    );
  }

  static bool _meetsTextContrastOnSurfaces(
    Color foreground,
    List<Color> surfaces,
  ) => surfaces.every((surface) => _contrastRatio(foreground, surface) >= 4.5);

  static Color _readableOnSurfaces(Color preferred, List<Color> surfaces) {
    if (_meetsTextContrastOnSurfaces(preferred, surfaces)) return preferred;
    double minimumContrast(Color foreground) {
      var minimum = double.infinity;
      for (final surface in surfaces) {
        final contrast = _contrastRatio(foreground, surface);
        if (contrast < minimum) minimum = contrast;
      }
      return minimum;
    }

    final blackContrast = minimumContrast(Colors.black);
    final whiteContrast = minimumContrast(Colors.white);
    return blackContrast >= whiteContrast ? Colors.black : Colors.white;
  }

  static double _contrastRatio(Color foreground, Color background) {
    final opaqueForeground = Color.alphaBlend(foreground, background);
    final foregroundLuminance = opaqueForeground.computeLuminance();
    final backgroundLuminance = background.computeLuminance();
    final lighter = foregroundLuminance > backgroundLuminance
        ? foregroundLuminance
        : backgroundLuminance;
    final darker = foregroundLuminance > backgroundLuminance
        ? backgroundLuminance
        : foregroundLuminance;
    return (lighter + 0.05) / (darker + 0.05);
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
        fillColor: glass.inset,
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
