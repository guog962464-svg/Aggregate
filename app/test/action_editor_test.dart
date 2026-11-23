import 'package:aggregate/app/theme.dart';
import 'package:aggregate/features/connections/action_editor_dialog.dart';
import 'package:aggregate/features/connections/connections_page.dart';
import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:aggregate/widgets/glass/glass_motion.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Host CLI connection does not expose local action editor', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final runtime = _HostConnectionRuntime();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ConnectionsPage(runtime: runtime, onOpen: (_) {}),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('编辑动作'), findsNothing);
    await tester.tap(find.text('删除连接'));
    await tester.pumpAndSettle();
    expect(find.text('此连接将从配对的 Mac Host 删除。'), findsOneWidget);
    await tester.tap(find.text('删除').last);
    await tester.pumpAndSettle();
    expect(runtime.removed?.value, 'host-cli');
    expect(tester.takeException(), isNull);
  });

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

  testWidgets('connection action editor cancel discards its draft', (
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

    await tester.tap(find.text('编辑动作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新增动作'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('action-manifest-json')))
          .controller!
          .text,
      contains('action1'),
    );

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('action-manifest-json')), findsNothing);
    expect(runtime.saved, isNull);

    await tester.tap(find.text('编辑动作'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('action-manifest-json')))
          .controller!
          .text,
      isNot(contains('action1')),
    );
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('macOS action editor follows the v9 design board', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(1360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    final runtime = _ActionRuntime();
    await tester.pumpWidget(
      GlassMotionScope(
        child: MaterialApp(
          theme: AggregateTheme.forPlatform(
            AggregateTheme.light,
            TargetPlatform.macOS,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => ActionEditorDialog(
                      runtime: runtime,
                      connection: runtime.connection,
                    ),
                  ),
                  child: const Text('打开编辑器'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开编辑器'));
    await tester.pumpAndSettle();

    final panel = tester.getRect(find.byKey(const Key('action-editor-panel')));
    final manifest = tester.getRect(
      find.byKey(const Key('action-manifest-json')),
    );
    final sample = tester.getRect(
      find.byKey(const Key('action-editor-sample-json')),
    );
    final actionChoice = tester.getRect(
      find.byType(DropdownButtonFormField<String>),
    );
    final previewButton = tester.getRect(
      find.byKey(const Key('action-editor-preview-button')),
    );
    final previewResult = tester.getRect(
      find.byKey(const Key('action-editor-preview-result')),
    );
    expect(panel.size, const Size(680, 700));
    expect(manifest.width, closeTo(620, .1));
    expect(manifest.height, closeTo(300, .1));
    expect(manifest.left, closeTo(panel.left + 30, .1));
    expect(manifest.top, closeTo(panel.top + 167, .1));
    expect(sample.width, closeTo(300, .1));
    expect(sample.height, closeTo(55, .1));
    expect(actionChoice.width, closeTo(300, .1));
    expect(actionChoice.height, closeTo(55, .1));
    expect(sample.top, closeTo(panel.top + 472, .1));
    expect(actionChoice.top, closeTo(panel.top + 472, .1));
    expect(previewButton.width, closeTo(179, .1));
    expect(previewButton.height, closeTo(40, .1));
    expect(previewButton.top, closeTo(panel.top + 540, .1));
    expect(previewResult.top, closeTo(panel.top + 540, .1));
    expect(sample.bottom, lessThan(previewResult.top));
    expect(panel.top, closeTo(95.5, .5));
    final manifestLabel = tester.getRect(
      find.byKey(const Key('action-manifest-label')),
    );
    expect(manifestLabel.top, closeTo(panel.top + 140, .1));
    expect(find.byKey(const Key('preview-action-label')), findsOneWidget);
    expect(find.byKey(const Key('action-sample-label')), findsOneWidget);
    final renderError = tester.takeException();
    debugDefaultTargetPlatformOverride = null;
    expect(renderError, isNull);
  });

  testWidgets('macOS compact action editor keeps footer reachable', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(800, 632);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    final runtime = _ActionRuntime();
    await tester.pumpWidget(
      GlassMotionScope(
        child: MaterialApp(
          theme: AggregateTheme.forPlatform(
            AggregateTheme.light,
            TargetPlatform.macOS,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => ActionEditorDialog(
                      runtime: runtime,
                      connection: runtime.connection,
                    ),
                  ),
                  child: const Text('打开编辑器'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开编辑器'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('action-editor-panel')), findsNothing);
    expect(find.byKey(const Key('action-manifest-json')), findsOneWidget);
    final cancel = find.text('取消');
    final save = find.text('保存动作');
    expect(tester.getRect(cancel).bottom, lessThanOrEqualTo(632));
    expect(tester.getRect(save).bottom, lessThanOrEqualTo(632));

    await tester.tap(find.text('新增动作'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('action-manifest-json')))
          .controller!
          .text,
      contains('action1'),
    );
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(runtime.saved?['actions'], hasLength(2));

    await tester.tap(find.text('打开编辑器'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('action-manifest-json')))
          .controller!
          .text,
      contains('action1'),
    );
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    final renderError = tester.takeException();
    debugDefaultTargetPlatformOverride = null;
    expect(renderError, isNull);
  });
}

final class _HostConnectionRuntime implements RuntimePort {
  ConnectionId? removed;

  @override
  bool get isPreview => false;

  @override
  RuntimeFeatures get features => RuntimeFeatures.httpOnly;

  @override
  Future<List<Connection>> listConnections() async => [
    Connection(
      id: ConnectionId('host-cli'),
      kind: ConnectionKind.cli,
      label: 'Host CLI',
      location: 'Host managed executable',
      executionTarget: ExecutionTarget.host('mac-host'),
    ),
  ];

  @override
  Future<List<Capability>> searchCapabilities(SearchQuery query) async => [];

  @override
  Future<void> removeConnection(ConnectionId id) async {
    removed = id;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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
  Future<JsonMap?> loadActionManifest(ConnectionId id) async => saved;

  @override
  Future<void> saveActionManifest(ConnectionId id, JsonMap manifest) async {
    saved = manifest;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
