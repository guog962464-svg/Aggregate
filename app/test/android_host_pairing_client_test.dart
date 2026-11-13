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
      final notifications = <Map<String, Object?>>[];
      final notificationSubscription = session.notifications.listen(
        notifications.add,
      );
      connector.sockets.last.emit({
        'jsonrpc': '2.0',
        'method': 'run.event',
        'params': {'subscriptionId': 'sub-test'},
      });
      await Future<void>.delayed(Duration.zero);
      expect(notifications.single['method'], 'run.event');
      final status = await session.call('host.status', const {});
      expect(status['phase'], 'running');
      expect(connector.sockets.last.methods, contains('host.status'));

      await session.close();
      await notificationSubscription.cancel();
      expect(session.isOpen, isFalse);
      expect(connector.sockets.last.isClosed, isTrue);
    },
  );

  test('rotates the device identity through the identity port', () async {
    final identity = _FakeIdentity();
    final client = AndroidHostPairingClient(identity: identity);
    final original = await identity.loadOrCreate();

    final rotated = await client.rotateDeviceIdentity();

    expect(rotated.deviceId, isNot(original.deviceId));
    expect(
      rotated.deviceId,
      HostPairingProtocol.deviceIdForPublicKey(rotated.publicKeySpki),
    );
    expect(identity.rotationCount, 1);
  });

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
      expect(manager.statusFor(_hostId), AndroidHostStatus.online);
      await manager.disconnect(_hostId);
      expect(manager.statusFor(_hostId), AndroidHostStatus.offline);
      await manager.dispose();

      final restored = AndroidHostManager(AndroidRuntimeStore(directory));
      await restored.load();
      expect(restored.hosts, hasLength(1));
      expect(restored.hosts.single.displayName, '家庭 Mac');
      expect(restored.isConnected(_hostId), isFalse);
      expect(restored.statusFor(_hostId), AndroidHostStatus.offline);
      await restored.remove(_hostId);
      expect(restored.hosts, isEmpty);
      await restored.dispose();
    },
  );

  test(
    'identity rotation clears saved hosts and closes their sessions',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'aggregate-android-host-rotation-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final identity = _FakeIdentity();
      final connector = _FakeConnector();
      final store = AndroidRuntimeStore(directory);
      final manager = AndroidHostManager(
        store,
        pairingClient: AndroidHostPairingClient(
          identity: identity,
          connector: connector,
          now: () => _now,
        ),
        now: () => _now,
      );
      await manager.load();
      final invitation = _invitation();
      await manager.completePairing(
        invitation: invitation,
        displayName: '家庭 Mac',
      );
      final oldDeviceId = (await identity.loadOrCreate()).deviceId;

      final result = await manager.rotateDeviceIdentity();

      expect(result.deviceId, isNot(oldDeviceId));
      expect(result.localHostRecordsCleared, isTrue);
      expect(manager.hosts, isEmpty);
      expect(manager.isConnected(_hostId), isFalse);
      expect(connector.sockets.single.isClosed, isTrue);
      final registry = await store.read('hosts') as Map<String, Object?>;
      expect(registry['hosts'], isEmpty);
      await manager.dispose();
    },
  );

  test(
    'classifies Host access, protocol and uncertain operation failures',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'aggregate-android-host-status-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final connector = _FakeConnector();
      final manager = AndroidHostManager(
        AndroidRuntimeStore(directory),
        pairingClient: AndroidHostPairingClient(
          identity: _FakeIdentity(),
          connector: connector,
          now: () => _now,
          rpcTimeout: const Duration(milliseconds: 50),
        ),
        now: () => _now,
      );
      await manager.load();
      await manager.completePairing(
        invitation: _invitation(),
        displayName: '测试手机',
      );
      final socket = connector.sockets.single;
      for (final (code, status) in [
        (-32001, AndroidHostStatus.versionIncompatible),
        (-32002, AndroidHostStatus.permissionDenied),
        (-32013, AndroidHostStatus.authenticationInvalid),
        (-32004, AndroidHostStatus.outcomeUnknown),
      ]) {
        socket.rpcErrorCodes['host.status'] = code;
        await expectLater(
          manager.call(_hostId, 'host.status', const {}),
          throwsA(isA<AndroidHostRpcException>()),
        );
        expect(manager.statusFor(_hostId), status);
      }

      socket.rpcErrorCodes['host.status'] = -32603;
      await expectLater(
        manager.call(_hostId, 'host.status', const {}, sideEffect: true),
        throwsA(isA<AndroidHostRpcException>()),
      );
      expect(manager.statusFor(_hostId), AndroidHostStatus.outcomeUnknown);

      socket.rpcErrorCodes.clear();
      socket.noReplyMethods.add('host.status');
      await expectLater(
        manager.call(_hostId, 'host.status', const {}),
        throwsA(isA<AndroidHostPairingException>()),
      );
      expect(manager.statusFor(_hostId), AndroidHostStatus.timedOut);
      await expectLater(
        manager.call(_hostId, 'host.status', const {}, sideEffect: true),
        throwsA(isA<AndroidHostPairingException>()),
      );
      expect(manager.statusFor(_hostId), AndroidHostStatus.outcomeUnknown);
      await manager.dispose();
    },
  );
}

final class _FakeIdentity implements AndroidHostIdentityPort {
  static final deviceId = HostPairingProtocol.deviceIdForPublicKey(
    List<int>.generate(91, (index) => index + 1),
  );

  int rotationCount = 0;

  Uint8List get _publicKey => Uint8List.fromList(
    List<int>.generate(91, (index) => index + 1 + rotationCount),
  );

  String get _deviceId => HostPairingProtocol.deviceIdForPublicKey(_publicKey);

  @override
  Future<AndroidHostPublicIdentity> loadOrCreate() async =>
      AndroidHostPublicIdentity(deviceId: _deviceId, publicKeySpki: _publicKey);

  @override
  Future<AndroidHostPublicIdentity> rotate() async {
    rotationCount++;
    return loadOrCreate();
  }

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
  final rpcErrorCodes = <String, int>{};
  final noReplyMethods = <String>{};
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
    if (noReplyMethods.contains(method)) return;
    final errorCode = rpcErrorCodes[method];
    if (errorCode != null) {
      _respondError(payload['id']! as String, errorCode);
      return;
    }
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

  void _respondError(String id, int code) {
    scheduleMicrotask(() {
      if (!_controller.isClosed) {
        _controller.add(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': id,
            'error': {'code': code, 'message': 'failure'},
          }),
        );
      }
    });
  }

  void emit(Map<String, Object?> notification) {
    if (!_controller.isClosed) _controller.add(jsonEncode(notification));
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
