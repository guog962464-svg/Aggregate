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
  final List<int> _publicKey = const [1, 3, 3, 7, 9, 2, 4, 8];
  var _grantCounter = 0;

  String get _deviceId => HostPairingProtocol.deviceIdForPublicKey(_publicKey);

  @override
  HostStatus get status => _status;

  @override
  Stream<HostStatus> watchStatus() => _changes.stream;

  @override
  Future<void> start() async {
    _setStatus(const HostStatus(HostPhase.running));
    if (_paired.isEmpty) {
      _paired.add(_grant(scopes: const {HostGrantScope.readConnections}));
    }
    if (_pending.isEmpty) {
      final now = DateTime.now().toUtc();
      _pending.add(
        HostPendingPairing(
          deviceId: _deviceId,
          displayName: 'UI 检查 Android',
          platform: 'android',
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
    _pending.removeWhere((item) => item.deviceId == deviceId);
    final grant = _grant(
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
    final grant = _grant(
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
    Set<HostGrantScope> scopes = const {HostGrantScope.readConnections},
    Map<String, Set<PermissionLevel>> connectionPermissions = const {},
  }) => HostDeviceGrant(
    deviceId: _deviceId,
    publicKeySpki: _publicKey,
    displayName: '已配对预览设备 ${++_grantCounter}',
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
