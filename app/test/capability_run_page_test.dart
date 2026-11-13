import 'dart:async';

import 'package:aggregate/features/invocation/capability_run_page.dart';
import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'phone run shows execution context, redacts submitted secrets, and expands long output',
    (tester) async {
      _usePhoneSize(tester);
      final runtime = _RunRuntime();
      addTearDown(runtime.dispose);
      await _showRunPage(tester, runtime);

      expect(find.text('来源'), findsOneWidget);
      expect(find.text('示例服务'), findsOneWidget);
      expect(find.text('执行端'), findsOneWidget);
      expect(find.text('配对 Mac'), findsOneWidget);
      expect(find.text('外部写入'), findsOneWidget);

      final field = find.byKey(const Key('field-apiToken'));
      await tester.ensureVisible(field);
      await tester.enterText(field, 'do-not-display');
      await tester.tap(find.text('运行'));
      await tester.pumpAndSettle();
      final dialog = find.byType(AlertDialog);
      expect(
        find.descendant(
          of: dialog,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is SelectableText &&
                (widget.data?.contains('••••••') ?? false),
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: dialog, matching: find.text('do-not-display')),
        findsNothing,
      );
      await tester.tap(find.widgetWithText(FilledButton, '执行'));
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 250));
      expect(runtime.invocations, 1);
      expect(runtime.lastArguments?['apiToken'], 'do-not-display');

      final longOutput = '输出内容' * 600;
      runtime.events.add(
        RunEvent(
          runId: const RunId('run-1'),
          sequence: 1,
          state: RunState.failed,
          occurredAt: DateTime.utc(2026, 11, 14),
          blocks: [ResultBlock(ResultKind.text, longOutput)],
          failure: const RuntimeFailure(
            RuntimeErrorCode.connectionFailed,
            '连接已断开',
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);

      await tester.ensureVisible(find.text('本次提交参数（密钥字段已隐藏）'));
      await tester.tap(find.text('本次提交参数（密钥字段已隐藏）'));
      await tester.pump();
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is SelectableText &&
              (widget.data?.contains('••••••') ?? false),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('检查网络和执行端在线状态'), findsOneWidget);
      await tester.ensureVisible(find.text('展开完整内容（${longOutput.length} 字符）'));
      await tester.tap(find.text('展开完整内容（${longOutput.length} 字符）'));
      await tester.pump();
      expect(
        tester
            .widgetList<SelectableText>(find.byType(SelectableText))
            .any((text) => text.data == longOutput),
        isTrue,
      );

      final runButton = find.text('运行');
      final buttonRect = tester.getRect(runButton);
      expect(
        buttonRect.bottom,
        lessThanOrEqualTo(tester.view.physicalSize.height),
      );
      expect(
        runtime.invocations,
        1,
        reason: 'error recovery must not auto-run',
      );
    },
  );

  testWidgets('unknown outcome can inspect activity without re-running', (
    tester,
  ) async {
    _usePhoneSize(tester);
    final runtime = _RunRuntime();
    addTearDown(runtime.dispose);
    await _showRunPage(tester, runtime);

    await tester.enterText(find.byKey(const Key('field-apiToken')), 'test');
    await tester.tap(find.text('运行'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '执行'));
    await tester.pump();
    expect(runtime.invocations, 1);
    runtime.events.add(
      RunEvent(
        runId: const RunId('run-1'),
        sequence: 1,
        state: RunState.outcomeUnknown,
        occurredAt: DateTime.utc(2026, 11, 14),
        failure: const RuntimeFailure(
          RuntimeErrorCode.outcomeUnknown,
          '等待远端响应超时',
        ),
      ),
    );
    runtime.recentRuns = [
      RunSummary(
        const RunId('run-1'),
        _capability.id,
        RunEvent(
          runId: const RunId('run-1'),
          sequence: 1,
          state: RunState.outcomeUnknown,
          occurredAt: DateTime.utc(2026, 11, 14),
          failure: const RuntimeFailure(
            RuntimeErrorCode.outcomeUnknown,
            '等待远端响应超时',
          ),
        ),
      ),
    ];
    await tester.pump();
    await tester.ensureVisible(find.text('检查活动状态'));
    await tester.tap(find.text('检查活动状态'));
    await tester.pumpAndSettle();
    expect(
      runtime.activityChecks,
      2,
      reason: 'one restore read and one manual check',
    );
    expect(runtime.invocations, 1);
    expect(find.text('结果仍未知；请先在执行端确认，不要直接重跑。'), findsOneWidget);
  });

  testWidgets('phone run action remains above the software keyboard', (
    tester,
  ) async {
    _usePhoneSize(tester);
    final runtime = _RunRuntime();
    addTearDown(runtime.dispose);
    await _showRunPage(tester, runtime);

    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    final runButton = tester.getRect(find.text('运行'));
    expect(runButton.bottom, lessThanOrEqualTo(492));
    expect(tester.takeException(), isNull);
  });

  testWidgets('run page waits for the execution target before labeling it', (
    tester,
  ) async {
    _usePhoneSize(tester);
    final runtime = _RunRuntime()
      ..connectionLookup = Completer<List<Connection>>();
    addTearDown(runtime.dispose);
    await _showRunPage(tester, runtime);

    expect(find.text('执行端待确认'), findsOneWidget);
    runtime.connectionLookup!.complete([_hostConnection()]);
    await tester.pumpAndSettle();
    expect(find.text('配对 Mac'), findsOneWidget);
    expect(find.text('执行端未知'), findsNothing);
  });

  testWidgets('an ongoing run resumes from activity and remains cancellable', (
    tester,
  ) async {
    _usePhoneSize(tester);
    final runtime = _RunRuntime();
    addTearDown(runtime.dispose);
    runtime.recentRuns = [
      RunSummary(
        const RunId('run-1'),
        _capability.id,
        RunEvent(
          runId: const RunId('run-1'),
          sequence: 3,
          state: RunState.running,
          occurredAt: DateTime.utc(2026, 11, 14),
          blocks: const [ResultBlock(ResultKind.text, '仍在运行')],
        ),
      ),
    ];
    await _showRunPage(tester, runtime);

    expect(find.text('正在运行…'), findsOneWidget);
    expect(find.text('已从活动记录恢复运行状态；原始参数不会保存在活动记录中。'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pump();
    expect(runtime.cancelCalls, 1);
    expect(find.text('已取消'), findsOneWidget);
    expect(runtime.invocations, 0);
  });
}

void _usePhoneSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(375, 812);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetViewInsets);
}

Future<void> _showRunPage(WidgetTester tester, _RunRuntime runtime) async {
  await tester.pumpWidget(
    MaterialApp(
      home: CapabilityRunPage(runtime: runtime, capability: _capability),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
  expect(tester.takeException(), isNull);
}

const _capability = Capability(
  id: CapabilityId(
    ConnectionId('connection-1'),
    CapabilityKind.mcpTool,
    'submit',
  ),
  title: '提交数据',
  description: '测试手机调用结果流程',
  permission: PermissionLevel.externalWrite,
  inputSchema: {
    'properties': {
      'apiToken': {'type': 'string', 'title': '访问令牌', 'writeOnly': true},
    },
    'required': ['apiToken'],
  },
);

final class _RunRuntime implements RuntimePort {
  final StreamController<RunEvent> events =
      StreamController<RunEvent>.broadcast(sync: true);
  Completer<List<Connection>>? connectionLookup;
  JsonMap? lastArguments;
  List<RunSummary> recentRuns = [];
  int invocations = 0;
  int activityChecks = 0;
  int cancelCalls = 0;

  @override
  bool get isPreview => false;

  @override
  RuntimeFeatures get features => RuntimeFeatures.httpOnly;

  @override
  Future<List<Connection>> listConnections() async =>
      connectionLookup?.future ?? [_hostConnection()];

  @override
  Future<RunHandle> invoke(
    CapabilityId id,
    JsonMap arguments, {
    bool permissionGranted = false,
  }) async {
    invocations++;
    lastArguments = arguments;
    return const RunHandle(RunId('run-1'));
  }

  @override
  Stream<RunEvent> watchRun(RunId id) => events.stream;

  @override
  Future<void> cancel(RunId id) async {
    cancelCalls++;
    events.add(
      RunEvent(
        runId: id,
        sequence: 4,
        state: RunState.cancelled,
        occurredAt: DateTime.utc(2026, 11, 14),
        failure: const RuntimeFailure(RuntimeErrorCode.cancelled, '已取消'),
      ),
    );
  }

  @override
  Future<List<RunSummary>> listRecentRuns() async {
    activityChecks++;
    return recentRuns;
  }

  Future<void> dispose() => events.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Connection _hostConnection() => Connection(
  id: ConnectionId('connection-1'),
  kind: ConnectionKind.mcpHttp,
  label: '示例服务',
  location: 'Mac Host',
  executionTarget: ExecutionTarget.host('test-host'),
);
