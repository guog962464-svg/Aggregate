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
typedef _Scenario = ({String name, Size size, double pixelRatio});
const _scenarios = <_Scenario>[
  (name: '800x600@1x', size: Size(800, 600), pixelRatio: 1),
  (name: '800x600@2x', size: Size(800, 600), pixelRatio: 2),
  (name: '1024x768@1x', size: Size(1024, 768), pixelRatio: 1),
  (name: '1024x768@2x', size: Size(1024, 768), pixelRatio: 2),
  (name: '1440x900@1x', size: Size(1440, 900), pixelRatio: 1),
  (name: '1440x900@2x', size: Size(1440, 900), pixelRatio: 2),
];
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
  0.52,
  0.525,
];

void main() {
  testWidgets(
    'midpoint text halo protects readable text over the live glass backdrop',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      for (final initialAppearance in [
        AppearancePreference.dark,
        AppearancePreference.light,
      ]) {
        for (final scenario in _scenarios) {
          await _verifyScenario(tester, scenario, initialAppearance);
        }
      }
    },
    variant: _macOS,
  );
}

Future<void> _verifyScenario(
  WidgetTester tester,
  _Scenario scenario,
  AppearancePreference initialAppearance,
) async {
  final size = scenario.size;
  final pixelRatio = scenario.pixelRatio;
  final imageWidth = (size.width * pixelRatio).round();
  tester.view.physicalSize = Size(
    size.width * pixelRatio,
    size.height * pixelRatio,
  );
  tester.view.devicePixelRatio = pixelRatio;

  final runtime = createPreviewRuntime();
  final reduceMotion = ValueNotifier(true);
  try {
    await runtime.savePreferences(
      UserPreferences(appearance: initialAppearance),
    );
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

    final textRegions = <String, Rect>{
      'page title': tester.getRect(find.text('设置').last),
      'page subtitle': tester.getRect(find.text('让工作台适应你的使用方式。')),
      'section title': tester.getRect(find.text('外观')),
      'body text': tester.getRect(find.text('主题选择保存在本机。')),
    };
    for (final label in ['搜索所有功能', '运行当前功能']) {
      await tester.ensureVisible(find.text(label));
      await tester.pumpAndSettle();
      textRegions['ListTile: $label'] = tester.getRect(find.text(label));
    }
    final shaderSeconds = tester
        .widget<GlassSceneScope>(find.byType(GlassSceneScope))
        .frame
        .seconds;
    await tester.pumpWidget(const SizedBox.shrink());

    final baseTheme = AggregateTheme.withMacOSSurfaceTextContrast(
      AggregateTheme.forPlatform(
        initialAppearance == AppearancePreference.light
            ? AggregateTheme.light
            : AggregateTheme.dark,
        TargetPlatform.macOS,
      ),
    );
    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(size: size, devicePixelRatio: pixelRatio),
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
    final samplePoints = [
      for (final entry in textRegions.entries)
        for (var xIndex = 0; xIndex < 9; xIndex++)
          for (final y in [
            entry.value.top,
            entry.value.center.dy,
            entry.value.bottom - 1,
          ])
            (
              region: entry.key,
              x:
                  ((entry.value.left + (xIndex + 0.5) * entry.value.width / 9) *
                          pixelRatio)
                      .floor(),
              y: (y * pixelRatio).floor(),
            ),
    ];

    for (final daylight in _samples) {
      frame.publishThemeSwitch(shaderSeconds, daylight);
      await tester.pump();
      final useDarkForeground = daylight >= 0.5;
      final needsHalo = daylight >= 0.46 && daylight <= 0.52;
      final foreground = useDarkForeground ? Colors.black : Colors.white;
      final halo = useDarkForeground ? Colors.white : Colors.black;
      final textTheme = AggregateTheme.withMacOSBackdropTextContrast(
        baseTheme,
        usesDarkForeground: useDarkForeground,
        addContrastHalo: needsHalo,
      );
      final textStylesUnderTest = [
        textTheme.textTheme.headlineMedium!,
        textTheme.textTheme.titleMedium!,
        textTheme.textTheme.bodyMedium!,
        textTheme.textTheme.bodySmall!,
        textTheme.listTileTheme.titleTextStyle!,
        textTheme.listTileTheme.subtitleTextStyle!,
      ];
      for (final textStyle in textStylesUnderTest) {
        expect(textStyle.color, foreground);
        expect(textStyle.shadows?.length ?? 0, needsHalo ? 8 : 0);
        if (needsHalo) {
          expect(
            textStyle.shadows!.every((shadow) => shadow.color == halo),
            isTrue,
          );
        }
      }
      for (final buttonLabelStyle in [
        textTheme.textTheme.labelLarge!,
        textTheme.textTheme.labelMedium!,
        textTheme.textTheme.labelSmall!,
      ]) {
        expect(buttonLabelStyle.color, foreground);
        expect(buttonLabelStyle.shadows, isNull);
      }

      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(boundaryKey),
      );
      final pixelData = await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: pixelRatio);
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
      var minimumTextRegion = '';
      var minimumHaloRegion = '';
      for (final sample in samplePoints) {
        final background = _pixel(pixels, sample.x, sample.y, imageWidth);
        final textContrast = _contrast(foreground, background);
        if (textContrast < minimumTextContrast) {
          minimumTextContrast = textContrast;
          minimumTextRegion = sample.region;
        }
        final haloContrast = _contrast(halo, background);
        if (haloContrast < minimumHaloContrast) {
          minimumHaloContrast = haloContrast;
          minimumHaloRegion = sample.region;
        }
      }

      final reason =
          '${initialAppearance.name} start, ${scenario.name}, shader phase $daylight';
      if (needsHalo) {
        expect(
          minimumHaloContrast,
          greaterThanOrEqualTo(3),
          reason: 'Halo/background contrast at $reason, $minimumHaloRegion',
        );
        expect(
          _contrast(foreground, halo),
          greaterThanOrEqualTo(7),
          reason: 'Text/halo contrast at $reason',
        );
        if (scenario.name == '1024x768@1x' &&
            daylight >= 0.475 &&
            daylight <= 0.5) {
          expect(
            minimumTextContrast,
            lessThan(4.5),
            reason: 'Sample must exercise the halo at $reason',
          );
        }
      } else {
        expect(
          minimumTextContrast,
          greaterThanOrEqualTo(4.5),
          reason: 'Text/background contrast at $reason, $minimumTextRegion',
        );
      }
    }
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    reduceMotion.dispose();
    await runtime.dispose();
  }
}

Color _pixel(Uint8List pixels, int x, int y, int imageWidth) {
  final offset = (y * imageWidth + x) * 4;
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
