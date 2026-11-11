import 'package:aggregate/app/aggregate_app.dart';
import 'package:aggregate/platform/android/android_runtime_port.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Android shell navigates the shared compact layout', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(AggregateApp(runtime: AndroidRuntimePort()));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.menu), findsOneWidget);
    expect(find.byTooltip('添加连接'), findsNothing);
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('管理连接'));
    await tester.pumpAndSettle();
    expect(find.text('当前运行端尚无可添加的连接。'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
