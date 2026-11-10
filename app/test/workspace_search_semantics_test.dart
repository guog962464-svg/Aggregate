import 'package:aggregate/app/aggregate_app.dart';
import 'package:aggregate/preview/preview_runtime_factory.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('global shortcut reaches the accessible workspace results', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(AggregateApp(runtime: createPreviewRuntime()));
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
        matching: find.byType(ListTile),
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
}
