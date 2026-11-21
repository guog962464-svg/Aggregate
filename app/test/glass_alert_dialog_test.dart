import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aggregate/app/theme.dart';
import 'package:aggregate/widgets/glass/glass_alert_dialog.dart';
import 'package:aggregate/widgets/glass/glass_motion.dart';
import 'package:aggregate/widgets/glass/glass_panel_surface.dart';

const _macOS = TargetPlatformVariant({TargetPlatform.macOS});
const _android = TargetPlatformVariant({TargetPlatform.android});

void main() {
  testWidgets('macOS alerts use the shared glass surface', (tester) async {
    final clock = ManualGlassMotionClock();
    addTearDown(clock.dispose);
    bool? result;

    await tester.pumpWidget(
      MaterialApp(
        theme: AggregateTheme.forPlatform(
          AggregateTheme.light,
          TargetPlatform.macOS,
        ),
        builder: (context, child) => GlassMotionScope(
          clock: clock,
          child: child ?? const SizedBox.shrink(),
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showGlassDialog<bool>(
                  context: context,
                  builder: (dialogContext) => GlassAlertDialog(
                    title: const Text('确认操作'),
                    content: const Text('请确认后继续。'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialogContext, false),
                        child: const Text('取消'),
                      ),
                    ],
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

    expect(find.byType(GlassPanelSurface), findsOneWidget);
    expect(find.text('确认操作'), findsOneWidget);
    final panel = tester.getRect(find.byType(GlassPanelSurface));
    final title = tester.getRect(find.text('确认操作'));
    expect(title.left - panel.left, moreOrLessEquals(30, epsilon: 1));
    expect(
      tester.widget<Dialog>(find.byType(Dialog)).alignment,
      Alignment.center,
    );
    final barrier = tester.widgetList<ModalBarrier>(find.byType(ModalBarrier));
    expect(barrier.any((item) => item.color != null), isTrue);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(result, isFalse);
  }, variant: _macOS);

  testWidgets('non macOS alerts retain the Material implementation', (
    tester,
  ) async {
    final clock = ManualGlassMotionClock();
    addTearDown(clock.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AggregateTheme.forPlatform(
          AggregateTheme.light,
          TargetPlatform.android,
        ),
        builder: (context, child) => GlassMotionScope(
          clock: clock,
          child: child ?? const SizedBox.shrink(),
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showGlassDialog<void>(
                context: context,
                builder: (_) => const GlassAlertDialog(
                  title: Text('Material alert'),
                  content: Text('Shared behavior.'),
                ),
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.byType(GlassPanelSurface), findsNothing);
  }, variant: _android);
}
