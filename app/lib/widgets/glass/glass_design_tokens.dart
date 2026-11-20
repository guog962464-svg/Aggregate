import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

/// macOS glass colors and dimensions shared by the window backdrop and the
/// glass controls. The theme switch keeps its own calibrated optical values.
@immutable
class GlassDesignTokens extends ThemeExtension<GlassDesignTokens> {
  const GlassDesignTokens({
    required this.daylight,
    required this.surface,
    required this.raised,
    required this.text,
    required this.muted,
    required this.line,
    required this.inset,
    required this.glassTop,
    required this.glassBottom,
    required this.highlight,
    required this.glow,
    required this.focusRing,
    required this.ink,
    required this.warm,
    required this.status,
    required this.danger,
    required this.shadow,
  });

  final double daylight;
  final Color surface;
  final Color raised;
  final Color text;
  final Color muted;
  final Color line;
  final Color inset;
  final Color glassTop;
  final Color glassBottom;
  final Color highlight;
  final Color glow;
  final Color focusRing;
  final Color ink;
  final Color warm;
  final Color status;
  final Color danger;
  final Color shadow;

  static const dark = GlassDesignTokens(
    daylight: 0,
    surface: Color(0xFF191A1B),
    raised: Color(0xFF222325),
    text: Color(0xFFF0EFEB),
    muted: Color(0xFFB4B1AA),
    line: Color(0xFF41413F),
    inset: Color(0xFF161718),
    glassTop: Color(0xFF383A3B),
    glassBottom: Color(0xFF292A2C),
    highlight: Color(0x42FFFFFF),
    glow: Color(0xFFD28A3D),
    focusRing: Color(0xFFF2BD70),
    ink: Color(0xFFDFD5C1),
    warm: Color(0xFFF2BD70),
    status: Color(0xFF9DC7AA),
    danger: Color(0xFFE5948C),
    shadow: Color(0x4D000000),
  );

  static const light = GlassDesignTokens(
    daylight: 1,
    surface: Color(0xFFD9D8D5),
    raised: Color(0xFFF8F7F3),
    text: Color(0xFF2B2A27),
    muted: Color(0xFF686761),
    line: Color(0xFFC1BFBA),
    inset: Color(0xFFD0CEC8),
    glassTop: Color(0xFFF8F7F3),
    glassBottom: Color(0xFFE5E3DE),
    highlight: Color(0xD8FFFFFF),
    glow: Color(0xFFA95F1E),
    focusRing: Color(0xFFA95F1E),
    ink: Color(0xFF5D574B),
    warm: Color(0xFFFFC66B),
    status: Color(0xFF35735B),
    danger: Color(0xFFA24640),
    shadow: Color(0x2B4C4942),
  );

  static GlassDesignTokens forBrightness(Brightness brightness) =>
      brightness == Brightness.light ? light : dark;

  static const double primaryHeight = 46;
  static const double secondaryHeight = 40;
  static const double iconButtonSize = 46;
  static const double referenceHeight = 96;
  static const double disabledButtonFaceOpacity = .52;
  static const double restingButtonInsetOpacity = .13;

  static const int glyphGridSize = 9;
  static const double glyphPitch = 2.7;
  static const double glyphCellSize = 2.15;
  static const double glyphCornerRadius = 1.075;
  static const double glyphFeather = 0.28;
  static const double glyphOuterHalo = 0.18;
  static const double glyphHaloAlpha = 0.10;

  @override
  GlassDesignTokens copyWith({
    double? daylight,
    Color? surface,
    Color? raised,
    Color? text,
    Color? muted,
    Color? line,
    Color? inset,
    Color? glassTop,
    Color? glassBottom,
    Color? highlight,
    Color? glow,
    Color? focusRing,
    Color? ink,
    Color? warm,
    Color? status,
    Color? danger,
    Color? shadow,
  }) => GlassDesignTokens(
    daylight: daylight ?? this.daylight,
    surface: surface ?? this.surface,
    raised: raised ?? this.raised,
    text: text ?? this.text,
    muted: muted ?? this.muted,
    line: line ?? this.line,
    inset: inset ?? this.inset,
    glassTop: glassTop ?? this.glassTop,
    glassBottom: glassBottom ?? this.glassBottom,
    highlight: highlight ?? this.highlight,
    glow: glow ?? this.glow,
    focusRing: focusRing ?? this.focusRing,
    ink: ink ?? this.ink,
    warm: warm ?? this.warm,
    status: status ?? this.status,
    danger: danger ?? this.danger,
    shadow: shadow ?? this.shadow,
  );

  @override
  GlassDesignTokens lerp(
    covariant ThemeExtension<GlassDesignTokens>? other,
    double t,
  ) {
    if (other is! GlassDesignTokens) return this;
    return GlassDesignTokens(
      daylight: lerpDouble(daylight, other.daylight, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      raised: Color.lerp(raised, other.raised, t)!,
      text: Color.lerp(text, other.text, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      line: Color.lerp(line, other.line, t)!,
      inset: Color.lerp(inset, other.inset, t)!,
      glassTop: Color.lerp(glassTop, other.glassTop, t)!,
      glassBottom: Color.lerp(glassBottom, other.glassBottom, t)!,
      highlight: Color.lerp(highlight, other.highlight, t)!,
      glow: Color.lerp(glow, other.glow, t)!,
      focusRing: Color.lerp(focusRing, other.focusRing, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      warm: Color.lerp(warm, other.warm, t)!,
      status: Color.lerp(status, other.status, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
    );
  }
}
