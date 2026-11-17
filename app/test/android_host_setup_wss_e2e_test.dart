import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:aggregate/platform/android/android_host_device_identity.dart';
import 'package:aggregate/platform/android/android_host_discovery.dart';
import 'package:aggregate/platform/android/android_host_manager.dart';
import 'package:aggregate/platform/android/android_host_pairing_client.dart';
import 'package:aggregate/platform/android/android_runtime_port.dart';
import 'package:aggregate/platform/android/android_runtime_store.dart';
import 'package:aggregate/platform/host/host_pairing_protocol.dart';
import 'package:aggregate/platform/macos/host/host_device_signature_verifier.dart';
import 'package:aggregate/platform/macos/host/host_operation_ledger.dart';
import 'package:aggregate/platform/macos/host/host_pairing_authority.dart';
import 'package:aggregate/platform/macos/host/host_setup_coordinator.dart';
import 'package:aggregate/platform/macos/host/host_setup_rpc_dispatcher.dart';
import 'package:aggregate/platform/macos/host/host_tls_identity.dart';
import 'package:aggregate/platform/macos/host/host_wss_transport.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const hostId = 'host-0123456789abcdef0123456789abcdef';
  const publicKeySpkiBase64 =
      'MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEFzccygtE2fioNux4FgJ07FEIj5YlwLPF+2Dly7FntiLHhNLSRjORgAXdfE1J21cxZb+Ebce8Ub+e6oG8k5BNXQ==';

  late Directory directory;
  late HostWssTransport transport;
  late HostWssServices services;
  late _SandboxSetupPort setupPort;
  late AndroidHostPairingClient client;
  late String deviceId;
  AndroidHostManager? manager;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'aggregate-android-host-setup-e2e-',
    );
    manager = null;
    final publicKey = base64Decode(publicKeySpkiBase64);
    deviceId = HostPairingProtocol.deviceIdForPublicKey(publicKey);
    final provider = _FixtureIdentityProvider(
      certificatePem: await File('test/fixtures/host_test_cert.pem')
          .readAsString(),
      privateKeyPem: await File('test/fixtures/host_test_key.pem')
          .readAsString(),
    );
    final identity = await HostTlsIdentityStore(provider: provider)
        .loadOrCreate();
    setupPort = _SandboxSetupPort();
    final coordinator = HostSetupCoordinator(
      setup: setupPort,
      random: Random(17),
    );
    final pairing = HostPairingAuthority(
      identity: identity,
      store: InMemoryHostPairingStore(),
      signatureVerifier: const _DigestSignatureVerifier(),
      setupCoordinator: coordinator,
      random: Random(23),
    );
    final ledger = await FileHostOperationLedger.open(
      File('${directory.path}/operations.json'),
    );
    final dispatcher = HostSetupRpcDispatcher(
      setup: coordinator,
      ledger: ledger,
      authorization: pairing,
    );
    services = HostWssServices(
      identity: identity,
      pairing: pairing,
      dispatcher: dispatcher,
    );
    transport = _createTransport(services, 0);
    await transport.start();
    client = AndroidHostPairingClient(
      identity: _FixtureAndroidIdentity(
        AndroidHostPublicIdentity(deviceId: deviceId, publicKeySpki: publicKey),
      ),
      random: Random(31),
    );
  });

  tearDown(() async {
    await transport.stop();
    await manager?.dispose();
    await directory.delete(recursive: true);
  });

  test('pairs over pinned WSS and completes an isolated setup save', () async {
    final issued = await transport.createInvitation();
    final invitation = AndroidHostInvitation.fromQrPayload(issued.qrPayload);
    expect(invitation.hostId, hostId);
    final receipt = await client.requestPairing(
      invitation: invitation,
      displayName: 'Android setup fixture',
    );
    expect(receipt.deviceId, deviceId);
    expect(receipt.confirmationCode, matches(RegExp(r'^\d{6}$')));

    await transport.approvePending(
      deviceId,
      scopes: const {HostGrantScope.connectionSetup},
    );
    final session = await client.authenticate(
      AndroidHostTarget.fromInvitation(invitation),
    );
    try {
      final adapters = await session.call('setup.adapters', const {});
      final adapterRows = adapters['adapters']! as List<Object?>;
      expect(
        adapterRows.cast<Map<String, Object?>>().map((row) => row['id']),
        contains('netease-music'),
      );

      final detected = await session.call('setup.detectExecutable', const {
        'adapterId': 'netease-music',
      });
      final executableRef = detected['executableRef']! as String;
      expect(detected['displayLocation'], 'Mac 主机 · ncm-cli');
      expect(jsonEncode(detected), isNot(contains(_SandboxSetupPort.path)));

      const secret = 'fixture-only-secret-value';
      final tested = await session.call('setup.test', {
        'operationId': 'android-setup-test',
        'draft': {
          'adapterId': 'netease-music',
          'label': 'Isolated music connection',
          'fieldValues': {'appId': 'fixture-app'},
          'executableRef': executableRef,
        },
        'secretValues': {'privateKey': secret},
      });
      expect(tested['canSave'], isTrue);
      expect(tested['draftHandle'], isA<String>());
      expect(jsonEncode(tested), isNot(contains(secret)));
      expect(jsonEncode(tested), isNot(contains(_SandboxSetupPort.path)));
      expect(setupPort.lastDraft?.values['privateKey'], secret);

      final saved = await session.call('setup.save', {
        'operationId': 'android-setup-save',
        'draftHandle': tested['draftHandle'],
      });
      expect(saved['connectionId'], 'fixture-connection');
      expect(saved['label'], 'Isolated music connection');
      expect(jsonEncode(saved), isNot(contains(_SandboxSetupPort.path)));
      expect(setupPort.saveCount, 1);
      expect(setupPort.discardedDrafts, isEmpty);
    } finally {
      await session.close();
    }
  });

  test(
    'reports WSS Host restart as offline and reconnects using saved endpoint',
    () async {
      final androidDirectory = Directory('${directory.path}/android-app')
        ..createSync();
      manager = AndroidHostManager(
        AndroidRuntimeStore(androidDirectory),
        pairingClient: client,
        discovery: const _NoopHostDiscovery(),
      );
      await manager!.load();
      final issued = await transport.createInvitation();
      final invitation = AndroidHostInvitation.fromQrPayload(issued.qrPayload);
      final savedPort = invitation.endpoints.single.uri.port;
      await manager!.requestPairing(
        invitation: invitation,
        displayName: 'Android WSS reconnect fixture',
      );
      await transport.approvePending(
        deviceId,
        scopes: const {HostGrantScope.readConnections},
      );
      await manager!.completePairing(
        invitation: invitation,
        displayName: 'Android WSS reconnect fixture',
      );
      expect(manager!.statusFor(hostId), AndroidHostStatus.online);

      final offlineChange = manager!.statusChanges.firstWhere(
        (change) =>
            change.hostId == hostId &&
            change.status == AndroidHostStatus.offline,
      );
      await transport.stop();
      await offlineChange.timeout(const Duration(seconds: 2));
      expect(manager!.isConnected(hostId), isFalse);
      expect(manager!.statusFor(hostId), AndroidHostStatus.offline);

      transport = _createTransport(services, savedPort);
      await transport.start();
      await manager!.connect(hostId);
      expect(manager!.statusFor(hostId), AndroidHostStatus.online);
      expect(manager!.isConnected(hostId), isTrue);
      expect(manager!.hosts.single.endpoints.single.uri.port, savedPort);
    },
  );

  test(
    'Android RuntimePort routes setup drafts through the paired Host',
    () async {
      final issued = await transport.createInvitation();
      final invitation = AndroidHostInvitation.fromQrPayload(issued.qrPayload);
      final androidDirectory = Directory('${directory.path}/android-app')
        ..createSync();
      final manager = AndroidHostManager(
        AndroidRuntimeStore(androidDirectory),
        pairingClient: client,
        discovery: const _NoopHostDiscovery(),
      );
      final runtime = await AndroidRuntimePort.open(
        dataDirectory: androidDirectory,
        hostManager: manager,
      );
      try {
        await manager.requestPairing(
          invitation: invitation,
          displayName: 'Android RuntimePort fixture',
        );
        await transport.approvePending(
          deviceId,
          scopes: const {HostGrantScope.connectionSetup},
        );
        await manager.completePairing(
          invitation: invitation,
          displayName: 'Android RuntimePort fixture',
        );

        final target = ExecutionTarget.host(hostId);
        final targets = await runtime.listSetupTargets();
        expect(targets.last.target, target);
        expect(targets.last.selectable, isTrue);
        final setup = await runtime.setupForTarget(target);
        expect(setup.connectionAdapters.map((adapter) => adapter.id), [
          'netease-music',
        ]);
        final executable =
            await (setup as ConnectionSetupExecutableSelectionPort)
                .detectExecutableSelection('netease-music');
        expect(executable?.displayLocation, 'Mac 主机 · ncm-cli');
        expect(executable?.path, isNull);

        const secret = 'runtime-port-fixture-secret';
        final report = await setup.testConnectionSetup(
          ConnectionSetupDraft(
            adapterId: 'netease-music',
            executableReference: executable!.reference,
            values: const {'appId': 'fixture-app', 'privateKey': secret},
            spec: ConnectionSpec(
              kind: ConnectionKind.cli,
              label: 'RuntimePort fixture connection',
              executionTarget: target,
            ),
          ),
        );
        expect(report.canSave, isTrue);
        expect(report.checks.map((check) => check.label), ['程序检查', '账号登录']);
        expect(setupPort.lastDraft?.values['privateKey'], secret);
        expect(
          jsonEncode({
            'canSave': report.canSave,
            'draftId': report.draftId,
            'checks': [
              for (final check in report.checks)
                {'label': check.label, 'detail': check.detail},
            ],
          }),
          isNot(contains(secret)),
        );

        final saved = await setup.saveConnectionSetup(report.draftId);
        expect(saved.id.value, 'remote:$hostId:fixture-connection');
        expect(saved.executionTarget, target);
        expect(saved.location, 'Mac Host');
        expect(setupPort.saveCount, 1);
      } finally {
        await runtime.dispose();
      }
    },
  );
}

HostWssTransport _createTransport(
  HostWssServices services,
  int requestedPort,
) => HostWssTransport(
  loadServices: () async => services,
  bindAddressProvider: const _LoopbackAddressProvider(),
  bonjourPublisher: const NoopHostBonjourPublisher(),
  requestedPort: requestedPort,
);

final class _FixtureAndroidIdentity implements AndroidHostIdentityPort {
  const _FixtureAndroidIdentity(this.identity);

  final AndroidHostPublicIdentity identity;

  @override
  Future<AndroidHostPublicIdentity> loadOrCreate() async => identity;

  @override
  Future<AndroidHostPublicIdentity> rotate() async => identity;

  @override
  Future<Uint8List> sign(Uint8List message) async =>
      Uint8List.fromList(sha256.convert(message).bytes);
}

final class _SandboxSetupPort implements ConnectionSetupPort {
  static const path = '/isolated-host/bin/ncm-cli';

  ConnectionSetupDraft? lastDraft;
  var saveCount = 0;
  final discardedDrafts = <String>[];

  @override
  List<ConnectionAdapter> get connectionAdapters => const [
    ConnectionAdapter(
      id: 'netease-music',
      label: '网易云音乐',
      kind: ConnectionKind.cli,
      fields: [
        SetupField(key: 'appId', label: 'App ID'),
        SetupField(
          key: 'privateKey',
          label: 'Private Key',
          kind: SetupFieldKind.secret,
        ),
      ],
      autoDetectExecutable: true,
      showGenericCliFields: false,
    ),
  ];

  @override
  Future<String?> detectExecutable(String adapterId) async =>
      adapterId == 'netease-music' ? path : null;

  @override
  Future<ConnectionSetupReport> testConnectionSetup(
    ConnectionSetupDraft draft,
  ) async {
    lastDraft = draft;
    return const ConnectionSetupReport(
      draftId: 'isolated-runtime-draft',
      checks: [
        SetupCheck('程序检查', SetupCheckStatus.passed, path),
        SetupCheck(
          '账号登录',
          SetupCheckStatus.actionRequired,
          'Sign-in is a separate step.',
        ),
      ],
      canSave: true,
    );
  }

  @override
  Future<Connection> saveConnectionSetup(String draftId) async {
    saveCount++;
    return const Connection(
      id: ConnectionId('fixture-connection'),
      kind: ConnectionKind.cli,
      label: 'Isolated music connection',
      location: path,
    );
  }

  @override
  Future<void> discardConnectionSetup(String draftId) async {
    discardedDrafts.add(draftId);
  }
}

final class _LoopbackAddressProvider implements HostWssBindAddressProvider {
  const _LoopbackAddressProvider();

  @override
  Future<List<HostWssBindTarget>> addresses() async => [
    HostWssBindTarget(address: InternetAddress.loopbackIPv4, interfaceIndex: 1),
  ];
}

final class _NoopHostDiscovery implements AndroidHostDiscoveryPort {
  const _NoopHostDiscovery();

  @override
  Future<List<AndroidHostEndpoint>> discover(String hostId) async => const [];
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

final class _DigestSignatureVerifier implements HostDeviceSignatureVerifier {
  const _DigestSignatureVerifier();

  @override
  Future<bool> verify({
    required List<int> publicKeySpki,
    required List<int> message,
    required List<int> signatureDer,
  }) async {
    final expected = sha256.convert(message).bytes;
    if (signatureDer.length != expected.length) return false;
    var difference = 0;
    for (var index = 0; index < expected.length; index++) {
      difference |= signatureDer[index] ^ expected[index];
    }
    return difference == 0;
  }
}
