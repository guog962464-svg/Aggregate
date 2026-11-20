import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'glass_design_tokens.dart';
import 'glass_motion.dart';

/// A quiet glass surface for content groups that appear in the macOS boards.
///
/// It only activates inside the macOS glass scene. Other platforms keep the
/// ordinary Material surface and border so the shared page code stays portable.
class GlassPanelSurface extends StatelessWidget {
  const GlassPanelSurface({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
    this.blurSigma = 10,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final double blurSigma;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens =
        theme.extension<GlassDesignTokens>() ??
        GlassDesignTokens.forBrightness(theme.brightness);
    final isMacGlass =
        defaultTargetPlatform == TargetPlatform.macOS &&
        GlassMotionScope.maybeOf(context) != null;
    final decoration = isMacGlass
        ? BoxDecoration(
            borderRadius: borderRadius,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                tokens.glassTop.withValues(alpha: .76),
                tokens.glassBottom.withValues(alpha: .78),
              ],
            ),
            border: Border.all(color: tokens.highlight.withValues(alpha: .42)),
          )
        : BoxDecoration(
            color: tokens.surface,
            borderRadius: borderRadius,
            border: Border.all(color: theme.dividerColor),
          );
    final surface = DecoratedBox(decoration: decoration, child: child);

    if (!isMacGlass) return surface;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: [
          BoxShadow(
            color: tokens.shadow.withValues(alpha: .24),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
          BoxShadow(
            color: tokens.glassTop.withValues(alpha: .24),
            blurRadius: 1,
            offset: const Offset(0, -1),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
          child: surface,
        ),
      ),
    );
  }
}
