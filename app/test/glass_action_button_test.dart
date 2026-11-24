import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aggregate/widgets/glass/aggregate_buttons.dart';
import 'package:aggregate/widgets/glass/glass_action_button.dart';
import 'package:aggregate/widgets/glass/glass_design_tokens.dart';
import 'package:aggregate/widgets/glass/glass_glyph.dart';
import 'package:aggregate/widgets/glass/glass_motion.dart';

const _macOS = TargetPlatformVariant({TargetPlatform.macOS});

void main() {
  testWidgets('glass actions remain operable with 200 percent text', (
    tester,
  ) async {
    final clock = ManualGlassMotionClock();
    addTearDown(clock.dispose);
    var activations = 0;
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: GlassMotionScope(clock: clock, child: child!),
        ),
        home: Scaffold(
          body: Center(
            child: AggregateActionButton(
              label: '运行当前功能',
              icon: Icons.play_arrow,
              style: AggregateActionStyle.primary,
              size: GlassButtonSize.primary,
              onPressed: () => activations++,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final button = find.bySemanticsLabel('运行当前功能');
    expect(button, findsOneWidget);
    expect(tester.getSize(button).height, GlassDesignTokens.primaryHeight);
    await tester.tap(button);
    expect(activations, 1);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  }, variant: _macOS);

  test('all current Material action glyph names have a shared dot mapping', () {
    const materialNames = [
      'account_circle_outlined',
      'add',
      'arrow_back',
      'arrow_downward',
      'arrow_forward_rounded',
      'arrow_upward',
      'brightness_auto_outlined',
      'build_outlined',
      'chat_bubble_outline',
      'check_circle_outline',
      'chevron_right',
      'close',
      'content_paste',
      'content_paste_outlined',
      'copy',
      'copy_outlined',
      'dark_mode',
      'data_object',
      'delete_outline',
      'description_outlined',
      'desktop_mac',
      'desktop_mac_outlined',
      'desktop_windows_outlined',
      'devices_outlined',
      'edit_outlined',
      'error_outline',
      'file_open_outlined',
      'flash_off',
      'flash_on',
      'folder_open_outlined',
      'grid_view_outlined',
      'history',
      'history_outlined',
      'help_outline',
      'hourglass_empty',
      'hourglass_top_outlined',
      'hub',
      'hub_outlined',
      'inbox_outlined',
      'info_outline',
      'key_off_outlined',
      'lan_outlined',
      'light_mode',
      'link',
      'link_off',
      'lock_outline',
      'logout',
      'manage_search',
      'manage_search_outlined',
      'music_note_outlined',
      'music_note_rounded',
      'more_horiz',
      'network_check_outlined',
      'open_in_full',
      'open_in_new',
      'pause',
      'pause_rounded',
      'phone_android',
      'phone_android_outlined',
      'play_arrow',
      'play_arrow_rounded',
      'play_circle_outline',
      'playlist_add',
      'preview_outlined',
      'qr_code_2',
      'qr_code_scanner',
      'refresh',
      'refresh_rounded',
      'save_alt',
      'save_outlined',
      'search',
      'search_outlined',
      'settings_outlined',
      'skip_next',
      'skip_next_rounded',
      'skip_previous',
      'skip_previous_rounded',
      'star_border_rounded',
      'star_rounded',
      'stop',
      'stop_circle_outlined',
      'switch_account_outlined',
      'terminal',
      'terminal_outlined',
      'tune',
      'tune_outlined',
      'unfold_less',
      'unfold_more',
      'visibility_outlined',
      'vpn_key_off_outlined',
      'vpn_key_outlined',
    ];

    for (final name in materialNames) {
      expect(
        () => GlassGlyphCatalog.fromMaterialIconName(name),
        returnsNormally,
        reason: name,
      );
    }
    expect(GlassGlyph.values.length, greaterThanOrEqualTo(12));
    for (final glyph in GlassGlyph.values) {
      final points = GlassGlyphFactory.pointsFor(glyph);
      expect(points, isNotEmpty, reason: glyph.name);
      expect(
        points.every((point) => point.dx >= 4 && point.dx <= 25.6),
        isTrue,
      );
      expect(
        points.every((point) => point.dy >= 4 && point.dy <= 25.6),
        isTrue,
      );
    }
  });

  test('production button icon codepoints match their named glyph aliases', () {
    const mappings = <(IconData, String)>[
      (Icons.help_outline, 'help_outline'),
      (Icons.logout, 'logout'),
      (Icons.more_horiz, 'more_horiz'),
      (Icons.network_check_outlined, 'network_check_outlined'),
      (Icons.preview_outlined, 'preview_outlined'),
      (Icons.save_outlined, 'save_outlined'),
      (Icons.switch_account_outlined, 'switch_account_outlined'),
      (Icons.vpn_key_off_outlined, 'vpn_key_off_outlined'),
    ];

    for (final (icon, name) in mappings) {
      expect(
        GlassGlyphCatalog.fromMaterialIcon(icon),
        GlassGlyphCatalog.fromMaterialIconName(name),
        reason: name,
      );
    }
    expect(
      GlassGlyphFactory.pointsFor(GlassGlyph.logout),
      isNot(GlassGlyphFactory.pointsFor(GlassGlyph.externalLink)),
    );
    expect(
      GlassGlyphFactory.pointsFor(GlassGlyph.more),
      isNot(GlassGlyphFactory.pointsFor(GlassGlyph.grid)),
    );
  });

  test(
    'run, refresh, and search keep recognizable shared-grid silhouettes',
    () {
      bool hasPoint(List<Offset> points, Offset target) => points.any(
        (point) =>
            (point.dx - target.dx).abs() < 1e-6 &&
            (point.dy - target.dy).abs() < 1e-6,
      );

      for (final glyph in const [
        GlassGlyph.play,
        GlassGlyph.refresh,
        GlassGlyph.search,
      ]) {
        final points = GlassGlyphFactory.pointsFor(glyph);
        expect(points.toSet(), hasLength(points.length), reason: glyph.name);
        for (final point in points) {
          final column = (point.dx - 4) / GlassDesignTokens.glyphPitch;
          final row = (point.dy - 4) / GlassDesignTokens.glyphPitch;
          expect(
            column,
            closeTo(column.roundToDouble(), 1e-9),
            reason: glyph.name,
          );
          expect(row, closeTo(row.roundToDouble(), 1e-9), reason: glyph.name);
        }
      }

      final refresh = GlassGlyphFactory.pointsFor(GlassGlyph.refresh);
      expect(refresh, hasLength(17));
      expect(hasPoint(refresh, const Offset(14.8, 4)), isTrue);
      expect(hasPoint(refresh, const Offset(6.7, 9.4)), isTrue);
      expect(hasPoint(refresh, const Offset(22.9, 9.4)), isTrue);
      expect(hasPoint(refresh, const Offset(20.2, 6.7)), isTrue);
      expect(hasPoint(refresh, const Offset(22.9, 6.7)), isTrue);
      expect(hasPoint(refresh, const Offset(9.4, 17.5)), isTrue);

      final play = GlassGlyphFactory.pointsFor(GlassGlyph.play);
      expect(play, hasLength(17));
      expect(hasPoint(play, const Offset(9.4, 6.7)), isTrue);
      expect(hasPoint(play, const Offset(9.4, 22.9)), isTrue);
      expect(hasPoint(play, const Offset(20.2, 14.8)), isTrue);
      expect(hasPoint(play, const Offset(25.6, 14.8)), isFalse);

      final search = GlassGlyphFactory.pointsFor(GlassGlyph.search);
      expect(search, hasLength(22));
      expect(hasPoint(search, const Offset(14.8, 4)), isTrue);
      expect(hasPoint(search, const Offset(20.2, 20.2)), isTrue);
      expect(hasPoint(search, const Offset(22.9, 22.9)), isTrue);
      expect(hasPoint(search, const Offset(25.6, 25.6)), isTrue);
      expect(hasPoint(search, const Offset(25.6, 22.9)), isFalse);
    },
  );

  testWidgets('production action icons build in the macOS glass scope', (
    tester,
  ) async {
    const buttons = <(String, IconData)>[
      ('未知权限', Icons.help_outline),
      ('退出登录', Icons.logout),
      ('更多终端键', Icons.more_horiz),
      ('测试连接', Icons.network_check_outlined),
      ('预览参数', Icons.preview_outlined),
      ('保存设置', Icons.save_outlined),
      ('切换账号', Icons.switch_account_outlined),
      ('撤销密钥', Icons.vpn_key_off_outlined),
    ];

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => GlassMotionScope(child: child!),
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                for (final (label, icon) in buttons)
                  AggregateActionButton(
                    label: label,
                    icon: icon,
                    onPressed: () {},
                  ),
                const SizedBox(height: 8),
                AggregateIconButton(
                  tooltip: '退出账号',
                  icon: Icons.logout,
                  onPressed: () {},
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(GlassActionButton), findsNWidgets(buttons.length + 1));
    expect(tester.takeException(), isNull);
  }, variant: _macOS);

  test('Host revoke Material icon resolves to the glass close glyph', () {
    expect(
      GlassGlyphCatalog.fromMaterialIcon(Icons.link_off),
      GlassGlyph.close,
    );
  });

  test('Host setup Material icon resolves to the glass settings glyph', () {
    expect(
      GlassGlyphCatalog.fromMaterialIcon(Icons.settings_outlined),
      GlassGlyph.settings,
    );
  });

  testWidgets('every glyph paints through the shared mark in both themes', (
    tester,
  ) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    for (final ratio in [1.0, 2.0]) {
      tester.view.devicePixelRatio = ratio;
      tester.view.physicalSize = Size(800 * ratio, 600 * ratio);
      for (final brightness in [Brightness.light, Brightness.dark]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness).copyWith(
              extensions: [GlassDesignTokens.forBrightness(brightness)],
            ),
            home: Scaffold(
              body: SingleChildScrollView(
                child: Wrap(
                  children: [
                    for (final glyph in GlassGlyph.values)
                      GlassGlyphMark(glyph: glyph, size: 20),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(
          find.byType(GlassGlyphMark),
          findsNWidgets(GlassGlyph.values.length),
        );
        expect(tester.takeException(), isNull);
      }
    }
  });

  testWidgets('mouse and keyboard activation invoke one action each', (
    tester,
  ) async {
    var calls = 0;
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: GlassActionButton(
              key: const ValueKey('run'),
              label: '运行',
              glyph: GlassGlyph.play,
              kind: GlassButtonKind.primary,
              size: GlassButtonSize.primary,
              focusNode: focusNode,
              onPressed: () => calls++,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('run')));
    await tester.pump();
    expect(calls, 1);

    focusNode.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(calls, 2);
  });

  testWidgets('Tab and Shift+Tab follow the visible glass action order', (
    tester,
  ) async {
    final first = FocusNode();
    final second = FocusNode();
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FocusTraversalGroup(
            child: Column(
              children: [
                GlassActionButton(
                  label: '搜索',
                  glyph: GlassGlyph.search,
                  focusNode: first,
                  onPressed: () {},
                ),
                GlassActionButton(
                  label: '运行',
                  glyph: GlassGlyph.play,
                  focusNode: second,
                  onPressed: () {},
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(first.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(second.hasFocus, isTrue);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(first.hasFocus, isTrue);
  }, variant: _macOS);

  testWidgets('glass action semantics follows its keyboard focus state', (
    tester,
  ) async {
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: GlassActionButton(
              label: '键盘焦点按钮',
              glyph: GlassGlyph.search,
              focusNode: focusNode,
              onPressed: () {},
            ),
          ),
        ),
      ),
    );

    final button = find.bySemanticsLabel('键盘焦点按钮');
    var data = tester.getSemantics(button).getSemanticsData();
    expect(data.flagsCollection.isFocused, ui.Tristate.isFalse);

    focusNode.requestFocus();
    await tester.pump();
    data = tester.getSemantics(button).getSemanticsData();
    expect(data.flagsCollection.isFocused, ui.Tristate.isTrue);

    focusNode.unfocus();
    await tester.pump();
    data = tester.getSemantics(button).getSemanticsData();
    expect(data.flagsCollection.isFocused, ui.Tristate.isFalse);
    semantics.dispose();
  }, variant: _macOS);

  testWidgets('pressed action visibly depresses and releases after one tap', (
    tester,
  ) async {
    var calls = 0;
    const actionKey = ValueKey('pressed-action');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: GlassActionButton(
              key: actionKey,
              label: '导出动作清单',
              glyph: GlassGlyph.save,
              size: GlassButtonSize.compactAction,
              onPressed: () => calls++,
            ),
          ),
        ),
      ),
    );

    final button = find.descendant(
      of: find.byKey(actionKey),
      matching: find.byType(TextButton),
    );
    expect(button, findsOneWidget);
    final idleTop = tester.getTopLeft(button).dy;
    final gesture = await tester.startGesture(tester.getCenter(button));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 39));

    final pressedTop = tester.getTopLeft(button).dy;
    expect(pressedTop - idleTop, inInclusiveRange(.5, .9));
    expect(calls, 0);

    await gesture.up();
    await tester.pump();
    expect(calls, 1);
    await tester.pump(const Duration(milliseconds: 39));
    expect(tester.getTopLeft(button).dy, lessThan(pressedTop));
    await tester.pump(const Duration(milliseconds: 39));
    expect(tester.getTopLeft(button).dy, closeTo(idleTop, .01));
  });

  testWidgets('busy and disabled states suppress the operation', (
    tester,
  ) async {
    var calls = 0;
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              GlassActionButton(
                label: '保存',
                glyph: GlassGlyph.save,
                busy: true,
                onPressed: () => calls++,
              ),
              GlassActionButton(
                label: '复制结果',
                glyph: GlassGlyph.copy,
                enabled: false,
                onPressed: () => calls++,
              ),
            ],
          ),
        ),
      ),
    );

    expect(
      tester
          .getSemantics(find.bySemanticsLabel('保存'))
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      isFalse,
    );
    final disabledData = tester
        .getSemantics(find.bySemanticsLabel('复制结果'))
        .getSemanticsData();
    expect(disabledData.flagsCollection.isEnabled, ui.Tristate.isFalse);
    expect(disabledData.hasAction(SemanticsAction.tap), isFalse);
    await tester.tap(find.bySemanticsLabel('保存'));
    await tester.tap(find.bySemanticsLabel('复制结果'));
    await tester.pump();
    expect(calls, 0);
    semantics.dispose();
  });

  testWidgets('null callback keeps disabled framework semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: GlassActionButton(
              label: 'Disabled AX probe',
              glyph: GlassGlyph.copy,
              enabled: false,
              onPressed: null,
            ),
          ),
        ),
      ),
    );

    final data = tester
        .getSemantics(find.bySemanticsLabel('Disabled AX probe'))
        .getSemanticsData();
    expect(data.flagsCollection.isEnabled, ui.Tristate.isFalse);
    expect(data.hasAction(SemanticsAction.tap), isFalse);
    semantics.dispose();
  });

  testWidgets(
    'button sizes preserve their target heights and selected semantics',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                GlassActionButton(
                  key: const ValueKey('primary'),
                  label: '运行',
                  glyph: GlassGlyph.play,
                  size: GlassButtonSize.primary,
                  kind: GlassButtonKind.primary,
                  onPressed: () {},
                ),
                GlassActionButton(
                  key: const ValueKey('icon'),
                  label: '搜索',
                  glyph: GlassGlyph.search,
                  iconOnly: true,
                  selected: true,
                  size: GlassButtonSize.icon,
                  onPressed: () {},
                ),
                GlassActionButton(
                  key: const ValueKey('reference'),
                  label: '运行设计样本',
                  glyph: GlassGlyph.play,
                  iconOnly: true,
                  size: GlassButtonSize.reference,
                  onPressed: () {},
                ),
                GlassActionButton(
                  key: const ValueKey('activity-row'),
                  label: '查看 Git 状态',
                  glyph: GlassGlyph.history,
                  size: GlassButtonSize.activityRow,
                  onPressed: () {},
                ),
                GlassActionButton(
                  key: const ValueKey('capability-row'),
                  label: '查看 Git 状态',
                  glyph: GlassGlyph.play,
                  size: GlassButtonSize.capabilityRow,
                  onPressed: () {},
                ),
                GlassActionButton(
                  key: const ValueKey('target-option'),
                  label: '此 Mac',
                  glyph: GlassGlyph.device,
                  size: GlassButtonSize.targetOption,
                  onPressed: () {},
                ),
              ],
            ),
          ),
        ),
      );

      expect(
        tester.getSize(find.byKey(const ValueKey('primary'))).height,
        GlassDesignTokens.primaryHeight,
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('icon'))),
        const Size.square(GlassDesignTokens.iconButtonSize),
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('reference'))),
        const Size.square(GlassDesignTokens.referenceHeight),
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('activity-row'))).height,
        72,
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('capability-row'))).height,
        48,
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('target-option'))).height,
        61,
      );
      expect(
        tester
            .getSemantics(find.bySemanticsLabel('搜索'))
            .flagsCollection
            .isSelected,
        ui.Tristate.isTrue,
      );
      expect(
        tester
            .getSemantics(find.bySemanticsLabel('搜索'))
            .flagsCollection
            .isButton,
        isTrue,
      );
      semantics.dispose();
    },
  );
}
