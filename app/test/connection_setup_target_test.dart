import 'package:aggregate/features/connections/connections_page.dart';
import 'package:aggregate/features/connections/connection_setup_target_dialog.dart';
import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Android setup asks for a target before showing its fields', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final runtime = _TargetedSetupRuntime();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ConnectionsPage(runtime: runtime, onOpen: (_) {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加连接'));
    await tester.pumpAndSettle();

    expect(find.text('选择执行设备'), findsOneWidget);
    expect(find.text('此 Android 设备'), findsOneWidget);
    expect(find.text('Office Mac'), findsOneWidget);
    await tester.tap(find.text('Office Mac'));
    await tester.pumpAndSettle();

    expect(runtime.selectedTarget, ExecutionTarget.host('office-mac'));
    expect(find.text('Host 程序名称'), findsOneWidget);
    expect(find.text('HTTP URL'), findsNothing);
    expect(find.text('程序绝对路径'), findsNothing);
    expect(find.byIcon(Icons.folder_open_outlined), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('target picker fits landscape with larger text', (tester) async {
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.35)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) {
              final options = [
                const ConnectionSetupTargetOption(
                  target: ExecutionTarget.device,
                  label: '此 Android 设备',
                  detail: '本机 HTTP MCP',
                ),
                ConnectionSetupTargetOption(
                  target: ExecutionTarget.host('office-mac'),
                  label: 'Office Mac',
                  detail: 'Mac Host 在线',
                ),
              ];
              return TextButton(
                onPressed: () async {
                  await showConnectionSetupTargetDialog(context, options);
                },
                child: const Text('打开'),
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.text('先选择执行设备'), findsOneWidget);
    expect(find.text('Office Mac'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

final class _TargetedSetupRuntime
    implements RuntimePort, ConnectionSetupPort, ConnectionSetupTargetPort {
  ExecutionTarget? selectedTarget;

  @override
  bool get isPreview => false;

  @override
  RuntimeFeatures get features => RuntimeFeatures.httpOnly;

  @override
  List<ConnectionAdapter> get connectionAdapters => const [
    ConnectionAdapter(
      id: 'mcp-http',
      label: 'HTTP MCP',
      kind: ConnectionKind.mcpHttp,
    ),
  ];

  @override
  Future<List<ConnectionSetupTargetOption>> listSetupTargets() async => [
    const ConnectionSetupTargetOption(
      target: ExecutionTarget.device,
      label: '此 Android 设备',
      detail: '本机 HTTP MCP 连接',
    ),
    ConnectionSetupTargetOption(
      target: ExecutionTarget.host('office-mac'),
      label: 'Office Mac',
      detail: 'Mac Host 在线 · 由 Mac 执行配置检查',
    ),
  ];

  @override
  Future<ConnectionSetupPort> setupForTarget(ExecutionTarget target) async {
    selectedTarget = target;
    return _TargetSetup(target);
  }

  @override
  Future<List<Connection>> listConnections() async => [];

  @override
  Future<List<Capability>> searchCapabilities(SearchQuery query) async => [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _TargetSetup implements ConnectionSetupPort {
  _TargetSetup(this.target);
  final ExecutionTarget target;

  @override
  List<ConnectionAdapter> get connectionAdapters =>
      target.kind == ExecutionTargetKind.host
      ? [
          ConnectionAdapter(
            id: 'cli',
            label: '自定义 CLI',
            kind: ConnectionKind.cli,
            executionTarget: target,
          ),
        ]
      : const [
          ConnectionAdapter(
            id: 'mcp-http',
            label: 'HTTP MCP',
            kind: ConnectionKind.mcpHttp,
          ),
        ];

  @override
  Future<String?> detectExecutable(String adapterId) async => null;

  @override
  Future<ConnectionSetupReport> testConnectionSetup(
    ConnectionSetupDraft draft,
  ) async => const ConnectionSetupReport(
    draftId: 'setup-draft',
    checks: [],
    canSave: false,
  );

  @override
  Future<Connection> saveConnectionSetup(String draftId) async =>
      throw UnimplementedError();

  @override
  Future<void> discardConnectionSetup(String draftId) async {}
}
