import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aggregate/app/theme.dart';
import 'package:aggregate/features/settings/glass_theme_switch.dart';
import 'package:aggregate/widgets/glass/glass_design_tokens.dart';
import 'package:aggregate/widgets/glass/glass_scene.dart';

void main() {
  test('macOS themes provide the continuous glass scene palette', () {
    final light = AggregateTheme.forPlatform(
      AggregateTheme.light,
      TargetPlatform.macOS,
    );
    final dark = AggregateTheme.forPlatform(
      AggregateTheme.dark,
      TargetPlatform.macOS,
    );

    expect(light.scaffoldBackgroundColor, Colors.transparent);
    expect(dark.scaffoldBackgroundColor, Colors.transparent);
    expect(light.extension<GlassDesignTokens>()?.daylight, 1);
    expect(dark.extension<GlassDesignTokens>()?.daylight, 0);
  });

  test('macOS theme changes interpolate glass brightness and colors', () {
    final light = AggregateTheme.forPlatform(
      AggregateTheme.light,
      TargetPlatform.macOS,
    );
    final dark = AggregateTheme.forPlatform(
      AggregateTheme.dark,
      TargetPlatform.macOS,
    );
    final halfway = ThemeData.lerp(light, dark, 0.5);
    final tokens = halfway.extension<GlassDesignTokens>()!;

    expect(tokens.daylight, closeTo(0.5, 1e-6));
    expect(
      tokens.surface,
      Color.lerp(
        GlassDesignTokens.light.surface,
        GlassDesignTokens.dark.surface,
        0.5,
      ),
    );
    expect(
      tokens.focusRing,
      Color.lerp(
        light.extension<GlassDesignTokens>()!.focusRing,
        dark.extension<GlassDesignTokens>()!.focusRing,
        0.5,
      ),
    );
  });

  test(
    'macOS foreground colors retain AA contrast during theme interpolation',
    () {
      final light = AggregateTheme.forPlatform(
        AggregateTheme.light,
        TargetPlatform.macOS,
      );
      final dark = AggregateTheme.forPlatform(
        AggregateTheme.dark,
        TargetPlatform.macOS,
      );

      expect(
        AggregateTheme.withMacOSSurfaceTextContrast(light)
            .colorScheme
            .onSurface,
        light.colorScheme.onSurface,
      );
      expect(
        AggregateTheme.withMacOSSurfaceTextContrast(dark).colorScheme.onSurface,
        dark.colorScheme.onSurface,
      );

      for (var frame = 0; frame <= 100; frame++) {
        final interpolated = ThemeData.lerp(light, dark, frame / 100);
        final safe = AggregateTheme.withMacOSSurfaceTextContrast(interpolated);
        final surface = safe.colorScheme.surface;
        final tokens = safe.extension<GlassDesignTokens>()!;

        expect(
          _contrast(safe.colorScheme.onSurface, surface),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          _contrast(safe.colorScheme.onSurfaceVariant, surface),
          greaterThanOrEqualTo(4.5),
        );
        expect(_contrast(tokens.text, surface), greaterThanOrEqualTo(4.5));
        expect(_contrast(tokens.muted, surface), greaterThanOrEqualTo(4.5));
        for (final style in [
          safe.textTheme.displayLarge,
          safe.textTheme.displayMedium,
          safe.textTheme.displaySmall,
          safe.textTheme.headlineLarge,
          safe.textTheme.headlineMedium,
          safe.textTheme.headlineSmall,
          safe.textTheme.titleLarge,
          safe.textTheme.titleMedium,
          safe.textTheme.titleSmall,
          safe.textTheme.bodyLarge,
          safe.textTheme.bodyMedium,
          safe.textTheme.bodySmall,
          safe.textTheme.labelLarge,
          safe.textTheme.labelMedium,
          safe.textTheme.labelSmall,
        ]) {
          if (style?.color case final color?) {
            expect(_contrast(color, surface), greaterThanOrEqualTo(4.5));
          }
        }
        expect(
          _contrast(safe.appBarTheme.foregroundColor!, surface),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          _contrast(safe.iconTheme.color!, surface),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          _contrast(safe.listTileTheme.titleTextStyle!.color!, surface),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          _contrast(safe.listTileTheme.subtitleTextStyle!.color!, surface),
          greaterThanOrEqualTo(4.5),
        );
      }
    },
  );

  test(
    'macOS page text remains readable on raised surfaces while blending',
    () {
      final light = AggregateTheme.forPlatform(
        AggregateTheme.light,
        TargetPlatform.macOS,
      );
      final dark = AggregateTheme.forPlatform(
        AggregateTheme.dark,
        TargetPlatform.macOS,
      );
      final styles = [
        (
          name: 'headline',
          get: (ThemeData theme) => theme.textTheme.headlineMedium,
        ),
        (name: 'title', get: (ThemeData theme) => theme.textTheme.titleMedium),
        (name: 'body', get: (ThemeData theme) => theme.textTheme.bodyMedium),
        (
          name: 'small body',
          get: (ThemeData theme) => theme.textTheme.bodySmall,
        ),
        (
          name: 'list title',
          get: (ThemeData theme) => theme.listTileTheme.titleTextStyle,
        ),
        (
          name: 'list subtitle',
          get: (ThemeData theme) => theme.listTileTheme.subtitleTextStyle,
        ),
      ];

      for (var frame = 0; frame <= 100; frame++) {
        final safe = AggregateTheme.withMacOSSurfaceTextContrast(
          ThemeData.lerp(dark, light, frame / 100),
        );
        final surfaces = [
          (name: 'surface', color: safe.colorScheme.surface),
          (name: 'low', color: safe.colorScheme.surfaceContainerLow),
          (name: 'container', color: safe.colorScheme.surfaceContainer),
        ];
        for (final style in styles) {
          final textStyle = style.get(safe);
          final foreground = textStyle?.color;
          if (textStyle == null || foreground == null) continue;
          final needsHalo = textStyle.shadows?.isNotEmpty ?? false;
          expect(textStyle.shadows?.length ?? 0, needsHalo ? 8 : 0);
          if (needsHalo) {
            final halo = foreground == Colors.black
                ? Colors.white
                : Colors.black;
            expect(
              textStyle.shadows!.every((shadow) => shadow.color == halo),
              isTrue,
            );
            expect(_contrast(foreground, halo), greaterThanOrEqualTo(7));
          }
          for (final surface in surfaces) {
            if (needsHalo) {
              final halo = textStyle.shadows!.first.color;
              expect(
                _contrast(halo, surface.color),
                greaterThanOrEqualTo(3),
                reason: 'frame $frame ${style.name} halo on ${surface.name}',
              );
            } else {
              expect(
                _contrast(foreground, surface.color),
                greaterThanOrEqualTo(4.5),
                reason:
                    'frame $frame ${style.name} color $foreground on '
                    '${surface.name} (${surface.color})',
              );
            }
          }
        }
      }
    },
  );

  test(
    'backdrop text follows the scene while surface colors stay readable',
    () {
      final baseTheme = AggregateTheme.withMacOSSurfaceTextContrast(
        AggregateTheme.forPlatform(AggregateTheme.dark, TargetPlatform.macOS),
      );
      final baseTokens = baseTheme.extension<GlassDesignTokens>()!;

      for (final (usesDarkForeground, expected) in [
        (true, Colors.black),
        (false, Colors.white),
      ]) {
        final theme = AggregateTheme.withMacOSBackdropTextContrast(
          baseTheme,
          usesDarkForeground: usesDarkForeground,
        );
        final tokens = theme.extension<GlassDesignTokens>()!;

        expect(theme.colorScheme.onSurface, baseTheme.colorScheme.onSurface);
        expect(
          theme.colorScheme.onSurfaceVariant,
          baseTheme.colorScheme.onSurfaceVariant,
        );
        for (final surface in [
          theme.colorScheme.surface,
          theme.colorScheme.surfaceContainerLow,
          theme.colorScheme.surfaceContainer,
        ]) {
          expect(
            _contrast(theme.colorScheme.onSurface, surface),
            greaterThanOrEqualTo(4.5),
          );
          expect(
            _contrast(theme.colorScheme.onSurfaceVariant, surface),
            greaterThanOrEqualTo(4.5),
          );
        }
        expect(theme.textTheme.bodyMedium?.color, expected);
        expect(theme.textTheme.bodySmall?.color, expected);
        expect(theme.appBarTheme.foregroundColor, expected);
        expect(theme.iconTheme.color, expected);
        expect(theme.listTileTheme.titleTextStyle?.color, expected);
        expect(theme.listTileTheme.subtitleTextStyle?.color, expected);
        expect(tokens.text, baseTokens.text);
        expect(tokens.muted, baseTokens.muted);
      }
    },
  );

  test('glass text gets a one-pixel contrasting halo only when needed', () {
    final baseTheme = AggregateTheme.withMacOSSurfaceTextContrast(
      AggregateTheme.forPlatform(AggregateTheme.dark, TargetPlatform.macOS),
    );

    for (final (usesDarkForeground, foreground, halo) in [
      (true, Colors.black, Colors.white),
      (false, Colors.white, Colors.black),
    ]) {
      final theme = AggregateTheme.withMacOSBackdropTextContrast(
        baseTheme,
        usesDarkForeground: usesDarkForeground,
        addContrastHalo: true,
      );
      final textStyle = theme.textTheme.bodyMedium!;

      expect(textStyle.color, foreground);
      expect(textStyle.shadows, hasLength(8));
      expect(theme.textTheme.labelLarge?.shadows, isNull);
      expect(
        textStyle.shadows!.every((shadow) => shadow.color == halo),
        isTrue,
      );
    }

    final noHalo = AggregateTheme.withMacOSBackdropTextContrast(
      baseTheme,
      usesDarkForeground: false,
    );
    expect(noHalo.textTheme.bodyMedium!.shadows, isNull);
  });

  test('glass scene follows and releases the theme switch backdrop phase', () {
    final frame = GlassSceneFrame();
    var notifications = 0;
    final textForegroundStates = <bool?>[];
    frame.addListener(() => notifications++);
    frame.textContrastUsesDarkForeground.addListener(
      () =>
          textForegroundStates.add(frame.textContrastUsesDarkForeground.value),
    );

    frame.publishThemeSwitch(1.25, 0.42);
    frame.publishThemeSwitch(1.26, 0.43);
    frame.publishThemeSwitch(1.27, 0.51);
    frame.publishThemeSwitch(1.28, 0.62);
    frame.publishThemeSwitch(1.29, 0.48);
    expect(frame.seconds, 1.29);
    expect(frame.switchDaylight, 0.48);
    expect(textForegroundStates, [false, true, false]);
    frame.clearThemeSwitch();
    expect(frame.switchDaylight, isNull);
    expect(textForegroundStates, [false, true, false, null]);
    expect(notifications, 6);

    frame.dispose();
  });

  test('glass scene halo changes only at the measured contrast window', () {
    final frame = GlassSceneFrame();
    final haloStates = <bool>[];
    frame.textContrastNeedsHalo.addListener(
      () => haloStates.add(frame.textContrastNeedsHalo.value),
    );

    frame.publishThemeSwitch(1, 0.455);
    expect(frame.textContrastNeedsHalo.value, isFalse);
    frame.publishThemeSwitch(1.01, 0.46);
    frame.publishThemeSwitch(1.02, 0.475);
    frame.publishThemeSwitch(1.03, 0.5);
    frame.publishThemeSwitch(1.04, 0.51);
    frame.publishThemeSwitch(1.05, 0.515);
    frame.publishThemeSwitch(1.06, 0.52);
    expect(frame.textContrastNeedsHalo.value, isTrue);
    frame.publishThemeSwitch(1.07, 0.525);
    frame.publishThemeSwitch(1.08, 0.53);
    expect(frame.textContrastNeedsHalo.value, isTrue);
    frame.publishThemeSwitch(1.09, 0.535);
    expect(frame.textContrastNeedsHalo.value, isFalse);
    frame.clearThemeSwitch();

    expect(haloStates, [true, false]);
    frame.dispose();
  });

  test('other platform themes do not enable the glass scene palette', () {
    final android = AggregateTheme.forPlatform(
      AggregateTheme.light,
      TargetPlatform.android,
    );
    final windows = AggregateTheme.forPlatform(
      AggregateTheme.light,
      TargetPlatform.windows,
    );

    expect(android.extension<GlassDesignTokens>(), isNull);
    expect(windows.extension<GlassDesignTokens>(), isNull);
    expect(
      android.scaffoldBackgroundColor,
      AggregateTheme.light.scaffoldBackgroundColor,
    );
    expect(
      windows.scaffoldBackgroundColor,
      AggregateTheme.light.scaffoldBackgroundColor,
    );
  });

  testWidgets('glass scene keeps a logical viewport at both pixel ratios', (
    tester,
  ) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    for (final ratio in [1.0, 2.0]) {
      tester.view.devicePixelRatio = ratio;
      tester.view.physicalSize = Size(800 * ratio, 600 * ratio);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.macOS),
          home: const GlassScene(child: SizedBox.expand()),
        ),
      );
      await tester.pump(const Duration(milliseconds: 16));

      expect(tester.getSize(find.byType(GlassScene)), const Size(800, 600));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'theme switch resolves its offset in the root scene after layout',
    (tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.macOS),
          builder: (context, child) =>
              GlassScene(child: child ?? const SizedBox.shrink()),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 24, top: 18),
                child: SizedBox(
                  width: 360,
                  child: GlassThemeSwitch(light: false, onChanged: (_) {}),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      final artwork = tester.widget<ThemeSwitchArtwork>(
        find.byType(ThemeSwitchArtwork),
      );
      expect(artwork.backdropOrigin, const Offset(24, 18));
      expect(artwork.backdropSize, const Size(800, 600));
      expect(tester.takeException(), isNull);
    },
  );
}

double _contrast(Color foreground, Color background) {
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
