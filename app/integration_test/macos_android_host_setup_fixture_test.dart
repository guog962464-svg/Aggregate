import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:aggregate/platform/macos/mac_runtime.dart';
import 'package:aggregate/platform/macos/host/host_device_signature_verifier.dart';
import 'package:aggregate/platform/macos/host/host_operation_ledger.dart';
import 'package:aggregate/platform/macos/host/host_pairing_authority.dart';
import 'package:aggregate/platform/macos/host/host_runtime_rpc_dispatcher.dart';
import 'package:aggregate/platform/macos/host/host_setup_coordinator.dart';
import 'package:aggregate/platform/macos/host/host_setup_rpc_dispatcher.dart';
import 'package:aggregate/platform/macos/host/host_tls_identity.dart';
import 'package:aggregate/platform/macos/host/host_wss_transport.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'serves an isolated WSS setup fixture for a real Android Keystore client',
    (_) async {
      const fixtureDirectoryPath = String.fromEnvironment(
        'aggregateHostSetupFixtureDirectory',
      );
      expect(fixtureDirectoryPath, isNotEmpty);
      final fixtureDirectory = Directory(fixtureDirectoryPath);
      await fixtureDirectory.create(recursive: true);

      final provider = _FixtureIdentityProvider(
        certificatePem: await File('test/fixtures/host_test_cert.pem')
            .readAsString(),
        privateKeyPem: await File('test/fixtures/host_test_key.pem')
            .readAsString(),
      );
      final identity = await HostTlsIdentityStore(provider: provider)
          .loadOrCreate();
      final fixtureHome = Platform.environment['HOME']!;
      expect(fixtureHome.startsWith(fixtureDirectory.path), isTrue);
      final executable = File('$fixtureHome/.local/bin/ncm-cli');
      expect(await executable.exists(), isTrue);
      final runtimeDirectory = Directory('${fixtureDirectory.path}/runtime');
      final runtime = await MacRuntime.open(dataDirectory: runtimeDirectory);
      final androidResultFile = File(
        '${fixtureDirectory.path}/android-result.txt',
      );
      final coordinator = HostSetupCoordinator(
        setup: runtime,
        random: Random(41),
      );
      final pairing = HostPairingAuthority(
        identity: identity,
        store: InMemoryHostPairingStore(),
        signatureVerifier: const MacHostDeviceSignatureVerifier(),
        setupCoordinator: coordinator,
        random: Random(43),
      );
      final ledger = await FileHostOperationLedger.open(
        File('${fixtureDirectory.path}/operations.json'),
      );
      final setupDispatcher = HostSetupRpcDispatcher(
        setup: coordinator,
        ledger: ledger,
        authorization: pairing,
      );
      final dispatcher = HostRuntimeRpcDispatcher(
        runtime: runtime,
        accounts: runtime,
        setupDispatcher: setupDispatcher,
        ledger: ledger,
        authorization: pairing,
      );
      final transport = HostWssTransport(
        loadServices: () async => HostWssServices(
          identity: identity,
          pairing: pairing,
          dispatcher: dispatcher,
        ),
        bindAddressProvider: const _LoopbackAddressProvider(),
        bonjourPublisher: const NoopHostBonjourPublisher(),
        requestedPort: 0,
      );

      var approving = false;
      Object? approvalError;
      final approvalTimer = Timer.periodic(const Duration(milliseconds: 100), (
        _,
      ) async {
        if (approving) return;
        approving = true;
        try {
          final requests = await transport.pendingRequests();
          for (final request in requests) {
            await transport.approvePending(
              request.deviceId,
              scopes: const {
                HostGrantScope.connectionSetup,
                HostGrantScope.readConnections,
              },
            );
          }
        } on Object catch (error) {
          approvalError = error;
        } finally {
          approving = false;
        }
      });

      try {
        await transport.start();
        final invitation = await transport.createInvitation();
        await File('${fixtureDirectory.path}/invitation.json')
            .writeAsString(invitation.qrPayload, flush: true);
        final androidResult = await _waitForAndroidResult(androidResultFile);
        expect(androidResult, 'passed', reason: 'Android setup flow failed');
        expect(approvalError, isNull);
        final savedConnections = File(
          '${runtimeDirectory.path}/connections.json',
        );
        final savedJson = await savedConnections.readAsString();
        final fixtureSecret = (await File(
          '${fixtureDirectory.path}/setup-private-key.pem',
        ).readAsString()).trim();
        expect(savedJson, isNot(contains(fixtureSecret)));
        final root = jsonDecode(savedJson) as Map<String, Object?>;
        final connections = root['connections']! as List;
        expect(connections, hasLength(1));
        final savedSpec =
            (connections.single as Map<String, Object?>)['spec']!
                as Map<String, Object?>;
        expect(savedSpec['label'], 'Android isolated physical fixture');
        expect(savedSpec['executable'], executable.path);
        final profileId = savedSpec['profileId']! as String;
        final profile = Directory(
          '${runtimeDirectory.path}/connector-profiles/$profileId',
        );
        final storedKey = File('${profile.path}/private-key.pem');
        expect(
          await File('${profile.path}/app-id.txt').readAsString(),
          'fixture-app',
        );
        expect((await storedKey.readAsString()).trim(), fixtureSecret);
        expect((await storedKey.stat()).mode & 0x180, 0x180);
        expect(
          await File('${profile.path}/.setup-private-key.pem').exists(),
          isFalse,
        );
        expect((await profile.stat()).mode & 0x3f, 0);
        expect((await storedKey.stat()).mode & 0x3f, 0);
      } finally {
        approvalTimer.cancel();
        await transport.stop();
        await runtime.dispose();
      }
    },
    timeout: const Timeout(Duration(minutes: 15)),
  );
}

Future<String> _waitForAndroidResult(File resultFile) async {
  final deadline = DateTime.now().add(const Duration(minutes: 12));
  while (DateTime.now().isBefore(deadline)) {
    if (await resultFile.exists()) return resultFile.readAsString();
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  throw TimeoutException('Android fixture did not report its result');
}

final class _LoopbackAddressProvider implements HostWssBindAddressProvider {
  const _LoopbackAddressProvider();

  @override
  Future<List<HostWssBindTarget>> addresses() async => [
    HostWssBindTarget(address: InternetAddress.loopbackIPv4, interfaceIndex: 1),
  ];
}

final class _FixtureIdentityProvider implements HostTlsIdentityProvider {
  const _FixtureIdentityProvider({
    required this.certificatePem,
    required this.privateKeyPem,
  });

  final String certificatePem;
  final String privateKeyPem;

  @override
  Future<HostTlsIdentityMaterial> loadOrCreate() async =>
      HostTlsIdentityMaterial(
        hostId: 'host-0123456789abcdef0123456789abcdef',
        certificatePem: certificatePem,
        privateKeyPem: privateKeyPem,
      );

  @override
  Future<HostTlsIdentityMaterial> rotate() => loadOrCreate();
}
