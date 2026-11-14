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
  final Color ink;
  final Color warm;
  final Color status;
  final Color danger;
  final Color shadow;

  static const dark = GlassDesignTokens(
    daylight: 0,
    surface: Color(0xFF202126),
    raised: Color(0xFF292B32),
    text: Color(0xFFEFEFF3),
    muted: Color(0xFFA6A8B3),
    line: Color(0xFF35363E),
    inset: Color(0xFF111216),
    glassTop: Color(0xFF41434C),
    glassBottom: Color(0xFF242630),
    highlight: Color(0x3BF0F3FF),
    glow: Color(0xFF8B9AFF),
    ink: Color(0xFFF4EFDF),
    warm: Color(0xFFFFD29B),
    status: Color(0xFFA2D6BC),
    danger: Color(0xFFF2A09D),
    shadow: Color(0x99000000),
  );

  static const light = GlassDesignTokens(
    daylight: 1,
    surface: Color(0xFFF3F3F5),
    raised: Color(0xFFFBFBFC),
    text: Color(0xFF27272F),
    muted: Color(0xFF656571),
    line: Color(0xFFC9C9D2),
    inset: Color(0xFFD4D4DC),
    glassTop: Color(0xFFFFFFFF),
    glassBottom: Color(0xFFECECF0),
    highlight: Color(0xF2FFFFFF),
    glow: Color(0xFFB06520),
    ink: Color(0xFF4F493B),
    warm: Color(0xFF8D4B16),
    status: Color(0xFF35735B),
    danger: Color(0xFFA24640),
    shadow: Color(0x385A596F),
  );

  static GlassDesignTokens forBrightness(Brightness brightness) =>
      brightness == Brightness.light ? light : dark;

  static const double primaryHeight = 54;
  static const double secondaryHeight = 40;
  static const double iconButtonSize = 46;
  static const double referenceHeight = 96;

  static const int glyphGridSize = 9;
  static const double glyphPitch = 2.7;
  static const double glyphCellSize = 1.9;
  static const double glyphCornerRadius = 0.64;
  static const double glyphFeather = 0.17;
  static const double glyphOuterHalo = 0.16;
  static const double glyphHaloAlpha = 0.075;

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
      ink: Color.lerp(ink, other.ink, t)!,
      warm: Color.lerp(warm, other.warm, t)!,
      status: Color.lerp(status, other.status, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
    );
  }
}
