import 'dart:convert';
import 'dart:io';

import 'package:aggregate/platform/macos/host/host_device_signature_verifier.dart';
import 'package:aggregate/platform/macos/host/host_pairing_authority.dart';
import 'package:aggregate/platform/macos/host/host_tls_identity.dart';
import 'package:aggregate/platform/host/host_pairing_protocol.dart';
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

    const devicePublicKey =
        'MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEFzccygtE2fioNux4FgJ07FEIj5YlwLPF+2Dly7FntiLHhNLSRjORgAXdfE1J21cxZb+Ebce8Ub+e6oG8k5BNXQ==';
    final publicKeySpki = base64Decode(devicePublicKey);
    final deviceId = HostPairingProtocol.deviceIdForPublicKey(publicKeySpki);
    const pairingStore = MacKeychainHostPairingStore();
    final priorRecords = await pairingStore.readAll();
    HostDeviceGrant? prior;
    for (final record in priorRecords) {
      if (record.deviceId == deviceId) prior = record;
    }
    final testGrant = HostDeviceGrant(
      deviceId: deviceId,
      publicKeySpki: publicKeySpki,
      displayName: 'Fixture Android device',
      platform: 'android',
      approvedAt: DateTime.now().toUtc(),
      scopes: const {HostGrantScope.readConnections},
    );
    try {
      await pairingStore.save(testGrant);
      final persisted = (await pairingStore.readAll()).singleWhere(
        (record) => record.deviceId == deviceId,
      );
      expect(persisted.toJson(), testGrant.toJson());
    } finally {
      if (prior == null) {
        await pairingStore.remove(deviceId);
      } else {
        await pairingStore.save(prior);
      }
    }
  });
}
