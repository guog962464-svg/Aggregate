import 'package:aggregate/app/aggregate_app.dart';
import 'package:aggregate/app/app_shell.dart';
import 'package:aggregate/features/connections/connections_page.dart';
import 'package:aggregate/platform/macos/mac_host_settings_panel.dart';
import 'package:aggregate/preview/preview_runtime_factory.dart';
import 'package:aggregate/preview/ui6_inspection_host.dart';
import 'package:aggregate/widgets/glass/glass_design_tokens.dart';
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

  testWidgets('v3.5 macOS workspace geometry follows its design board', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(preview());
    await tester.pumpAndSettle();
    await openAll(tester);

    final title = tester.getRect(find.byKey(const Key('workspace-page-title')));
    expect(title.left, 299);
    expect(title.top, 72);

    final search = tester.getRect(find.byKey(const Key('global-search')));
    expect(search.left, 299);
    expect(search.top, 147);
    expect(search.width, 600);
    expect(search.height, 42);

    final allFilter = tester.getRect(find.bySemanticsLabel('按类型筛选：全部'));
    expect(allFilter.left, 299);
    expect(allFilter.top, 201);
    expect(allFilter.height, 32);

    final directory = tester.getRect(
      find.byKey(const Key('workspace-capability-directory-panel')),
    );
    final divider = tester.getRect(
      find.byKey(const Key('workspace-capability-directory-divider')),
    );
    final details = tester.getRect(
      find.byKey(const Key('workspace-capability-details')),
    );
    expect(directory.left, 299);
    expect(directory.width, closeTo(343.4, 1));
    expect(divider.left, closeTo(642.4, 1));
    expect(details.left, closeTo(689.4, 1));
    expect(details.right, 1309);

    await tester.tap(find.text('两个整数相加').first);
    await tester.pumpAndSettle();
    final detailTitle = tester.getRect(
      find.descendant(
        of: find.byKey(const Key('workspace-capability-details')),
        matching: find.text('两个整数相加'),
      ),
    );
    final result = tester.getRect(
      find.byKey(const Key('macos-embedded-result-pane')),
    );
    expect(detailTitle.left, closeTo(716.4, 1));
    expect(result.left, closeTo(689.4, 1));
    expect(result.right, 1309);
    expect(tester.takeException(), isNull);
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

  testWidgets('wide macOS settings are one continuous v9 page', (tester) async {
    tester.view.physicalSize = const Size(1360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(preview());
    await tester.pumpAndSettle();
    await tester.tap(find.text('设置').first);
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.byKey(const Key('macos-settings-category-rail')), findsNothing);
    expect(
      find.byKey(const Key('macos-settings-appearance-section')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('macos-settings-host-section')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('macos-settings-shortcuts-section')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('macos-settings-local-data-section')),
      findsOneWidget,
    );
    final switchRect = tester.getRect(find.bySemanticsLabel('外观主题'));
    expect(switchRect.left, closeTo(850, 1));
    expect(switchRect.width, 448);
    expect(switchRect.height, 224);
    // Widget tests omit the native 32pt title bar, so the in-window target
    // position 205pt is 173pt inside the Flutter surface.
    expect(switchRect.top, closeTo(173, 1));
    final helperRect = tester.getRect(
      find.text('切换控件保持原始实时拖动、方向反转与太阳/月亮内部变化。'),
    );
    expect(helperRect.left, 316);
    expect(helperRect.top, closeTo(310, 2));
    final systemButtonRect = tester.getRect(
      find.bySemanticsLabel('跟随 macOS 系统'),
    );
    expect(systemButtonRect.left, 316);
    expect(systemButtonRect.width, 178);
    expect(systemButtonRect.height, 40);
    expect(systemButtonRect.top, closeTo(342, 2));
    expect(
      tester.widget<PageFrame>(find.byType(PageFrame)).subtitle,
      '外观、设备和本机数据',
    );
    expect(find.text('跟随 macOS'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('外观主题'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('深色'), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const Key('macos-settings-shortcuts-section')),
    );
    expect(
      tester.widget<PageFrame>(find.byType(PageFrame)).subtitle,
      '外观、设备和本机数据',
    );
    expect(find.text('运行当前功能'), findsOneWidget);
    expect(find.text('返回'), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const Key('macos-settings-local-data-section')),
    );
    expect(find.text('连接配置和活动记录保存在本机。'), findsOneWidget);
    expect(find.text('仅保存脱敏后的运行状态信息'), findsOneWidget);
    final retention = tester.getRect(find.byType(DropdownButtonFormField<int>));
    expect(retention.left, 1075);
    expect(retention.width, 223);
    expect(retention.height, 44);
    final clearActivity = tester.getRect(find.bySemanticsLabel('清空记录'));
    expect(clearActivity.left, 1135);
    expect(clearActivity.width, 163);
    expect(clearActivity.height, 40);
    expect(tester.takeException(), isNull);
  }, variant: _macOS);

  testWidgets('wide macOS Host settings match the v9.0.10 sample layout', (
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
    await tester.ensureVisible(find.text('启动 Host'));
    expect(find.text('让已配对设备连接到这台 Mac'), findsOneWidget);
    final glassTokens = Theme.of(
      tester.element(find.byType(MacHostSettingsPanel)),
    ).extension<GlassDesignTokens>()!;
    expect(
      tester.widget<Text>(find.text('已停止')).style?.color,
      glassTokens.warm,
    );
    await tester.tap(find.text('启动 Host'));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.text('生成新邀请'));
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('Pixel 9'), findsOneWidget);
    expect(find.text('运行状态、配对邀请和已连接设备'), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('运行中')).style?.color,
      glassTokens.status,
    );
    expect(find.text('Android · 确认码 482 193'), findsOneWidget);
    expect(find.text('LGE AN10'), findsOneWidget);
    final stop = tester.getRect(find.bySemanticsLabel('停止 Host'));
    expect(stop.left, 1018);
    expect(stop.width, 130);
    expect(stop.height, 40);
    final rotate = tester.getRect(find.bySemanticsLabel('轮换 Mac Host 身份'));
    expect(rotate.left, 1158);
    expect(rotate.width, 140);
    expect(rotate.height, 40);
    final createInvite = tester.getRect(find.bySemanticsLabel('生成新邀请'));
    expect(createInvite.left, closeTo(1147, 1));
    expect(createInvite.width, 150);
    expect(createInvite.height, 46);

    final invitationCard = tester.getRect(
      find.byKey(const Key('host-invitation-card')),
    );
    expect(invitationCard.left, 316);
    expect(invitationCard.width, 982);
    expect(invitationCard.height, closeTo(154, 3));

    final pendingCard = tester.getRect(
      find.byKey(Key('host-pending-card-${host.inspectionPendingDeviceId}')),
    );
    expect(pendingCard.left, 316);
    expect(pendingCard.width, 982);
    expect(pendingCard.height, closeTo(68, 3));
    final pendingActions = [
      (find.bySemanticsLabel('拒绝'), 765.0, 81.0),
      (find.bySemanticsLabel('批准只读'), 853.0, 103.0),
      (find.bySemanticsLabel('允许连接向导'), 963.0, 125.0),
      (find.bySemanticsLabel('自定义权限'), 1095.0, 125.0),
    ];
    for (final (finder, left, width) in pendingActions) {
      final rect = tester.getRect(finder);
      expect(rect.left, closeTo(left, 1));
      expect(rect.width, width);
      expect(rect.height, 40);
    }

    final pairedCard = tester.getRect(
      find.byKey(Key('host-paired-card-${host.inspectionPairedDeviceId}')),
    );
    expect(pairedCard.left, 316);
    expect(pairedCard.width, 982);
    expect(pairedCard.height, closeTo(48, 3));
    final pairedDevice = tester.getRect(find.text('LGE AN10'));
    expect(pairedDevice.left, closeTo(363, 1));
    final editGrant = tester.getRect(find.bySemanticsLabel('修改权限'));
    expect(editGrant.left, closeTo(1060, 1));
    expect(editGrant.width, 111);
    expect(editGrant.height, 40);
    final revokeGrant = tester.getRect(find.bySemanticsLabel('撤销'));
    expect(revokeGrant.left, closeTo(1179, 1));
    expect(revokeGrant.width, 119);
    expect(revokeGrant.height, 40);
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
