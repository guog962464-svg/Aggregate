import 'dart:async';
import 'dart:io';

import 'package:aggregate_contracts/aggregate_contracts.dart';

import '../platform/host/host_pairing_protocol.dart';
import '../platform/macos/host/host_control_port.dart';
import '../platform/macos/host/host_pairing_authority.dart';
import '../platform/macos/host/host_tls_identity.dart';
import '../platform/macos/host/host_wss_transport.dart';

/// A process-local Host fixture. It never opens a listener or reads Keychain.
final class Ui6InspectionHost
    implements
        HostControlPort,
        HostPairingControlPort,
        HostTlsIdentityRotationPort {
  final StreamController<HostStatus> _changes =
      StreamController<HostStatus>.broadcast(sync: true);
  HostStatus _status = const HostStatus(HostPhase.stopped);
  final List<HostDeviceGrant> _paired = [];
  final List<HostPendingPairing> _pending = [];
  final List<int> _pairedPublicKey = const [1, 3, 3, 7, 9, 2, 4, 8];
  final List<int> _pendingPublicKey = const [1, 3, 3, 7, 9, 2, 4, 9];
  var _grantCounter = 0;

  String get _pairedDeviceId =>
      HostPairingProtocol.deviceIdForPublicKey(_pairedPublicKey);
  String get _pendingDeviceId =>
      HostPairingProtocol.deviceIdForPublicKey(_pendingPublicKey);

  /// Kept as the pending request ID for existing preview callers.
  String get inspectionDeviceId => _pendingDeviceId;
  String get inspectionPendingDeviceId => _pendingDeviceId;
  String get inspectionPairedDeviceId => _pairedDeviceId;

  @override
  HostStatus get status => _status;

  @override
  Stream<HostStatus> watchStatus() => _changes.stream;

  @override
  Future<void> start() async {
    _setStatus(const HostStatus(HostPhase.running));
    if (_paired.isEmpty) {
      _paired.add(
        _grant(
          displayName: 'LGE AN10',
          scopes: const {
            HostGrantScope.readConnections,
            HostGrantScope.connectionSetup,
            HostGrantScope.connectionManagement,
          },
          connectionPermissions: const {
            'ui6-review-git': {
              PermissionLevel.read,
              PermissionLevel.localControl,
            },
            'ui6-review-mcp': {PermissionLevel.read},
            'ui6-review-music': {
              PermissionLevel.read,
              PermissionLevel.externalWrite,
            },
          },
        ),
      );
    }
    if (_pending.isEmpty) {
      final now = DateTime.now().toUtc();
      _pending.add(
        HostPendingPairing(
          deviceId: _pendingDeviceId,
          displayName: 'Pixel 9',
          platform: 'Android',
          confirmationCode: '482 193',
          requestedAt: now,
          expiresAt: now.add(const Duration(minutes: 5)),
        ),
      );
    }
  }

  @override
  Future<void> stop() async {
    _setStatus(const HostStatus(HostPhase.stopped));
  }

  void _setStatus(HostStatus status) {
    _status = status;
    _changes.add(status);
  }

  @override
  Future<HostWssPairingInvitation> createInvitation() async {
    final now = DateTime.now().toUtc();
    return HostWssPairingInvitation(
      invitation: HostPairingInvitation(
        hostId: 'host-00000000000000000000000000000001',
        certificateSha256:
            '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
        nonce: 'ui6-inspection-nonce',
        issuedAt: now,
        expiresAt: now.add(const Duration(minutes: 5)),
      ),
      endpoints: [
        HostWssEndpoint(
          address: InternetAddress.loopbackIPv4,
          port: 44321,
          interfaceIndex: 1,
        ),
      ],
    );
  }

  @override
  Future<List<HostPendingPairing>> pendingRequests() async =>
      List.unmodifiable(_pending);

  @override
  Future<void> rejectPending(String deviceId) async {
    _pending.removeWhere((item) => item.deviceId == deviceId);
  }

  @override
  Future<HostDeviceGrant> approvePending(
    String deviceId, {
    Set<HostGrantScope> scopes = const {HostGrantScope.readConnections},
    Map<String, Set<PermissionLevel>> connectionPermissions = const {},
  }) async {
    var displayName = '预览设备 ${++_grantCounter}';
    var publicKeySpki = _pendingPublicKey;
    for (final request in _pending) {
      if (request.deviceId == deviceId) {
        displayName = request.displayName;
        break;
      }
    }
    _pending.removeWhere((item) => item.deviceId == deviceId);
    final grant = _grant(
      displayName: displayName,
      deviceId: deviceId,
      publicKeySpki: publicKeySpki,
      scopes: scopes,
      connectionPermissions: connectionPermissions,
    );
    _paired.removeWhere((item) => item.deviceId == deviceId);
    _paired.add(grant);
    return grant;
  }

  @override
  Future<HostDeviceGrant> updateDeviceGrant(
    String deviceId, {
    required Set<HostGrantScope> scopes,
    required Map<String, Set<PermissionLevel>> connectionPermissions,
  }) async {
    var displayName = '预览设备 ${++_grantCounter}';
    var publicKeySpki = _pairedPublicKey;
    for (final grant in _paired) {
      if (grant.deviceId == deviceId) {
        displayName = grant.displayName;
        publicKeySpki = grant.publicKeySpki;
        break;
      }
    }
    final grant = _grant(
      displayName: displayName,
      deviceId: deviceId,
      publicKeySpki: publicKeySpki,
      scopes: scopes,
      connectionPermissions: connectionPermissions,
    );
    final index = _paired.indexWhere((item) => item.deviceId == deviceId);
    if (index >= 0) _paired[index] = grant;
    return grant;
  }

  @override
  Future<List<HostDeviceGrant>> pairedDevices() async =>
      List.unmodifiable(_paired);

  @override
  Future<void> revokeDevice(String deviceId) async {
    _paired.removeWhere((item) => item.deviceId == deviceId);
  }

  HostDeviceGrant _grant({
    required String displayName,
    String? deviceId,
    List<int>? publicKeySpki,
    Set<HostGrantScope> scopes = const {HostGrantScope.readConnections},
    Map<String, Set<PermissionLevel>> connectionPermissions = const {},
  }) => HostDeviceGrant(
    deviceId: deviceId ?? _pairedDeviceId,
    publicKeySpki: publicKeySpki ?? _pairedPublicKey,
    displayName: displayName,
    platform: 'android',
    approvedAt: DateTime.now().toUtc(),
    scopes: scopes,
    connectionPermissions: connectionPermissions,
  );

  @override
  Future<HostTlsIdentity> rotate() async => const HostTlsIdentity(
    hostId: 'host-00000000000000000000000000000001',
    certificatePem: 'PREVIEW ONLY',
    privateKeyPem: 'PREVIEW ONLY',
    certificateSha256:
        '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
  );

  Future<void> dispose() => _changes.close();
}
