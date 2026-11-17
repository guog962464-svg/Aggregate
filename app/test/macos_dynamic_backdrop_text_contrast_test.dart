import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:aggregate/app/aggregate_app.dart';
import 'package:aggregate/app/theme.dart';
import 'package:aggregate/preview/preview_runtime_factory.dart';
import 'package:aggregate/widgets/glass/glass_motion.dart';
import 'package:aggregate/widgets/glass/glass_scene.dart';
import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

const _macOS = TargetPlatformVariant({TargetPlatform.macOS});
const _viewport = Size(1024, 768);
const _samples = [
  0.46,
  0.475,
  0.48,
  0.485,
  0.49,
  0.495,
  0.5,
  0.505,
  0.51,
  0.515,
];

void main() {
  testWidgets(
    'midpoint text halo protects readable text over the live glass backdrop',
    (tester) async {
      final runtime = createPreviewRuntime();
      await runtime.savePreferences(
        const UserPreferences(appearance: AppearancePreference.dark),
      );
      final reduceMotion = ValueNotifier(true);
      tester.view.physicalSize = _viewport;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(reduceMotion.dispose);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await runtime.dispose();
      });

      await tester.pumpWidget(
        AggregateApp(
          runtime: runtime,
          glassMotionClock: ManualGlassMotionClock(),
          systemDisableAnimations: reduceMotion,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('设置').first);
      await tester.pumpAndSettle();
      final subtitleRect = tester.getRect(find.text('主题选择保存在本机。'));
      final shaderSeconds = tester
          .widget<GlassSceneScope>(find.byType(GlassSceneScope))
          .frame
          .seconds;
      await tester.pumpWidget(const SizedBox.shrink());

      final baseTheme = AggregateTheme.withMacOSSurfaceTextContrast(
        AggregateTheme.forPlatform(AggregateTheme.dark, TargetPlatform.macOS),
      );
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: _viewport, devicePixelRatio: 1),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Theme(
              data: baseTheme,
              child: RepaintBoundary(
                key: boundaryKey,
                child: const SizedBox.expand(
                  child: GlassScene(child: SizedBox.expand()),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
      final frame = tester
          .widget<GlassSceneScope>(find.byType(GlassSceneScope))
          .frame;
      final horizontalSamples = [
        for (var i = 0; i < 9; i++)
          (subtitleRect.left + (i + 0.5) * subtitleRect.width / 9).floor(),
      ];
      final verticalSamples = [
        subtitleRect.top.floor(),
        subtitleRect.center.dy.floor(),
        (subtitleRect.bottom - 1).floor(),
      ];

      for (final daylight in _samples) {
        frame.publishThemeSwitch(shaderSeconds, daylight);
        await tester.pump();
        final useDarkForeground = daylight >= 0.5;
        final needsHalo = daylight >= 0.46 && daylight <= 0.51;
        final foreground = useDarkForeground ? Colors.black : Colors.white;
        final halo = useDarkForeground ? Colors.white : Colors.black;
        final textTheme = AggregateTheme.withMacOSBackdropTextContrast(
          baseTheme,
          usesDarkForeground: useDarkForeground,
          addContrastHalo: needsHalo,
        );
        final textStyle = textTheme.textTheme.bodyMedium!;
        expect(textStyle.color, foreground);
        expect(textStyle.shadows?.length ?? 0, needsHalo ? 8 : 0);
        if (needsHalo) {
          expect(
            textStyle.shadows!.every((shadow) => shadow.color == halo),
            isTrue,
          );
        }

        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(boundaryKey),
        );
        final pixelData = await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          try {
            return await image.toByteData(format: ui.ImageByteFormat.rawRgba);
          } finally {
            image.dispose();
          }
        });
        final pixels = pixelData!.buffer.asUint8List(
          pixelData.offsetInBytes,
          pixelData.lengthInBytes,
        );
        var minimumTextContrast = double.infinity;
        var minimumHaloContrast = double.infinity;
        for (final y in verticalSamples) {
          for (final x in horizontalSamples) {
            final background = _pixel(pixels, x, y);
            minimumTextContrast = min(
              minimumTextContrast,
              _contrast(foreground, background),
            );
            minimumHaloContrast = min(
              minimumHaloContrast,
              _contrast(halo, background),
            );
          }
        }

        if (needsHalo) {
          expect(
            minimumHaloContrast,
            greaterThanOrEqualTo(3),
            reason: 'Halo/background contrast at shader phase $daylight',
          );
          expect(
            _contrast(foreground, halo),
            greaterThanOrEqualTo(7),
            reason: 'Text/halo contrast at shader phase $daylight',
          );
          if (daylight >= 0.475 && daylight <= 0.5) {
            expect(
              minimumTextContrast,
              lessThan(4.5),
              reason: 'Sample must exercise the halo at phase $daylight',
            );
          }
        } else {
          expect(
            minimumTextContrast,
            greaterThanOrEqualTo(4.5),
            reason: 'Text/background contrast at shader phase $daylight',
          );
        }
      }
    },
    variant: _macOS,
  );
}

Color _pixel(Uint8List pixels, int x, int y) {
  final offset = (y * _viewport.width.toInt() + x) * 4;
  return Color.fromARGB(
    255,
    pixels[offset],
    pixels[offset + 1],
    pixels[offset + 2],
  );
}

double _contrast(Color foreground, Color background) {
  final opaqueForeground = Color.alphaBlend(foreground, background);
  final foregroundLuminance = opaqueForeground.computeLuminance();
  final backgroundLuminance = background.computeLuminance();
  final lighter = max(foregroundLuminance, backgroundLuminance);
  final darker = min(foregroundLuminance, backgroundLuminance);
  return (lighter + 0.05) / (darker + 0.05);
}

double min(double a, double b) => a < b ? a : b;

double max(double a, double b) => a > b ? a : b;
