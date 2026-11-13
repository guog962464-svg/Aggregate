import 'dart:async';
import 'dart:convert';

import 'package:aggregate/platform/android/android_host_manager.dart';
import 'package:aggregate/platform/android/android_host_pairing_client.dart';
import 'package:aggregate/platform/host/host_pairing_protocol.dart';
import 'package:aggregate/platform/host/host_wss_protocol.dart';
import 'package:aggregate/features/settings/android_host_settings_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _hostId = 'host-0123456789abcdef0123456789abcdef';
final _pin = List<String>.filled(64, 'b').join();
final _expires = DateTime.now().toUtc().add(const Duration(minutes: 5));
final _payload = jsonEncode({
  'version': HostPairingProtocol.version,
  'hostId': _hostId,
  'certificateSha256': _pin,
  'nonce': 'AAAAAAAAAAAAAAAAAAAAAA',
  'expiresAt': _expires.toIso8601String(),
  'serviceType': hostBonjourServiceType,
  'endpoints': [
    {'uri': 'wss://192.168.1.20:48123/host'},
  ],
});

void main() {
  testWidgets('scans, requests Mac approval and completes pairing', (
    tester,
  ) async {
    final manager = _FakeHostManager();
    addTearDown(manager.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AndroidHostSettingsPanel(
              hostManager: manager,
              scanQr: (_) async => _payload,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('扫描二维码'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField).at(1)).controller!.text,
      _payload,
    );

    await tester.tap(find.text('请求配对'));
    await tester.pumpAndSettle();
    expect(find.text('123456'), findsOneWidget);
    expect(manager.requestedDisplayName, '这台手机');

    await tester.tap(find.text('已批准，连接'));
    await tester.pumpAndSettle();
    expect(find.text('Mac Host 已配对并连接'), findsOneWidget);
    expect(find.text('家庭 Mac'), findsOneWidget);
    expect(manager.isConnected(_hostId), isTrue);
    manager.statusOverride = AndroidHostStatus.permissionDenied;
    manager.statusChangesController.add(
      AndroidHostStatusChange(_hostId, AndroidHostStatus.permissionDenied),
    );
    await tester.pumpAndSettle();
    expect(find.text('权限拒绝 · 1 个局域网地址'), findsOneWidget);
  });
}

final class _FakeHostManager implements AndroidHostManagerPort {
  final _hosts = <AndroidPairedHost>[];
  final _connected = <String>{};
  final _statusChanges = StreamController<AndroidHostStatusChange>.broadcast();
  String? requestedDisplayName;
  AndroidHostStatus? statusOverride;

  StreamController<AndroidHostStatusChange> get statusChangesController =>
      _statusChanges;

  @override
  List<AndroidPairedHost> get hosts => List.unmodifiable(_hosts);

  @override
  bool isConnected(String hostId) => _connected.contains(hostId);

  @override
  AndroidHostStatus statusFor(String hostId) =>
      statusOverride ??
      (_connected.contains(hostId)
          ? AndroidHostStatus.online
          : AndroidHostStatus.offline);

  @override
  Stream<AndroidHostStatusChange> get statusChanges => _statusChanges.stream;

  @override
  Future<Map<String, Object?>> call(
    String hostId,
    String method,
    Map<String, Object?> params, {
    bool sideEffect = false,
  }) async => throw UnimplementedError();

  @override
  Stream<Map<String, Object?>> watchNotifications(String hostId) =>
      const Stream.empty();

  @override
  Future<AndroidHostPairingReceipt> requestPairing({
    required AndroidHostInvitation invitation,
    required String displayName,
  }) async {
    requestedDisplayName = displayName;
    return AndroidHostPairingReceipt(
      hostId: invitation.hostId,
      deviceId: 'device-0123456789abcdef0123456789abcdef',
      confirmationCode: '123456',
      expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 2)),
    );
  }

  @override
  Future<AndroidPairedHost> completePairing({
    required AndroidHostInvitation invitation,
    required String displayName,
  }) async {
    final host = AndroidPairedHost(
      hostId: invitation.hostId,
      displayName: '家庭 Mac',
      certificateSha256: invitation.certificateSha256,
      endpoints: invitation.endpoints,
      pairedAt: DateTime.now().toUtc(),
      lastConnectedAt: DateTime.now().toUtc(),
    );
    _hosts.add(host);
    _connected.add(host.hostId);
    return host;
  }

  @override
  Future<AndroidPairedHost> connect(String hostId) async => _hosts.single;

  @override
  Future<void> disconnect(String hostId) async => _connected.remove(hostId);

  @override
  Future<void> remove(String hostId) async {
    _hosts.removeWhere((host) => host.hostId == hostId);
    _connected.remove(hostId);
  }

  @override
  Future<void> dispose() => _statusChanges.close();
}
