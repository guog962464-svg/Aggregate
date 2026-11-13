import 'dart:convert';
import 'dart:math';

import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:aggregate/platform/host/host_pairing_protocol.dart';
import 'package:aggregate/platform/macos/host/host_pairing_authority.dart';
import 'package:aggregate/platform/macos/host/host_device_signature_verifier.dart';
import 'package:aggregate/platform/macos/host/host_tls_identity.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const hostId = 'host-0123456789abcdef0123456789abcdef';
  const publicKeySpki = <int>[0x30, 0x03, 0x01, 0x02];

  late DateTime now;
  late InMemoryHostPairingStore store;
  late HostPairingAuthority authority;
  late String deviceId;
  late List<String> revokedDevices;

  setUp(() async {
    now = DateTime.utc(2026, 11, 13, 12);
    store = InMemoryHostPairingStore();
    deviceId = HostPairingProtocol.deviceIdForPublicKey(publicKeySpki);
    revokedDevices = [];
    authority = HostPairingAuthority(
      identity: const HostTlsIdentity(
        hostId: hostId,
        certificatePem: 'fixture certificate',
        privateKeyPem: 'fixture key',
        certificateSha256:
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      ),
      store: store,
      signatureVerifier: const _DigestSignatureVerifier(),
      now: () => now,
      random: Random(41),
      onDeviceRevoked: (id) async => revokedDevices.add(id),
    );
    await authority.initialize();
  });

  HostPairingRequest pairingRequest(HostPairingInvitation invitation) {
    final timestamp = now.millisecondsSinceEpoch ~/ 1000;
    final proof = HostPairingProtocol.pairingProof(
      hostId: hostId,
      deviceId: deviceId,
      invitationNonce: invitation.nonce,
      timestampSeconds: timestamp,
    );
    return HostPairingRequest(
      hostId: hostId,
      deviceId: deviceId,
      publicKeySpki: publicKeySpki,
      displayName: 'Pixel fixture',
      platform: 'android',
      invitationNonce: invitation.nonce,
      timestampSeconds: timestamp,
      signatureDer: _signature(proof),
    );
  }

  Future<void> approve() async {
    final invitation = await authority.createInvitation();
    await authority.submitPairingRequest(pairingRequest(invitation));
    await authority.approvePending(
      deviceId,
      scopes: const {
        HostGrantScope.readConnections,
        HostGrantScope.connectionSetup,
      },
    );
  }

  test(
    'creates a short lived invite and consumes it after signed request',
    () async {
      final invitation = await authority.createInvitation();
      final qr = jsonDecode(invitation.qrPayload) as Map<String, Object?>;
      expect(qr.keys.toSet(), {
        'version',
        'hostId',
        'certificateSha256',
        'nonce',
        'expiresAt',
      });
      expect(
        invitation.expiresAt.difference(invitation.issuedAt),
        const Duration(minutes: 5),
      );

      final request = pairingRequest(invitation);
      final pending = await authority.submitPairingRequest(request);
      expect(pending.deviceId, deviceId);
      expect(pending.confirmationCode, matches(RegExp(r'^\d{6}$')));
      expect((await authority.pendingRequests()), hasLength(1));
      await expectLater(
        authority.submitPairingRequest(request),
        throwsA(
          isA<HostPairingException>().having(
            (error) => error.error,
            'error',
            HostPairingError.invitationExpired,
          ),
        ),
      );
    },
  );

  test(
    'requires local approval and stores only the explicitly granted scopes',
    () async {
      final invitation = await authority.createInvitation();
      await authority.submitPairingRequest(pairingRequest(invitation));
      expect(
        await authority.isAuthorized(
          deviceId: deviceId,
          method: 'setup.save',
          params: const {},
        ),
        isFalse,
      );

      final grant = await authority.approvePending(
        deviceId,
        scopes: const {
          HostGrantScope.readConnections,
          HostGrantScope.connectionSetup,
        },
        connectionPermissions: const {
          'connection-a': {PermissionLevel.read},
        },
      );
      expect(grant.scopes, contains(HostGrantScope.connectionSetup));
      expect(
        HostDeviceGrant.fromJson(grant.toJson())
            .connectionPermissions['connection-a'],
        {PermissionLevel.read},
      );
      expect(
        await authority.isAuthorized(
          deviceId: deviceId,
          method: 'setup.save',
          params: const {},
        ),
        isTrue,
      );
      expect(
        await authority.isAuthorized(
          deviceId: deviceId,
          method: 'run.invoke',
          params: const {},
        ),
        isFalse,
      );
    },
  );

  test('challenge binds a session and rejects a replayed signed RPC', () async {
    await approve();
    final challenge = await authority.issueChallenge(deviceId);
    final authMessage = HostPairingProtocol.authenticationProof(
      hostId: hostId,
      deviceId: deviceId,
      connectionId: challenge.connectionId,
      challenge: challenge.challenge,
    );
    final session = await authority.completeChallenge(
      connectionId: challenge.connectionId,
      signatureDer: _signature(authMessage),
    );
    final payload = jsonEncode({
      'jsonrpc': '2.0',
      'id': 'request-1',
      'method': 'host.status',
      'params': {},
    });
    final requestNonce = _token('request-nonce');
    final payloadBytes = utf8.encode(payload);
    final proof = HostPairingProtocol.rpcRequestProof(
      hostId: hostId,
      deviceId: deviceId,
      sessionId: session.sessionId,
      timestampSeconds: now.millisecondsSinceEpoch ~/ 1000,
      nonce: requestNonce,
      payloadBytes: payloadBytes,
    );
    final envelope = HostSignedRpcEnvelope(
      hostId: hostId,
      deviceId: deviceId,
      sessionId: session.sessionId,
      timestampSeconds: now.millisecondsSinceEpoch ~/ 1000,
      nonce: requestNonce,
      payload: payload,
      signatureDer: _signature(proof),
    );
    final authenticated = await authority.authenticateRequest(envelope);
    expect(authenticated.deviceId, deviceId);
    expect(authenticated.payload, payload);
    await expectLater(
      authority.authenticateRequest(envelope),
      throwsA(
        isA<HostPairingException>().having(
          (error) => error.error,
          'error',
          HostPairingError.replayedRequest,
        ),
      ),
    );
  });

  test('caps active authenticated sessions', () async {
    await approve();
    for (var index = 0; index < 64; index++) {
      final challenge = await authority.issueChallenge(deviceId);
      final proof = HostPairingProtocol.authenticationProof(
        hostId: hostId,
        deviceId: deviceId,
        connectionId: challenge.connectionId,
        challenge: challenge.challenge,
      );
      await authority.completeChallenge(
        connectionId: challenge.connectionId,
        signatureDer: _signature(proof),
      );
    }

    final challenge = await authority.issueChallenge(deviceId);
    final proof = HostPairingProtocol.authenticationProof(
      hostId: hostId,
      deviceId: deviceId,
      connectionId: challenge.connectionId,
      challenge: challenge.challenge,
    );
    await expectLater(
      authority.completeChallenge(
        connectionId: challenge.connectionId,
        signatureDer: _signature(proof),
      ),
      throwsA(
        isA<HostPairingException>().having(
          (error) => error.error,
          'error',
          HostPairingError.resourceLimitExceeded,
        ),
      ),
    );
  });

  test(
    'rejects changed payload, stale timestamp, and wrong challenge proof',
    () async {
      await approve();
      final challenge = await authority.issueChallenge(deviceId);
      await expectLater(
        authority.completeChallenge(
          connectionId: challenge.connectionId,
          signatureDer: List.filled(32, 0xFF),
        ),
        throwsA(isA<HostPairingException>()),
      );

      final nextChallenge = await authority.issueChallenge(deviceId);
      final proof = HostPairingProtocol.authenticationProof(
        hostId: hostId,
        deviceId: deviceId,
        connectionId: nextChallenge.connectionId,
        challenge: nextChallenge.challenge,
      );
      final session = await authority.completeChallenge(
        connectionId: nextChallenge.connectionId,
        signatureDer: _signature(proof),
      );
      final payload =
          '{"jsonrpc":"2.0","id":"r","method":"host.status","params":{}}';
      final nonce = _token('different-request-nonce');
      final timestamp = now.millisecondsSinceEpoch ~/ 1000;
      final signedBytes = HostPairingProtocol.rpcRequestProof(
        hostId: hostId,
        deviceId: deviceId,
        sessionId: session.sessionId,
        timestampSeconds: timestamp,
        nonce: nonce,
        payloadBytes: utf8.encode(payload),
      );
      final altered = HostSignedRpcEnvelope(
        hostId: hostId,
        deviceId: deviceId,
        sessionId: session.sessionId,
        timestampSeconds: timestamp,
        nonce: nonce,
        payload: '$payload ',
        signatureDer: _signature(signedBytes),
      );
      await expectLater(
        authority.authenticateRequest(altered),
        throwsA(isA<HostPairingException>()),
      );
      final stale = HostSignedRpcEnvelope(
        hostId: hostId,
        deviceId: deviceId,
        sessionId: session.sessionId,
        timestampSeconds: timestamp - 61,
        nonce: _token('stale-request-nonce'),
        payload: payload,
        signatureDer: _signature(signedBytes),
      );
      await expectLater(
        authority.authenticateRequest(stale),
        throwsA(isA<HostPairingException>()),
      );
    },
  );

  test(
    'revocation removes persistent grant and invalidates active sessions',
    () async {
      await approve();
      final challenge = await authority.issueChallenge(deviceId);
      final proof = HostPairingProtocol.authenticationProof(
        hostId: hostId,
        deviceId: deviceId,
        connectionId: challenge.connectionId,
        challenge: challenge.challenge,
      );
      final session = await authority.completeChallenge(
        connectionId: challenge.connectionId,
        signatureDer: _signature(proof),
      );
      await authority.revokeDevice(deviceId);
      expect(revokedDevices, [deviceId]);
      expect(await store.readAll(), isEmpty);
      await expectLater(
        authority.authenticateRequest(
          HostSignedRpcEnvelope(
            hostId: hostId,
            deviceId: deviceId,
            sessionId: session.sessionId,
            timestampSeconds: now.millisecondsSinceEpoch ~/ 1000,
            nonce: _token('revoked-request-nonce'),
            payload: '{}',
            signatureDer: List.filled(32, 0),
          ),
        ),
        throwsA(isA<HostPairingException>()),
      );
    },
  );

  test('expires invitations and pending approval requests', () async {
    final invitation = await authority.createInvitation();
    now = now.add(const Duration(minutes: 6));
    await expectLater(
      authority.submitPairingRequest(pairingRequest(invitation)),
      throwsA(isA<HostPairingException>()),
    );

    final nextInvitation = await authority.createInvitation();
    await authority.submitPairingRequest(pairingRequest(nextInvitation));
    now = now.add(const Duration(minutes: 3));
    expect(await authority.pendingRequests(), isEmpty);
    await expectLater(
      authority.approvePending(deviceId),
      throwsA(isA<HostPairingException>()),
    );
  });
}

String _token(String seed) =>
    base64UrlEncode(sha256.convert(utf8.encode(seed)).bytes)
        .replaceAll('=', '');

List<int> _signature(List<int> message) => sha256.convert(message).bytes;

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
