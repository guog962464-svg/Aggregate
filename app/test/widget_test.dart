import 'package:aggregate/app/aggregate_app.dart';
import 'package:aggregate/app/app_shell.dart';
import 'package:aggregate/preview/preview_runtime_factory.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget preview() => AggregateApp(runtime: createPreviewRuntime());

  testWidgets('follows system dark appearance', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await tester.pumpWidget(preview());
    expect(
      Theme.of(tester.element(find.byType(AppShell))).brightness,
      Brightness.dark,
    );
  });

  testWidgets('wide shell shows all primary pages', (tester) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(preview());
    await tester.pumpAndSettle();
    expect(find.text('工作台'), findsWidgets);
    await tester.tap(find.text('连接').first);
    await tester.pumpAndSettle();
    expect(find.text('示例 Git CLI'), findsOneWidget);
    await tester.tap(find.text('设置').first);
    await tester.pumpAndSettle();
    expect(find.text('跟随 macOS 系统'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact drawer navigates and closes', (tester) async {
    tester.view.physicalSize = const Size(640, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(preview());
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('活动').first);
    await tester.pumpAndSettle();
    expect(find.text('还没有运行记录。'), findsOneWidget);
    expect(find.byType(Drawer), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('search, validate, run and see result through RuntimePort', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(preview());
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('global-search')), '整数');
    await tester.pumpAndSettle();
    expect(find.text('两个整数相加'), findsOneWidget);
    await tester.tap(find.text('两个整数相加'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('field-a')), 'abc');
    await tester.enterText(find.byKey(const Key('field-b')), '5');
    await tester.tap(find.text('运行'));
    await tester.pumpAndSettle();
    expect(find.text('请输入整数'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('field-a')), '7');
    await tester.tap(find.text('运行'));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('运行成功'), findsOneWidget);
    expect(find.textContaining('"sum": 12'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('活动').first);
    await tester.pumpAndSettle();
    expect(find.text('add'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keyboard search opens the first result', (tester) async {
    await tester.pumpWidget(preview());
    await tester.pumpAndSettle();
    final field = find.byKey(const Key('global-search'));
    await tester.enterText(field, 'Git');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('查看 Git 状态'), findsWidgets);
    expect(find.text('参数'), findsOneWidget);
  });

  for (final width in [800.0, 1024.0, 1440.0]) {
    testWidgets('shell fits ${width.toInt()} width', (tester) async {
      tester.view.physicalSize = Size(width, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(preview());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
