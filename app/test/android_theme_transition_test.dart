import 'package:aggregate/app/aggregate_app.dart';
import 'package:aggregate/app/theme.dart';
import 'package:aggregate/features/settings/glass_theme_switch.dart';
import 'package:aggregate/features/settings/settings_page.dart';
import 'package:aggregate/preview/preview_runtime_factory.dart';
import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'Android applies the page theme once while the live glass switch keeps moving',
    (tester) async {
      final runtime = createPreviewRuntime();
      await runtime.savePreferences(
        const UserPreferences(appearance: AppearancePreference.dark),
      );
      _setView(tester, const Size(393, 852));
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await runtime.dispose();
      });
      await tester.pumpWidget(AggregateApp(runtime: runtime));
      await tester.pumpAndSettle();
      await _openSettings(tester);

      expect(_pageTheme(tester).brightness, Brightness.dark);
      expect(_artwork(tester).frame.position, closeTo(0, 0.002));
      expect(
        MediaQuery.disableAnimationsOf(
          tester.element(find.byType(SettingsPage)),
        ),
        isFalse,
      );
      await tester.tap(find.bySemanticsLabel('外观主题'));
      await tester.pump();

      expect(
        (await runtime.loadPreferences()).appearance,
        AppearancePreference.light,
      );
      final target = AggregateTheme.light.colorScheme;
      expect(_pageTheme(tester).brightness, Brightness.light);
      expect(_pageTheme(tester).colorScheme.surface, target.surface);
      expect(_pageTheme(tester).colorScheme.primary, target.primary);

      await tester.pump(const Duration(milliseconds: 33));
      final early = _artwork(tester).frame;
      expect(early.position, allOf(greaterThan(0), lessThan(1)));
      await tester.pump(const Duration(milliseconds: 67));
      final later = _artwork(tester).frame;
      expect(later.position, allOf(greaterThan(early.position), lessThan(1)));
      expect(later.theta, isNot(closeTo(early.theta, 1e-8)));
      expect(_pageTheme(tester).colorScheme.surface, target.surface);
      expect(_pageTheme(tester).colorScheme.primary, target.primary);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets('macOS retains its animated glass theme transition', (
    tester,
  ) async {
    final runtime = createPreviewRuntime();
    await runtime.savePreferences(
      const UserPreferences(appearance: AppearancePreference.dark),
    );
    _setView(tester, const Size(1024, 768));
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await runtime.dispose();
    });
    await tester.pumpWidget(AggregateApp(runtime: runtime));
    await tester.pumpAndSettle();
    await _openSettings(tester);
    expect(_pageTheme(tester).brightness, Brightness.dark);
    await tester.tap(find.bySemanticsLabel('外观主题'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final surface = _pageTheme(tester).colorScheme.surface;
    expect(surface, isNot(AggregateTheme.dark.colorScheme.surface));
    expect(surface, isNot(AggregateTheme.light.colorScheme.surface));
    expect(_artwork(tester).frame.position, allOf(greaterThan(0), lessThan(1)));
    await tester.pump(const Duration(milliseconds: 500));
    expect(_pageTheme(tester).brightness, Brightness.light);
    expect(
      _pageTheme(tester).colorScheme.surface,
      AggregateTheme.forPlatform(
        AggregateTheme.light,
        TargetPlatform.macOS,
      ).colorScheme.surface,
    );
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
}

Future<void> _openSettings(WidgetTester tester) async {
  await tester.tap(find.text('设置').first);
  // The active switch deliberately schedules frames continuously; settling it
  // would suppress the very internal animation these tests need to exercise.
  await tester.pump();
  // Preferences load asynchronously while this page is offstage. Give its
  // newly visible live model bounded frames to reach the loaded dark endpoint.
  for (var frame = 0; frame < 60; frame++) {
    await tester.pump(const Duration(microseconds: 16667));
  }
  expect(find.byType(SettingsPage), findsOneWidget);
}

ThemeData _pageTheme(WidgetTester tester) =>
    Theme.of(tester.element(find.byType(SettingsPage)));

ThemeSwitchArtwork _artwork(WidgetTester tester) =>
    tester.widget<ThemeSwitchArtwork>(find.byType(ThemeSwitchArtwork));

void _setView(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}
