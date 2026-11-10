import 'package:aggregate/app/aggregate_app.dart';
import 'package:aggregate/app/app_shell.dart';
import 'package:aggregate/features/connections/connections_page.dart';
import 'package:aggregate/preview/preview_runtime_factory.dart';
import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget preview() => AggregateApp(runtime: createPreviewRuntime());

  Future<void> openAll(WidgetTester tester) async {
    await tester.tap(find.text('所有功能').first);
    await tester.pumpAndSettle();
  }

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
    expect(find.text('音乐播放器'), findsOneWidget);
    expect(find.text('所有功能'), findsOneWidget);
    await tester.tap(find.text('管理连接').first);
    await tester.pumpAndSettle();
    expect(find.text('示例 Git CLI'), findsWidgets);
    await tester.tap(find.text('设置').first);
    await tester.pumpAndSettle();
    expect(find.text('跟随系统'), findsOneWidget);
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
    await openAll(tester);
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
    expect(find.text('add'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keyboard search opens the first result', (tester) async {
    await tester.pumpWidget(preview());
    await tester.pumpAndSettle();
    await openAll(tester);
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

  testWidgets('compact settings fit', (tester) async {
    tester.view.physicalSize = const Size(640, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(preview());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('设置').first);
    await tester.pumpAndSettle();
    expect(find.text('跟随系统'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('command K focuses accessible workspace search from run', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await tester.pumpWidget(preview());
      await tester.pumpAndSettle();
      await openAll(tester);
      await tester.enterText(find.byKey(const Key('global-search')), 'Git');
      await tester.pumpAndSettle();
      await tester.tap(find.text('查看 Git 状态'));
      await tester.pumpAndSettle();
      expect(find.text('参数'), findsOneWidget);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();
      final search = find.byKey(const Key('global-search'));
      expect(search, findsOneWidget);
      expect(Focus.of(tester.element(search)).hasFocus, isTrue);
      expect(tester.testTextInput.isVisible, isTrue);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('add connection dialog validates required fields', (
    tester,
  ) async {
    ConnectionSpec? submitted;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                submitted = await showDialog<ConnectionSpec>(
                  context: context,
                  builder: (_) => const AddConnectionDialog(),
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
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) => widget is TextField && widget.decoration?.labelText == '名称',
      ),
      '本机工具',
    );
    await tester.tap(find.text('添加').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('请选择程序绝对路径'), findsOneWidget);
    expect(submitted, isNull);
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == '程序绝对路径',
      ),
      '/usr/bin/env',
    );
    await tester.tap(find.text('添加').last);
    await tester.pumpAndSettle();
    expect(submitted?.label, '本机工具');
    expect(submitted?.executable, '/usr/bin/env');
  });

  testWidgets('favorite and appearance persist in the runtime', (tester) async {
    final runtime = createPreviewRuntime();
    await tester.pumpWidget(AggregateApp(runtime: runtime));
    await tester.pumpAndSettle();
    await openAll(tester);
    await tester.enterText(find.byKey(const Key('global-search')), 'Git');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('收藏 查看 Git 状态'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('设置').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('深色'));
    await tester.pumpAndSettle();
    expect(
      (await runtime.loadPreferences()).appearance,
      AppearancePreference.dark,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(AggregateApp(runtime: runtime));
    await tester.pumpAndSettle();
    await openAll(tester);
    expect(
      (await runtime.loadPreferences()).favoriteCapabilityKeys,
      contains('example-git:cliAction:status'),
    );
    expect(
      Theme.of(tester.element(find.byType(AppShell))).brightness,
      Brightness.dark,
    );
    expect(find.text('收藏的功能'), findsOneWidget);
  });

  testWidgets('music result opens mini player and refreshes state', (
    tester,
  ) async {
    await tester.pumpWidget(preview());
    await tester.pumpAndSettle();
    await openAll(tester);
    await tester.enterText(find.byKey(const Key('global-search')), '播放');
    await tester.pumpAndSettle();
    await tester.tap(find.text('播放歌曲').first);
    await tester.pumpAndSettle();
    expect(find.text('参数'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('field-encryptedId')), 'enc');
    await tester.enterText(find.byKey(const Key('field-originalId')), '123');
    await tester.tap(find.text('运行').first);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byTooltip('收起迷你播放器'), findsOneWidget);
    await tester.tap(find.byTooltip('刷新播放状态'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('示例歌曲'), findsWidgets);
    expect(find.text('播放中'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('music search results can start a playable song', (tester) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(preview());
    await tester.pumpAndSettle();
    await openAll(tester);
    await tester.enterText(find.byKey(const Key('global-search')), '搜索');
    await tester.pumpAndSettle();
    await tester.tap(find.text('搜索歌曲').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('field-keyword')), '示例');
    await tester.tap(find.text('运行').first);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('歌曲 · 2 首'), findsOneWidget);
    expect(find.text('不可播放'), findsOneWidget);
    await tester.tap(find.byTooltip('播放 示例歌曲'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byTooltip('收起迷你播放器'), findsOneWidget);
    expect(find.text('示例歌曲'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
