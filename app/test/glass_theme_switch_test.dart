import 'package:aggregate/features/settings/glass_theme_switch.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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

Widget _host({required List<bool> changes, bool reduceMotion = false}) {
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
