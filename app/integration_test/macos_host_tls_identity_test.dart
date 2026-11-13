import 'dart:convert';
import 'dart:io';

import 'package:aggregate/platform/macos/host/host_device_signature_verifier.dart';
import 'package:aggregate/platform/macos/host/host_tls_identity.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('verifies pairing signature format and Mac pinned WSS', (
    tester,
  ) async {
    const verifier = MacHostDeviceSignatureVerifier();
    final publicKey = base64Decode(
      'MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEFzccygtE2fioNux4FgJ07FEIj5YlwLPF+2Dly7FntiLHhNLSRjORgAXdfE1J21cxZb+Ebce8Ub+e6oG8k5BNXQ==',
    );
    const message =
        'aggregate-host-pair-v1\nhost-0123456789abcdef0123456789abcdef\n'
        'device-0123456789abcdef0123456789abcdef\nfixture-nonce-0123456789\n1794528000';
    final bytes = utf8.encode(message);
    final signature = base64Decode(
      'MEUCIBixemHJb7uaVOM14+3OApXAzIlZsOe/AYBDv25IFYAiAiEAlv2oTaK0hXYsqIGIVAG63BhU+pnrzFim/RkwJ8Rznw0=',
    );

    expect(
      await verifier.verify(
        publicKeySpki: publicKey,
        message: bytes,
        signatureDer: signature,
      ),
      isTrue,
    );
    expect(
      await verifier.verify(
        publicKeySpki: publicKey,
        message: [...bytes, 0x21],
        signatureDer: signature,
      ),
      isFalse,
    );
    expect(
      await verifier.verify(
        publicKeySpki: publicKey,
        message: bytes,
        signatureDer: signature.map((byte) => byte ^ 0x01).toList(),
      ),
      isFalse,
    );

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
