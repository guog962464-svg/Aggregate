import 'package:aggregate/features/music/music_mini_player.dart';
import 'package:aggregate/features/music/music_player_page.dart';
import 'package:aggregate/features/music/music_session.dart';
import 'package:aggregate/app/app_shell.dart';
import 'package:aggregate/app/theme.dart';
import 'package:aggregate/preview/preview_runtime_factory.dart';
import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('phone mini player groups primary and overflow controls', (
    tester,
  ) async {
    _useSize(tester, const Size(320, 800));
    final semantics = tester.ensureSemantics();
    final session = _playingSession();
    var openCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: const SizedBox.shrink(),
          bottomNavigationBar: MusicMiniPlayer(
            session: session,
            onOpen: () => openCalls++,
          ),
        ),
      ),
    );

    expect(find.byTooltip('上一首'), findsOneWidget);
    expect(find.byTooltip('暂停'), findsOneWidget);
    expect(find.byTooltip('下一首'), findsOneWidget);
    expect(find.byTooltip('更多播放操作'), findsOneWidget);
    expect(find.byTooltip('打开播放器'), findsOneWidget);
    expect(find.textContaining('Mac 输出'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('声音由配对 Mac 输出')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('打开播放器'));
    expect(openCalls, 1);
    await tester.tap(find.byTooltip('更多播放操作'));
    await tester.pumpAndSettle();
    expect(find.text('停止播放'), findsOneWidget);
    expect(find.text('刷新播放状态'), findsOneWidget);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('mini player hides while the software keyboard is open', (
    tester,
  ) async {
    _useSize(tester, const Size(375, 812));
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    final session = _playingSession();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: const SizedBox.shrink(),
          bottomNavigationBar: MusicMiniPlayer(session: session, onOpen: () {}),
        ),
      ),
    );

    expect(find.byTooltip('打开播放器'), findsNothing);
    expect(find.byTooltip('暂停'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Android mini-player controls have 48 dp semantic hit targets', (
    tester,
  ) async {
    await _withPlatform(TargetPlatform.android, () async {
      _useSize(tester, const Size(320, 800));
      final semantics = tester.ensureSemantics();
      final session = _playingSession();
      addTearDown(session.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AggregateTheme.forPlatform(
            AggregateTheme.light,
            TargetPlatform.android,
          ),
          home: Scaffold(
            body: const SizedBox.shrink(),
            bottomNavigationBar: MusicMiniPlayer(
              session: session,
              onOpen: () {},
            ),
          ),
        ),
      );

      for (final tooltip in [
        '上一首',
        '暂停',
        '下一首',
        '打开播放器',
        '更多播放操作',
        '收起迷你播放器',
      ]) {
        final bounds = tester.getSemantics(find.byTooltip(tooltip)).rect;
        expect(bounds.width, greaterThanOrEqualTo(48), reason: tooltip);
        expect(bounds.height, greaterThanOrEqualTo(48), reason: tooltip);
      }
      semantics.dispose();
    });
  });

  testWidgets('desktop mini player keeps direct playback actions', (
    tester,
  ) async {
    _useSize(tester, const Size(1024, 768));
    final session = _playingSession();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: const SizedBox.shrink(),
          bottomNavigationBar: MusicMiniPlayer(session: session),
        ),
      ),
    );

    expect(find.byTooltip('停止播放'), findsOneWidget);
    expect(find.byTooltip('刷新播放状态'), findsOneWidget);
    expect(find.byTooltip('暂停'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone mini player opens the matching full music page', (
    tester,
  ) async {
    await _withPlatform(TargetPlatform.android, () async {
      _useSize(tester, const Size(375, 812));
      final runtime = createPreviewRuntime();
      final session = MusicSession(runtime);
      final shellKey = GlobalKey<AppShellState>();
      addTearDown(session.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: AppShell(
            key: shellKey,
            runtime: runtime,
            preferences: const UserPreferences(),
            onPreferencesChanged: (_) {},
            onClearActivity: () async {},
            musicSession: session,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final musicConnection = shellKey.currentState!.connectionHomes.firstWhere(
        (connection) => connection.label == '示例网易云音乐',
      );
      session.connection = musicConnection.id;
      session.prepareTrack('示例歌曲', '示例歌手');
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('打开播放器'));
      await tester.pumpAndSettle();
      expect(find.byType(MusicPlayerPage), findsOneWidget);
      expect(find.text('音乐播放器'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

MusicSession _playingSession() {
  final session = MusicSession(createPreviewRuntime())
    ..visible = true
    ..title = '名称很长的示例歌曲用于检查窄屏布局是否溢出'
    ..source = '一个名字较长的网易云连接'
    ..outputLocation = '声音由配对 Mac 输出'
    ..artist = '一位名字很长的示例歌手'
    ..detail = 'Mac 上播放'
    ..playing = true
    ..playbackStatus = '播放中'
    ..queueLength = 5
    ..currentIndex = 2;
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
  addTearDown(tester.view.resetViewInsets);
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
