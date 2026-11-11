import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const enabled = bool.fromEnvironment('A3_PROBE_ENABLED');
  const backgroundTest = bool.fromEnvironment('A3_BACKGROUND_TEST');
  const longBackgroundTest = bool.fromEnvironment('A3_LONG_BACKGROUND_TEST');
  const repeatTest = bool.fromEnvironment('A3_REPEAT_TEST');
  const activeBackgroundTest = bool.fromEnvironment('A3_ACTIVE_BACKGROUND_TEST');
  const channel = MethodChannel('aggregate/node_probe');

  testWidgets('Flutter receives isolated Node results across process generations', (
    tester,
  ) async {
    final events = <Map<Object?, Object?>>[];
    channel.setMethodCallHandler((call) async {
      if (call.method == 'event') {
        events.add(Map<Object?, Object?>.from(call.arguments as Map));
      }
    });
    addTearDown(() => channel.setMethodCallHandler(null));

    await tester.runAsync(() async {
      Future<Map<Object?, Object?>> run() async {
        final result = await channel.invokeMethod<Map<Object?, Object?>>('run');
        expect(result, isNotNull);
        expect(result!['kind'], 3);
        expect(result['exitCode'], 0);
        expect(jsonDecode(result['detail'] as String), {
          'version': 'v24.22.1',
          'file': 'ok',
          'network': 'network-ok',
        });
        return result;
      }

      final first = await run();
      final second = await run();
      expect(second['requestId'], greaterThan(first['requestId'] as int));
      expect(second['generation'], isNot(first['generation']));
      expect(
        events.where((event) => event['kind'] == 2).length,
        greaterThanOrEqualTo(2),
      );
      final types = events
          .where((event) => event['kind'] == 7)
          .map((event) => jsonDecode(event['detail'] as String)['type']);
      expect(types, containsAll(['ready', 'console', 'network', 'fileWrite', 'fileRead']));
    });
  }, skip: !enabled);

  testWidgets('capability query allows only the fixed entry and rejects stale references', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final capabilityEvent = await channel.invokeMethod<Map<Object?, Object?>>(
        'capabilities',
      );
      expect(capabilityEvent?['kind'], 10);
      expect(jsonDecode(capabilityEvent?['detail'] as String), {
        'packaged': true,
        'protocol': 1,
        'entrypoints': ['a3-fixed'],
        'headerVersion': 'v24.22.1',
        'npm': false,
        'cli': false,
        'profiles': false,
      });

      Future<void> rejected(Map<String, Object?> arguments, String code) async {
        await expectLater(
          channel.invokeMethod<Map<Object?, Object?>>('run', arguments),
          throwsA(
            isA<PlatformException>().having(
              (error) => error.code,
              'code',
              code,
            ),
          ),
        );
      }

      await rejected({'entrypoint': 'arbitrary-cli'}, 'invalidEntrypoint');
      await rejected({'profileRef': 'old-profile'}, 'invalidReference');
      await rejected({'draftId': 'old-draft'}, 'invalidReference');
      final previous = await channel.invokeMethod<Map<Object?, Object?>>('run');
      await rejected({
        'expectedGeneration': previous?['generation'] as String,
      }, 'staleGeneration');
      expect((await channel.invokeMethod<Map<Object?, Object?>>('run'))?['kind'], 3);
    });
  }, skip: !enabled);

  testWidgets('Node exception is reported as an event and a failure', (
    tester,
  ) async {
    final types = <String>[];
    channel.setMethodCallHandler((call) async {
      if (call.method != 'event') return;
      final event = Map<Object?, Object?>.from(call.arguments as Map);
      if (event['kind'] == 7) {
        types.add(jsonDecode(event['detail'] as String)['type'] as String);
      }
    });
    addTearDown(() => channel.setMethodCallHandler(null));
    await tester.runAsync(() async {
      await expectLater(
        channel.invokeMethod<Map<Object?, Object?>>('run', {'fail': true}),
        throwsA(
          isA<PlatformException>().having(
            (error) => error.code,
            'code',
            'nodeFailure',
          ),
        ),
      );
      expect(types, containsAll(['ready', 'exception']));
    });
  }, skip: !enabled);

  testWidgets('cancel emits an event and reports unknown outcome', (
    tester,
  ) async {
    final ready = Completer<void>();
    final types = <String>[];
    channel.setMethodCallHandler((call) async {
      if (call.method != 'event') return;
      final event = Map<Object?, Object?>.from(call.arguments as Map);
      if (event['kind'] != 7) return;
      final type = jsonDecode(event['detail'] as String)['type'] as String;
      types.add(type);
      if (type == 'ready' && !ready.isCompleted) ready.complete();
    });
    addTearDown(() => channel.setMethodCallHandler(null));
    await tester.runAsync(() async {
      final pending = channel.invokeMethod<Map<Object?, Object?>>('run', {
        'delayMs': 5000,
      });
      await ready.future.timeout(const Duration(seconds: 5));
      await channel.invokeMethod<void>('cancel');
      await expectLater(
        pending,
        throwsA(
          isA<PlatformException>().having(
            (error) => error.code,
            'code',
            'outcomeUnknown',
          ),
        ),
      );
      expect(types, contains('cancelRequested'));
      expect((await channel.invokeMethod<Map<Object?, Object?>>('run'))?['kind'], 3);
    });
  }, skip: !enabled);

  testWidgets('Node crash reports unknown outcome and next request uses a new generation', (
    tester,
  ) async {
    final started = Completer<String>();
    channel.setMethodCallHandler((call) async {
      if (call.method != 'event') return;
      final event = Map<Object?, Object?>.from(call.arguments as Map);
      if (event['kind'] == 2 && !started.isCompleted) {
        started.complete(event['generation'] as String);
      }
    });
    addTearDown(() => channel.setMethodCallHandler(null));

    await tester.runAsync(() async {
      final pending = channel.invokeMethod<Map<Object?, Object?>>('run', {
        'delayMs': 5000,
      });
      final firstGeneration = await started.future.timeout(
        const Duration(seconds: 5),
      );
      await channel.invokeMethod<void>('crash');
      await expectLater(
        pending,
        throwsA(
          isA<PlatformException>().having(
            (error) => error.code,
            'code',
            'outcomeUnknown',
          ),
        ),
      );
      final recovered = await channel.invokeMethod<Map<Object?, Object?>>(
        'run',
      );
      expect(recovered?['kind'], 3);
      expect(recovered?['generation'], isNot(firstGeneration));
    });
  }, skip: !enabled);

  testWidgets('default Android APK keeps the Node probe unavailable', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final capabilities = await channel.invokeMethod<Map<Object?, Object?>>(
        'capabilities',
      );
      expect(capabilities?['packaged'], isFalse);
      await expectLater(
        channel.invokeMethod<Map<Object?, Object?>>('run'),
        throwsA(
          isA<PlatformException>().having(
            (error) => error.code,
            'code',
            'unavailable',
          ),
        ),
      );
    });
  }, skip: enabled);

  testWidgets('Node request survives a temporary app background', (
    tester,
  ) async {
    final ready = Completer<void>();
    channel.setMethodCallHandler((call) async {
      if (call.method != 'event') return;
      final event = Map<Object?, Object?>.from(call.arguments as Map);
      if (event['kind'] != 7) return;
      if (jsonDecode(event['detail'] as String)['type'] == 'ready' &&
          !ready.isCompleted) {
        ready.complete();
      }
    });
    addTearDown(() => channel.setMethodCallHandler(null));
    await tester.runAsync(() async {
      final pending = channel.invokeMethod<Map<Object?, Object?>>('run', {
        'delayMs': 5000,
      });
      await ready.future.timeout(const Duration(seconds: 5));
      // The host test runner sends HOME and then returns this Activity.
      // ignore: avoid_print
      print('A3_BACKGROUND_READY');
      final result = await pending.timeout(const Duration(seconds: 12));
      expect(result?['kind'], 3);
    });
  }, skip: !enabled || !backgroundTest);

  testWidgets('idle background returns to a fresh Node generation', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final first = await channel.invokeMethod<Map<Object?, Object?>>('run');
      expect(first?['kind'], 3);
      // The host runner sends HOME, waits one minute, and resumes this Activity.
      // ignore: avoid_print
      print('A3_LONG_BACKGROUND_READY');
      await Future<void>.delayed(const Duration(seconds: 70));
      final second = await channel.invokeMethod<Map<Object?, Object?>>('run');
      expect(second?['kind'], 3);
      expect(second?['generation'], isNot(first?['generation']));
    });
  }, skip: !enabled || !longBackgroundTest);

  testWidgets('repeated calls use fresh Node generations', (tester) async {
    await tester.runAsync(() async {
      final generations = <String>{};
      for (var index = 0; index < 20; index++) {
        final result = await channel.invokeMethod<Map<Object?, Object?>>('run');
        expect(result?['kind'], 3);
        expect(generations.add(result?['generation'] as String), isTrue);
      }
    });
  }, skip: !enabled || !repeatTest);

  testWidgets('active Node request survives a minute in the background', (
    tester,
  ) async {
    final ready = Completer<void>();
    channel.setMethodCallHandler((call) async {
      if (call.method != 'event') return;
      final event = Map<Object?, Object?>.from(call.arguments as Map);
      if (event['kind'] == 7 &&
          jsonDecode(event['detail'] as String)['type'] == 'ready' &&
          !ready.isCompleted) {
        ready.complete();
      }
    });
    addTearDown(() => channel.setMethodCallHandler(null));
    await tester.runAsync(() async {
      final pending = channel.invokeMethod<Map<Object?, Object?>>('run', {
        'delayMs': 70000,
      });
      await ready.future.timeout(const Duration(seconds: 10));
      // The host sends HOME, waits 60 seconds, then resumes the Activity.
      // ignore: avoid_print
      print('A3_ACTIVE_BACKGROUND_READY');
      final result = await pending.timeout(const Duration(seconds: 100));
      expect(result?['kind'], 3);
      expect(jsonDecode(result?['detail'] as String)['version'], 'v24.22.1');
    });
  }, skip: !enabled || !activeBackgroundTest);
}
