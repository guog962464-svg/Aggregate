import 'package:aggregate/features/connections/connections_page.dart';
import 'package:aggregate/widgets/capability_row.dart';
import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:aggregate_runtime/aggregate_runtime.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _macOS = TargetPlatformVariant({TargetPlatform.macOS});

void main() {
  testWidgets('desktop connection management builds only visible connections', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final runtime = _runtime(connections: _connections(90));
    addTearDown(runtime.dispose);

    await tester.pumpWidget(_page(runtime));
    await tester.pumpAndSettle();

    final lastConnection = _connectionKey(89);
    expect(find.byKey(lastConnection), findsNothing);
    expect(find.byType(ListTile), findsWidgets);
    expect(find.byType(ListTile).evaluate().length, lessThan(20));
    await _scrollTo(
      tester,
      find.byKey(lastConnection),
      const Key('managed-connection-list'),
    );

    expect(find.byKey(lastConnection), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, variant: _macOS);

  testWidgets('compact connection management builds and selects long lists', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(700, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final runtime = _runtime(connections: _connections(90));
    addTearDown(runtime.dispose);

    await tester.pumpWidget(_page(runtime));
    await tester.pumpAndSettle();

    final lastConnection = _connectionKey(89);
    expect(find.byKey(lastConnection), findsNothing);
    expect(find.byType(ListTile).evaluate().length, lessThan(20));
    await _scrollTo(
      tester,
      find.byKey(lastConnection),
      const Key('managed-connection-list'),
    );
    expect(find.byKey(lastConnection), findsOneWidget);
    await tester.tap(find.byKey(lastConnection));
    await tester.pumpAndSettle();

    expect(find.text('返回连接'), findsOneWidget);
    expect(find.text('连接 89'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, variant: _macOS);

  testWidgets('short connection and capability lists keep natural height', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final runtime = _runtime(
      connections: const [_connection0],
      capabilities: _capabilities(1),
    );
    addTearDown(runtime.dispose);

    await tester.pumpWidget(_page(runtime));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('managed-connection-list')), findsNothing);
    expect(find.byKey(const Key('managed-capability-list')), findsNothing);
    expect(find.byKey(_connectionKey(0)), findsOneWidget);
    expect(find.byKey(_capabilityKey(0)), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, variant: _macOS);

  testWidgets('connection details build long capability lists lazily', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final runtime = _runtime(
      connections: const [_connection0],
      capabilities: _capabilities(90),
    );
    addTearDown(runtime.dispose);

    await tester.pumpWidget(_page(runtime));
    await tester.pumpAndSettle();

    final lastCapability = _capabilityKey(89);
    expect(find.byKey(lastCapability), findsNothing);
    expect(
      tester.widgetList<CapabilityRow>(find.byType(CapabilityRow)).length,
      lessThan(20),
    );
    await _scrollTo(
      tester,
      find.byKey(lastCapability),
      const Key('managed-capability-list'),
    );

    expect(find.byKey(lastCapability), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, variant: _macOS);
}

Widget _page(PreviewRuntime runtime) => MaterialApp(
  home: Scaffold(
    body: ConnectionsPage(runtime: runtime, onOpen: (_) {}),
  ),
);

Future<void> _scrollTo(WidgetTester tester, Finder target, Key listKey) async {
  final scrollable = find.descendant(
    of: find.byKey(listKey),
    matching: find.byType(Scrollable),
  );
  await tester.scrollUntilVisible(target, 240, scrollable: scrollable);
}

PreviewRuntime _runtime({
  required List<Connection> connections,
  List<Capability> capabilities = const [],
}) => PreviewRuntime(
  connections: connections,
  capabilities: capabilities,
  latency: Duration.zero,
);

const _connection0 = Connection(
  id: ConnectionId('connection-0'),
  kind: ConnectionKind.cli,
  label: '连接 0',
  location: '/preview/connection-0',
);

List<Connection> _connections(int count) => [
  for (var index = 0; index < count; index++)
    Connection(
      id: ConnectionId('connection-$index'),
      kind: ConnectionKind.cli,
      label: '连接 $index',
      location: '/preview/connection-$index',
    ),
];

List<Capability> _capabilities(int count) => [
  for (var index = 0; index < count; index++)
    Capability(
      id: CapabilityId(
        _connection0.id,
        CapabilityKind.cliCommand,
        'capability-$index',
      ),
      title: '功能 $index',
      description: '管理页长列表虚拟化样本 $index',
      permission: PermissionLevel.read,
    ),
];

Key _connectionKey(int index) =>
    ValueKey('managed-connection-connection-$index');

Key _capabilityKey(int index) =>
    ValueKey('managed-capability-connection-0:cliCommand:capability-$index');
