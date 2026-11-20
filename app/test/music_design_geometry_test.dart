import 'package:aggregate/features/music/music_mini_player.dart';
import 'package:aggregate/features/music/music_player_page.dart';
import 'package:aggregate/features/music/music_session.dart';
import 'package:aggregate/app/aggregate_app.dart';
import 'package:aggregate/app/theme.dart';
import 'package:aggregate/preview/preview_runtime_factory.dart';
import 'package:aggregate/widgets/glass/glass_motion.dart';
import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _macOS = TargetPlatformVariant({TargetPlatform.macOS});

void main() {
  testWidgets('music home matches the wide v3.5 board geometry', (
    tester,
  ) async {
    _useSize(tester, const Size(1360, 900));
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    final runtime = createPreviewRuntime();
    final connection = (await runtime.listConnections()).singleWhere(
      (item) => item.id.value == 'example-music',
    );
    final capabilities = await runtime.searchCapabilities(
      const SearchQuery(''),
    );
    final session = MusicSession(runtime);
    addTearDown(session.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AggregateTheme.forPlatform(
          AggregateTheme.light,
          TargetPlatform.macOS,
        ),
        home: GlassMotionScope(
          child: Scaffold(
            appBar: const PreferredSize(
              preferredSize: Size.fromHeight(80),
              child: SizedBox.shrink(),
            ),
            body: Row(
              children: [
                const SizedBox(width: 240),
                Expanded(
                  child: MusicPlayerPage(
                    connection: connection,
                    capabilities: capabilities,
                    runtime: runtime,
                    session: session,
                    showPreviewSample: true,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    for (var tick = 0; tick < 8; tick++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();

    final playerCard = tester.getRect(
      find.byKey(const Key('music-player-card')),
    );
    final artwork = tester.getRect(
      find.byKey(const Key('music-player-artwork')),
    );
    final search = tester.getRect(find.byKey(const Key('music-search')));
    expect(playerCard.left, closeTo(299, 1));
    expect(playerCard.width, closeTo(394, 1));
    expect(playerCard.height, closeTo(430, .1));
    expect(search.left, closeTo(717, 1));
    expect(search.width, closeTo(592, 1));
    expect(search.height, closeTo(46, .1));
    expect(search.top, closeTo(playerCard.top, 1));
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('music-search')))
          .controller
          ?.text,
      isEmpty,
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('music-search')))
          .decoration
          ?.prefixIcon,
      isNull,
    );
    expect(artwork.left, closeTo(playerCard.left + 122, 1));
    expect(artwork.top, closeTo(playerCard.top + 28, 1));
    expect(
      tester.getRect(find.byKey(const Key('music-player-title'))).center.dx,
      closeTo(playerCard.center.dx, .5),
    );
    expect(session.title, '示例歌曲');
    expect(session.artist, '示例歌手');
    expect(find.text('歌曲 · 2 首'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, variant: _macOS);

  testWidgets('macOS mini player matches the floating board frame', (
    tester,
  ) async {
    _useSize(tester, const Size(1360, 900));
    final clock = ManualGlassMotionClock();
    addTearDown(clock.dispose);
    final session = _playingSession();
    addTearDown(session.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AggregateTheme.forPlatform(
          AggregateTheme.light,
          TargetPlatform.macOS,
        ),
        home: GlassMotionScope(
          clock: clock,
          child: Scaffold(
            body: const SizedBox.expand(),
            bottomNavigationBar: MusicMiniPlayer(
              session: session,
              includeBottomSafeArea: false,
              onOpen: () {},
            ),
          ),
        ),
      ),
    );

    final frame = tester.getRect(
      find.byKey(const Key('music-mini-player-panel')),
    );
    expect(frame.left, closeTo(52, .1));
    expect(frame.top, closeTo(788, .1));
    expect(frame.width, closeTo(1292, .1));
    expect(frame.height, closeTo(96, .1));
    expect(find.textContaining('示例歌曲'), findsOneWidget);
    expect(find.bySemanticsLabel('暂停'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, variant: _macOS);

  testWidgets('full design preview lays music inside the shared shell', (
    tester,
  ) async {
    _useSize(tester, const Size(1360, 900));
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final runtime = createPreviewRuntime();
    await runtime.savePreferences(
      const UserPreferences(appearance: AppearancePreference.light),
    );
    final clock = ManualGlassMotionClock();
    addTearDown(clock.dispose);

    await tester.pumpWidget(
      AggregateApp(
        runtime: runtime,
        glassMotionClock: clock,
        showMusicDesignPreview: true,
      ),
    );
    for (var tick = 0; tick < 12; tick++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('music-player-card')), findsOneWidget);
    final card = tester.getRect(find.byKey(const Key('music-player-card')));
    // The design board reserves 40pt for the macOS titlebar. The native
    // Flutter content view starts 32pt below the window origin, so the shared
    // PageFrame adds the measured 8pt compensation.
    expect(card.top, closeTo(179, 1));
    expect(find.text('歌曲 · 2 首'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, variant: _macOS);
}

MusicSession _playingSession() {
  final session = MusicSession(createPreviewRuntime())
    ..visible = true
    ..title = '示例歌曲'
    ..source = '示例网易云音乐'
    ..outputLocation = '声音由此设备输出'
    ..artist = '示例歌手'
    ..detail = '0:12 / 3:20'
    ..playing = true
    ..playbackStatus = '播放中'
    ..queueLength = 1;
  for (final role in ['prev', 'pause', 'next', 'stop', 'state']) {
    session.actions['music.$role'] = Capability(
      id: CapabilityId(
        const ConnectionId('music-connection'),
        CapabilityKind.cliAction,
        role,
      ),
      title: role,
      description: '',
      permission: PermissionLevel.localControl,
      presentation: 'music.$role',
    );
  }
  return session;
}

void _useSize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}
