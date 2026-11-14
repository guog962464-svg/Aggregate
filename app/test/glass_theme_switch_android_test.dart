import 'package:aggregate/features/settings/appearance_selector.dart';
import 'package:aggregate/features/settings/glass_theme_switch.dart';
import 'package:aggregate/features/settings/theme_switch_simulation.dart';
import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _android = TargetPlatformVariant.only(TargetPlatform.android);

void main() {
  for (final startsOnHandle in [true, false]) {
    testWidgets(
      'vertical scrolling from ${startsOnHandle ? 'handle' : 'track'} keeps the theme',
      (tester) async {
        final changes = <bool>[];
        final scroll = await _pumpSwitch(tester, changes: changes);
        final start = _point(tester, startsOnHandle ? -104 : 104);
        final pointer = await tester.startGesture(start);
        await pointer.moveTo(
          start + const Offset(0, -35),
          timeStamp: const Duration(milliseconds: 40),
        );
        await tester.pump(const Duration(milliseconds: 16));
        await pointer.moveTo(
          start + const Offset(0, -150),
          timeStamp: const Duration(milliseconds: 100),
        );
        await tester.pump(const Duration(milliseconds: 16));
        await pointer.up(timeStamp: const Duration(milliseconds: 120));
        await tester.pump(const Duration(milliseconds: 16));

        expect(scroll.offset, greaterThan(40));
        expect(changes, isEmpty);
        expect(_frame(tester).position, closeTo(0, 0.001));
        scroll.jumpTo(0);
        await tester.pump(const Duration(milliseconds: 16));
        await tester.tapAt(_point(tester, -104));
        await tester.pump(const Duration(milliseconds: 16));
        expect(changes, [
          true,
        ], reason: 'An arena rejection must release the pointer.');
        expect(tester.takeException(), isNull);
      },
      variant: _android,
    );
  }

  testWidgets(
    'horizontal reversal owns the gesture and commits only on release',
    (tester) async {
      final changes = <bool>[];
      final scroll = await _pumpSwitch(tester, changes: changes);
      final start = _point(tester, -104);
      final pointer = await tester.startGesture(start);
      await pointer.moveTo(
        start + const Offset(50, 6),
        timeStamp: const Duration(milliseconds: 50),
      );
      await tester.pump(const Duration(milliseconds: 16));
      final forward = _frame(tester).position;
      expect(forward, greaterThan(0.5));
      expect(changes, isEmpty);

      await pointer.moveTo(
        start + const Offset(16, 8),
        timeStamp: const Duration(milliseconds: 150),
      );
      await tester.pump(const Duration(milliseconds: 16));
      expect(_frame(tester).position, lessThan(forward));
      expect(changes, isEmpty);
      expect(scroll.offset, 0);
      await pointer.up(timeStamp: const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 16));

      expect(changes, [false]);
      expect(scroll.offset, 0);
      expect(tester.takeException(), isNull);
    },
    variant: _android,
  );

  testWidgets('a second finger cannot take over the held handle', (
    tester,
  ) async {
    final changes = <bool>[];
    final scroll = await _pumpSwitch(tester, changes: changes);
    final start = _point(tester, -104);
    final first = await tester.startGesture(start, pointer: 11);
    await first.moveTo(
      start + const Offset(45, 0),
      timeStamp: const Duration(milliseconds: 50),
    );
    await tester.pump(const Duration(milliseconds: 16));
    final held = _frame(tester);
    expect(held.position, greaterThan(0.5));

    final otherStart = _point(tester, held.knobX);
    final second = await tester.startGesture(otherStart, pointer: 12);
    await second.moveTo(
      otherStart - const Offset(55, 0),
      timeStamp: const Duration(milliseconds: 100),
    );
    await tester.pump(const Duration(milliseconds: 16));
    await second.up(timeStamp: const Duration(milliseconds: 120));
    await tester.pump(const Duration(milliseconds: 16));
    expect(_frame(tester).position, closeTo(held.position, 1e-10));
    expect(changes, isEmpty);

    await first.moveTo(
      start + const Offset(65, 0),
      timeStamp: const Duration(milliseconds: 180),
    );
    await first.up(timeStamp: const Duration(milliseconds: 220));
    await tester.pump(const Duration(milliseconds: 16));
    expect(changes, [true]);
    expect(scroll.offset, 0);
    expect(tester.takeException(), isNull);
  }, variant: _android);

  for (final vertical in [true, false]) {
    testWidgets(
      'reduced motion ${vertical ? 'vertical' : 'horizontal'} swipe is not a tap',
      (tester) async {
        final changes = <bool>[];
        final scroll = await _pumpSwitch(
          tester,
          changes: changes,
          reduceMotion: true,
        );
        final start = _point(tester, -104);
        final pointer = await tester.startGesture(start);
        final direction = vertical ? const Offset(0, -1) : const Offset(1, 0);
        await pointer.moveTo(
          start + direction * 35,
          timeStamp: const Duration(milliseconds: 50),
        );
        await tester.pump(const Duration(milliseconds: 16));
        await pointer.moveTo(
          start + direction * 90,
          timeStamp: const Duration(milliseconds: 100),
        );
        await tester.pump(const Duration(milliseconds: 16));
        await pointer.up(timeStamp: const Duration(milliseconds: 150));
        await tester.pump();
        expect(changes, isEmpty);
        expect(_frame(tester).position, 0);
        if (vertical) expect(scroll.offset, greaterThan(20));
        scroll.jumpTo(0);
        await tester.pump();
        await tester.tapAt(_point(tester, -104));
        await tester.pump();
        expect(changes, [
          true,
        ], reason: 'A rejected swipe must not leave a held pointer.');
        expect(tester.takeException(), isNull);
      },
      variant: _android,
    );
  }

  for (final size in const [Size(320, 720), Size(393, 852), Size(844, 390)]) {
    testWidgets(
      'Android appearance fits ${size.width.toInt()}x${size.height.toInt()} at 200% text',
      (tester) async {
        _setView(tester, size);
        final changes = <AppearancePreference>[];
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(platform: TargetPlatform.android),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: AppearanceSelector(
                  appearance: AppearancePreference.dark,
                  onChanged: changes.add,
                  systemLabel: '跟随系统',
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        final artwork = find.byType(ThemeSwitchArtwork);
        expect(
          tester.getSize(artwork).width,
          lessThanOrEqualTo(size.width - 40),
        );
        await tester.tap(find.bySemanticsLabel('外观主题'));
        await tester.pump(const Duration(milliseconds: 16));
        expect(changes, [AppearancePreference.light]);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
      variant: _android,
    );
  }
}

Future<ScrollController> _pumpSwitch(
  WidgetTester tester, {
  required List<bool> changes,
  bool reduceMotion = false,
}) async {
  _setView(tester, const Size(360, 720));
  final controller = ScrollController();
  var light = false;
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(platform: TargetPlatform.android),
      home: Scaffold(
        body: SingleChildScrollView(
          controller: controller,
          child: Column(
            children: [
              const SizedBox(height: 80),
              MediaQuery(
                data: MediaQueryData(disableAnimations: reduceMotion),
                child: StatefulBuilder(
                  builder: (context, update) => SizedBox(
                    width: 360,
                    child: GlassThemeSwitch(
                      light: light,
                      onChanged: (value) => update(() {
                        changes.add(value);
                        light = value;
                      }),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 1400),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
  return controller;
}

void _setView(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Offset _point(WidgetTester tester, double designX) {
  final artwork = find.byType(ThemeSwitchArtwork);
  final size = tester.getSize(artwork);
  return tester.getTopLeft(artwork) +
      ThemeSwitchArtwork.sceneOrigin(size) +
      Offset(designX, 0) * ThemeSwitchArtwork.sceneScale(size);
}

ThemeSwitchSnapshot _frame(WidgetTester tester) =>
    tester.widget<ThemeSwitchArtwork>(find.byType(ThemeSwitchArtwork)).frame;
