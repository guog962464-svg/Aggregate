import 'package:aggregate/app/aggregate_app.dart';
import 'package:aggregate/preview/preview_runtime_factory.dart';
import 'package:aggregate/widgets/capability_row.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const boundaryKey = Key('ui-review-boundary');

  Future<void> capture(WidgetTester tester, String name) async {
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(boundaryKey),
      matchesGoldenFile('../../work/ui-review/$name.png'),
    );
  }

  for (final size in const [Size(800, 600), Size(1024, 768), Size(1440, 900)]) {
    for (final brightness in [Brightness.light, Brightness.dark]) {
      final label =
          '${size.width.toInt()}x${size.height.toInt()}-${brightness.name}';
      testWidgets('capture $label', (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        try {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          tester.platformDispatcher.platformBrightnessTestValue = brightness;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(
            tester.platformDispatcher.clearPlatformBrightnessTestValue,
          );

          await tester.pumpWidget(
            RepaintBoundary(
              key: boundaryKey,
              child: AggregateApp(runtime: createPreviewRuntime()),
            ),
          );
          await capture(tester, '$label-player');

          await tester.enterText(find.byKey(const Key('music-search')), '示例');
          await tester.ensureVisible(find.byTooltip('搜索歌曲'));
          await tester.pumpAndSettle();
          await tester.tap(find.byTooltip('搜索歌曲'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(find.text('歌曲 · 2 首'), findsOneWidget);
          await capture(tester, '$label-player-results');
          final homePlay = find.byTooltip('播放 示例歌曲');
          await tester.ensureVisible(homePlay);
          await tester.tap(homePlay);
          await tester.pump(const Duration(milliseconds: 300));
          await capture(tester, '$label-player-playing');

          await tester.tap(find.widgetWithText(ListTile, '管理连接').first);
          await capture(tester, '$label-connections');

          await tester.tap(find.widgetWithText(ListTile, '设置').first);
          await capture(tester, '$label-settings');

          await tester.tap(find.widgetWithText(ListTile, '所有功能').first);
          await capture(tester, '$label-workspace');
          await tester.pumpAndSettle();
          await tester.enterText(
            find.byKey(const Key('global-search')),
            '搜索歌曲',
          );
          await tester.pumpAndSettle();
          await tester.tap(find.widgetWithText(CapabilityRow, '搜索歌曲').first);
          await capture(tester, '$label-music');

          await tester.enterText(find.byKey(const Key('field-keyword')), '示例');
          await tester.tap(find.text('运行').first);
          await tester.pump(const Duration(milliseconds: 300));
          await capture(tester, '$label-music-results');
          final play = find.byTooltip('播放 示例歌曲');
          await tester.ensureVisible(play);
          await tester.tap(play);
          await tester.pump(const Duration(milliseconds: 300));
          await capture(tester, '$label-music-playing');
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }
  }
}
