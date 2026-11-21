import 'package:aggregate/features/music/music_mini_player.dart';
import 'package:aggregate/features/music/music_player_page.dart';
import 'package:aggregate/features/music/music_session.dart';
import 'package:aggregate/app/aggregate_app.dart';
import 'package:aggregate/app/theme.dart';
import 'package:aggregate/preview/preview_runtime_factory.dart';
import 'package:aggregate/preview/ui6_inspection_runtime.dart';
import 'package:aggregate/widgets/glass/glass_motion.dart';
import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _macOS = TargetPlatformVariant({TargetPlatform.macOS});

void main() {
  testWidgets(
    'UI inspection runtime loads the music sample only when design preview is enabled',
    (tester) async {
      final runtime = Ui6InspectionRuntime();
      final connection = (await runtime.listConnections()).singleWhere(
        (item) => item.id.value == 'ui6-review-music',
      );
      final capabilities = await runtime.searchCapabilities(
        const SearchQuery(''),
      );
      final session = MusicSession(runtime);
      addTearDown(session.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MusicPlayerPage(
              connection: connection,
              capabilities: capabilities,
              runtime: runtime,
              session: session,
              showPreviewSample: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(session.title, '示例歌曲');
      expect(session.artist, '示例歌手');
      expect(find.text('歌曲 · 2 首'), findsOneWidget);
      expect(find.text('暂不可播放的歌曲'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    variant: _macOS,
  );

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
    expect(frame.left, closeTo(270, .1));
    expect(frame.top, closeTo(812, .1));
    expect(frame.width, closeTo(1048, .1));
    expect(frame.height, closeTo(58, .1));
    expect(find.textContaining('示例歌曲'), findsOneWidget);
    expect(find.bySemanticsLabel('暂停'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, variant: _macOS);

  testWidgets('full design preview aligns music home with the v9.0.2 board', (
    tester,
  ) async {
    _useSize(tester, const Size(1360, 900));
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final runtime = Ui6InspectionRuntime();
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
    final artwork = tester.getRect(
      find.byKey(const Key('music-player-artwork')),
    );
    final title = tester.getRect(find.byKey(const Key('music-player-title')));
    final search = tester.getRect(find.byKey(const Key('music-search')));
    final searchButton = tester.getRect(
      find.byKey(const Key('music-search-submit')),
    );
    final settings = tester.getRect(
      find.byKey(const Key('macos-sidebar-settings')),
    );
    final refresh = tester.getRect(
      find.byKey(const Key('music-refresh-status')),
    );
    final playResult = tester.getRect(find.bySemanticsLabel('播放 示例歌曲'));
    final playbackControls = [
      ('上一首', 314.0),
      ('暂停', 392.0),
      ('下一首', 470.0),
      ('停止播放', 548.0),
    ];
    expect(card.left, closeTo(280, 1));
    // The WidgetTester root omits the native 32pt titlebar/content inset;
    // the paired Profile window adds it, placing this card at y=188.
    expect(card.top, closeTo(156, 1));
    expect(card.width, closeTo(468, 1));
    expect(card.height, closeTo(530, 1));
    expect(artwork.left, closeTo(310, 1));
    expect(artwork.top, closeTo(216, 1));
    expect(artwork.width, closeTo(150, 1));
    expect(title.left, closeTo(482, 1));
    for (final (label, left) in playbackControls) {
      final control = tester.getRect(find.bySemanticsLabel(label));
      expect(control.left, closeTo(left, 1));
      expect(control.top, closeTo(400, 1));
      expect(control.width, closeTo(64, 1));
      expect(control.height, closeTo(58, 1));
    }
    expect(search.left, closeTo(786, 1));
    expect(search.top, closeTo(213, 1));
    expect(search.width, closeTo(522, 1));
    expect(search.height, closeTo(44, 1));
    expect(searchButton.right, closeTo(1308, 1));
    expect(searchButton.height, closeTo(46, 1));
    expect(refresh.left, closeTo(310, 1));
    expect(refresh.top, closeTo(581, 1));
    expect(refresh.width, closeTo(132, 1));
    expect(refresh.height, closeTo(40, 1));
    final account = tester.getRect(
      find.byKey(const Key('music-account-frame')),
    );
    expect(account.left, closeTo(454, 1));
    expect(account.top, closeTo(581, 1));
    expect(account.width, closeTo(132, 1));
    expect(account.height, closeTo(40, 1));
    expect(settings.top, closeTo(807, 2));
    expect(playResult.right, closeTo(1296, 2));
    expect(find.text('示例歌手 · 可播放'), findsOneWidget);
    expect(find.text('示例歌手 · 当前音源不可播放'), findsOneWidget);
    expect(find.byKey(const Key('music-refresh-status')), findsOneWidget);
    expect(find.bySemanticsLabel('停止播放'), findsOneWidget);
    expect(find.bySemanticsLabel('上一首'), findsOneWidget);
    expect(find.bySemanticsLabel('下一首'), findsOneWidget);
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
    ..queueLength = 3
    ..currentIndex = 1;
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
