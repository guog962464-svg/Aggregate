import 'package:aggregate/app/aggregate_app.dart';
import 'package:aggregate/preview/preview_runtime_factory.dart';
import 'package:aggregate/widgets/capability_row.dart';
import 'package:aggregate/widgets/glass/glass_motion.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const boundaryKey = Key('ui-review-boundary');

  Future<void> capture(
    WidgetTester tester,
    String name, {
    bool compareGolden = true,
  }) async {
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    if (compareGolden) {
      await expectLater(
        find.byKey(boundaryKey),
        matchesGoldenFile('../../work/ui-review/$name.png'),
      );
    }
  }

  for (final size in const [Size(800, 600), Size(1024, 768), Size(1440, 900)]) {
    for (final brightness in [Brightness.light, Brightness.dark]) {
      for (final ratio in [1.0, 2.0]) {
        final label =
            '${size.width.toInt()}x${size.height.toInt()}-${brightness.name}';
        testWidgets('review ${ratio.toInt()}x $label', (tester) async {
          debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
          final motionClock = ManualGlassMotionClock();
          try {
            tester.platformDispatcher.accessibilityFeaturesTestValue =
                const FakeAccessibilityFeatures(disableAnimations: true);
            addTearDown(
              tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
            );
            addTearDown(motionClock.dispose);
            tester.view.physicalSize = Size(
              size.width * ratio,
              size.height * ratio,
            );
            tester.view.devicePixelRatio = ratio;
            tester.platformDispatcher.platformBrightnessTestValue = brightness;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            addTearDown(
              tester.platformDispatcher.clearPlatformBrightnessTestValue,
            );

            await tester.pumpWidget(
              RepaintBoundary(
                key: boundaryKey,
                child: AggregateApp(
                  runtime: createPreviewRuntime(),
                  glassMotionClock: motionClock,
                ),
              ),
            );
            Future<void> checkpoint(String state) =>
                capture(tester, '$label-$state', compareGolden: ratio == 1);

            await checkpoint('player');

            await tester.enterText(find.byKey(const Key('music-search')), '示例');
            await tester.ensureVisible(find.byTooltip('搜索歌曲'));
            await tester.pumpAndSettle();
            await tester.tap(find.byTooltip('搜索歌曲'));
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 300));
            expect(find.text('歌曲 · 2 首'), findsOneWidget);
            await checkpoint('player-results');
            final homePlay = find.byTooltip('播放 示例歌曲');
            await tester.ensureVisible(homePlay);
            await tester.tap(homePlay);
            await tester.pump(const Duration(milliseconds: 300));
            await checkpoint('player-playing');

            await tester.tap(find.text('管理连接').first);
            await checkpoint('connections');

            await tester.tap(find.text('设置').first);
            await checkpoint('settings');

            await tester.tap(find.text('所有功能').first);
            await checkpoint('workspace');
            await tester.pumpAndSettle();
            await tester.enterText(
              find.byKey(const Key('global-search')),
              '搜索歌曲',
            );
            await tester.pumpAndSettle();
            await tester.tap(find.widgetWithText(CapabilityRow, '搜索歌曲').first);
            await checkpoint('music');

            await tester.enterText(
              find.byKey(const Key('field-keyword')),
              '示例',
            );
            await tester.tap(find.text('运行').first);
            await tester.pump(const Duration(milliseconds: 300));
            await checkpoint('music-results');
            final play = find.byTooltip('播放 示例歌曲');
            await tester.ensureVisible(play);
            await tester.tap(play);
            await tester.pump(const Duration(milliseconds: 300));
            await checkpoint('music-playing');
          } finally {
            debugDefaultTargetPlatformOverride = null;
          }
        });
      }
    }
  }
}
