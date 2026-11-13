import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:flutter/services.dart';

import 'host_device_signature_verifier.dart';
import 'host_setup_coordinator.dart';
import 'host_setup_rpc_dispatcher.dart';
import 'host_tls_identity.dart';
import '../../host/host_pairing_protocol.dart';

const _maxPairedDevices = 128;
const _maxActiveInvitations = 8;
const _maxPendingPairings = 32;
const _maxAuthenticatedSessions = 64;
const _maxInviteProofAttempts = 5;
const _maxSessionNonces = 4096;
const _pairingTextLimit = 80;
final _hostIdentifierPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$');
final _controlCharacters = RegExp(r'[\x00-\x1f\x7f]');

enum HostGrantScope {
  readConnections,
  connectionSetup,
  connectionManagement,
  account,
  terminal,
  activityClear,
  contentTransfer,
}

final class HostDeviceGrant {
  HostDeviceGrant({
    required this.deviceId,
    required List<int> publicKeySpki,
    required this.displayName,
    required this.platform,
    required this.approvedAt,
    Set<HostGrantScope> scopes = const {HostGrantScope.readConnections},
    Map<String, Set<PermissionLevel>> connectionPermissions = const {},
  }) : publicKeySpki = List.unmodifiable(publicKeySpki),
       scopes = Set.unmodifiable(scopes),
       connectionPermissions = Map.unmodifiable({
         for (final entry in connectionPermissions.entries)
           entry.key: Set<PermissionLevel>.unmodifiable(entry.value),
       }) {
    _validate();
  }

  final String deviceId;
  final List<int> publicKeySpki;
  final String displayName;
  final String platform;
  final DateTime approvedAt;
  final Set<HostGrantScope> scopes;
  final Map<String, Set<PermissionLevel>> connectionPermissions;

  bool permitsInvocation(String connectionId, PermissionLevel permission) {
    if (permission == PermissionLevel.unknown) return false;
    return connectionPermissions[connectionId]?.contains(permission) ?? false;
  }

  Map<String, Object?> toJson() => {
    'deviceId': deviceId,
    'publicKeySpki': base64Encode(publicKeySpki),
    'displayName': displayName,
    'platform': platform,
    'approvedAt': approvedAt.toUtc().toIso8601String(),
    'scopes': scopes.map((scope) => scope.name).toList()..sort(),
    'connectionPermissions': {
      for (final entry
          in connectionPermissions.entries.toList()
            ..sort((left, right) => left.key.compareTo(right.key)))
        entry.key: entry.value.map((permission) => permission.name).toList()
          ..sort(),
    },
  };

  factory HostDeviceGrant.fromJson(Object? value) {
    final json = _readJsonObject(value, {
      'deviceId',
      'publicKeySpki',
      'displayName',
      'platform',
      'approvedAt',
      'scopes',
      'connectionPermissions',
    });
    final deviceId = json['deviceId'];
    final publicKey = json['publicKeySpki'];
    final displayName = json['displayName'];
    final platform = json['platform'];
    final approvedAtValue = json['approvedAt'];
    final rawScopes = json['scopes'];
    final rawPermissions = json['connectionPermissions'];
    if (deviceId is! String ||
        publicKey is! String ||
        displayName is! String ||
        platform is! String ||
        approvedAtValue is! String ||
        rawScopes is! List ||
        rawPermissions is! Map) {
      throw const FormatException('Host pairing record is invalid');
    }
    final scopeNames = _stringList(rawScopes);
    final permissionMap = <String, Set<PermissionLevel>>{};
    for (final entry in rawPermissions.entries) {
      if (entry.key is! String || entry.value is! List) {
        throw const FormatException('Host pairing record is invalid');
      }
      permissionMap[entry.key as String] = {
        for (final name in _stringList(entry.value as List))
          _parsePermission(name),
      };
    }
    final parsedScopes = {for (final name in scopeNames) _parseScope(name)};
    final decodedPublicKey = base64Decode(publicKey);
    final approvedAt = DateTime.tryParse(approvedAtValue);
    if (approvedAt == null) {
      throw const FormatException('Host pairing record is invalid');
    }
    return HostDeviceGrant(
      deviceId: deviceId,
      publicKeySpki: decodedPublicKey,
      displayName: displayName,
      platform: platform,
      approvedAt: approvedAt,
      scopes: parsedScopes,
      connectionPermissions: permissionMap,
    );
  }

  void _validate() {
    if (!HostPairingProtocol.isDeviceId(deviceId) ||
        HostPairingProtocol.deviceIdForPublicKey(publicKeySpki) != deviceId ||
        publicKeySpki.length > 256 ||
        !_isSafeDisplayName(displayName) ||
        platform != 'android' ||
        scopes.length > HostGrantScope.values.length ||
        connectionPermissions.length > 256 ||
        connectionPermissions.entries.any(
          (entry) =>
              !_hostIdentifierPattern.hasMatch(entry.key) ||
              entry.value.isEmpty ||
              entry.value.contains(PermissionLevel.unknown),
        )) {
      throw const FormatException('Host pairing record is invalid');
    }
  }
}

abstract interface class HostPairingStore {
  Future<List<HostDeviceGrant>> readAll();
  Future<void> save(HostDeviceGrant grant);
  Future<void> remove(String deviceId);
}

/// Pairing identities and grants are public metadata stored in one app-owned
/// Keychain registry item. The native channel serializes mutations and
/// validates every record before replacing the registry value.
final class MacKeychainHostPairingStore implements HostPairingStore {
  const MacKeychainHostPairingStore({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('aggregate/host_pairing');

  final MethodChannel _channel;

  @override
  Future<List<HostDeviceGrant>> readAll() async {
    try {
      final encoded = await _channel.invokeMethod<String>('loadAll');
      if (encoded == null) return const [];
      final entries = jsonDecode(encoded);
      if (entries is! Map ||
          entries.keys.any((key) => key is! String) ||
          entries.length > _maxPairedDevices) {
        throw const FormatException('Host pairing registry is invalid');
      }
      return List.unmodifiable([
        for (final entry in entries.entries)
          _readGrantEntry(entry.key as String, entry.value),
      ]);
    } catch (_) {
      throw const HostPairingException(HostPairingError.storageFailure);
    }
  }

  @override
  Future<void> save(HostDeviceGrant grant) async {
    final encoded = jsonEncode(grant.toJson());
    if (utf8.encode(encoded).length > 16 * 1024) {
      throw const HostPairingException(HostPairingError.storageFailure);
    }
    try {
      await _channel.invokeMethod<void>('save', {
        'deviceId': grant.deviceId,
        'record': encoded,
      });
    } on PlatformException {
      throw const HostPairingException(HostPairingError.storageFailure);
    }
  }

  @override
  Future<void> remove(String deviceId) async {
    try {
      await _channel.invokeMethod<void>('remove', {'deviceId': deviceId});
    } on PlatformException {
      throw const HostPairingException(HostPairingError.storageFailure);
    }
  }
}

final class InMemoryHostPairingStore implements HostPairingStore {
  InMemoryHostPairingStore([Iterable<HostDeviceGrant> initial = const []])
    : _records = {for (final record in initial) record.deviceId: record};

  final Map<String, HostDeviceGrant> _records;

  @override
  Future<List<HostDeviceGrant>> readAll() async => List.unmodifiable(
    _records.values.toList()..sort((a, b) => a.deviceId.compareTo(b.deviceId)),
  );

  @override
  Future<void> save(HostDeviceGrant grant) async {
    if (!_records.containsKey(grant.deviceId) &&
        _records.length >= _maxPairedDevices) {
      throw const HostPairingException(HostPairingError.resourceLimitExceeded);
    }
    _records[grant.deviceId] = grant;
  }

  @override
  Future<void> remove(String deviceId) async {
    _records.remove(deviceId);
  }
}

final class HostPairingInvitation {
  const HostPairingInvitation({
    required this.hostId,
    required this.certificateSha256,
    required this.nonce,
    required this.issuedAt,
    required this.expiresAt,
  });

  final String hostId;
  final String certificateSha256;
  final String nonce;
  final DateTime issuedAt;
  final DateTime expiresAt;

  String get qrPayload => jsonEncode({
    'version': HostPairingProtocol.version,
    'hostId': hostId,
    'certificateSha256': certificateSha256,
    'nonce': nonce,
    'expiresAt': expiresAt.toUtc().toIso8601String(),
  });
}

final class HostPairingRequest {
  HostPairingRequest({
    required this.hostId,
    required this.deviceId,
    required List<int> publicKeySpki,
    required this.displayName,
    required this.platform,
    required this.invitationNonce,
    required this.timestampSeconds,
    required List<int> signatureDer,
  }) : publicKeySpki = List.unmodifiable(publicKeySpki),
       signatureDer = List.unmodifiable(signatureDer);

  final String hostId;
  final String deviceId;
  final List<int> publicKeySpki;
  final String displayName;
  final String platform;
  final String invitationNonce;
  final int timestampSeconds;
  final List<int> signatureDer;
}

final class HostPendingPairing {
  const HostPendingPairing({
    required this.deviceId,
    required this.displayName,
    required this.platform,
    required this.confirmationCode,
    required this.requestedAt,
    required this.expiresAt,
  });

  final String deviceId;
  final String displayName;
  final String platform;
  final String confirmationCode;
  final DateTime requestedAt;
  final DateTime expiresAt;
}

final class HostAuthenticationChallenge {
  const HostAuthenticationChallenge({
    required this.hostId,
    required this.deviceId,
    required this.connectionId,
    required this.challenge,
    required this.expiresAt,
  });

  final String hostId;
  final String deviceId;
  final String connectionId;
  final String challenge;
  final DateTime expiresAt;
}

final class HostAuthenticatedSession {
  const HostAuthenticatedSession({
    required this.deviceId,
    required this.sessionId,
    required this.connectionId,
    required this.authenticatedAt,
  });

  final String deviceId;
  final String sessionId;
  final String connectionId;
  final DateTime authenticatedAt;
}

final class HostSignedRpcEnvelope {
  HostSignedRpcEnvelope({
    required this.hostId,
    required this.deviceId,
    required this.sessionId,
    required this.timestampSeconds,
    required this.nonce,
    required this.payload,
    required List<int> signatureDer,
  }) : signatureDer = List.unmodifiable(signatureDer);

  final String hostId;
  final String deviceId;
  final String sessionId;
  final int timestampSeconds;
  final String nonce;
  final String payload;
  final List<int> signatureDer;
}

final class HostAuthenticatedRequest {
  const HostAuthenticatedRequest({
    required this.deviceId,
    required this.sessionId,
    required this.payload,
  });

  final String deviceId;
  final String sessionId;
  final String payload;
}

enum HostPairingError {
  invalidRequest,
  invitationExpired,
  invalidProof,
  approvalRequired,
  alreadyPaired,
  notPaired,
  unauthorized,
  replayedRequest,
  expiredSession,
  resourceLimitExceeded,
  storageFailure,
  revocationCleanupFailed,
}

final class HostPairingException implements Exception {
  const HostPairingException(this.error);

  final HostPairingError error;

  @override
  String toString() => 'HostPairingException(${error.name})';
}

/// Owns one-time pairing, explicit grants, signed challenges and per-request
/// authentication. Callers still decide how to display and locally approve
/// pending requests and which transport carries authenticated sessions.
final class HostPairingAuthority implements HostRpcAuthorizationPort {
  HostPairingAuthority({
    required this.identity,
    required this.store,
    required this.signatureVerifier,
    this.setupCoordinator,
    this.onDeviceRevoked,
    DateTime Function()? now,
    Random? random,
    this.invitationLifetime = const Duration(minutes: 5),
    this.pendingLifetime = const Duration(minutes: 2),
    this.challengeLifetime = const Duration(seconds: 30),
    this.requestClockSkew = const Duration(seconds: 60),
    this.sessionIdleTimeout = const Duration(minutes: 15),
    this.sessionLifetime = const Duration(hours: 12),
  }) : _now = now ?? DateTime.now,
       _random = random ?? Random.secure() {
    if (invitationLifetime <= Duration.zero ||
        pendingLifetime <= Duration.zero ||
        challengeLifetime <= Duration.zero ||
        requestClockSkew <= Duration.zero ||
        sessionIdleTimeout <= Duration.zero ||
        sessionLifetime < sessionIdleTimeout) {
      throw ArgumentError('Invalid Host pairing policy');
    }
  }

  final HostTlsIdentity identity;
  final HostPairingStore store;
  final HostDeviceSignatureVerifier signatureVerifier;
  final HostSetupCoordinator? setupCoordinator;
  final Future<void> Function(String deviceId)? onDeviceRevoked;
  final Duration invitationLifetime;
  final Duration pendingLifetime;
  final Duration challengeLifetime;
  final Duration requestClockSkew;
  final Duration sessionIdleTimeout;
  final Duration sessionLifetime;
  final DateTime Function() _now;
  final Random _random;
  final Map<String, HostDeviceGrant> _grants = {};
  final Map<String, _InvitationRecord> _invitations = {};
  final Map<String, _PendingPairingRecord> _pending = {};
  final Map<String, _ChallengeRecord> _challenges = {};
  final Map<String, _SessionRecord> _sessions = {};
  final Set<String> _revokedDevices = {};
  final _revocations = StreamController<String>.broadcast(sync: true);
  Future<void>? _loadOperation;
  Future<void> _tail = Future<void>.value();

  Future<void> initialize() => _serialize(_ensureLoaded);

  Stream<String> watchRevocations() => _revocations.stream;

  Future<List<HostDeviceGrant>> pairedDevices() => _serialize(() async {
    await _ensureLoaded();
    return List.unmodifiable(
      _grants.values.toList()
        ..sort((left, right) => left.deviceId.compareTo(right.deviceId)),
    );
  });

  Future<List<HostPendingPairing>> pendingRequests() => _serialize(() async {
    _sweepExpired();
    return List.unmodifiable([
      for (final record in _pending.values) _pendingView(record),
    ]);
  });

  Future<HostPairingInvitation> createInvitation() => _serialize(() async {
    await _ensureLoaded();
    _sweepExpired();
    if (_invitations.length >= _maxActiveInvitations) {
      throw const HostPairingException(HostPairingError.resourceLimitExceeded);
    }
    final issuedAt = _utcNow();
    late String nonce;
    do {
      nonce = _newToken(32);
    } while (_invitations.containsKey(nonce));
    final expiresAt = issuedAt.add(invitationLifetime);
    final invitation = HostPairingInvitation(
      hostId: identity.hostId,
      certificateSha256: identity.certificateSha256,
      nonce: nonce,
      issuedAt: issuedAt,
      expiresAt: expiresAt,
    );
    _invitations[nonce] = _InvitationRecord(invitation);
    return invitation;
  });

  Future<HostPendingPairing> submitPairingRequest(HostPairingRequest request) =>
      _serialize(() async {
        await _ensureLoaded();
        _sweepExpired();
        final invitation = _invitations[request.invitationNonce];
        if (invitation == null ||
            invitation.invitation.expiresAt.isBefore(_utcNow())) {
          throw const HostPairingException(HostPairingError.invitationExpired);
        }
        if (request.hostId != identity.hostId ||
            !_isSafeDisplayName(request.displayName) ||
            request.platform != 'android' ||
            request.publicKeySpki.isEmpty ||
            request.publicKeySpki.length > 256 ||
            request.signatureDer.length < 8 ||
            request.signatureDer.length > 80 ||
            !HostPairingProtocol.isToken(request.invitationNonce) ||
            HostPairingProtocol.deviceIdForPublicKey(request.publicKeySpki) !=
                request.deviceId ||
            !_timestampIsCurrent(request.timestampSeconds)) {
          throw const HostPairingException(HostPairingError.invalidRequest);
        }
        if (_grants.containsKey(request.deviceId)) {
          throw const HostPairingException(HostPairingError.alreadyPaired);
        }
        if (_pending.containsKey(request.deviceId)) {
          throw const HostPairingException(HostPairingError.approvalRequired);
        }
        final proof = HostPairingProtocol.pairingProof(
          hostId: request.hostId,
          deviceId: request.deviceId,
          invitationNonce: request.invitationNonce,
          timestampSeconds: request.timestampSeconds,
        );
        var validProof = false;
        try {
          validProof = await signatureVerifier.verify(
            publicKeySpki: request.publicKeySpki,
            message: proof,
            signatureDer: request.signatureDer,
          );
        } catch (_) {
          validProof = false;
        }
        if (!validProof) {
          invitation.failedProofAttempts++;
          if (invitation.failedProofAttempts >= _maxInviteProofAttempts) {
            _invitations.remove(request.invitationNonce);
          }
          throw const HostPairingException(HostPairingError.invalidProof);
        }
        if (_pending.length >= _maxPendingPairings) {
          throw const HostPairingException(
            HostPairingError.resourceLimitExceeded,
          );
        }

        _invitations.remove(request.invitationNonce);
        final now = _utcNow();
        final pending = _PendingPairingRecord(
          request: request,
          confirmationCode: HostPairingProtocol.confirmationCode(
            hostId: request.hostId,
            deviceId: request.deviceId,
            invitationNonce: request.invitationNonce,
          ),
          requestedAt: now,
          expiresAt: now.add(pendingLifetime),
        );
        _pending[request.deviceId] = pending;
        return _pendingView(pending);
      });

  Future<HostDeviceGrant> approvePending(
    String deviceId, {
    Set<HostGrantScope> scopes = const {HostGrantScope.readConnections},
    Map<String, Set<PermissionLevel>> connectionPermissions = const {},
  }) => _serialize(() async {
    await _ensureLoaded();
    _sweepExpired();
    final pending = _pending[deviceId];
    if (pending == null || pending.expiresAt.isBefore(_utcNow())) {
      throw const HostPairingException(HostPairingError.approvalRequired);
    }
    if (_grants.length >= _maxPairedDevices && !_grants.containsKey(deviceId)) {
      throw const HostPairingException(HostPairingError.resourceLimitExceeded);
    }
    final grant = HostDeviceGrant(
      deviceId: pending.request.deviceId,
      publicKeySpki: pending.request.publicKeySpki,
      displayName: pending.request.displayName,
      platform: pending.request.platform,
      approvedAt: _utcNow(),
      scopes: scopes,
      connectionPermissions: connectionPermissions,
    );
    await store.save(grant);
    _grants[deviceId] = grant;
    _revokedDevices.remove(deviceId);
    _pending.remove(deviceId);
    return grant;
  });

  Future<void> rejectPending(String deviceId) => _serialize(() async {
    await _ensureLoaded();
    _pending.remove(deviceId);
  });

  Future<HostAuthenticationChallenge> issueChallenge(
    String deviceId,
  ) => _serialize(() async {
    await _ensureLoaded();
    _sweepExpired();
    if (!_grants.containsKey(deviceId) || _revokedDevices.contains(deviceId)) {
      throw const HostPairingException(HostPairingError.notPaired);
    }
    if (_challenges.length >= _maxPendingPairings) {
      throw const HostPairingException(HostPairingError.resourceLimitExceeded);
    }
    String connectionId;
    do {
      connectionId = _newToken(24);
    } while (_challenges.containsKey(connectionId) ||
        _sessions.values.any(
          (session) => session.session.connectionId == connectionId,
        ));
    final challenge = _newToken(32);
    final expiresAt = _utcNow().add(challengeLifetime);
    _challenges[connectionId] = _ChallengeRecord(
      deviceId: deviceId,
      challenge: challenge,
      expiresAt: expiresAt,
    );
    return HostAuthenticationChallenge(
      hostId: identity.hostId,
      deviceId: deviceId,
      connectionId: connectionId,
      challenge: challenge,
      expiresAt: expiresAt,
    );
  });

  Future<HostAuthenticatedSession> completeChallenge({
    required String connectionId,
    required List<int> signatureDer,
  }) => _serialize(() async {
    await _ensureLoaded();
    _sweepExpired();
    final challenge = _challenges.remove(connectionId);
    if (challenge == null || challenge.expiresAt.isBefore(_utcNow())) {
      throw const HostPairingException(HostPairingError.unauthorized);
    }
    final grant = _activeGrant(challenge.deviceId);
    if (grant == null || signatureDer.length < 8 || signatureDer.length > 80) {
      throw const HostPairingException(HostPairingError.unauthorized);
    }
    final proof = HostPairingProtocol.authenticationProof(
      hostId: identity.hostId,
      deviceId: challenge.deviceId,
      connectionId: connectionId,
      challenge: challenge.challenge,
    );
    if (!await _verify(
      publicKeySpki: grant.publicKeySpki,
      message: proof,
      signatureDer: signatureDer,
    )) {
      throw const HostPairingException(HostPairingError.unauthorized);
    }
    if (_sessions.length >= _maxAuthenticatedSessions) {
      throw const HostPairingException(HostPairingError.resourceLimitExceeded);
    }
    String sessionId;
    do {
      sessionId = _newToken(32);
    } while (_sessions.containsKey(sessionId));
    final authenticatedAt = _utcNow();
    final session = HostAuthenticatedSession(
      deviceId: challenge.deviceId,
      sessionId: sessionId,
      connectionId: connectionId,
      authenticatedAt: authenticatedAt,
    );
    _sessions[sessionId] = _SessionRecord(
      session,
      lastActivity: authenticatedAt,
    );
    return session;
  });

  Future<HostAuthenticatedRequest> authenticateRequest(
    HostSignedRpcEnvelope envelope,
  ) => _serialize(() async {
    await _ensureLoaded();
    final now = _utcNow();
    final sessionRecord = _sessions[envelope.sessionId];
    if (sessionRecord == null ||
        sessionRecord.isExpired(now, sessionIdleTimeout, sessionLifetime)) {
      _sessions.remove(envelope.sessionId);
      throw const HostPairingException(HostPairingError.expiredSession);
    }
    final session = sessionRecord.session;
    if (_revokedDevices.contains(session.deviceId) ||
        envelope.hostId != identity.hostId ||
        envelope.deviceId != session.deviceId ||
        envelope.sessionId != session.sessionId ||
        !_timestampIsCurrent(envelope.timestampSeconds) ||
        !HostPairingProtocol.isToken(envelope.nonce) ||
        envelope.signatureDer.length < 8 ||
        envelope.signatureDer.length > 80) {
      throw const HostPairingException(HostPairingError.unauthorized);
    }
    final payloadBytes = utf8.encode(envelope.payload);
    if (payloadBytes.isEmpty || payloadBytes.length > 1024 * 1024) {
      throw const HostPairingException(HostPairingError.invalidRequest);
    }
    if (sessionRecord.seenNonces.contains(envelope.nonce)) {
      throw const HostPairingException(HostPairingError.replayedRequest);
    }
    if (sessionRecord.seenNonces.length >= _maxSessionNonces) {
      _sessions.remove(session.sessionId);
      throw const HostPairingException(HostPairingError.resourceLimitExceeded);
    }
    final grant = _activeGrant(session.deviceId);
    if (grant == null) {
      throw const HostPairingException(HostPairingError.unauthorized);
    }
    final proof = HostPairingProtocol.rpcRequestProof(
      hostId: envelope.hostId,
      deviceId: envelope.deviceId,
      sessionId: envelope.sessionId,
      timestampSeconds: envelope.timestampSeconds,
      nonce: envelope.nonce,
      payloadBytes: payloadBytes,
    );
    if (!await _verify(
      publicKeySpki: grant.publicKeySpki,
      message: proof,
      signatureDer: envelope.signatureDer,
    )) {
      throw const HostPairingException(HostPairingError.unauthorized);
    }
    sessionRecord.seenNonces.add(envelope.nonce);
    sessionRecord.lastActivity = now;
    return HostAuthenticatedRequest(
      deviceId: session.deviceId,
      sessionId: session.sessionId,
      payload: envelope.payload,
    );
  });

  Future<void> closeSession(String sessionId) => _serialize(() async {
    _sessions.remove(sessionId);
  });

  Future<void> closeConnection(String connectionId) => _serialize(() async {
    _challenges.remove(connectionId);
    _sessions.removeWhere(
      (_, session) => session.session.connectionId == connectionId,
    );
  });

  Future<void> revokeDevice(String deviceId) => _serialize(() async {
    await _ensureLoaded();
    if (!_grants.containsKey(deviceId)) {
      _pending.remove(deviceId);
      throw const HostPairingException(HostPairingError.notPaired);
    }
    _revokedDevices.add(deviceId);
    try {
      await store.remove(deviceId);
    } catch (_) {
      throw const HostPairingException(HostPairingError.storageFailure);
    }
    _grants.remove(deviceId);
    _pending.remove(deviceId);
    _challenges.removeWhere((_, challenge) => challenge.deviceId == deviceId);
    _sessions.removeWhere((_, session) => session.session.deviceId == deviceId);
    _revocations.add(deviceId);
    try {
      await setupCoordinator?.closeDevice(deviceId);
      await onDeviceRevoked?.call(deviceId);
    } catch (_) {
      throw const HostPairingException(
        HostPairingError.revocationCleanupFailed,
      );
    }
  });

  @override
  Future<bool> isAuthorized({
    required String deviceId,
    required String method,
    required JsonMap params,
  }) => _serialize(() async {
    await _ensureLoaded();
    final grant = _activeGrant(deviceId);
    if (grant == null) return false;
    if (method == 'host.hello' || method == 'host.status') return true;
    if (method == 'operation.read' || method.startsWith('setup.')) {
      return grant.scopes.contains(HostGrantScope.connectionSetup);
    }
    if (method == 'capability.search' || method == 'run.listRecent') {
      return grant.scopes.contains(HostGrantScope.readConnections);
    }
    if (method == 'runtime.connection.read') {
      final connectionId = params['connectionId'];
      if (!grant.scopes.contains(HostGrantScope.readConnections) ||
          connectionId is! String) {
        return false;
      }
      final permissions = grant.connectionPermissions[connectionId];
      return permissions == null
          ? grant.connectionPermissions.isEmpty
          : permissions.contains(PermissionLevel.read);
    }
    if (method == 'runtime.connection.invoke') {
      final connectionId = params['connectionId'];
      final permissionName = params['permissionLevel'];
      if (!grant.scopes.contains(HostGrantScope.readConnections) ||
          connectionId is! String ||
          permissionName is! String) {
        return false;
      }
      final permission = PermissionLevel.values.where(
        (value) => value.name == permissionName,
      );
      if (permission.length != 1 ||
          permission.single == PermissionLevel.unknown) {
        return false;
      }
      if (permission.single == PermissionLevel.read) {
        final permissions = grant.connectionPermissions[connectionId];
        return permissions == null
            ? grant.connectionPermissions.isEmpty
            : permissions.contains(PermissionLevel.read);
      }
      return grant.permitsInvocation(connectionId, permission.single);
    }
    if (method == 'run.invoke' ||
        method == 'run.subscribe' ||
        method == 'run.cancel' ||
        method == 'resource.read' ||
        method == 'prompt.get') {
      if (!grant.scopes.contains(HostGrantScope.readConnections)) return false;
      final connectionId = _connectionIdForRuntimeRequest(params);
      if (connectionId == null) {
        // run.subscribe/cancel are checked again by the dispatcher after it
        // resolves the device-owned RunId to its connection and permission.
        return method == 'run.subscribe' || method == 'run.cancel';
      }
      final permissionName = params['permissionLevel'];
      if (permissionName == null) {
        // The transport sees only the wire payload. The dispatcher performs
        // the decisive check after resolving the capability's declared level.
        return method != 'run.invoke';
      }
      final permission = PermissionLevel.values.where(
        (value) => value.name == permissionName,
      );
      if (permission.length != 1 ||
          permission.single == PermissionLevel.unknown) {
        return false;
      }
      if (permission.single == PermissionLevel.read) {
        final connectionGrant = grant.connectionPermissions[connectionId];
        return connectionGrant == null
            ? true
            : connectionGrant.contains(PermissionLevel.read);
      }
      return grant.permitsInvocation(connectionId, permission.single);
    }
    if (method == 'connection.list') {
      return grant.scopes.contains(HostGrantScope.readConnections);
    }
    if (method == 'connection.refresh') {
      final connectionId = params['connectionId'];
      if (!grant.scopes.contains(HostGrantScope.readConnections) ||
          connectionId is! String) {
        return false;
      }
      final permissions = grant.connectionPermissions[connectionId];
      return permissions == null
          ? grant.connectionPermissions.isEmpty
          : permissions.contains(PermissionLevel.read);
    }
    if (method == 'connection.remove' || method == 'connection.move') {
      final connectionId = params['connectionId'];
      return grant.scopes.contains(HostGrantScope.connectionManagement) &&
          connectionId is String &&
          grant.connectionPermissions.containsKey(connectionId);
    }
    if (method == 'activity.clear') {
      return grant.scopes.contains(HostGrantScope.activityClear);
    }
    if (method == 'manifest.get') {
      return grant.scopes.contains(HostGrantScope.readConnections);
    }
    if (method == 'manifest.save') {
      return grant.scopes.contains(HostGrantScope.connectionManagement);
    }
    if (method == 'manifest.readContent' ||
        method == 'manifest.exportContent') {
      return grant.scopes.contains(HostGrantScope.contentTransfer);
    }
    if (method.startsWith('account.')) {
      return grant.scopes.contains(HostGrantScope.account);
    }
    if (method.startsWith('terminal.')) {
      return grant.scopes.contains(HostGrantScope.terminal);
    }
    return false;
  });

  String? _connectionIdForRuntimeRequest(JsonMap params) {
    final direct = params['connectionId'];
    if (direct is String) return direct;
    final capability = params['capability'];
    if (capability is Map && capability['connection'] is Map) {
      final value = (capability['connection'] as Map)['value'];
      if (value is String) return value;
    }
    final ref = params['ref'];
    if (ref is Map && ref['capability'] is Map) {
      final nested = (ref['capability'] as Map)['connection'];
      if (nested is Map && nested['value'] is String) {
        return nested['value'] as String;
      }
    }
    return null;
  }

  Future<void> _ensureLoaded() => _loadOperation ??= _loadRecords();

  Future<void> _loadRecords() async {
    try {
      final records = await store.readAll();
      if (records.length > _maxPairedDevices ||
          records.map((record) => record.deviceId).toSet().length !=
              records.length) {
        throw const FormatException('Host pairing registry is invalid');
      }
      _grants.addEntries(
        records.map((record) => MapEntry(record.deviceId, record)),
      );
    } catch (_) {
      throw const HostPairingException(HostPairingError.storageFailure);
    }
  }

  HostDeviceGrant? _activeGrant(String deviceId) =>
      _revokedDevices.contains(deviceId) ? null : _grants[deviceId];

  bool _timestampIsCurrent(int timestampSeconds) {
    if (timestampSeconds < 0 || timestampSeconds > 9007199254740991) {
      return false;
    }
    final nowSeconds = _utcNow().millisecondsSinceEpoch ~/ 1000;
    return (nowSeconds - timestampSeconds).abs() <= requestClockSkew.inSeconds;
  }

  void _sweepExpired() {
    final now = _utcNow();
    _invitations.removeWhere(
      (_, value) => value.invitation.expiresAt.isBefore(now),
    );
    _pending.removeWhere((_, value) => value.expiresAt.isBefore(now));
    _challenges.removeWhere((_, value) => value.expiresAt.isBefore(now));
    _sessions.removeWhere(
      (_, value) => value.isExpired(now, sessionIdleTimeout, sessionLifetime),
    );
  }

  HostPendingPairing _pendingView(_PendingPairingRecord record) =>
      HostPendingPairing(
        deviceId: record.request.deviceId,
        displayName: record.request.displayName,
        platform: record.request.platform,
        confirmationCode: record.confirmationCode,
        requestedAt: record.requestedAt,
        expiresAt: record.expiresAt,
      );

  DateTime _utcNow() => _now().toUtc();

  String _newToken(int byteCount) => base64UrlEncode([
    for (var index = 0; index < byteCount; index++) _random.nextInt(256),
  ]).replaceAll('=', '');

  Future<bool> _verify({
    required List<int> publicKeySpki,
    required List<int> message,
    required List<int> signatureDer,
  }) async {
    try {
      return await signatureVerifier.verify(
        publicKeySpki: publicKeySpki,
        message: message,
        signatureDer: signatureDer,
      );
    } catch (_) {
      return false;
    }
  }

  Future<T> _serialize<T>(Future<T> Function() operation) {
    final result = _tail.then((_) => operation());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }
}

final class _InvitationRecord {
  _InvitationRecord(this.invitation);

  final HostPairingInvitation invitation;
  var failedProofAttempts = 0;
}

final class _PendingPairingRecord {
  const _PendingPairingRecord({
    required this.request,
    required this.confirmationCode,
    required this.requestedAt,
    required this.expiresAt,
  });

  final HostPairingRequest request;
  final String confirmationCode;
  final DateTime requestedAt;
  final DateTime expiresAt;
}

final class _ChallengeRecord {
  const _ChallengeRecord({
    required this.deviceId,
    required this.challenge,
    required this.expiresAt,
  });

  final String deviceId;
  final String challenge;
  final DateTime expiresAt;
}

final class _SessionRecord {
  _SessionRecord(this.session, {required this.lastActivity});

  final HostAuthenticatedSession session;
  final Set<String> seenNonces = {};
  DateTime lastActivity;

  bool isExpired(DateTime now, Duration idleTimeout, Duration lifetime) =>
      now.isBefore(session.authenticatedAt) ||
      now.difference(lastActivity) > idleTimeout ||
      now.difference(session.authenticatedAt) > lifetime;
}

HostDeviceGrant _readGrantEntry(String key, Object? value) {
  if (value is! String) {
    throw const FormatException('Host pairing registry is invalid');
  }
  final record = HostDeviceGrant.fromJson(jsonDecode(value));
  if (record.deviceId != key) {
    throw const FormatException('Host pairing registry is invalid');
  }
  return record;
}

Map<String, Object?> _readJsonObject(Object? value, Set<String> expectedKeys) {
  if (value is! Map ||
      value.keys.any((key) => key is! String) ||
      value.keys.length != expectedKeys.length ||
      !value.keys.toSet().containsAll(expectedKeys)) {
    throw const FormatException('Host pairing record is invalid');
  }
  return Map<String, Object?>.from(value);
}

List<String> _stringList(List value) {
  if (value.any((entry) => entry is! String) ||
      value.map((entry) => entry as String).toSet().length != value.length) {
    throw const FormatException('Host pairing record is invalid');
  }
  return value.cast<String>();
}

HostGrantScope _parseScope(String value) {
  for (final scope in HostGrantScope.values) {
    if (scope.name == value) return scope;
  }
  throw const FormatException('Host pairing grant is invalid');
}

PermissionLevel _parsePermission(String value) {
  for (final permission in PermissionLevel.values) {
    if (permission.name == value && permission != PermissionLevel.unknown) {
      return permission;
    }
  }
  throw const FormatException('Host pairing grant is invalid');
}

bool _isSafeDisplayName(String value) =>
    value.trim().isNotEmpty &&
    value.trim().length <= _pairingTextLimit &&
    !_controlCharacters.hasMatch(value);
