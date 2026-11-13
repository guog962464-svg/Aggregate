import 'dart:async';
import 'dart:io';

import 'package:aggregate/platform/macos/mac_host_settings_panel.dart';
import 'package:aggregate/platform/host/host_pairing_protocol.dart';
import 'package:aggregate/platform/macos/host/host_control_port.dart';
import 'package:aggregate/platform/macos/host/host_pairing_authority.dart';
import 'package:aggregate/platform/macos/host/host_tls_identity.dart';
import 'package:aggregate/platform/macos/host/host_wss_transport.dart';
import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

void main() {
  testWidgets('rotates Mac Host identity after revoking grants and stopping', (
    tester,
  ) async {
    final events = <String>[];
    final host = _FakeHostControl(events: events);
    final pairing = _FakePairingControl(events: events);
    final identity = _FakeIdentityRotation(events);
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MacHostSettingsPanel(
              hostControl: host,
              pairingControl: pairing,
              identityRotation: identity,
              loadConnections: () async => const [],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('启动 Host'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('允许连接向导'));
    await tester.pumpAndSettle();
    expect(pairing._grants, hasLength(1));

    await tester.tap(find.text('轮换 Mac Host 身份'));
    await tester.pumpAndSettle();
    expect(identity.calls, 0);
    expect(find.text('撤销授权并轮换'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(pairing.revokedDeviceIds, isEmpty);
    expect(host.stopCalls, 0);
    expect(identity.calls, 0);

    await tester.tap(find.text('轮换 Mac Host 身份'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('撤销授权并轮换'));
    await tester.pumpAndSettle();

    expect(pairing.revokedDeviceIds, [pairing.deviceId]);
    expect(pairing._grants, isEmpty);
    expect(host.stopCalls, 1);
    expect(identity.calls, 1);
    expect(events, ['revoke', 'stop', 'rotate']);
    expect(host.status.phase, HostPhase.stopped);
    expect(find.text('状态：已关闭'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await host.close();
  });

  testWidgets('does not stop Host or rotate identity when revocation fails', (
    tester,
  ) async {
    final host = _FakeHostControl();
    final pairing = _FakePairingControl()..failRevocation = true;
    final identity = _FakeIdentityRotation([]);
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MacHostSettingsPanel(
              hostControl: host,
              pairingControl: pairing,
              identityRotation: identity,
              loadConnections: () async => const [],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('启动 Host'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('允许连接向导'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('轮换 Mac Host 身份'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('撤销授权并轮换'));
    await tester.pumpAndSettle();

    expect(host.stopCalls, 0);
    expect(identity.calls, 0);
    expect(pairing.revokedDeviceIds, isEmpty);
    expect(find.textContaining('Host 身份未轮换'), findsOneWidget);
    expect(host.status.phase, HostPhase.running);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await host.close();
  });

  testWidgets('starts Host, presents invitation, approves and revokes device', (
    tester,
  ) async {
    final host = _FakeHostControl();
    final pairing = _FakePairingControl();
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MacHostSettingsPanel(
              hostControl: host,
              pairingControl: pairing,
              loadConnections: () async => const [],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('启动 Host'));
    await tester.pumpAndSettle();
    expect(host.startCalls, 1);
    expect(find.text('状态：运行中'), findsOneWidget);
    expect(find.text('Pixel 9'), findsOneWidget);

    await tester.tap(find.text('生成新邀请'));
    await tester.pumpAndSettle();
    expect(pairing.invitationCalls, 1);
    expect(find.byType(QrImageView), findsOneWidget);

    await tester.tap(find.text('允许连接向导'));
    await tester.pumpAndSettle();
    expect(pairing.approvedScopes, {
      HostGrantScope.readConnections,
      HostGrantScope.connectionSetup,
    });
    expect(find.text('待处理设备'), findsOneWidget);
    expect(find.text('Pixel 9'), findsOneWidget);

    await tester.tap(find.text('修改权限'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('连接向导'));
    await tester.tap(find.text('保存权限'));
    await tester.pumpAndSettle();
    expect(pairing.updatedDeviceIds, [pairing.deviceId]);
    expect(pairing.approvedScopes, {HostGrantScope.readConnections});

    await tester.tap(find.text('撤销').last);
    await tester.pumpAndSettle();
    expect(pairing.revokedDeviceIds, isEmpty);
    await tester.tap(find.text('撤销设备'));
    await tester.pumpAndSettle();
    expect(pairing.revokedDeviceIds, [pairing.deviceId]);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await host.close();
  });

  testWidgets('approves selected scopes and per-connection permissions', (
    tester,
  ) async {
    final host = _FakeHostControl();
    final pairing = _FakePairingControl();
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MacHostSettingsPanel(
              hostControl: host,
              pairingControl: pairing,
              loadConnections: () async => const [
                Connection(
                  id: ConnectionId('host-connection-1'),
                  kind: ConnectionKind.cli,
                  label: 'Mac CLI',
                  location: '/Applications/tool',
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('启动 Host'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('自定义权限'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('连接管理'));
    await tester.tap(find.text('终端'));
    await tester.tap(find.text('Mac CLI'));
    await tester.pumpAndSettle();
    final localControl = find.text('本机控制');
    await tester.ensureVisible(localControl);
    await tester.pumpAndSettle();
    await tester.tap(localControl);
    await tester.pumpAndSettle();
    await tester.tap(find.text('批准所选权限'));
    await tester.pumpAndSettle();

    expect(pairing.approvedScopes, {
      HostGrantScope.readConnections,
      HostGrantScope.connectionManagement,
      HostGrantScope.terminal,
    });
    expect(pairing.approvedConnectionPermissions, {
      'host-connection-1': {PermissionLevel.read, PermissionLevel.localControl},
    });
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await host.close();
  });
}

final class _FakeHostControl implements HostControlPort {
  _FakeHostControl({this._events});

  final StreamController<HostStatus> _changes =
      StreamController<HostStatus>.broadcast(sync: true);
  final List<String>? _events;
  HostStatus _status = const HostStatus(HostPhase.stopped);
  var startCalls = 0;
  var stopCalls = 0;

  @override
  HostStatus get status => _status;

  @override
  Stream<HostStatus> watchStatus() => Stream<HostStatus>.multi((sink) {
    sink.add(_status);
    final subscription = _changes.stream.listen(sink.add);
    sink.onCancel = subscription.cancel;
  });

  @override
  Future<void> start() async {
    startCalls++;
    _status = const HostStatus(HostPhase.running);
    _changes.add(_status);
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    _events?.add('stop');
    _status = const HostStatus(HostPhase.stopped);
    _changes.add(_status);
  }

  Future<void> close() => _changes.close();
}

final class _FakePairingControl implements HostPairingControlPort {
  static const _publicKey = [1, 2, 3, 4, 5, 6];

  _FakePairingControl({this._events})
    : deviceId = HostPairingProtocol.deviceIdForPublicKey(_publicKey),
      _pending = [
        HostPendingPairing(
          deviceId: HostPairingProtocol.deviceIdForPublicKey(_publicKey),
          displayName: 'Pixel 9',
          platform: 'android',
          confirmationCode: '482913',
          requestedAt: DateTime.utc(2026, 11, 13),
          expiresAt: DateTime.utc(2026, 11, 13, 0, 5),
        ),
      ];

  final String deviceId;
  final List<String>? _events;
  final List<HostPendingPairing> _pending;
  final List<HostDeviceGrant> _grants = [];
  var invitationCalls = 0;
  var failRevocation = false;
  Set<HostGrantScope> approvedScopes = const {};
  Map<String, Set<PermissionLevel>> approvedConnectionPermissions = const {};
  final List<String> updatedDeviceIds = [];
  final List<String> revokedDeviceIds = [];

  @override
  Future<HostWssPairingInvitation> createInvitation() async {
    invitationCalls++;
    final now = DateTime.utc(2026, 11, 13);
    return HostWssPairingInvitation(
      invitation: HostPairingInvitation(
        hostId: 'host-0123456789abcdef0123456789abcdef',
        certificateSha256: List.filled(64, 'a').join(),
        nonce: 'invite-nonce',
        issuedAt: now,
        expiresAt: now.add(const Duration(minutes: 5)),
      ),
      endpoints: [
        HostWssEndpoint(
          address: InternetAddress.loopbackIPv4,
          port: 43123,
          interfaceIndex: 1,
        ),
      ],
    );
  }

  @override
  Future<List<HostPendingPairing>> pendingRequests() async =>
      List.unmodifiable(_pending);

  @override
  Future<void> rejectPending(String requestedDeviceId) async {
    _pending.removeWhere((request) => request.deviceId == requestedDeviceId);
  }

  @override
  Future<HostDeviceGrant> approvePending(
    String requestedDeviceId, {
    Set<HostGrantScope> scopes = const {HostGrantScope.readConnections},
    Map<String, Set<PermissionLevel>> connectionPermissions = const {},
  }) async {
    approvedScopes = Set.unmodifiable(scopes);
    approvedConnectionPermissions = connectionPermissions;
    _pending.removeWhere((request) => request.deviceId == requestedDeviceId);
    final grant = HostDeviceGrant(
      deviceId: deviceId,
      publicKeySpki: _publicKey,
      displayName: 'Pixel 9',
      platform: 'android',
      approvedAt: DateTime.utc(2026, 11, 13),
      scopes: scopes,
      connectionPermissions: connectionPermissions,
    );
    _grants.add(grant);
    return grant;
  }

  @override
  Future<HostDeviceGrant> updateDeviceGrant(
    String requestedDeviceId, {
    required Set<HostGrantScope> scopes,
    required Map<String, Set<PermissionLevel>> connectionPermissions,
  }) async {
    updatedDeviceIds.add(requestedDeviceId);
    approvedScopes = Set.unmodifiable(scopes);
    approvedConnectionPermissions = connectionPermissions;
    final index = _grants.indexWhere(
      (grant) => grant.deviceId == requestedDeviceId,
    );
    if (index < 0) throw StateError('device is not paired');
    final previous = _grants[index];
    final updated = HostDeviceGrant(
      deviceId: previous.deviceId,
      publicKeySpki: previous.publicKeySpki,
      displayName: previous.displayName,
      platform: previous.platform,
      approvedAt: previous.approvedAt,
      scopes: scopes,
      connectionPermissions: connectionPermissions,
    );
    _grants[index] = updated;
    return updated;
  }

  @override
  Future<List<HostDeviceGrant>> pairedDevices() async =>
      List.unmodifiable(_grants);

  @override
  Future<void> revokeDevice(String requestedDeviceId) async {
    if (failRevocation) throw StateError('simulated revoke failure');
    _events?.add('revoke');
    revokedDeviceIds.add(requestedDeviceId);
    _grants.removeWhere((grant) => grant.deviceId == requestedDeviceId);
  }
}

final class _FakeIdentityRotation implements HostTlsIdentityRotationPort {
  _FakeIdentityRotation(this.events);

  final List<String> events;
  var calls = 0;

  @override
  Future<HostTlsIdentity> rotate() async {
    calls++;
    events.add('rotate');
    return const HostTlsIdentity(
      hostId: 'host-0123456789abcdef0123456789abcdef',
      certificatePem: 'certificate',
      privateKeyPem: 'private-key',
      certificateSha256: 'certificate-sha256',
    );
  }
}
