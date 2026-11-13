import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:aggregate/platform/host/host_pairing_protocol.dart';
import 'package:aggregate/platform/macos/host/host_device_signature_verifier.dart';
import 'package:aggregate/platform/macos/host/host_operation_ledger.dart';
import 'package:aggregate/platform/macos/host/host_pairing_authority.dart';
import 'package:aggregate/platform/macos/host/host_rpc_protocol.dart';
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
  late DateTime now;
  late HostTlsIdentity identity;
  late HostPairingAuthority pairing;
  late HostSetupCoordinator setup;
  late HostWssTransport transport;
  late HttpClient client;
  late String deviceId;
  late List<int> publicKeySpki;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('aggregate-host-wss-');
    now = DateTime.now().toUtc();
    publicKeySpki = base64Decode(publicKeySpkiBase64);
    deviceId = HostPairingProtocol.deviceIdForPublicKey(publicKeySpki);

    final provider = _FixtureIdentityProvider(
      certificatePem: await File('test/fixtures/host_test_cert.pem')
          .readAsString(),
      privateKeyPem: await File('test/fixtures/host_test_key.pem')
          .readAsString(),
    );
    identity = await HostTlsIdentityStore(provider: provider).loadOrCreate();
    setup = HostSetupCoordinator(setup: _SetupFixture());
    pairing = HostPairingAuthority(
      identity: identity,
      store: InMemoryHostPairingStore(),
      signatureVerifier: const _DigestSignatureVerifier(),
      setupCoordinator: setup,
      now: () => now,
      random: Random(41),
    );
    final ledger = await FileHostOperationLedger.open(
      File('${directory.path}/operations.json'),
    );
    final dispatcher = HostSetupRpcDispatcher(
      setup: setup,
      ledger: ledger,
      authorization: pairing,
    );
    transport = HostWssTransport(
      loadServices: () async => HostWssServices(
        identity: identity,
        pairing: pairing,
        dispatcher: dispatcher,
      ),
      bindAddressProvider: const _LoopbackAddressProvider(),
      bonjourPublisher: const NoopHostBonjourPublisher(),
      maxConnectionsPerDevice: 1,
    );
    client = HttpClient()
      ..badCertificateCallback = (certificate, _, _) =>
          sha256.convert(certificate.der).toString() ==
          identity.certificateSha256;
  });

  tearDown(() async {
    client.close(force: true);
    await transport.stop();
    await directory.delete(recursive: true);
  });

  Future<WebSocket> connect(Uri uri) => WebSocket.connect(
    uri.toString(),
    protocols: const [hostWssSubprotocol],
    compression: CompressionOptions.compressionOff,
    customClient: client,
  );

  test(
    'pairs, authenticates, dispatches signed RPC and disconnects on revoke',
    () async {
      await transport.start();
      final invitation = await transport.createInvitation();
      final qr = jsonDecode(invitation.qrPayload) as Map<String, Object?>;
      expect(qr['serviceType'], hostBonjourServiceType);
      expect(qr['endpoints'], hasLength(1));

      final pairSocket = await connect(invitation.endpoints.single.uri);
      final pairIterator = StreamIterator<Object?>(pairSocket);
      final timestamp = now.millisecondsSinceEpoch ~/ 1000;
      final pairProof = HostPairingProtocol.pairingProof(
        hostId: hostId,
        deviceId: deviceId,
        invitationNonce: invitation.invitation.nonce,
        timestampSeconds: timestamp,
      );
      pairSocket.add(
        HostRpcCodec.encodeFrame({
          'jsonrpc': '2.0',
          'id': 'pair-1',
          'method': 'host.pair.request',
          'params': {
            'hostId': hostId,
            'deviceId': deviceId,
            'publicKeySpki': publicKeySpkiBase64,
            'displayName': 'Pixel test device',
            'platform': 'android',
            'invitationNonce': invitation.invitation.nonce,
            'timestampSeconds': timestamp,
            'signatureDer': base64Encode(_signature(pairProof)),
          },
        }),
      );
      final pending = await _readResponse(pairIterator);
      expect(
        (pending['result']! as Map<String, Object?>)['state'],
        'pendingApproval',
      );
      expect(await transport.pendingRequests(), hasLength(1));
      await pairSocket.close();
      await pairIterator.cancel();

      await transport.approvePending(
        deviceId,
        scopes: const {
          HostGrantScope.readConnections,
          HostGrantScope.connectionSetup,
        },
      );

      final socket = await connect(invitation.endpoints.single.uri);
      final iterator = StreamIterator<Object?>(socket);
      socket.add(
        HostRpcCodec.encodeFrame({
          'jsonrpc': '2.0',
          'id': 'auth-begin',
          'method': 'host.auth.begin',
          'params': {'deviceId': deviceId},
        }),
      );
      final challengeResponse = await _readResponse(iterator);
      final challenge = challengeResponse['result']! as Map<String, Object?>;
      final connectionId = challenge['connectionId']! as String;
      final challengeText = challenge['challenge']! as String;
      final authProof = HostPairingProtocol.authenticationProof(
        hostId: hostId,
        deviceId: deviceId,
        connectionId: connectionId,
        challenge: challengeText,
      );
      socket.add(
        HostRpcCodec.encodeFrame({
          'jsonrpc': '2.0',
          'id': 'auth-prove',
          'method': 'host.auth.prove',
          'params': {
            'connectionId': connectionId,
            'signatureDer': base64Encode(_signature(authProof)),
          },
        }),
      );
      final authenticated = await _readResponse(iterator);
      final sessionId =
          (authenticated['result']! as Map<String, Object?>)['sessionId']!
              as String;

      final timestampNow = now.millisecondsSinceEpoch ~/ 1000;
      final setupPayload = jsonEncode({
        'jsonrpc': '2.0',
        'id': 'rpc-adapters',
        'method': 'setup.adapters',
        'params': {},
      });
      socket.add(
        HostRpcCodec.encodeFrame(
          _signedRpcFrame(
            hostId: hostId,
            deviceId: deviceId,
            sessionId: sessionId,
            timestampSeconds: timestampNow,
            nonceSeed: 'setup-adapters',
            payload: setupPayload,
          ),
        ),
      );
      final adapters = await _readResponse(iterator);
      final adapterResult = adapters['result']! as Map<String, Object?>;
      expect(adapterResult['adapters'], hasLength(1));

      final deniedPayload = jsonEncode({
        'jsonrpc': '2.0',
        'id': 'rpc-run',
        'method': 'run.invoke',
        'params': {
          'operationId': 'operation-1',
          'capability': {
            'connection': {'value': 'connection-1'},
            'kind': 'mcpTool',
            'name': 'search',
          },
          'arguments': {},
        },
      });
      socket.add(
        HostRpcCodec.encodeFrame(
          _signedRpcFrame(
            hostId: hostId,
            deviceId: deviceId,
            sessionId: sessionId,
            timestampSeconds: timestampNow,
            nonceSeed: 'unauthorized-run',
            payload: deniedPayload,
          ),
        ),
      );
      final denied = await _readResponse(iterator);
      expect(
        (denied['error']! as Map<String, Object?>)['code'],
        HostRpcErrorCode.unauthorized.value,
      );

      final secondSocket = await connect(invitation.endpoints.single.uri);
      final secondIterator = StreamIterator<Object?>(secondSocket);
      secondSocket.add(
        HostRpcCodec.encodeFrame({
          'jsonrpc': '2.0',
          'id': 'auth-begin-2',
          'method': 'host.auth.begin',
          'params': {'deviceId': deviceId},
        }),
      );
      final capped = await _readResponse(secondIterator);
      expect(
        (capped['error']! as Map<String, Object?>)['code'],
        HostRpcErrorCode.resourceLimitExceeded.value,
      );
      await secondSocket.close();
      await secondIterator.cancel();

      await transport.revokeDevice(deviceId);
      expect(
        await iterator.moveNext().timeout(const Duration(seconds: 2)),
        isFalse,
      );
      await iterator.cancel();
    },
  );
}

Map<String, Object?> _signedRpcFrame({
  required String hostId,
  required String deviceId,
  required String sessionId,
  required int timestampSeconds,
  required String nonceSeed,
  required String payload,
}) {
  final nonce = base64UrlEncode(sha256.convert(utf8.encode(nonceSeed)).bytes)
      .replaceAll('=', '');
  final proof = HostPairingProtocol.rpcRequestProof(
    hostId: hostId,
    deviceId: deviceId,
    sessionId: sessionId,
    timestampSeconds: timestampSeconds,
    nonce: nonce,
    payloadBytes: utf8.encode(payload),
  );
  return {
    'hostId': hostId,
    'deviceId': deviceId,
    'sessionId': sessionId,
    'timestampSeconds': timestampSeconds,
    'nonce': nonce,
    'payload': payload,
    'signatureDer': base64Encode(_signature(proof)),
  };
}

Future<Map<String, Object?>> _readResponse(
  StreamIterator<Object?> iterator,
) async {
  expect(await iterator.moveNext().timeout(const Duration(seconds: 3)), isTrue);
  final frame = iterator.current;
  expect(frame, isA<String>());
  return jsonDecode(frame! as String) as Map<String, Object?>;
}

List<int> _signature(List<int> message) => sha256.convert(message).bytes;

final class _LoopbackAddressProvider implements HostWssBindAddressProvider {
  const _LoopbackAddressProvider();

  @override
  Future<List<InternetAddress>> addresses() async => [
    InternetAddress.loopbackIPv4,
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

final class _DigestSignatureVerifier implements HostDeviceSignatureVerifier {
  const _DigestSignatureVerifier();

  @override
  Future<bool> verify({
    required List<int> publicKeySpki,
    required List<int> message,
    required List<int> signatureDer,
  }) async {
    final expected = _signature(message);
    if (signatureDer.length != expected.length) return false;
    var difference = 0;
    for (var index = 0; index < expected.length; index++) {
      difference |= signatureDer[index] ^ expected[index];
    }
    return difference == 0;
  }
}

final class _SetupFixture implements ConnectionSetupPort {
  @override
  List<ConnectionAdapter> get connectionAdapters => const [
    ConnectionAdapter(
      id: 'netease-music',
      label: '网易云音乐',
      kind: ConnectionKind.cli,
      fields: [SetupField(key: 'appId', label: 'App ID')],
      autoDetectExecutable: true,
      showGenericCliFields: false,
    ),
  ];

  @override
  Future<String?> detectExecutable(String adapterId) async => null;

  @override
  Future<ConnectionSetupReport> testConnectionSetup(
    ConnectionSetupDraft draft,
  ) async => const ConnectionSetupReport(
    draftId: 'fixture-draft',
    checks: [],
    canSave: true,
  );

  @override
  Future<Connection> saveConnectionSetup(String draftId) async =>
      const Connection(
        id: ConnectionId('fixture-connection'),
        kind: ConnectionKind.cli,
        label: 'Fixture',
        location: '/fixture',
      );

  @override
  Future<void> discardConnectionSetup(String draftId) async {}
}
