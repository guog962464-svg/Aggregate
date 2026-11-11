import 'dart:io';

import 'package:aggregate/app/aggregate_app.dart';
import 'package:aggregate/platform/android/android_runtime_port.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late AndroidRuntimePort runtime;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('aggregate-shell-test-');
    runtime = await AndroidRuntimePort.open(dataDirectory: directory);
  });
  tearDownAll(() async {
    await runtime.dispose();
    await directory.delete(recursive: true);
  });

  testWidgets('Android shell navigates the shared compact layout', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(AggregateApp(runtime: runtime));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.menu), findsOneWidget);
    expect(find.byTooltip('添加连接'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('管理连接'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('添加连接'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
