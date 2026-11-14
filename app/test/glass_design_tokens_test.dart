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
  });

  test('glass scene follows and releases the theme switch backdrop phase', () {
    final frame = GlassSceneFrame();
    var notifications = 0;
    frame.addListener(() => notifications++);

    frame.publishThemeSwitch(1.25, 0.42);
    expect(frame.seconds, 1.25);
    expect(frame.switchDaylight, 0.42);
    frame.clearThemeSwitch();
    expect(frame.switchDaylight, isNull);
    expect(notifications, 2);

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
