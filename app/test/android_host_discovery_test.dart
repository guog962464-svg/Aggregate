import 'package:aggregate/platform/android/android_host_discovery.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'resolves only private IPv4 WSS endpoints for a stable Host ID',
    () async {
      const channel = MethodChannel('aggregate/test_host_discovery');
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return ['wss://192.168.1.20:47321/host'];
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final discovery = MethodChannelAndroidHostDiscovery(
        channel: channel,
        timeout: const Duration(seconds: 1),
      );

      final endpoints = await discovery.discover(
        'host-0123456789abcdef0123456789abcdef',
      );

      expect(endpoints.map((endpoint) => endpoint.uri.toString()), [
        'wss://192.168.1.20:47321/host',
      ]);
      expect(calls, hasLength(1));
      expect(calls.single.method, 'discover');
      expect(calls.single.arguments, {
        'hostId': 'host-0123456789abcdef0123456789abcdef',
      });
    },
  );

  test('rejects an unsafe native discovery result as a whole', () async {
    const channel = MethodChannel('aggregate/test_unsafe_host_discovery');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (call) async => [
            'wss://192.168.1.20:47321/host',
            'wss://203.0.113.4:47321/host',
          ],
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    expect(
      await MethodChannelAndroidHostDiscovery(channel: channel)
          .discover('host-0123456789abcdef0123456789abcdef'),
      isEmpty,
    );
  });

  test('does not query native discovery for an invalid Host ID', () async {
    const channel = MethodChannel('aggregate/test_invalid_host_discovery');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return const <String>[];
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    expect(
      await MethodChannelAndroidHostDiscovery(channel: channel)
          .discover('not-a-host'),
      isEmpty,
    );
    expect(calls, isEmpty);
  });
}
