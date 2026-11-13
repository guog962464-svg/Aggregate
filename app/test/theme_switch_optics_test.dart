import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:aggregate/features/settings/glass_theme_switch.dart';
import 'package:aggregate/features/settings/theme_switch_simulation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'matches independent WebGL optical probes through interrupted motion',
    (tester) async {
      // Expected colors come from the author's WebGL renderer, not from native
      // screenshots. Keep that independent oracle when updating this fixture.
      final fixture = jsonDecode(
        File('test/fixtures/theme_switch_optics.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final provenance = fixture['provenance'] as Map<String, dynamic>;
      final cases = <int, Map<String, dynamic>>{
        for (final row in fixture['cases'] as List)
          (row as Map<String, dynamic>)['frame'] as int: row,
      };
      final events = <int, Map<String, dynamic>>{
        for (final row in provenance['events_before_frame'] as List)
          (row as Map<String, dynamic>)['frame'] as int: row,
      };
      final fps = (provenance['frames_per_second'] as num).toDouble();
      final tolerance = provenance['tolerance_rgb255'] as int;
      final sceneOrigin = provenance['scene_origin'] as List;
      final sceneScale = (provenance['scene_scale'] as num).toDouble();
      final simulation = ThemeSwitchSimulation(seed: provenance['seed'] as int);
      const size = Size(720, 540);
      const boundaryKey = ValueKey('theme-switch-optical-probes');

      expect(cases.keys, unorderedEquals([0, 60, 70, 90, 110, 150]));
      expect(provenance['viewport'], [720, 540]);
      expect(provenance['device_pixel_ratio'], 1);
      expect(tolerance, 2);

      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final program = await tester.runAsync(ThemeSwitchArtwork.loadProgram);
      expect(program, isNotNull);
      final lastFrame = cases.keys.reduce((a, b) => a > b ? a : b);
      var previousCaptureTime = 0.0;

      for (var frame = 0; frame <= lastFrame; frame++) {
        final event = events[frame];
        if (event?.containsKey('hover') ?? false) {
          simulation.setHovered(event!['hover'] as bool);
        }
        if (event?.containsKey('light') ?? false) {
          simulation.setLight(event!['light'] as bool);
        }
        final time = frame / fps;
        simulation.advance(frame == 0 ? 0 : 1 / fps, time);
        final sample = cases[frame];
        if (sample == null) continue;

        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: MediaQuery(
              data: const MediaQueryData(size: size, devicePixelRatio: 1),
              child: RepaintBoundary(
                key: boundaryKey,
                child: SizedBox.fromSize(
                  size: size,
                  child: ThemeSwitchArtwork(
                    frame: simulation.snapshot,
                    time: time,
                    program: program!,
                    center: Offset(
                      (sceneOrigin[0] as num).toDouble(),
                      (sceneOrigin[1] as num).toDouble(),
                    ),
                    scale: sceneScale,
                  ),
                ),
              ),
            ),
          ),
          duration: Duration(
            microseconds: ((time - previousCaptureTime) * 1000000).round(),
          ),
        );
        previousCaptureTime = time;
        expect(tester.takeException(), isNull);
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(boundaryKey),
        );
        final pixels = await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          try {
            expect(image.width, size.width.toInt());
            expect(image.height, size.height.toInt());
            return await image.toByteData(format: ui.ImageByteFormat.rawRgba);
          } finally {
            image.dispose();
          }
        });
        expect(pixels, isNotNull);

        for (final value in sample['probes'] as List) {
          final probe = value as Map<String, dynamic>;
          final x = probe['x'] as int;
          final y = probe['y'] as int;
          final expected = (probe['rgb'] as List).cast<int>();
          final offset = (y * size.width.toInt() + x) * 4;
          for (var channel = 0; channel < 3; channel++) {
            final actual = pixels!.getUint8(offset + channel);
            expect(
              (actual - expected[channel]).abs(),
              lessThanOrEqualTo(tolerance),
              reason:
                  'source frame $frame, ${probe['name']} at ($x,$y), '
                  'RGB channel $channel: native $actual, '
                  'WebGL ${expected[channel]}; ${probe['checks']}',
            );
          }
          expect(pixels!.getUint8(offset + 3), 255);
        }
      }
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );
}
