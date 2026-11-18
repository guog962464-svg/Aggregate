import 'dart:io';

import 'package:aggregate/platform/android/android_application_directory.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('aggregate/application_directory');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'reads the Android app support directory from the native channel',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'aggregate-android-support-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'applicationSupportDirectory');
            return directory.path;
          });

      expect((await androidApplicationSupportDirectory()).path, directory.path);
    },
  );

  test('rejects an empty Android app support directory response', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => '');

    await expectLater(
      androidApplicationSupportDirectory(),
      throwsA(isA<StateError>()),
    );
  });
}
