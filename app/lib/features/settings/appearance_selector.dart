import 'dart:math' as math;

import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:flutter/material.dart';

class AppearanceSelector extends StatelessWidget {
  const AppearanceSelector({
    super.key,
    required this.appearance,
    required this.onChanged,
    required this.systemLabel,
  });

  final AppearancePreference appearance;
  final ValueChanged<AppearancePreference> onChanged;
  final String systemLabel;

  @override
  Widget build(BuildContext context) {
    final effectiveDark = switch (appearance) {
      AppearancePreference.dark => true,
      AppearancePreference.light => false,
      AppearancePreference.system =>
        Theme.of(context).brightness == Brightness.dark,
    };
    final followsSystem = appearance == AppearancePreference.system;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final duration = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 480);
    final currentMode = effectiveDark ? '深色' : '浅色';
    final groupLabel = followsSystem
        ? '主题模式，$systemLabel，当前$currentMode'
        : '主题模式，当前$currentMode';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          container: true,
          explicitChildNodes: true,
          label: groupLabel,
          child: _ThemeModeTrack(
            effectiveDark: effectiveDark,
            appearance: appearance,
            followsSystem: followsSystem,
            duration: duration,
            onChanged: onChanged,
          ),
        ),
        const SizedBox(height: 8),
        Semantics(
          button: true,
          selected: followsSystem,
          label: systemLabel,
          onTap: () => onChanged(AppearancePreference.system),
          child: ExcludeSemantics(
            child: TextButton.icon(
              onPressed: () => onChanged(AppearancePreference.system),
              style: TextButton.styleFrom(
                minimumSize: const Size(48, 48),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                foregroundColor: followsSystem
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.onSurfaceVariant,
                backgroundColor: followsSystem
                    ? Theme.of(context).colorScheme.primaryContainer
                          .withValues(alpha: 0.48)
                    : Colors.transparent,
                shape: const StadiumBorder(),
              ),
              icon: const Icon(Icons.brightness_auto_outlined, size: 18),
              label: Text(systemLabel),
            ),
          ),
        ),
      ],
    );
  }
}

class _ThemeModeTrack extends StatelessWidget {
  const _ThemeModeTrack({
    required this.effectiveDark,
    required this.appearance,
    required this.followsSystem,
    required this.duration,
    required this.onChanged,
  });

  final bool effectiveDark;
  final AppearancePreference appearance;
  final bool followsSystem;
  final Duration duration;
  final ValueChanged<AppearancePreference> onChanged;

  static const _trackWidth = 176.0;
  static const _trackHeight = 82.0;
  static const _violet = Color(0xFF8B7AFF);
  static const _amber = Color(0xFFF2BD5B);

  @override
  Widget build(BuildContext context) {
    final trackFill = effectiveDark
        ? const Color(0xFF090A0F)
        : const Color(0xFFBFC1C4);
    final currentGlow = effectiveDark ? _violet : _amber;

    return Container(
      width: math
          .min(_trackWidth, MediaQuery.sizeOf(context).width - 40)
          .toDouble(),
      height: _trackHeight,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: trackFill,
        borderRadius: BorderRadius.circular(25),
        border: Border.all(
          color: effectiveDark
              ? const Color(0xFF292A32)
              : const Color(0xFFD9DADD),
          width: 0.8,
        ),
        boxShadow: [
          BoxShadow(
            color: effectiveDark
                ? const Color(0xFF23213A).withValues(alpha: 0.5)
                : Colors.white.withValues(alpha: 0.5),
            blurRadius: 20,
            spreadRadius: 1,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: effectiveDark ? 0.34 : 0.12),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final gap = 6.0;
          final optionWidth = (constraints.maxWidth - gap) / 2;
          return Stack(
            children: [
              AnimatedAlign(
                alignment: effectiveDark
                    ? Alignment.centerLeft
                    : Alignment.centerRight,
                duration: duration,
                curve: Curves.easeInOutCubic,
                child: IgnorePointer(
                  child: _SelectedGlow(
                    width: optionWidth,
                    height: constraints.maxHeight,
                    dark: effectiveDark,
                    glow: currentGlow,
                    duration: duration,
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: _ThemeModeOption(
                      label: '深色主题',
                      sun: false,
                      visuallyActive: effectiveDark,
                      selected: appearance == AppearancePreference.dark,
                      followsSystem: followsSystem,
                      duration: duration,
                      onPressed: () => onChanged(AppearancePreference.dark),
                    ),
                  ),
                  SizedBox(width: gap),
                  Expanded(
                    child: _ThemeModeOption(
                      label: '浅色主题',
                      sun: true,
                      visuallyActive: !effectiveDark,
                      selected: appearance == AppearancePreference.light,
                      followsSystem: followsSystem,
                      duration: duration,
                      onPressed: () => onChanged(AppearancePreference.light),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SelectedGlow extends StatelessWidget {
  const _SelectedGlow({
    required this.width,
    required this.height,
    required this.dark,
    required this.glow,
    required this.duration,
  });

  final double width;
  final double height;
  final bool dark;
  final Color glow;
  final Duration duration;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    width: width,
    height: height,
    duration: duration,
    curve: Curves.easeInOutCubic,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(20),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: dark
            ? const [Color(0xFF494852), Color(0xFF1E1F28)]
            : const [Color(0xFFE5E4DF), Color(0xFFD0D0CB)],
      ),
      border: Border.all(color: glow.withValues(alpha: 0.8), width: 1.1),
      boxShadow: [
        BoxShadow(
          color: glow.withValues(alpha: dark ? 0.5 : 0.42),
          blurRadius: 24,
          spreadRadius: 1,
        ),
        BoxShadow(
          color: glow.withValues(alpha: 0.72),
          blurRadius: 11,
          spreadRadius: -2,
        ),
        BoxShadow(
          color: dark
              ? Colors.black.withValues(alpha: 0.45)
              : Colors.white.withValues(alpha: 0.5),
          blurRadius: 5,
          offset: const Offset(0, 3),
        ),
      ],
    ),
  );
}

class _ThemeModeOption extends StatelessWidget {
  const _ThemeModeOption({
    required this.label,
    required this.sun,
    required this.visuallyActive,
    required this.selected,
    required this.followsSystem,
    required this.duration,
    required this.onPressed,
  });

  final String label;
  final bool sun;
  final bool visuallyActive;
  final bool selected;
  final bool followsSystem;
  final Duration duration;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final activeGlyphColor = sun
        ? const Color(0xFF54472D)
        : const Color(0xFFF5F3FF);
    final inactiveGlyphColor = sun
        ? const Color(0xFF8B8982)
        : const Color(0xFF595C6B);
    final accessibleLabel = followsSystem && visuallyActive
        ? '$label，当前系统外观'
        : label;

    return Semantics(
      button: true,
      selected: selected,
      label: accessibleLabel,
      onTap: onPressed,
      child: InkWell(
        excludeFromSemantics: true,
        onTap: onPressed,
        borderRadius: BorderRadius.circular(20),
        child: ExcludeSemantics(
          child: SizedBox.expand(
            child: Center(
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(
                  begin: visuallyActive ? 1 : 0,
                  end: visuallyActive ? 1 : 0,
                ),
                duration: duration,
                curve: Curves.easeInOutCubic,
                builder: (context, progress, _) => CustomPaint(
                  size: const Size.square(32),
                  painter: _ThemeGlyphPainter(
                    sun: sun,
                    color: Color.lerp(
                      inactiveGlyphColor,
                      activeGlyphColor,
                      progress,
                    )!,
                    activation: progress,
                    glow: sun
                        ? const Color(0xFFF2BD5B)
                        : const Color(0xFF8B7AFF),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ThemeGlyphPainter extends CustomPainter {
  const _ThemeGlyphPainter({
    required this.sun,
    required this.color,
    required this.activation,
    this.glow,
  });

  final bool sun;
  final Color color;
  final double activation;
  final Color? glow;

  @override
  void paint(Canvas canvas, Size size) {
    const cells = 15;
    final cell = math.min(size.width, size.height) / cells;
    final left = (size.width - cell * cells) / 2;
    final top = (size.height - cell * cells) / 2;
    final pixels = <({Rect rect, double alpha})>[];
    final glowPath = Path();

    for (var y = 0; y < cells; y++) {
      for (var x = 0; x < cells; x++) {
        final alpha = _pixelAlpha(x, y);
        if (alpha == null) continue;
        final rect = Rect.fromLTWH(
          left + x * cell,
          top + y * cell,
          cell * 0.86,
          cell * 0.86,
        );
        pixels.add((rect: rect, alpha: alpha));
        glowPath.addRect(rect);
      }
    }

    if (glow case final glowColor?) {
      canvas.drawPath(
        glowPath,
        Paint()
          ..color = glowColor.withValues(alpha: 0.34)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.5),
      );
    }

    final center = Offset(size.width / 2, size.height / 2);
    for (final pixel in pixels) {
      var rect = pixel.rect;
      if (sun && pixel.alpha < 0.8) {
        final reach = 0.42 + activation * 0.58;
        final dotSize = cell * (0.38 + activation * 0.48);
        final pixelCenter = rect.center;
        final point = center + (pixelCenter - center) * reach;
        rect = Rect.fromCenter(center: point, width: dotSize, height: dotSize);
      }
      canvas.drawRect(
        rect,
        Paint()..color = color.withValues(alpha: pixel.alpha),
      );
    }
  }

  double? _pixelAlpha(int x, int y) {
    if (sun) return _sunPixelAlpha(x, y);

    final outer = math.pow((x - 6.5) / 6.25, 2) + math.pow((y - 7.2) / 6.6, 2);
    final cutout = math.pow((x - 9.5) / 5.15, 2) + math.pow((y - 4.3) / 5.3, 2);
    final crescent = outer <= 1 && cutout > 1;
    final particle = ((x * 7 + y * 11) % 5) == 0;
    final star =
        (x == 11 && y == 2) ||
        (x == 12 && y == 5) ||
        (x == 10 && y == 9) ||
        (x == 11 && y == 12);

    if (star) return 0.48 + activation * 0.52;
    if (crescent) {
      final texture = ((x + y * 2) % 4) == 0 ? 0.7 : 1.0;
      return texture * (0.42 + activation * 0.58);
    }
    if (outer <= 1.28 && cutout <= 1.12 && particle) {
      return 0.12 + activation * 0.28;
    }
    if (outer > 1 && outer <= 1.38 && particle) {
      return 0.08 + activation * 0.2;
    }
    return null;
  }

  double? _sunPixelAlpha(int x, int y) {
    final center = x >= 5 && x <= 9 && y >= 5 && y <= 9;
    final cardinalRay =
        (x == 7 && (y == 1 || y == 2 || y == 12 || y == 13)) ||
        (y == 7 && (x == 1 || x == 2 || x == 12 || x == 13));
    final diagonalRay =
        (x == 3 && (y == 3 || y == 11)) || (x == 11 && (y == 3 || y == 11));
    if (center) {
      final gridTexture = ((x + y) % 5) == 0 ? 0.72 : 1.0;
      return gridTexture * (0.44 + activation * 0.56);
    }
    if (cardinalRay) return 0.18 + activation * 0.82;
    if (diagonalRay) return 0.12 + activation * 0.72;
    return null;
  }

  @override
  bool shouldRepaint(covariant _ThemeGlyphPainter oldDelegate) =>
      sun != oldDelegate.sun ||
      color != oldDelegate.color ||
      activation != oldDelegate.activation ||
      glow != oldDelegate.glow;
}
