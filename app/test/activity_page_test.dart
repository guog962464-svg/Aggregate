import 'package:aggregate/features/activity/activity_page.dart';
import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('activity list builds more rows as the list scrolls', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final runtime = _ActivityRuntime()
      ..runs = [for (var index = 0; index < 60; index++) _activityRun(index)];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Material(
            child: ActivityPage(runtime: runtime, onOpen: (_) {}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('sample-59'), findsNothing);
    final list = find.byType(ListView);
    final listScrollable = find.descendant(
      of: list,
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(
      find.text('sample-59'),
      240,
      scrollable: listScrollable,
    );

    expect(find.text('sample-59'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('activity reopens an ongoing run and can request cancellation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final runtime = _ActivityRuntime();
    Capability? opened;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Material(
            child: ActivityPage(
              runtime: runtime,
              onOpen: (capability) => opened = capability,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ListTile), findsWidgets);
    await tester.tap(find.byType(ListTile).first);
    await tester.pumpAndSettle();

    expect(find.text('查看运行'), findsOneWidget);
    expect(find.text('取消运行'), findsOneWidget);
    await tester.tap(find.text('查看运行'));
    await tester.pumpAndSettle();
    expect(opened?.id.key, _capability.id.key);

    await tester.tap(find.text('取消运行'));
    await tester.pumpAndSettle();
    expect(runtime.cancelCalls, 1);
    expect(find.text('已请求取消；请刷新确认最终状态。'), findsOneWidget);
    expect(find.text('已取消'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

const _capability = Capability(
  id: CapabilityId(
    ConnectionId('host:connection-1'),
    CapabilityKind.cliCommand,
    'backup',
  ),
  title: '正在备份',
  description: '远程任务',
  permission: PermissionLevel.localControl,
);

final class _ActivityRuntime implements RuntimePort {
  int cancelCalls = 0;
  List<RunSummary> runs = [
    RunSummary(
      const RunId('run-1'),
      _capability.id,
      RunEvent(
        runId: const RunId('run-1'),
        sequence: 1,
        state: RunState.running,
        occurredAt: DateTime.utc(2026, 11, 14),
      ),
    ),
  ];

  @override
  bool get isPreview => false;

  @override
  RuntimeFeatures get features => RuntimeFeatures.httpOnly;

  @override
  Future<List<RunSummary>> listRecentRuns() async => runs;

  @override
  Future<List<Capability>> searchCapabilities(SearchQuery query) async =>
      const [_capability];

  @override
  Future<void> cancel(RunId id) async {
    cancelCalls++;
    runs = [
      RunSummary(
        id,
        _capability.id,
        RunEvent(
          runId: id,
          sequence: 2,
          state: RunState.cancelled,
          occurredAt: DateTime.utc(2026, 11, 14, 1),
          failure: const RuntimeFailure(
            RuntimeErrorCode.cancelled,
            'cancel requested',
          ),
        ),
      ),
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

RunSummary _activityRun(int index) {
  final id = RunId('run-${index + 1}');
  final capability = CapabilityId(
    ConnectionId('connection-${index + 1}'),
    CapabilityKind.cliCommand,
    'sample-$index',
  );
  return RunSummary(
    id,
    capability,
    RunEvent(
      runId: id,
      sequence: 1,
      state: RunState.succeeded,
      occurredAt: DateTime.utc(2026, 11, 14).add(Duration(minutes: index)),
    ),
  );
}
