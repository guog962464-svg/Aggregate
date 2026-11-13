import 'dart:convert';
import 'dart:io';

import 'package:aggregate/platform/macos/host/host_tls_identity.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late _FixtureIdentityProvider provider;
  late HostTlsIdentityStore identities;

  setUp(() async {
    provider = _FixtureIdentityProvider(
      hostId: 'host-0123456789abcdef0123456789abcdef',
      certificatePem: await File('test/fixtures/host_test_cert.pem')
          .readAsString(),
      privateKeyPem: await File('test/fixtures/host_test_key.pem')
          .readAsString(),
    );
    identities = HostTlsIdentityStore(provider: provider);
  });

  test('validates and retains a stable Keychain identity', () async {
    final first = await identities.loadOrCreate();
    final loaded = await identities.loadOrCreate();

    expect(loaded.hostId, first.hostId);
    expect(loaded.certificateSha256, first.certificateSha256);
    expect(
      first.certificateSha256,
      sha256.convert(_certificateDer(first.certificatePem)).toString(),
    );
    expect(provider.loadCount, 2);
  });

  test('rejects malformed or unsupported identity material', () async {
    provider.material = const HostTlsIdentityMaterial(
      hostId: 'invalid',
      certificatePem: 'not a certificate',
      privateKeyPem: 'not a key',
    );

    await expectLater(
      identities.loadOrCreate(),
      throwsA(isA<HostTlsIdentityException>()),
    );
  });

  test('serves WSS only to a client that pins the Host certificate', () async {
    final identity = await identities.loadOrCreate();
    final server = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      0,
      identity.createServerContext(),
    );
    final accepted = <WebSocket>[];
    final serverSubscription = server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      accepted.add(socket);
      socket.listen(socket.add);
    });
    final client = HttpClient()
      ..badCertificateCallback = (certificate, _, _) =>
          sha256.convert(certificate.der).toString() ==
          identity.certificateSha256;
    final wrongPinClient = HttpClient()
      ..badCertificateCallback = (_, _, _) => false;

    try {
      final socket = await WebSocket.connect(
        'wss://127.0.0.1:${server.port}/host',
        customClient: client,
      );
      final response = socket.first;
      socket.add(jsonEncode({'id': 'r1', 'method': 'host.status'}));
      expect(await response, jsonEncode({'id': 'r1', 'method': 'host.status'}));
      await socket.close();

      await expectLater(
        WebSocket.connect(
          'wss://127.0.0.1:${server.port}/host',
          customClient: wrongPinClient,
        ),
        throwsA(anything),
      );
      expect(accepted, hasLength(1));
    } finally {
      client.close(force: true);
      wrongPinClient.close(force: true);
      for (final socket in accepted) {
        await socket.close();
      }
      await serverSubscription.cancel();
      await server.close(force: true);
    }
  });
}

List<int> _certificateDer(String pem) => base64Decode(
  RegExp(
    r'^-----BEGIN CERTIFICATE-----\s*([A-Za-z0-9+/=\r\n]+)\s*-----END CERTIFICATE-----\s*$',
  ).firstMatch(pem)!.group(1)!.replaceAll(RegExp(r'\s'), ''),
);

final class _FixtureIdentityProvider implements HostTlsIdentityProvider {
  _FixtureIdentityProvider({
    required String hostId,
    required String certificatePem,
    required String privateKeyPem,
  }) : material = HostTlsIdentityMaterial(
         hostId: hostId,
         certificatePem: certificatePem,
         privateKeyPem: privateKeyPem,
       );

  HostTlsIdentityMaterial material;
  var loadCount = 0;

  @override
  Future<HostTlsIdentityMaterial> loadOrCreate() async {
    loadCount++;
    return material;
  }

  @override
  Future<HostTlsIdentityMaterial> rotate() async => material;
}
