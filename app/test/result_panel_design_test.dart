import 'package:aggregate/app/theme.dart';
import 'package:aggregate/widgets/glass/aggregate_buttons.dart';
import 'package:aggregate/widgets/glass/glass_action_button.dart';
import 'package:aggregate/widgets/glass/glass_design_tokens.dart';
import 'package:aggregate/widgets/glass/glass_motion.dart';
import 'package:aggregate/widgets/glass/glass_panel_surface.dart';
import 'package:aggregate/widgets/result_panel.dart';
import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _macOS = TargetPlatformVariant({TargetPlatform.macOS});
const _android = TargetPlatformVariant({TargetPlatform.android});

void main() {
  testWidgets('macOS unknown result uses the restrained glass recovery panel', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AggregateTheme.light,
        home: GlassMotionScope(
          clock: ManualGlassMotionClock(),
          child: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 684,
                child: const ResultPanel(
                  state: RunState.outcomeUnknown,
                  blocks: [],
                  failure: RuntimeFailure(
                    RuntimeErrorCode.outcomeUnknown,
                    '仅内存预览结果待确认',
                  ),
                  compactMacOS: true,
                  onCheckActivity: _checkActivity,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(GlassPanelSurface), findsOneWidget);
    expect(find.text('需要处理'), findsOneWidget);
    expect(find.text('查看错误详情'), findsOneWidget);

    final recovery = tester.getRect(find.byType(GlassPanelSurface));
    expect(recovery.width, 684);
    expect(recovery.height, closeTo(162, 2));

    final action = tester.widget<AggregateActionButton>(
      find.byType(AggregateActionButton),
    );
    expect(action.style, AggregateActionStyle.primary);
    expect(action.size, GlassButtonSize.compactAction);
    expect(action.expand, isTrue);
    expect(tester.getRect(find.byType(AggregateActionButton)).width, 150);
    final outline = tester.widget<DecoratedBox>(
      find.byKey(const Key('result-recovery-danger-outline')),
    );
    expect(
      (outline.decoration as BoxDecoration).border!.top.color,
      GlassDesignTokens.light.danger.withValues(alpha: .62),
    );
    final errorContainer = AggregateTheme.light.colorScheme.errorContainer;
    expect(
      tester
          .widgetList<Material>(find.byType(Material))
          .any((material) => material.color == errorContainer),
      isFalse,
    );
    expect(tester.takeException(), isNull);
  }, variant: _macOS);

  testWidgets('Android keeps the native recovery surface', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AggregateTheme.light,
        home: Scaffold(
          body: ResultPanel(
            state: RunState.outcomeUnknown,
            blocks: const [],
            failure: const RuntimeFailure(
              RuntimeErrorCode.outcomeUnknown,
              '远端结果待确认',
            ),
            onCheckActivity: _checkActivity,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(GlassPanelSurface), findsNothing);
    expect(find.text('需要处理'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, variant: _android);
}

void _checkActivity() {}
