import 'package:aggregate/app/aggregate_app.dart';
import 'package:aggregate/features/connections/connections_page.dart';
import 'package:aggregate/preview/preview_runtime_factory.dart';
import 'package:aggregate/widgets/result_panel.dart';
import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:aggregate_runtime/aggregate_runtime.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('HTTP-only runtime cannot offer local connection types', (
    tester,
  ) async {
    ConnectionSpec? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                selected = await showDialog<ConnectionSpec>(
                  context: context,
                  builder: (_) => const AddConnectionDialog(
                    allowedKinds: {ConnectionKind.mcpHttp},
                  ),
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
    expect(find.text('HTTP MCP'), findsOneWidget);
    expect(find.text('程序绝对路径'), findsNothing);
    expect(find.byTooltip('选择程序'), findsNothing);
    await tester.enterText(find.widgetWithText(TextField, '名称'), '远程服务');
    await tester.enterText(
      find.widgetWithText(TextField, 'HTTP URL'),
      'https://example.invalid/mcp',
    );
    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();
    expect(selected?.kind, ConnectionKind.mcpHttp);
  });

  testWidgets('runtime without provisioning does not show add controls', (
    tester,
  ) async {
    final runtime = PreviewRuntime(
      connections: const [],
      capabilities: const [],
      features: const RuntimeFeatures(connectionKinds: {}),
    );
    addTearDown(runtime.dispose);
    await tester.pumpWidget(AggregateApp(runtime: runtime));
    await tester.pumpAndSettle();
    expect(find.text('添加连接'), findsNothing);
    await tester.tap(find.text('管理连接').first);
    await tester.pumpAndSettle();
    expect(find.text('添加连接'), findsNothing);
  });

  testWidgets('unsupported local file actions are absent', (tester) async {
    final runtime = PreviewRuntime(
      connections: const [],
      capabilities: const [],
      features: RuntimeFeatures.httpOnly,
    );
    addTearDown(runtime.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ResultPanel(
            state: RunState.succeeded,
            blocks: const [ResultBlock(ResultKind.file, '/remote/report.txt')],
            runtime: runtime,
          ),
        ),
      ),
    );
    expect(find.text('/remote/report.txt'), findsOneWidget);
    expect(find.text('预览文件'), findsNothing);
    expect(find.text('在文件管理器中显示'), findsNothing);
  });

  testWidgets('Windows keyboard convention works in the shared UI', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await tester.pumpWidget(AggregateApp(runtime: createPreviewRuntime()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('所有功能').first);
      await tester.pumpAndSettle();
      expect(find.text('Ctrl+K'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('global-search')), 'Git');
      await tester.pumpAndSettle();
      await tester.tap(find.text('查看 Git 状态'));
      await tester.pumpAndSettle();
      expect(find.text('运行快捷键  Ctrl+Enter'), findsOneWidget);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      final search = find.byKey(const Key('global-search'));
      expect(Focus.of(tester.element(search)).hasFocus, isTrue);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
