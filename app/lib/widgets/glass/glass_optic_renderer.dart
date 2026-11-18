import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// The shared runtime effect used by the theme switch and glass action buttons.
/// Each painter owns its FragmentShader because uniforms are mutable per draw;
/// the compiled FragmentProgram and 1×1 sampler are shared for the app lifetime.
abstract final class GlassOpticRenderer {
  static Future<ui.FragmentProgram>? _program;
  static ui.Image? _transparentSampler;

  static Future<ui.FragmentProgram> loadProgram() => _program ??=
      ui.FragmentProgram.fromAsset('shaders/glass_theme_switch.frag');

  static ui.Image get transparentSampler =>
      _transparentSampler ??= _makeTransparentSampler();

  static ui.Image _makeTransparentSampler() {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawColor(Colors.transparent, BlendMode.src);
    final picture = recorder.endRecording();
    final image = picture.toImageSync(1, 1);
    picture.dispose();
    return image;
  }

  /// Paint a rounded action lens through the same distance-field material
  /// functions used for the theme switch handle.
  static void paintActionLens({
    required Canvas canvas,
    required Size size,
    required ui.FragmentShader shader,
    required ui.Image sampler,
    required GlassActionLensFrame frame,
  }) {
    final zoom = frame.zoom;
    final halfExtent = Offset(
      ((size.width * .5 - 1) / zoom).clamp(1.0, size.width * .5 / zoom),
      ((size.height * .5 - 1) / zoom).clamp(1.0, size.height * .5 / zoom),
    );
    final floats = <double>[
      size.width,
      size.height,
      size.width * .5,
      size.height * .5,
      zoom,
      frame.displayRatio,
      0,
      0,
      halfExtent.dx,
      halfExtent.dy,
      frame.radius / zoom,
      frame.daylight,
      frame.time,
      frame.energy,
      frame.pressed ? 1 : 0,
      frame.angle,
      frame.accent.r,
      frame.accent.g,
      frame.accent.b,
      frame.refraction,
      frame.frost,
      frame.pixelGlow,
      frame.stripHalfAngle,
      0,
      0,
      0,
      0,
      1,
      frame.top.r,
      frame.top.g,
      frame.top.b,
      frame.bottom.r,
      frame.bottom.g,
      frame.bottom.b,
      frame.inset.r,
      frame.inset.g,
      frame.inset.b,
      frame.opacity,
      frame.hovered ? 1 : 0,
      frame.disabled ? 1 : 0,
      frame.selected ? 1 : 0,
      frame.navigation ? 1 : 0,
      frame.primary ? 1 : 0,
    ];
    for (var i = 0; i < floats.length; i++) {
      shader.setFloat(i, floats[i]);
    }
    shader.setImageSampler(0, sampler, filterQuality: FilterQuality.low);
    shader.setImageSampler(1, sampler, filterQuality: FilterQuality.low);
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }
}

@immutable
class GlassActionLensFrame {
  const GlassActionLensFrame({
    required this.daylight,
    required this.time,
    required this.displayRatio,
    required this.zoom,
    required this.radius,
    required this.energy,
    required this.angle,
    required this.refraction,
    required this.frost,
    required this.pixelGlow,
    required this.stripHalfAngle,
    required this.top,
    required this.bottom,
    required this.inset,
    required this.accent,
    required this.opacity,
    required this.pressed,
    required this.hovered,
    required this.disabled,
    required this.selected,
    required this.navigation,
    required this.primary,
  });

  final double daylight;
  final double time;
  final double displayRatio;
  final double zoom;
  final double radius;
  final double energy;
  final double angle;
  final double refraction;
  final double frost;
  final double pixelGlow;
  final double stripHalfAngle;
  final Color top;
  final Color bottom;
  final Color inset;
  final Color accent;
  final double opacity;
  final bool pressed;
  final bool hovered;
  final bool disabled;
  final bool selected;
  final bool navigation;
  final bool primary;
}
