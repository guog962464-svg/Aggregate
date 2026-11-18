import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:aggregate/app/aggregate_app.dart';
import 'package:aggregate/features/catalog/workspace_page.dart';
import 'package:aggregate/preview/preview_runtime_factory.dart';
import 'package:aggregate/preview/ui6_inspection_runtime.dart';
import 'package:aggregate/widgets/glass/glass_motion.dart';
import 'package:aggregate/widgets/glass/glass_action_button.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _workspace(
  Ui6InspectionRuntime runtime, {
  required ValueChanged<ConnectionKind> onAddConnection,
}) => GlassMotionScope(
  clock: ManualGlassMotionClock(),
  child: MaterialApp(
    home: Scaffold(
      body: WorkspacePage(
        runtime: runtime,
        onOpen: (_) {},
        onAddConnection: onAddConnection,
        favoriteKeys: const [],
        onFavoriteChanged: (_, _) {},
        autofocusSearch: false,
      ),
    ),
  ),
);

void main() {
  testWidgets('global shortcut reaches the accessible workspace results', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        AggregateApp(
          runtime: createPreviewRuntime(),
          glassMotionClock: ManualGlassMotionClock(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('管理连接').first);
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();

      final search = find.byKey(const Key('global-search'));
      expect(Focus.of(tester.element(search)).hasFocus, isTrue);
      await tester.enterText(search, 'Git');
      await tester.pumpAndSettle();
      final result = find.ancestor(
        of: find.text('查看 Git 状态'),
        matching: find.byType(GlassActionButton),
      );
      expect(result, findsOneWidget);
      expect(
        tester
            .getSemantics(result)
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isTrue,
      );
    } finally {
      semantics.dispose();
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('search and empty-filter actions restore workspace results', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await tester.pumpWidget(
        _workspace(Ui6InspectionRuntime(), onAddConnection: (_) {}),
      );
      await tester.pumpAndSettle();

      final search = find.byKey(const Key('global-search'));
      await tester.enterText(search, 'Git');
      await tester.pumpAndSettle();
      expect(find.text('查看 Git 状态'), findsOneWidget);

      await tester.tap(find.byTooltip('清除搜索'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(search).controller!.text, isEmpty);
      expect(find.text('全部功能 · 17'), findsOneWidget);

      await tester.tap(find.text('资源'));
      await tester.pumpAndSettle();
      await tester.enterText(search, 'ui6-no-match');
      await tester.pumpAndSettle();
      expect(find.textContaining('没有找到'), findsOneWidget);

      await tester.tap(find.text('清除筛选'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(search).controller!.text, isEmpty);
      expect(find.text('全部功能 · 17'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('empty workspace add actions route supported connection kinds', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final addedKinds = <ConnectionKind>[];
      await tester.pumpWidget(
        _workspace(
          Ui6InspectionRuntime(emptyWorkspace: true),
          onAddConnection: addedKinds.add,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('添加 CLI'), findsOneWidget);
      expect(find.text('添加 MCP'), findsOneWidget);
      await tester.tap(find.text('添加 CLI'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('添加 MCP'));
      await tester.pumpAndSettle();
      expect(addedKinds, [ConnectionKind.cli, ConnectionKind.mcpStdio]);

      await tester.pumpWidget(
        _workspace(
          Ui6InspectionRuntime(
            emptyWorkspace: true,
            features: RuntimeFeatures.httpOnly,
          ),
          onAddConnection: addedKinds.add,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('添加 HTTP MCP'), findsOneWidget);
      await tester.tap(find.text('添加 HTTP MCP'));
      await tester.pumpAndSettle();
      expect(addedKinds, [
        ConnectionKind.cli,
        ConnectionKind.mcpStdio,
        ConnectionKind.mcpHttp,
      ]);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
