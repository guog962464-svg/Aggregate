import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aggregate/widgets/glass/glass_action_button.dart';
import 'package:aggregate/widgets/glass/glass_design_tokens.dart';
import 'package:aggregate/widgets/glass/glass_glyph.dart';

void main() {
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
      'lock_outline',
      'manage_search',
      'manage_search_outlined',
      'music_note_outlined',
      'music_note_rounded',
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
      'qr_code_2',
      'qr_code_scanner',
      'refresh',
      'refresh_rounded',
      'save_alt',
      'search',
      'search_outlined',
      'skip_next',
      'skip_next_rounded',
      'skip_previous',
      'skip_previous_rounded',
      'star_border_rounded',
      'star_rounded',
      'stop',
      'stop_circle_outlined',
      'terminal',
      'terminal_outlined',
      'tune',
      'tune_outlined',
      'unfold_less',
      'unfold_more',
      'visibility_outlined',
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
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('复制结果'))
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      isFalse,
    );
    await tester.tap(find.bySemanticsLabel('保存'));
    await tester.tap(find.bySemanticsLabel('复制结果'));
    await tester.pump();
    expect(calls, 0);
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
