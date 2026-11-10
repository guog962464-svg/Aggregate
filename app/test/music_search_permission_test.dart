import 'package:aggregate/features/music/music_player_page.dart';
import 'package:aggregate/features/music/music_session.dart';
import 'package:aggregate/preview/preview_runtime_factory.dart';
import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:aggregate_runtime/aggregate_runtime.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('live CLI search asks once and passes the explicit grant', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final runtime = _PermissionGateRuntime();
    final session = MusicSession(runtime);
    addTearDown(session.dispose);
    addTearDown(runtime.delegate.dispose);
    final connection = (await runtime.listConnections()).single;
    final capabilities = await runtime.searchCapabilities(
      const SearchQuery(''),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MusicPlayerPage(
            connection: connection,
            capabilities: capabilities,
            runtime: runtime,
            session: session,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('music-search')), 'IU');
    await tester.tap(find.byTooltip('搜索歌曲'));
    await tester.pumpAndSettle();
    expect(find.text('允许搜索歌曲？'), findsOneWidget);
    expect(runtime.grantedSearches, 0);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(session.searchAuthorized, isFalse);
    expect(runtime.grantedSearches, 0);

    await tester.tap(find.byTooltip('搜索歌曲'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('允许搜索'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(session.searchAuthorized, isTrue);
    expect(runtime.grantedSearches, 1);
    expect(find.text('歌曲 · 2 首'), findsOneWidget);
    expect(find.text('需要确认此功能的执行权限'), findsNothing);

    await tester.enterText(find.byKey(const Key('music-search')), '周杰伦');
    await tester.tap(find.byTooltip('搜索歌曲'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('允许搜索歌曲？'), findsNothing);
    expect(runtime.grantedSearches, 2);

    await tester.pumpWidget(const SizedBox.shrink());
    await session.attach(
      const Capability(
        id: CapabilityId(
          ConnectionId('another-music'),
          CapabilityKind.cliAction,
          'search',
        ),
        title: '搜索歌曲',
        description: '',
        permission: PermissionLevel.unknown,
        presentation: 'music.search',
      ),
    );
    expect(session.searchAuthorized, isFalse);
  });
}

final class _PermissionGateRuntime implements RuntimePort {
  final PreviewRuntime delegate = createPreviewRuntime();
  int grantedSearches = 0;

  @override
  bool get isPreview => false;

  @override
  Future<List<Connection>> listConnections() async => [
    for (final connection in await delegate.listConnections())
      if (connection.id.value == 'example-music') connection,
  ];

  @override
  Future<List<Capability>> searchCapabilities(SearchQuery query) async => [
    for (final capability in await delegate.searchCapabilities(query))
      if (capability.presentation == 'music.search')
        Capability(
          id: capability.id,
          title: capability.title,
          description: capability.description,
          permission: PermissionLevel.unknown,
          inputSchema: capability.inputSchema,
          presentation: capability.presentation,
        )
      else if (capability.presentation == 'music.play')
        capability,
  ];

  @override
  Future<RunHandle> invoke(
    CapabilityId id,
    JsonMap arguments, {
    bool permissionGranted = false,
  }) {
    if (id.name == 'search') {
      if (!permissionGranted) {
        throw StateError('需要确认此功能的执行权限');
      }
      grantedSearches++;
    }
    return delegate.invoke(id, arguments, permissionGranted: permissionGranted);
  }

  @override
  Stream<RunEvent> watchRun(RunId id) => delegate.watchRun(id);

  @override
  Future<void> cancel(RunId id) => delegate.cancel(id);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
