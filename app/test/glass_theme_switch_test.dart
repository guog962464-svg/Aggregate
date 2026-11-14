import 'package:aggregate/features/settings/glass_theme_switch.dart';
import 'package:aggregate/features/settings/theme_switch_calibration.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('cancelled drag respects an external theme change', (
    tester,
  ) async {
    final light = ValueNotifier(false);
    addTearDown(light.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 360,
            child: ValueListenableBuilder<bool>(
              valueListenable: light,
              builder: (_, value, _) => GlassThemeSwitch(
                light: value,
                onChanged: (value) => light.value = value,
              ),
            ),
          ),
        ),
      ),
    );
    final artwork = find.byType(ThemeSwitchArtwork);
    final pointer = await tester.startGesture(
      tester.getTopLeft(artwork) + const Offset(140.48, 133.5),
    );
    light.value = true;
    await tester.pump();
    await pointer.cancel();
    for (var i = 0; i < 90; i++) {
      await tester.pump(const Duration(microseconds: 16667));
    }
    expect(
      tester.widget<ThemeSwitchArtwork>(artwork).frame.position,
      closeTo(1, 0.001),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'capturing an overshooting handle does not apply resistance twice',
    (tester) async {
      await tester.pumpWidget(_host(changes: []));
      final artwork = find.byType(ThemeSwitchArtwork);
      await tester.tap(find.bySemanticsLabel('外观主题'));
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(microseconds: 16667));
        if (tester.widget<ThemeSwitchArtwork>(artwork).frame.position > 1.02) {
          break;
        }
      }
      final before = tester.widget<ThemeSwitchArtwork>(artwork).frame;
      expect(before.position, greaterThan(1.02));
      final handle =
          tester.getTopLeft(artwork) + Offset(180 + before.knobX * 0.38, 133.5);
      final pointer = await tester.startGesture(handle);
      await pointer.moveTo(handle, timeStamp: const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 1));
      expect(
        tester.widget<ThemeSwitchArtwork>(artwork).frame.position,
        closeTo(before.position, 1e-10),
      );
      await pointer.cancel();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('live artwork shares the calibration clock and optics', (
    tester,
  ) async {
    const calibration = ThemeSwitchCalibration(
      timeOriginSeconds: 12,
      optics: ThemeSwitchOptics(refraction: 32, frost: 0.6),
    );
    await tester.pumpWidget(_host(changes: [], calibration: calibration));
    final artwork = find.byType(ThemeSwitchArtwork);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final view = tester.widget<ThemeSwitchArtwork>(artwork);
    expect(view.time, closeTo(12.1, 1e-6));
    expect(view.optics, same(calibration.optics));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('dragging can reverse before release without committing midway', (
    tester,
  ) async {
    final changes = <bool>[];
    await tester.pumpWidget(_host(changes: changes));
    final artwork = find.byType(ThemeSwitchArtwork);
    final origin = tester.getTopLeft(artwork);
    final pointer = await tester.startGesture(
      origin + const Offset(140.48, 133.5),
    );
    await pointer.moveTo(
      origin + const Offset(205, 133.5),
      timeStamp: const Duration(milliseconds: 50),
    );
    await tester.pump(const Duration(milliseconds: 16));
    final forward = tester.widget<ThemeSwitchArtwork>(artwork).frame;
    expect(forward.position, greaterThan(0.7));
    expect(changes, isEmpty);

    await pointer.moveTo(
      origin + const Offset(156, 133.5),
      timeStamp: const Duration(milliseconds: 150),
    );
    await tester.pump(const Duration(milliseconds: 16));
    final reversed = tester.widget<ThemeSwitchArtwork>(artwork).frame;
    expect(reversed.position, lessThan(forward.position));
    expect(reversed.position, greaterThan(0));
    expect(changes, isEmpty);

    await pointer.up(timeStamp: const Duration(milliseconds: 200));
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(changes, [false]);
    expect(
      tester.widget<ThemeSwitchArtwork>(artwork).frame.position,
      closeTo(0, 0.005),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion snaps and allows the frame scheduler to settle', (
    tester,
  ) async {
    final changes = <bool>[];
    await tester.pumpWidget(_host(changes: changes, reduceMotion: true));
    await tester.pumpAndSettle();
    final artwork = find.byType(ThemeSwitchArtwork);
    expect(tester.widget<ThemeSwitchArtwork>(artwork).frame.position, 0);
    await tester.tap(find.bySemanticsLabel('外观主题'));
    await tester.pumpAndSettle();
    expect(changes, [true]);
    final frame = tester.widget<ThemeSwitchArtwork>(artwork).frame;
    expect(frame.position, 1);
    expect(frame.velocity, 0);
    expect(frame.theme, 1);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });
}

Widget _host({
  required List<bool> changes,
  bool reduceMotion = false,
  ThemeSwitchCalibration calibration = ThemeSwitchCalibration.reference,
}) {
  var light = false;
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: MediaQuery(
          data: MediaQueryData(disableAnimations: reduceMotion),
          child: StatefulBuilder(
            builder: (context, update) => SizedBox(
              width: 360,
              child: GlassThemeSwitch(
                light: light,
                calibration: calibration,
                onChanged: (value) => update(() {
                  changes.add(value);
                  light = value;
                }),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
