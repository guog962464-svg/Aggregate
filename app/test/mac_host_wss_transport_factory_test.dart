import 'dart:io';

import 'package:aggregate/platform/macos/host/host_device_signature_verifier.dart';
import 'package:aggregate/platform/macos/host/host_pairing_authority.dart';
import 'package:aggregate/platform/macos/host/host_setup_coordinator.dart';
import 'package:aggregate/platform/macos/host/host_tls_identity.dart';
import 'package:aggregate/platform/macos/host/host_wss_transport.dart';
import 'package:aggregate/platform/macos/host/mac_host_wss_transport_factory.dart';
import 'package:aggregate/platform/macos/mac_runtime.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('production factory loads its configured TLS identity lazily', () async {
    final directory = await Directory.systemTemp.createTemp(
      'aggregate-host-factory-',
    );
    final runtime = await MacRuntime.open(dataDirectory: directory);
    final identityProvider = _FixtureIdentityProvider(
      certificatePem: await File('test/fixtures/host_test_cert.pem')
          .readAsString(),
      privateKeyPem: await File('test/fixtures/host_test_key.pem')
          .readAsString(),
    );
    final setup = HostSetupCoordinator(setup: runtime);
    final transport = createMacHostWssTransport(
      runtime: runtime,
      setupCoordinator: setup,
      bindAddressProvider: const _LoopbackAddressProvider(),
      bonjourPublisher: const NoopHostBonjourPublisher(),
      identityStore: HostTlsIdentityStore(provider: identityProvider),
      pairingStore: InMemoryHostPairingStore(),
      signatureVerifier: const _UnusedSignatureVerifier(),
    );

    try {
      expect(identityProvider.loadCalls, 0);
      await transport.start();
      expect(identityProvider.loadCalls, 1);
      final invitation = await (transport as HostPairingControlPort)
          .createInvitation();
      expect(invitation.endpoints, hasLength(1));
      expect(Directory('${directory.path}/host').existsSync(), isTrue);
      await transport.stop();
    } finally {
      await runtime.dispose();
      await directory.delete(recursive: true);
    }
  });
}

final class _FixtureIdentityProvider implements HostTlsIdentityProvider {
  _FixtureIdentityProvider({
    required this.certificatePem,
    required this.privateKeyPem,
  });

  final String certificatePem;
  final String privateKeyPem;
  var loadCalls = 0;

  @override
  Future<HostTlsIdentityMaterial> loadOrCreate() async {
    loadCalls++;
    return HostTlsIdentityMaterial(
      hostId: 'host-0123456789abcdef0123456789abcdef',
      certificatePem: certificatePem,
      privateKeyPem: privateKeyPem,
    );
  }

  @override
  Future<HostTlsIdentityMaterial> rotate() => loadOrCreate();
}

final class _UnusedSignatureVerifier implements HostDeviceSignatureVerifier {
  const _UnusedSignatureVerifier();

  @override
  Future<bool> verify({
    required List<int> publicKeySpki,
    required List<int> message,
    required List<int> signatureDer,
  }) async => false;
}

final class _LoopbackAddressProvider implements HostWssBindAddressProvider {
  const _LoopbackAddressProvider();

  @override
  Future<List<HostWssBindTarget>> addresses() async => [
    HostWssBindTarget(address: InternetAddress.loopbackIPv4, interfaceIndex: 1),
  ];
}
