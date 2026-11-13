import 'dart:convert';
import 'dart:typed_data';

import 'package:aggregate/platform/android/android_host_device_identity.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Android Host identity stays in Keystore and signs data', (
    tester,
  ) async {
    const identityStore = AndroidHostDeviceIdentity();
    final first = await identityStore.loadOrCreate();
    final second = await identityStore.loadOrCreate();

    expect(first.deviceId, second.deviceId);
    expect(first.publicKeySpki, second.publicKeySpki);
    expect(first.deviceId, matches(RegExp(r'^device-[a-f0-9]{32}$')));

    final message = Uint8List.fromList(
      utf8.encode('aggregate-host-pairing-v1'),
    );
    final signature = await identityStore.sign(message);
    expect(signature.length, inInclusiveRange(64, 80));

    await identityStore.delete();
    final rotated = await identityStore.loadOrCreate();
    expect(rotated.deviceId, isNot(first.deviceId));
    expect(rotated.publicKeySpki, isNot(first.publicKeySpki));
    await identityStore.delete();
  });
}
