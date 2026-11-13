import 'package:aggregate/features/connections/connection_setup_dialog.dart';
import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final class _SetupFixture
    implements ConnectionSetupPort, ConnectionSetupExecutableSelectionPort {
  _SetupFixture({
    this.withField = false,
    this.autoDetect = false,
    this.httpOnly = false,
    this.executionTarget = ExecutionTarget.device,
  });
  final bool withField;
  final bool autoDetect;
  final bool httpOnly;
  final ExecutionTarget executionTarget;
  int tests = 0;
  final discarded = <String>[];
  ConnectionSetupDraft? latest;

  @override
  List<ConnectionAdapter> get connectionAdapters => httpOnly
      ? const [
          ConnectionAdapter(
            id: 'mcp-http',
            label: 'HTTP MCP',
            kind: ConnectionKind.mcpHttp,
          ),
        ]
      : autoDetect
      ? const [
          ConnectionAdapter(
            id: 'detectable',
            label: '可检测程序',
            kind: ConnectionKind.cli,
            autoDetectExecutable: true,
          ),
        ]
      : withField
      ? const [
          ConnectionAdapter(
            id: 'special',
            label: '专用适配器',
            kind: ConnectionKind.cli,
            defaultLabel: '专用工具',
            showGenericCliFields: false,
            fields: [
              SetupField(
                key: 'secret',
                label: '令牌',
                kind: SetupFieldKind.secret,
              ),
            ],
          ),
        ]
      : [
          ConnectionAdapter(
            id: 'cli',
            label: '自定义 CLI',
            kind: ConnectionKind.cli,
            executionTarget: executionTarget,
          ),
        ];

  @override
  Future<String?> detectExecutable(String adapterId) async =>
      autoDetect ? '/usr/bin/printf' : null;

  @override
  Future<DetectedExecutableSelection?> detectExecutableSelection(
    String adapterId, {
    String? executableName,
  }) async {
    if (executionTarget.kind == ExecutionTargetKind.host &&
        executableName?.isNotEmpty == true) {
      return const DetectedExecutableSelection(
        displayLocation: 'Mac 主机 · CLI 程序',
        reference: 'host-executable-ref',
      );
    }
    final path = await detectExecutable(adapterId);
    return path == null
        ? null
        : DetectedExecutableSelection(displayLocation: path, path: path);
  }

  @override
  Future<ConnectionSetupReport> testConnectionSetup(
    ConnectionSetupDraft draft,
  ) async {
    tests++;
    latest = draft;
    return ConnectionSetupReport(
      draftId: 'draft-$tests',
      checks: const [SetupCheck('连通性', SetupCheckStatus.passed, '程序可启动。')],
      canSave: true,
    );
  }

  @override
  Future<Connection> saveConnectionSetup(String draftId) async =>
      const Connection(
        id: ConnectionId('saved'),
        kind: ConnectionKind.cli,
        label: '测试工具',
        location: '/usr/bin/printf',
        status: ConnectionStatus.ready,
      );

  @override
  Future<void> discardConnectionSetup(String draftId) async {
    discarded.add(draftId);
  }
}

void main() {
  testWidgets('save requires a fresh successful connection test', (
    tester,
  ) async {
    final setup = _SetupFixture();
    Connection? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                saved = await showDialog<Connection>(
                  context: context,
                  builder: (_) => ConnectionSetupDialog(setup: setup),
                );
              },
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    FilledButton saveButton() =>
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, '保存连接'));
    expect(saveButton().onPressed, isNull);
    await tester.enterText(find.widgetWithText(TextField, '名称'), '测试工具');
    await tester.enterText(
      find.widgetWithText(TextField, '程序绝对路径'),
      '/usr/bin/printf',
    );
    await tester.tap(find.text('测试连接'));
    await tester.pumpAndSettle();
    expect(saveButton().onPressed, isNotNull);
    await tester.enterText(find.widgetWithText(TextField, '名称'), '测试工具 2');
    await tester.pump();
    expect(saveButton().onPressed, isNull);
    expect(setup.discarded, contains('draft-1'));
    await tester.tap(find.text('测试连接'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存连接'));
    await tester.pumpAndSettle();
    expect(saved?.id.value, 'saved');
  });

  testWidgets('adapter metadata renders and clears a secret field', (
    tester,
  ) async {
    final setup = _SetupFixture(withField: true);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<Connection>(
                context: context,
                builder: (_) => ConnectionSetupDialog(setup: setup),
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.text('专用工具'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, '程序绝对路径'),
      '/usr/bin/printf',
    );
    final secret = find.widgetWithText(TextField, '令牌');
    expect(tester.widget<TextField>(secret).obscureText, isTrue);
    await tester.enterText(secret, 'fixture-secret');
    await tester.tap(find.text('测试连接'));
    await tester.pumpAndSettle();
    expect(setup.latest?.values['secret'], 'fixture-secret');
    expect(tester.widget<TextField>(secret).controller?.text, isEmpty);
  });

  testWidgets(
    'detectable adapter fills its program path and keeps manual edits',
    (tester) async {
      final setup = _SetupFixture(autoDetect: true);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog<Connection>(
                  context: context,
                  builder: (_) => ConnectionSetupDialog(setup: setup),
                ),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      final field = find.widgetWithText(TextField, '程序绝对路径');
      expect(
        tester.widget<TextField>(field).controller?.text,
        '/usr/bin/printf',
      );
      expect(find.text('已自动找到官方程序'), findsOneWidget);
      await tester.enterText(field, '/usr/bin/env');
      await tester.tap(find.byTooltip('自动检测程序'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(field).controller?.text, '/usr/bin/env');
    },
  );

  testWidgets('phone form finds a Host executable without selecting a path', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final setup = _SetupFixture(
      executionTarget: ExecutionTarget.host('paired-mac-1'),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.android),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<Connection>(
                context: context,
                builder: (_) => ConnectionSetupDialog(setup: setup),
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byTooltip('关闭添加连接'), findsOneWidget);
    expect(find.byIcon(Icons.folder_open_outlined), findsNothing);
    await tester.enterText(find.widgetWithText(TextField, '名称'), 'Mac 工具');
    await tester.enterText(find.widgetWithText(TextField, 'Host 程序名称'), 'git');
    final detect = find.byTooltip('在 Mac Host 查找程序');
    await tester.ensureVisible(detect);
    await tester.tap(detect);
    await tester.pumpAndSettle();
    expect(find.textContaining('实际路径不会传回手机'), findsOneWidget);
    await tester.tap(find.text('测试连接'));
    await tester.pumpAndSettle();
    expect(setup.latest?.spec.executionTarget.hostId, 'paired-mac-1');
    expect(setup.latest?.spec.executable, isNull);
    expect(setup.latest?.executableReference, 'host-executable-ref');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(setup.discarded, contains('draft-1'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Android local CLI field has no document path picker', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.android),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<Connection>(
                context: context,
                builder: (_) => ConnectionSetupDialog(setup: _SetupFixture()),
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.folder_open_outlined), findsNothing);
  });

  testWidgets('Android HTTP actions remain above the keyboard inset', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.view.resetViewInsets();
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.android),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<Connection>(
                context: context,
                builder: (_) => ConnectionSetupDialog(
                  setup: _SetupFixture(httpOnly: true),
                  initialKind: ConnectionKind.mcpHttp,
                  allowedKinds: const {ConnectionKind.mcpHttp},
                ),
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.byType(DropdownButtonFormField<String>)).dy,
      greaterThan(tester.getRect(find.byType(AppBar)).bottom),
    );
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    final saveButton = find.widgetWithText(FilledButton, '保存连接');
    expect(tester.getRect(saveButton).bottom, lessThanOrEqualTo(544));
    expect(tester.takeException(), isNull);
  });
}
