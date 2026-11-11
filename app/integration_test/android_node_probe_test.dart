import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const enabled = bool.fromEnvironment('A3_PROBE_ENABLED');
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
          'version': 'v18.20.4',
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
}
