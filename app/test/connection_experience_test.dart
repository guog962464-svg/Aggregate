import 'package:aggregate/app/aggregate_app.dart';
import 'package:aggregate/features/connections/connection_experience.dart';
import 'package:aggregate/features/music/music_mini_player.dart';
import 'package:aggregate/features/music/music_session.dart';
import 'package:aggregate/preview/preview_runtime_factory.dart';
import 'package:aggregate/features/connections/connection_home_page.dart';
import 'package:aggregate/widgets/capability_row.dart';
import 'package:aggregate/widgets/glass/glass_motion.dart';
import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:aggregate_runtime/aggregate_runtime.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _macOS = TargetPlatformVariant({TargetPlatform.macOS});

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
    await tester.pumpWidget(
      AggregateApp(
        runtime: createPreviewRuntime(),
        glassMotionClock: ManualGlassMotionClock(),
      ),
    );
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
  }, variant: _macOS);

  testWidgets('CLI and MCP connections use their own functional homes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      AggregateApp(
        runtime: createPreviewRuntime(),
        glassMotionClock: ManualGlassMotionClock(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('示例 Git CLI，已连接'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('connection-home-directory-title')),
      findsOneWidget,
    );
    expect(find.text('查看 Git 状态'), findsWidgets);
    await tester.tap(find.bySemanticsLabel('示例 MCP，已连接'));
    await tester.pumpAndSettle();
    final connectionTitle = find.byKey(
      const Key('connection-home-header-title'),
    );
    expect(connectionTitle, findsOneWidget);
    expect(tester.widget<Text>(connectionTitle).data, '示例 MCP');
    expect(
      find.byKey(const Key('connection-home-directory-title')),
      findsOneWidget,
    );
    expect(find.text('工具'), findsOneWidget);
    expect(find.text('资源'), findsOneWidget);
    expect(find.text('提示'), findsOneWidget);
    expect(find.text('两个整数相加'), findsWidgets);
    expect(find.text('项目中的 README 文本'), findsOneWidget);
    expect(find.text('根据输入生成摘要'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, variant: _macOS);

  testWidgets('v9.0 workspace geometry follows the 1360 point design board', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final runtime = createPreviewRuntime();
    addTearDown(runtime.dispose);

    await tester.pumpWidget(
      AggregateApp(
        runtime: runtime,
        glassMotionClock: ManualGlassMotionClock(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('所有功能').first);
    await tester.pumpAndSettle();

    final title = tester.getRect(find.byKey(const Key('workspace-page-title')));
    final search = tester.getRect(find.byKey(const Key('global-search')));
    final directory = tester.getRect(
      find.byKey(const Key('workspace-capability-directory-panel')),
    );
    final details = tester.getRect(
      find.byKey(const Key('workspace-capability-details')),
    );

    expect(title.left, 280);
    expect(search.width, closeTo(570, .5));
    expect(directory.left, 280);
    expect(directory.width, closeTo(296, .5));
    expect(details.left, closeTo(623, 1));
    await tester.tap(find.text('两个整数相加').first);
    await tester.pumpAndSettle();
    expect(find.text('两个字段都会在执行前检查'), findsOneWidget);
    expect(find.text('预览运行时'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, variant: _macOS);

  testWidgets('v9.0 macOS connection home geometry follows its design board', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final runtime = createPreviewRuntime();
    addTearDown(runtime.dispose);

    await tester.pumpWidget(
      AggregateApp(
        runtime: runtime,
        glassMotionClock: ManualGlassMotionClock(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('示例 Git CLI').first);
    await tester.pumpAndSettle();

    final title = tester.getRect(
      find.byKey(const Key('connection-home-header-title')),
    );
    final subtitle = tester.getRect(
      find.byKey(const Key('connection-home-header-subtitle')),
    );
    final refresh = tester.getRect(
      find.byKey(const Key('connection-home-refresh')),
    );
    final directory = tester.getRect(
      find.byKey(const Key('connection-home-directory')),
    );
    final directoryDivider = tester.getRect(
      find.byKey(const Key('connection-home-directory-divider')),
    );
    final runPane = tester.getRect(
      find.byKey(const Key('connection-home-run-pane')),
    );

    expect(title.left, 280);
    expect(title.top, 72);
    expect(subtitle.left, 280);
    expect(subtitle.top, 110);
    expect(refresh, const Rect.fromLTWH(1266, 72, 46, 46));
    expect(directory.left, 280);
    expect(directory.width, closeTo(306, 1));
    expect(directory.top, 159);
    expect(find.text('能力目录'), findsOneWidget);
    expect(find.text('选择一项查看详情或填写参数'), findsOneWidget);
    expect(directoryDivider.left, closeTo(610.5, 1));
    expect(runPane.left, closeTo(641, 1));
    expect(find.text('显示当前分支与工作区状态'), findsNWidgets(2));
    expect(
      find.descendant(
        of: find.byKey(const Key('connection-home-run-pane')),
        matching: find.text('查看 Git 状态'),
      ),
      findsOneWidget,
    );
    final embeddedTitle = tester.getRect(
      find.descendant(
        of: find.byKey(const Key('connection-home-run-pane')),
        matching: find.text('查看 Git 状态'),
      ),
    );
    expect(embeddedTitle.top, closeTo(196, 1));
    expect(
      find.descendant(
        of: find.byKey(const Key('connection-home-run-pane')),
        matching: find.byKey(const Key('connection-command-description')),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  }, variant: _macOS);

  testWidgets('macOS connection home keeps its directory beside the run form', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final runtime = createPreviewRuntime();
    addTearDown(runtime.dispose);

    await tester.pumpWidget(
      AggregateApp(
        runtime: runtime,
        glassMotionClock: ManualGlassMotionClock(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('示例 Git CLI').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('查看 Git 状态').first);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('capability-section-run')), findsOneWidget);
    expect(find.text('最近结果'), findsOneWidget);
    // The selected capability remains visible in the directory beside the
    // same title in the embedded run pane.
    expect(find.text('查看 Git 状态'), findsNWidgets(2));
    await tester.tap(find.byKey(const Key('capability-run')));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('运行成功'), findsOneWidget);
    expect(await runtime.listRecentRuns(), hasLength(1));
    expect(tester.takeException(), isNull);
  }, variant: _macOS);

  testWidgets(
    'desktop connection directory builds long capability lists lazily',
    (tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final runtime = _longConnectionRuntime();
      final session = MusicSession(runtime);
      addTearDown(session.dispose);
      addTearDown(runtime.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ConnectionHomePage(
              connection: _longConnection,
              capabilities: _longConnectionCapabilities(),
              runtime: runtime,
              musicSession: session,
              onOpen: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('能力 89'), findsNothing);
      expect(
        tester.widgetList<CapabilityRow>(find.byType(CapabilityRow)).length,
        lessThan(20),
      );
      final directoryScrollable = find.descendant(
        of: find.byType(CustomScrollView),
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(
        find.text('能力 89'),
        240,
        scrollable: directoryScrollable,
      );

      expect(find.text('能力 89'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    variant: _macOS,
  );

  testWidgets(
    'compact connection directory builds long capability lists lazily',
    (tester) async {
      tester.view.physicalSize = const Size(700, 768);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final runtime = _longConnectionRuntime();
      final session = MusicSession(runtime);
      addTearDown(session.dispose);
      addTearDown(runtime.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ConnectionHomePage(
              connection: _longConnection,
              capabilities: _longConnectionCapabilities(),
              runtime: runtime,
              musicSession: session,
              onOpen: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('能力 89'), findsNothing);
      expect(
        tester.widgetList<CapabilityRow>(find.byType(CapabilityRow)).length,
        lessThan(20),
      );
      final directoryScrollable = find.descendant(
        of: find.byType(CustomScrollView),
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(
        find.text('能力 89'),
        240,
        scrollable: directoryScrollable,
      );

      expect(find.text('能力 89'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    variant: _macOS,
  );

  testWidgets('the last selected connection opens after restart', (
    tester,
  ) async {
    final runtime = createPreviewRuntime();
    await tester.pumpWidget(
      AggregateApp(
        runtime: runtime,
        glassMotionClock: ManualGlassMotionClock(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('示例 Git CLI').first);
    await tester.pumpAndSettle();
    expect(
      (await runtime.loadPreferences()).preferredConnectionId,
      'example-git',
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      AggregateApp(
        runtime: runtime,
        glassMotionClock: ManualGlassMotionClock(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('命令与动作'), findsWidgets);
    expect(find.text('音乐播放器'), findsNothing);
  }, variant: _macOS);

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
  }, variant: _macOS);
}

const _longConnection = Connection(
  id: ConnectionId('long-cli'),
  kind: ConnectionKind.cli,
  label: '长列表 CLI',
  location: '/preview/long-cli',
);

List<Capability> _longConnectionCapabilities() => [
  for (var index = 0; index < 90; index++)
    Capability(
      id: CapabilityId(
        _longConnection.id,
        CapabilityKind.cliCommand,
        'capability-$index',
      ),
      title: '能力 $index',
      description: '长列表虚拟化样本 $index',
      permission: PermissionLevel.read,
    ),
];

PreviewRuntime _longConnectionRuntime() => PreviewRuntime(
  connections: const [_longConnection],
  capabilities: _longConnectionCapabilities(),
  latency: Duration.zero,
);
