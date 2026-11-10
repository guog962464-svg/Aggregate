import 'package:aggregate/app/aggregate_app.dart';
import 'package:aggregate/features/connections/connection_experience.dart';
import 'package:aggregate/features/music/music_mini_player.dart';
import 'package:aggregate/features/music/music_session.dart';
import 'package:aggregate/preview/preview_runtime_factory.dart';
import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('music home follows presentation metadata, not a connection name', () {
    const namedMusic = Connection(
      id: ConnectionId('namesake'),
      kind: ConnectionKind.cli,
      label: '网易云音乐',
      location: 'tool',
    );
    const musicAction = Capability(
      id: CapabilityId(
        ConnectionId('namesake'),
        CapabilityKind.cliAction,
        'search',
      ),
      title: '搜索',
      description: '',
      permission: PermissionLevel.read,
      presentation: 'music.search',
    );
    const playAction = Capability(
      id: CapabilityId(
        ConnectionId('namesake'),
        CapabilityKind.cliAction,
        'play',
      ),
      title: '播放',
      description: '',
      permission: PermissionLevel.localControl,
      presentation: 'music.play',
    );
    expect(experienceFor(namedMusic, const []), ConnectionExperience.cli);
    expect(
      experienceFor(namedMusic, const [musicAction]),
      ConnectionExperience.cli,
    );
    expect(
      experienceFor(namedMusic, const [musicAction, playAction]),
      ConnectionExperience.music,
    );
    const mcp = Connection(
      id: ConnectionId('mcp'),
      kind: ConnectionKind.mcpHttp,
      label: '音乐服务',
      location: 'https://example.invalid/mcp',
    );
    expect(
      experienceFor(mcp, const [musicAction, playAction]),
      ConnectionExperience.mcp,
    );
  });

  testWidgets('music connection opens a player and plays from its own search', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(AggregateApp(runtime: createPreviewRuntime()));
    await tester.pumpAndSettle();

    expect(find.text('音乐播放器'), findsOneWidget);
    expect(find.byKey(const Key('music-search')), findsOneWidget);
    expect(find.bySemanticsLabel('刷新播放状态'), findsOneWidget);
    expect(find.byKey(const Key('global-search')), findsNothing);
    await tester.enterText(find.byKey(const Key('music-search')), '示例');
    await tester.tap(find.byTooltip('搜索歌曲'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('歌曲 · 2 首'), findsOneWidget);
    expect(find.text('不可播放'), findsOneWidget);
    expect(find.bySemanticsLabel('播放 示例歌曲'), findsOneWidget);
    await tester.tap(find.byTooltip('播放 示例歌曲'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('示例歌曲'), findsWidgets);
    expect(find.byTooltip('收起迷你播放器'), findsNothing);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('CLI and MCP connections use their own functional homes', (
    tester,
  ) async {
    await tester.pumpWidget(AggregateApp(runtime: createPreviewRuntime()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('示例 Git CLI').first);
    await tester.pumpAndSettle();
    expect(find.text('命令与动作'), findsWidgets);
    expect(find.text('查看 Git 状态'), findsOneWidget);
    await tester.tap(find.text('示例 MCP').first);
    await tester.pumpAndSettle();
    expect(find.text('工具'), findsOneWidget);
    expect(find.text('资源'), findsOneWidget);
    expect(find.text('提示'), findsOneWidget);
    expect(find.text('两个整数相加'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the last selected connection opens after restart', (
    tester,
  ) async {
    final runtime = createPreviewRuntime();
    await tester.pumpWidget(AggregateApp(runtime: runtime));
    await tester.pumpAndSettle();
    await tester.tap(find.text('示例 Git CLI').first);
    await tester.pumpAndSettle();
    expect(
      (await runtime.loadPreferences()).preferredConnectionId,
      'example-git',
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(AggregateApp(runtime: runtime));
    await tester.pumpAndSettle();
    expect(find.text('命令与动作'), findsWidgets);
    expect(find.text('音乐播放器'), findsNothing);
  });

  testWidgets('music controls ask once per connection in this app session', (
    tester,
  ) async {
    final runtime = createPreviewRuntime();
    final session = MusicSession(runtime);
    addTearDown(session.dispose);
    final catalog = await runtime.searchCapabilities(const SearchQuery(''));
    await session.attach(
      catalog.firstWhere((item) => item.presentation == 'music.search'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  confirmMusicControl(context, session, 'pause', '暂停'),
              child: const Text('暂停'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('暂停'));
    await tester.pumpAndSettle();
    expect(find.text('暂停？'), findsOneWidget);
    await tester.tap(find.text('执行'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(session.controlsAuthorized, isTrue);
    await tester.tap(find.text('暂停'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('暂停？'), findsNothing);
  });
}
