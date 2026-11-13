import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:aggregate/platform/android/android_host_device_identity.dart';
import 'package:aggregate/platform/android/android_host_manager.dart';
import 'package:aggregate/platform/android/android_host_pairing_client.dart';
import 'package:aggregate/platform/android/android_runtime_store.dart';
import 'package:aggregate/platform/host/host_pairing_protocol.dart';
import 'package:aggregate/platform/host/host_wss_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

const _hostId = 'host-0123456789abcdef0123456789abcdef';
final _pin = List<String>.filled(64, 'a').join();
final _now = DateTime.utc(2026, 11, 13, 10);

AndroidHostInvitation _invitation({
  String endpoint = 'wss://192.168.1.20:48123/host',
}) => AndroidHostInvitation.fromQrPayload(
  jsonEncode({
    'version': HostPairingProtocol.version,
    'hostId': _hostId,
    'certificateSha256': _pin,
    'nonce': 'AAAAAAAAAAAAAAAAAAAAAA',
    'expiresAt': _now.add(const Duration(minutes: 5)).toIso8601String(),
    'serviceType': hostBonjourServiceType,
    'endpoints': [
      {'uri': endpoint},
    ],
  }),
  now: () => _now,
);

void main() {
  group('AndroidHostInvitation', () {
    test('accepts a private IPv4 WSS invitation', () {
      final invitation = _invitation();
      expect(invitation.hostId, _hostId);
      expect(invitation.certificateSha256, _pin);
      expect(invitation.endpoints.single.uri.host, '192.168.1.20');
    });

    test('rejects public hosts, names, paths and URL parameters', () {
      for (final endpoint in [
        'wss://203.0.113.10:48123/host',
        'wss://aggregate.local:48123/host',
        'wss://192.168.1.20:48123/other',
        'wss://192.168.1.20:48123/host?next=https://example.com',
      ]) {
        expect(
          () => _invitation(endpoint: endpoint),
          throwsA(
            isA<AndroidHostPairingException>().having(
              (error) => error.failure,
              'failure',
              AndroidHostPairingFailure.invalidInvitation,
            ),
          ),
        );
      }
    });

    test('reports expired invitations distinctly', () {
      final payload = jsonEncode({
        'version': HostPairingProtocol.version,
        'hostId': _hostId,
        'certificateSha256': _pin,
        'nonce': 'AAAAAAAAAAAAAAAAAAAAAA',
        'expiresAt': _now
            .subtract(const Duration(minutes: 1))
            .toIso8601String(),
        'serviceType': hostBonjourServiceType,
        'endpoints': [
          {'uri': 'wss://192.168.1.20:48123/host'},
        ],
      });
      expect(
        () => AndroidHostInvitation.fromQrPayload(payload, now: () => _now),
        throwsA(
          isA<AndroidHostPairingException>().having(
            (error) => error.failure,
            'failure',
            AndroidHostPairingFailure.invitationExpired,
          ),
        ),
      );
    });
  });

  test(
    'requests pairing, authenticates and signs subsequent RPC calls',
    () async {
      final connector = _FakeConnector();
      final client = AndroidHostPairingClient(
        identity: _FakeIdentity(),
        connector: connector,
        now: () => _now,
      );
      final invitation = _invitation();

      final receipt = await client.requestPairing(
        invitation: invitation,
        displayName: '测试手机',
      );
      expect(receipt.confirmationCode, '123456');
      expect(receipt.deviceId, _FakeIdentity.deviceId);
      expect(connector.sockets.first.isClosed, isTrue);

      final session = await client.authenticate(
        AndroidHostTarget.fromInvitation(invitation),
      );
      expect(session.isOpen, isTrue);
      expect(connector.sockets.last.methods, contains('host.hello'));
      final status = await session.call('host.status', const {});
      expect(status['phase'], 'running');
      expect(connector.sockets.last.methods, contains('host.status'));

      await session.close();
      expect(session.isOpen, isFalse);
      expect(connector.sockets.last.isClosed, isTrue);
    },
  );

  test(
    'persists public pairing metadata and reloads it without a session',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'aggregate-android-host-manager-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final manager = AndroidHostManager(
        AndroidRuntimeStore(directory),
        pairingClient: AndroidHostPairingClient(
          identity: _FakeIdentity(),
          connector: _FakeConnector(),
          now: () => _now,
        ),
        now: () => _now,
      );
      await manager.load();
      final invitation = _invitation();
      await manager.requestPairing(invitation: invitation, displayName: '测试手机');
      final host = await manager.completePairing(
        invitation: invitation,
        displayName: '家庭 Mac',
      );
      expect(host.hostId, _hostId);
      expect(manager.isConnected(_hostId), isTrue);
      await manager.dispose();

      final restored = AndroidHostManager(AndroidRuntimeStore(directory));
      await restored.load();
      expect(restored.hosts, hasLength(1));
      expect(restored.hosts.single.displayName, '家庭 Mac');
      expect(restored.isConnected(_hostId), isFalse);
      await restored.remove(_hostId);
      expect(restored.hosts, isEmpty);
      await restored.dispose();
    },
  );
}

final class _FakeIdentity implements AndroidHostIdentityPort {
  static final deviceId = HostPairingProtocol.deviceIdForPublicKey(
    List<int>.generate(91, (index) => index + 1),
  );

  final _publicKey = Uint8List.fromList(
    List<int>.generate(91, (index) => index + 1),
  );

  @override
  Future<AndroidHostPublicIdentity> loadOrCreate() async =>
      AndroidHostPublicIdentity(deviceId: deviceId, publicKeySpki: _publicKey);

  @override
  Future<Uint8List> sign(Uint8List message) async =>
      Uint8List.fromList(List<int>.filled(64, message.length % 255));
}

final class _FakeConnector implements AndroidHostSocketConnector {
  final sockets = <_FakeSocket>[];

  @override
  Future<AndroidHostSocket> connect(
    Uri uri, {
    required String certificateSha256,
  }) async {
    expect(uri.host, '192.168.1.20');
    expect(certificateSha256, _pin);
    final socket = _FakeSocket();
    sockets.add(socket);
    return socket;
  }
}

final class _FakeSocket implements AndroidHostSocket {
  final _controller = StreamController<Object?>();
  final methods = <String>[];
  String? _deviceId;
  var isClosed = false;

  @override
  Stream<Object?> get messages => _controller.stream;

  @override
  String get protocol => hostWssSubprotocol;

  @override
  set pingInterval(Duration interval) {}

  @override
  void send(String frame) {
    final decoded = jsonDecode(frame) as Map<String, Object?>;
    if (decoded['jsonrpc'] == '2.0') {
      final method = decoded['method']! as String;
      methods.add(method);
      final id = decoded['id']! as String;
      final params = decoded['params']! as Map<String, Object?>;
      switch (method) {
        case 'host.pair.request':
          _deviceId = params['deviceId']! as String;
          _respond(id, {
            'state': 'pendingApproval',
            'deviceId': _deviceId,
            'confirmationCode': '123456',
            'expiresAt': _now.add(const Duration(minutes: 2)).toIso8601String(),
          });
        case 'host.auth.begin':
          _deviceId = params['deviceId']! as String;
          _respond(id, {
            'hostId': _hostId,
            'deviceId': _deviceId,
            'connectionId': _token(1),
            'challenge': _token(2),
            'expiresAt': _now.add(const Duration(minutes: 1)).toIso8601String(),
          });
        case 'host.auth.prove':
          _respond(id, {'deviceId': _deviceId, 'sessionId': _token(3)});
        default:
          throw StateError('Unexpected unauthenticated method: $method');
      }
      return;
    }

    final envelope = decoded;
    final payload =
        jsonDecode(envelope['payload']! as String) as Map<String, Object?>;
    final method = payload['method']! as String;
    methods.add(method);
    final result = switch (method) {
      'host.hello' => {
        'protocolVersion': hostProtocolVersion,
        'hostId': _hostId,
        'certificateSha256': _pin,
      },
      'host.status' => {'hostId': _hostId, 'phase': 'running'},
      _ => <String, Object?>{},
    };
    _respond(payload['id']! as String, result);
  }

  void _respond(String id, Map<String, Object?> result) {
    scheduleMicrotask(() {
      if (!_controller.isClosed) {
        _controller.add(
          jsonEncode({'jsonrpc': '2.0', 'id': id, 'result': result}),
        );
      }
    });
  }

  String _token(int byte) =>
      base64UrlEncode(List<int>.filled(16, byte)).replaceAll('=', '');

  @override
  Future<void> close() async {
    if (isClosed) return;
    isClosed = true;
    await _controller.close();
  }
}
