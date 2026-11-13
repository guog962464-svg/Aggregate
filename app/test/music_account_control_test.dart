import 'dart:async';

import 'package:aggregate/features/music/music_player_page.dart';
import 'package:aggregate/features/music/music_session.dart';
import 'package:aggregate/preview/preview_runtime_factory.dart';
import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:aggregate_runtime/aggregate_runtime.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

void main() {
  testWidgets('account panel confirms logout and switches through QR login', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final runtime = _AccountPreviewRuntime();
    final session = MusicSession(runtime);
    addTearDown(session.dispose);
    addTearDown(runtime.delegate.dispose);
    final localConnection = (await runtime.listConnections()).single;
    final connection = Connection(
      id: localConnection.id,
      kind: localConnection.kind,
      label: localConnection.label,
      location: 'Mac 本机 CLI',
      executionTarget: ExecutionTarget.host('paired-mac'),
      status: localConnection.status,
      protocolVersion: localConnection.protocolVersion,
      diagnostic: localConnection.diagnostic,
    );
    final capabilities = await runtime.searchCapabilities(
      const SearchQuery(''),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(1.8)),
          child: child!,
        ),
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
    expect(tester.takeException(), isNull);
    expect(find.text('音乐播放器 · 声音由配对 Mac 输出'), findsOneWidget);
    expect(session.outputLocation, '声音由配对 Mac 输出');
    expect(find.byKey(const Key('music-account')), findsOneWidget);
    expect(find.bySemanticsLabel('管理网易云音乐账号，原账号'), findsOneWidget);
    session.authorizeSearch();
    session.authorizeControls();
    session.prepareTrack('旧账号歌曲', '歌手');
    session.playing = false;
    await tester.enterText(find.byKey(const Key('music-search')), '旧搜索');
    final searchButton = find.byTooltip('搜索歌曲');
    await tester.ensureVisible(searchButton);
    await tester.tap(searchButton);
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    expect(find.text('歌曲 · 2 首'), findsOneWidget);

    final accountButton = find.byKey(const Key('music-account'));
    await tester.ensureVisible(accountButton);
    await tester.tap(accountButton);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('已登录 · 原账号'), findsOneWidget);
    await tester.tap(find.text('退出登录'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('退出登录？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(runtime.logoutCalls, 0);

    await tester.tap(find.text('退出登录'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('退出登录').last);
    await tester.pumpAndSettle();
    expect(runtime.logoutCalls, 1);
    expect(find.text('当前未登录'), findsOneWidget);
    expect(session.searchAuthorized, isFalse);
    expect(session.controlsAuthorized, isFalse);
    expect(session.visible, isFalse);
    expect(find.text('旧搜索'), findsNothing);
    expect(find.text('歌曲 · 2 首'), findsNothing);

    await tester.tap(find.text('扫码登录'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(runtime.loginCalls, 1);
    expect(find.text('取消扫码'), findsOneWidget);
    expect(find.text('正在生成二维码…'), findsOneWidget);
    runtime.emitLoginOutput('或点击链接打开: https://163cn.tv/fakeLogin\r\n');
    await tester.pump();
    expect(find.byKey(const Key('music-login-qr')), findsOneWidget);
    expect(find.textContaining('当前手机无法扫描自己的屏幕'), findsOneWidget);
    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.text('等待手机确认…'), findsOneWidget);
    expect(tester.takeException(), isNull);
    tester.view.physicalSize = const Size(844, 390);
    await tester.pumpAndSettle();
    expect(find.text('取消扫码'), findsOneWidget);
    expect(tester.takeException(), isNull);
    tester.view.physicalSize = const Size(375, 812);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('取消扫码'));
    await tester.tap(
      find.ancestor(of: find.text('取消扫码'), matching: find.byType(TextButton)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(find.text('已取消登录'), findsOneWidget);
    expect(runtime.closeCalls, 1);

    await tester.tap(find.text('扫码登录'));
    await tester.pump();
    expect(runtime.loginCalls, 2);
    runtime.completeLogin();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
    expect(find.text('登录成功'), findsOneWidget);
    expect(find.text('已登录 · 新账号 2'), findsOneWidget);

    await tester.tap(find.text('切换账号'));
    await tester.pumpAndSettle();
    expect(find.text('切换账号？'), findsOneWidget);
    await tester.tap(find.text('退出并切换'));
    await tester.pump();
    expect(runtime.logoutCalls, 2);
    expect(runtime.loginCalls, 3);
    runtime.completeLogin();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
    expect(find.text('已登录 · 新账号 3'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

final class _AccountPreviewRuntime
    implements RuntimePort, ConnectionAccountPort {
  final PreviewRuntime delegate = createPreviewRuntime();
  AccountSnapshot account = const AccountSnapshot(
    AccountState.signedIn,
    nickname: '原账号',
  );
  int logoutCalls = 0;
  int loginCalls = 0;
  int closeCalls = 0;
  Completer<int>? loginDone;
  StreamController<String>? loginOutput;

  void emitLoginOutput(String output) => loginOutput!.add(output);

  void completeLogin() {
    account = AccountSnapshot(
      AccountState.signedIn,
      nickname: '新账号 $loginCalls',
    );
    loginDone!.complete(0);
  }

  @override
  bool get isPreview => true;

  @override
  Future<List<Connection>> listConnections() async => [
    for (final connection in await delegate.listConnections())
      if (connection.id.value == 'example-music')
        Connection(
          id: connection.id,
          kind: connection.kind,
          label: connection.label,
          location: 'Mac Host',
          executionTarget: ExecutionTarget.host('paired-mac'),
          status: connection.status,
          protocolVersion: connection.protocolVersion,
          diagnostic: connection.diagnostic,
        ),
  ];

  @override
  Future<List<Capability>> searchCapabilities(SearchQuery query) =>
      delegate.searchCapabilities(query);

  @override
  Future<RunHandle> invoke(
    CapabilityId id,
    JsonMap arguments, {
    bool permissionGranted = false,
  }) => delegate.invoke(id, arguments, permissionGranted: permissionGranted);

  @override
  Stream<RunEvent> watchRun(RunId id) => delegate.watchRun(id);

  @override
  Future<void> cancel(RunId id) => delegate.cancel(id);

  @override
  Future<AccountSnapshot?> readAccount(ConnectionId connection) async =>
      account;

  @override
  Future<TerminalSession> beginAccountLogin(ConnectionId connection) async {
    loginCalls++;
    loginDone = Completer<int>();
    loginOutput = StreamController<String>.broadcast();
    return TerminalSession('login-$loginCalls');
  }

  @override
  Future<int> waitAccountLogin(TerminalSession session) => loginDone!.future;

  @override
  Future<AccountSnapshot> logoutAccount(
    ConnectionId connection, {
    required bool confirmed,
  }) async {
    if (!confirmed) throw StateError('confirmation required');
    logoutCalls++;
    account = const AccountSnapshot(AccountState.signedOut);
    return account;
  }

  @override
  Stream<String> watchTerminal(TerminalSession session) => loginOutput!.stream;

  @override
  Future<void> closeTerminal(TerminalSession session) async {
    closeCalls++;
    if (loginDone != null && !loginDone!.isCompleted) loginDone!.complete(-1);
    await loginOutput?.close();
  }

  @override
  Future<void> writeTerminal(TerminalSession session, String text) async {}

  @override
  Future<void> resizeTerminal(
    TerminalSession session,
    int columns,
    int rows,
  ) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
