import 'package:aggregate/app/aggregate_app.dart';
import 'package:aggregate/features/settings/settings_page.dart';
import 'package:aggregate/features/settings/glass_theme_switch.dart';
import 'package:aggregate/preview/preview_runtime_factory.dart';
import 'package:aggregate/widgets/glass/glass_motion.dart';
import 'package:aggregate/widgets/glass/glass_scene.dart';
import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _macOS = TargetPlatformVariant({TargetPlatform.macOS});

void main() {
  testWidgets(
    'system reduced motion reaches the app and keeps the theme switch usable',
    (tester) async {
      final runtime = createPreviewRuntime();
      await runtime.savePreferences(
        const UserPreferences(appearance: AppearancePreference.dark),
      );
      final systemDisableAnimations = ValueNotifier(false);
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(systemDisableAnimations.dispose);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await runtime.dispose();
      });

      await tester.pumpWidget(
        AggregateApp(
          runtime: runtime,
          glassMotionClock: ManualGlassMotionClock(),
          systemDisableAnimations: systemDisableAnimations,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('设置').first);
      await tester.pump();
      for (var frame = 0; frame < 60; frame++) {
        await tester.pump(const Duration(microseconds: 16667));
      }

      final settings = find.byType(SettingsPage);
      expect(MediaQuery.disableAnimationsOf(tester.element(settings)), isFalse);

      systemDisableAnimations.value = true;
      await tester.pump();
      expect(MediaQuery.disableAnimationsOf(tester.element(settings)), isTrue);
      expect(
        tester
            .widget<ThemeSwitchArtwork>(find.byType(ThemeSwitchArtwork))
            .frame
            .position,
        0,
      );

      await tester.tap(find.bySemanticsLabel('外观主题'));
      await tester.pump();
      await tester.pump();
      expect(
        (await runtime.loadPreferences()).appearance,
        AppearancePreference.light,
      );
      expect(
        tester
            .widget<ThemeSwitchArtwork>(find.byType(ThemeSwitchArtwork))
            .frame
            .position,
        1,
      );
      expect(tester.takeException(), isNull);

      systemDisableAnimations.value = false;
      await tester.pump();
      expect(MediaQuery.disableAnimationsOf(tester.element(settings)), isFalse);
    },
    variant: _macOS,
  );

  testWidgets(
    'settings text follows the live glass switch in both directions',
    (tester) async {
      final runtime = createPreviewRuntime();
      await runtime.savePreferences(
        const UserPreferences(appearance: AppearancePreference.dark),
      );
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await runtime.dispose();
      });

      await tester.pumpWidget(
        AggregateApp(
          runtime: runtime,
          glassMotionClock: ManualGlassMotionClock(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('设置').first);
      for (var frame = 0; frame < 60; frame++) {
        await tester.pump(const Duration(microseconds: 16667));
      }

      final switchFinder = find.bySemanticsLabel('外观主题');
      final pageTextFinder = find.text('主题选择保存在本机。');
      Future<void> verifyFrames() async {
        for (var frame = 0; frame < 40; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
          final switchFrame = tester
              .widget<ThemeSwitchArtwork>(find.byType(ThemeSwitchArtwork))
              .frame;
          final expectedForeground = switchFrame.theme >= 0.5
              ? Colors.black
              : Colors.white;
          final pageText = tester.element(pageTextFinder);
          final haloFrame = tester
              .widget<GlassSceneScope>(find.byType(GlassSceneScope))
              .frame;
          final expectedHalo =
              switchFrame.theme >= 0.46 && switchFrame.theme <= 0.52;
          expect(
            DefaultTextStyle.of(pageText).style.color,
            expectedForeground,
            reason: 'Shader phase ${switchFrame.theme} at sample $frame',
          );
          expect(
            haloFrame.textContrastNeedsHalo.value,
            expectedHalo,
            reason: 'Contrast halo phase ${switchFrame.theme} at sample $frame',
          );
          expect(
            DefaultTextStyle.of(pageText).style.shadows?.length ?? 0,
            expectedHalo ? 8 : 0,
            reason: 'Text outline phase ${switchFrame.theme} at sample $frame',
          );
          expect(tester.takeException(), isNull);
        }
      }

      await tester.tap(switchFinder);
      await verifyFrames();
      await tester.tap(switchFinder);
      await verifyFrames();
    },
    variant: _macOS,
  );
}
