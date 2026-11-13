import 'dart:async';
import 'dart:io';

import 'package:aggregate/features/settings/mac_host_settings_panel.dart';
import 'package:aggregate/platform/host/host_pairing_protocol.dart';
import 'package:aggregate/platform/macos/host/host_control_port.dart';
import 'package:aggregate/platform/macos/host/host_pairing_authority.dart';
import 'package:aggregate/platform/macos/host/host_wss_transport.dart';
import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

void main() {
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
}

final class _FakeHostControl implements HostControlPort {
  final StreamController<HostStatus> _changes =
      StreamController<HostStatus>.broadcast(sync: true);
  HostStatus _status = const HostStatus(HostPhase.stopped);
  var startCalls = 0;

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
    _status = const HostStatus(HostPhase.stopped);
    _changes.add(_status);
  }

  Future<void> close() => _changes.close();
}

final class _FakePairingControl implements HostPairingControlPort {
  static const _publicKey = [1, 2, 3, 4, 5, 6];

  _FakePairingControl()
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
  final List<HostPendingPairing> _pending;
  final List<HostDeviceGrant> _grants = [];
  var invitationCalls = 0;
  Set<HostGrantScope> approvedScopes = const {};
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
  Future<List<HostDeviceGrant>> pairedDevices() async =>
      List.unmodifiable(_grants);

  @override
  Future<void> revokeDevice(String requestedDeviceId) async {
    revokedDeviceIds.add(requestedDeviceId);
    _grants.removeWhere((grant) => grant.deviceId == requestedDeviceId);
  }
}
