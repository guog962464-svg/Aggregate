import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aggregate/app/theme.dart';
import 'package:aggregate/widgets/glass/aggregate_buttons.dart';
import 'package:aggregate/widgets/glass/glass_glyph.dart';
import 'package:aggregate/widgets/page_state.dart';

void main() {
  testWidgets('wide page state aligns icon, message, and retry action', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 420));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var retries = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: AggregateTheme.light,
        home: Scaffold(
          body: SizedBox.expand(
            child: PageState.error('连接失败', onRetry: () => retries++),
          ),
        ),
      ),
    );

    final icon = tester.getRect(_pageStateIcon(tester));
    final message = tester.getRect(find.text('连接失败'));
    expect(icon.center.dy, closeTo(message.center.dy, 8));
    expect(icon.right, lessThan(message.left));

    await tester.tap(find.text('重试'));
    expect(retries, 1);
  });

  testWidgets('narrow page state stacks icon over message and action', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var retries = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: AggregateTheme.light,
        home: Scaffold(
          body: SizedBox.expand(
            child: PageState.error('连接失败', onRetry: () => retries++),
          ),
        ),
      ),
    );

    final icon = tester.getRect(_pageStateIcon(tester));
    final message = tester.getRect(find.text('连接失败'));
    expect(icon.bottom, lessThan(message.top));

    await tester.tap(find.text('重试'));
    expect(retries, 1);
  });

  testWidgets('wide empty page state retains its contextual action', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 420));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var additions = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: AggregateTheme.light,
        home: Scaffold(
          body: SizedBox.expand(
            child: PageState.empty(
              '添加一个连接后即可运行功能。',
              actions: [
                AggregateActionButton(
                  label: '添加连接',
                  icon: Icons.add_rounded,
                  style: AggregateActionStyle.primary,
                  onPressed: () => additions++,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text('添加连接'), findsOneWidget);
    await tester.tap(find.text('添加连接'));
    expect(additions, 1);
  });

  testWidgets('non-macOS page state keeps its Material icon fallback', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AggregateTheme.light,
        home: const Scaffold(body: PageState.empty('没有记录')),
      ),
    );

    expect(find.byIcon(Icons.inbox_outlined), findsOneWidget);
    expect(find.byType(GlassGlyphMark), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}

Finder _pageStateIcon(WidgetTester tester) =>
    find.byType(GlassGlyphMark).evaluate().isNotEmpty
    ? find.byType(GlassGlyphMark)
    : find.byIcon(Icons.error_outline);
