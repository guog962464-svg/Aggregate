import 'dart:math' as math;

import 'package:aggregate/app/theme.dart';
import 'package:aggregate/widgets/glass/glass_design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('primary and secondary text meet WCAG AA contrast in both themes', () {
    for (final theme in [AggregateTheme.light, AggregateTheme.dark]) {
      final scheme = theme.colorScheme;
      for (final background in [
        scheme.surface,
        theme.scaffoldBackgroundColor,
      ]) {
        expect(
          _contrast(scheme.onSurface, background),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          _contrast(scheme.onSurfaceVariant, background),
          greaterThanOrEqualTo(4.5),
        );
      }
    }
  });

  test('glass labels and helper text meet AA on the glass material range', () {
    for (final tokens in [GlassDesignTokens.light, GlassDesignTokens.dark]) {
      for (final background in [
        tokens.surface,
        tokens.raised,
        tokens.glassTop,
        tokens.glassBottom,
      ]) {
        expect(_contrast(tokens.text, background), greaterThanOrEqualTo(4.5));
        expect(_contrast(tokens.muted, background), greaterThanOrEqualTo(4.5));
        expect(_contrast(tokens.danger, background), greaterThanOrEqualTo(4.5));
        for (final mark in [tokens.ink, tokens.glow, tokens.status]) {
          expect(_contrast(mark, background), greaterThanOrEqualTo(3));
        }
      }
    }
  });
}

double _contrast(Color first, Color second) {
  final a = _luminance(first);
  final b = _luminance(second);
  final lighter = a > b ? a : b;
  final darker = a > b ? b : a;
  return (lighter + 0.05) / (darker + 0.05);
}

double _luminance(Color color) {
  final value = color.toARGB32();
  double linear(int channel) {
    final normalized = channel / 255;
    return normalized <= 0.04045
        ? normalized / 12.92
        : math.pow((normalized + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * linear((value >> 16) & 0xff) +
      0.7152 * linear((value >> 8) & 0xff) +
      0.0722 * linear(value & 0xff);
}
