import 'package:aggregate/app/aggregate_app.dart';
import 'package:aggregate/app/app_shell.dart';
import 'package:aggregate/features/connections/connections_page.dart';
import 'package:aggregate/platform/macos/mac_host_settings_panel.dart';
import 'package:aggregate/preview/preview_runtime_factory.dart';
import 'package:aggregate/preview/ui6_inspection_host.dart';
import 'package:aggregate/widgets/glass/glass_motion.dart';
import 'package:aggregate/widgets/page_frame.dart';
import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _macOS = TargetPlatformVariant({TargetPlatform.macOS});

void main() {
  Widget preview() => AggregateApp(
    runtime: createPreviewRuntime(),
    glassMotionClock: ManualGlassMotionClock(),
  );

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
  }, variant: _macOS);

  testWidgets('wide shell shows all primary pages', (tester) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(preview());
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text('Aggregate'),
      ),
      findsNothing,
    );
    expect(tester.getSize(find.byKey(const Key('macos-sidebar'))).width, 240);
    expect(find.text('音乐播放器'), findsOneWidget);
    expect(find.text('所有功能'), findsOneWidget);
    await tester.tap(find.text('管理连接').first);
    await tester.pumpAndSettle();
    expect(find.text('示例 Git CLI'), findsWidgets);
    await tester.tap(find.text('设置').first);
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('跟随 macOS 系统'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, variant: _macOS);

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
  }, variant: _macOS);

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
    expect(find.text('搜索功能…'), findsNothing);
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
    await tester.enterText(find.byKey(const Key('global-search')), '');
    await tester.pumpAndSettle();
    expect(find.text('最近使用'), findsOneWidget);
    await tester.tap(find.text('活动').first);
    await tester.pumpAndSettle();
    expect(find.text('add'), findsWidgets);
    expect(tester.takeException(), isNull);
  }, variant: _macOS);

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
  }, variant: _macOS);

  for (final width in [800.0, 1024.0, 1440.0]) {
    testWidgets('shell fits ${width.toInt()} width', (tester) async {
      tester.view.physicalSize = Size(width, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(preview());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }, variant: _macOS);
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
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('跟随 macOS 系统'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, variant: _macOS);

  testWidgets('wide macOS settings show category rail and theme state', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(preview());
    await tester.pumpAndSettle();
    await tester.tap(find.text('设置').first);
    await tester.pump(const Duration(milliseconds: 600));

    expect(
      find.byKey(const Key('macos-settings-category-rail')),
      findsOneWidget,
    );
    final railRect = tester.getRect(
      find.byKey(const Key('macos-settings-category-rail')),
    );
    expect(railRect.left, 299);
    expect(railRect.width, 176);
    final categoryRects = [
      '外观',
      'Mac Host',
      '快捷键',
      '本机数据',
    ].map((name) => tester.getRect(find.bySemanticsLabel('设置分类：$name')));
    final categories = categoryRects.toList();
    expect(categories.first.top - railRect.top, 8);
    for (var index = 0; index < categories.length; index++) {
      expect(categories[index].height, 40);
      if (index > 0) {
        expect(categories[index].top - categories[index - 1].top, 49);
      }
    }
    final appearanceHeading = tester.getRect(find.text('外观').last);
    final switchRect = tester.getRect(find.bySemanticsLabel('外观主题'));
    expect(switchRect.left, 655);
    expect(switchRect.width, 490);
    expect(switchRect.height, 245);
    expect(switchRect.top - appearanceHeading.top, closeTo(122, 1));
    final systemButtonRect = tester.getRect(
      find.bySemanticsLabel('跟随 macOS 系统'),
    );
    expect(systemButtonRect.left, 817);
    expect(systemButtonRect.width, 166);
    expect(systemButtonRect.height, 40);
    expect(systemButtonRect.top - switchRect.bottom, 8);
    expect(
      tester.widget<PageFrame>(find.byType(PageFrame)).subtitle,
      '让材质、光线和工作方式保持一致',
    );
    expect(find.text('让材质、光线和工作方式保持一致'), findsOneWidget);
    expect(find.text('跟随 macOS'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('外观主题'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('深色'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('设置分类：快捷键'));
    await tester.pump(const Duration(milliseconds: 350));
    expect(tester.widget<PageFrame>(find.byType(PageFrame)).subtitle, '快捷键');
    expect(find.text('常用操作始终使用同一组系统组合键。'), findsOneWidget);
    expect(find.text('运行当前功能'), findsOneWidget);
    expect(find.text('返回或关闭'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('设置分类：Mac Host'));
    await tester.pump(const Duration(milliseconds: 350));
    expect(
      tester.widget<PageFrame>(find.byType(PageFrame)).subtitle,
      '管理配对 Mac 与访问权限',
    );
    expect(find.text('管理配对 Mac 与访问权限'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('设置分类：本机数据'));
    await tester.pump(const Duration(milliseconds: 350));
    expect(tester.widget<PageFrame>(find.byType(PageFrame)).subtitle, '本机数据');
    expect(find.text('连接配置和活动记录保存在本机或执行端；活动内容不会保存参数或结果。'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, variant: _macOS);

  testWidgets('wide macOS Host settings match the v3.5 sample layout', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final runtime = createPreviewRuntime();
    final host = Ui6InspectionHost();
    await tester.pumpWidget(
      AggregateApp(
        runtime: runtime,
        glassMotionClock: ManualGlassMotionClock(),
        platformSettingsSections: [
          MacHostSettingsPanel(
            hostControl: host,
            pairingControl: host,
            identityRotation: host,
            loadConnections: runtime.listConnections,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('设置').first);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.bySemanticsLabel('设置分类：Mac Host'));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.tap(find.text('启动 Host'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('生成新邀请'));
    await tester.pumpAndSettle();

    expect(find.text('Pixel 9'), findsOneWidget);
    expect(find.text('Android · 确认码 482 193'), findsOneWidget);
    expect(find.text('LGE AN10'), findsOneWidget);
    final stop = tester.getRect(find.bySemanticsLabel('停止 Host'));
    expect(stop.left, 1189);
    expect(stop.width, 120);
    expect(stop.height, 40);
    final rotate = tester.getRect(find.bySemanticsLabel('轮换 Mac Host 身份'));
    expect(rotate.left, 1129);
    expect(rotate.width, 180);
    expect(rotate.height, 40);
    final createInvite = tester.getRect(find.bySemanticsLabel('生成新邀请'));
    expect(createInvite.left, 1168);
    expect(createInvite.width, 141);
    expect(createInvite.height, 40);

    final invitationCard = tester.getRect(
      find.byKey(const Key('host-invitation-card')),
    );
    expect(invitationCard.left, 526);
    expect(invitationCard.width, 783);
    expect(invitationCard.height, closeTo(200, 3));

    final pendingCard = tester.getRect(
      find.byKey(Key('host-pending-card-${host.inspectionDeviceId}')),
    );
    expect(pendingCard.left, 526);
    expect(pendingCard.width, 783);
    expect(pendingCard.height, closeTo(68, 3));
    final pendingActions = [
      (find.bySemanticsLabel('拒绝'), 748.0, 84.0),
      (find.bySemanticsLabel('批准只读'), 840.0, 107.0),
      (find.bySemanticsLabel('允许连接向导'), 955.0, 143.0),
      (find.bySemanticsLabel('自定义权限'), 1106.0, 125.0),
    ];
    for (final (finder, left, width) in pendingActions) {
      final rect = tester.getRect(finder);
      expect(rect.left, closeTo(left, 1));
      expect(rect.width, width);
      expect(rect.height, 40);
    }

    final pairedCard = tester.getRect(
      find.byKey(Key('host-paired-card-${host.inspectionDeviceId}')),
    );
    expect(pairedCard.left, 526);
    expect(pairedCard.width, 783);
    expect(pairedCard.height, closeTo(64, 3));
    final pairedDevice = tester.getRect(find.text('LGE AN10'));
    expect(pairedDevice.left, closeTo(540, 1));
    final editGrant = tester.getRect(find.bySemanticsLabel('修改权限'));
    expect(editGrant.left, closeTo(1080, 1));
    expect(editGrant.width, 112);
    expect(editGrant.height, 40);
    expect(tester.takeException(), isNull);
  }, variant: _macOS);

  testWidgets('compact macOS Host settings fit at 800pt', (tester) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final runtime = createPreviewRuntime();
    final host = Ui6InspectionHost();
    addTearDown(host.dispose);
    addTearDown(runtime.dispose);
    await tester.pumpWidget(
      AggregateApp(
        runtime: runtime,
        glassMotionClock: ManualGlassMotionClock(),
        platformSettingsSections: [
          MacHostSettingsPanel(
            hostControl: host,
            pairingControl: host,
            identityRotation: host,
            loadConnections: runtime.listConnections,
          ),
        ],
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.text('设置').first);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.bySemanticsLabel('设置分类：Mac Host'));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.ensureVisible(find.text('启动 Host'));
    await tester.tap(find.text('启动 Host'));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.ensureVisible(find.text('生成新邀请'));
    await tester.tap(find.text('生成新邀请'));
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('Pixel 9'), findsOneWidget);
    expect(find.text('LGE AN10'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, variant: _macOS);

  testWidgets('command K focuses accessible workspace search from run', (
    tester,
  ) async {
    await tester.pumpWidget(preview());
    await tester.pumpAndSettle();
    await openAll(tester);
    await tester.enterText(find.byKey(const Key('global-search')), 'Git');
    await tester.pumpAndSettle();
    await tester.tap(find.text('查看 Git 状态').first);
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
  }, variant: _macOS);

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
  }, variant: _macOS);

  testWidgets('favorite and appearance persist in the runtime', (tester) async {
    final runtime = createPreviewRuntime();
    await tester.pumpWidget(
      AggregateApp(
        runtime: runtime,
        glassMotionClock: ManualGlassMotionClock(),
      ),
    );
    await tester.pumpAndSettle();
    await openAll(tester);
    await tester.enterText(find.byKey(const Key('global-search')), 'Git');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('收藏 查看 Git 状态'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('设置').first);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.bySemanticsLabel('外观主题'));
    await tester.pump(const Duration(milliseconds: 600));
    expect(
      (await runtime.loadPreferences()).appearance,
      AppearancePreference.dark,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      AggregateApp(
        runtime: runtime,
        glassMotionClock: ManualGlassMotionClock(),
      ),
    );
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
  }, variant: _macOS);

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
  }, variant: _macOS);

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
  }, variant: _macOS);
}
