import 'dart:convert';
import 'dart:io';

import 'package:aggregate/platform/macos/host/host_tls_identity.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Mac Keychain identity serves pinned WSS', (tester) async {
    final identities = HostTlsIdentityStore();
    final first = await identities.loadOrCreate();
    final loaded = await identities.loadOrCreate();
    expect(loaded.hostId, first.hostId);
    expect(loaded.certificateSha256, first.certificateSha256);

    final server = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      0,
      first.createServerContext(),
    );
    final accepted = <WebSocket>[];
    final serverSubscription = server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      accepted.add(socket);
      socket.listen(socket.add);
    });
    final client = HttpClient()
      ..badCertificateCallback = (certificate, _, _) =>
          sha256.convert(certificate.der).toString() == first.certificateSha256;

    try {
      final socket = await WebSocket.connect(
        'wss://127.0.0.1:${server.port}/host',
        customClient: client,
      );
      final response = socket.first;
      socket.add(jsonEncode({'method': 'host.status', 'id': 'mac-test'}));
      expect(
        await response,
        jsonEncode({'method': 'host.status', 'id': 'mac-test'}),
      );
      await socket.close();
    } finally {
      client.close(force: true);
      for (final socket in accepted) {
        await socket.close();
      }
      await serverSubscription.cancel();
      await server.close(force: true);
    }

    final rotated = await identities.rotate();
    expect(rotated.hostId, isNot(first.hostId));
    expect(rotated.certificateSha256, isNot(first.certificateSha256));
    final loadedRotation = await identities.loadOrCreate();
    expect(loadedRotation.hostId, rotated.hostId);
    expect(loadedRotation.certificateSha256, rotated.certificateSha256);
  });
}
