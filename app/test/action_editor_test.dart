import 'package:aggregate/features/connections/connections_page.dart';
import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('connection action editor adds and saves an action', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final runtime = _ActionRuntime();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ConnectionsPage(runtime: runtime, onOpen: (_) {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final edit = find.text('编辑动作');
    await tester.ensureVisible(edit);
    await tester.tap(edit);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('action-manifest-json')), findsOneWidget);
    await tester.tap(find.text('新增动作'));
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(
      find.byKey(const Key('action-manifest-json')),
    );
    expect(field.controller!.text, contains('action1'));
    await tester.tap(find.text('检查并预览参数'));
    await tester.pumpAndSettle();
    expect(find.textContaining('--help'), findsWidgets);
    await tester.tap(find.text('保存动作'));
    await tester.pumpAndSettle();
    expect(runtime.saved?['actions'], hasLength(2));
    expect(tester.takeException(), isNull);
  });
}

final class _ActionRuntime implements RuntimePort {
  final connection = const Connection(
    id: ConnectionId('action-fixture'),
    kind: ConnectionKind.cli,
    label: 'Print fixture',
    location: '/usr/bin/printf',
  );
  JsonMap? saved;

  @override
  bool get isPreview => false;

  @override
  RuntimeFeatures get features => RuntimeFeatures.localDesktop;

  @override
  Future<List<Connection>> listConnections() async => [connection];

  @override
  Future<List<Capability>> searchCapabilities(SearchQuery query) async => [];

  @override
  Future<JsonMap?> loadActionManifest(ConnectionId id) async => null;

  @override
  Future<void> saveActionManifest(ConnectionId id, JsonMap manifest) async {
    saved = manifest;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
