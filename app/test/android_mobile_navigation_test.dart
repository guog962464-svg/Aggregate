import 'package:aggregate/app/aggregate_app.dart';
import 'package:aggregate/features/connections/connections_page.dart';
import 'package:aggregate/features/music/music_player_page.dart';
import 'package:aggregate/preview/preview_runtime_factory.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'Android phone starts in global functions and navigates by task',
    (tester) async {
      await _withPlatform(TargetPlatform.android, () async {
        tester.view.physicalSize = const Size(375, 812);
        tester.view.devicePixelRatio = 1;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          tester.view.resetViewInsets();
        });

        final runtime = createPreviewRuntime();
        addTearDown(runtime.dispose);
        await tester.pumpWidget(AggregateApp(runtime: runtime));
        await tester.pumpAndSettle();

        expect(find.byType(NavigationBar), findsOneWidget);
        expect(find.text('工作台'), findsOneWidget);
        expect(
          tester
              .widget<NavigationBar>(find.byType(NavigationBar))
              .selectedIndex,
          0,
        );
        expect(tester.takeException(), isNull);

        final navBar = tester.getRect(find.byType(NavigationBar));
        await tester.tapAt(
          Offset(navBar.left + navBar.width * 0.375, navBar.center.dy),
        );
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<NavigationBar>(find.byType(NavigationBar))
              .selectedIndex,
          1,
        );
        expect(find.byType(ConnectionsPage), findsOneWidget);

        await tester.tap(find.text('示例网易云音乐'));
        await tester.pumpAndSettle();
        final openPlayer = find.text('打开播放器');
        await tester.ensureVisible(openPlayer);
        await tester.tap(openPlayer);
        await tester.pumpAndSettle();
        expect(find.byType(MusicPlayerPage), findsOneWidget);
        expect(find.text('音乐播放器'), findsOneWidget);

        final musicSearch = find.byKey(const Key('music-search'));
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        await tester.pump();
        await tester.ensureVisible(musicSearch);
        await tester.pumpAndSettle();
        expect(tester.getRect(musicSearch).bottom, lessThanOrEqualTo(512));
        expect(tester.takeException(), isNull);
        tester.view.resetViewInsets();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.byType(ConnectionsPage), findsOneWidget);

        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        await tester.pump();
        expect(find.byType(NavigationBar), findsNothing);
        expect(tester.takeException(), isNull);
      });
    },
  );

  testWidgets('Android tablet uses width-based rail layouts', (tester) async {
    await _withPlatform(TargetPlatform.android, () async {
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final runtime = createPreviewRuntime();
      addTearDown(runtime.dispose);

      tester.view.physicalSize = const Size(700, 900);
      await tester.pumpWidget(AggregateApp(runtime: runtime));
      await tester.pumpAndSettle();
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      expect(tester.takeException(), isNull);

      tester.view.physicalSize = const Size(900, 900);
      await tester.pump();
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(
        tester.widget<NavigationRail>(find.byType(NavigationRail)).extended,
        isTrue,
      );
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('macOS keeps desktop navigation and connection home', (
    tester,
  ) async {
    await _withPlatform(TargetPlatform.macOS, () async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final runtime = createPreviewRuntime();
      addTearDown(runtime.dispose);

      await tester.pumpWidget(AggregateApp(runtime: runtime));
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(NavigationRail), findsNothing);
      expect(find.text('示例网易云音乐'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });
}

Future<void> _withPlatform(
  TargetPlatform platform,
  Future<void> Function() body,
) async {
  debugDefaultTargetPlatformOverride = platform;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}
