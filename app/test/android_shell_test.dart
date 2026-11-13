import 'dart:io';

import 'package:aggregate/app/aggregate_app.dart';
import 'package:aggregate/platform/android/android_runtime_port.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _android = TargetPlatformVariant({TargetPlatform.android});

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

  testWidgets('Android shell uses task navigation on a phone', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(AggregateApp(runtime: runtime));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byTooltip('添加连接'), findsOneWidget);
    await tester.tap(find.text('连接').last);
    await tester.pumpAndSettle();
    expect(find.byTooltip('添加连接'), findsOneWidget);
    expect(find.byType(Drawer), findsNothing);
    expect(tester.takeException(), isNull);
  }, variant: _android);
}
