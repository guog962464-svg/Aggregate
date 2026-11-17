import 'dart:convert';
import 'dart:io';

import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:aggregate/platform/android/android_host_device_identity.dart';
import 'package:aggregate/platform/android/android_host_discovery.dart';
import 'package:aggregate/platform/android/android_host_manager.dart';
import 'package:aggregate/platform/android/android_host_pairing_client.dart';
import 'package:aggregate/platform/android/android_runtime_port.dart';
import 'package:aggregate/platform/android/android_runtime_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Android Keystore completes isolated Host connection setup', (
    _,
  ) async {
    const encodedInvitation = String.fromEnvironment(
      'aggregateHostSetupFixtureInvitationBase64',
    );
    expect(encodedInvitation, isNotEmpty);
    final invitation = AndroidHostInvitation.fromQrPayload(
      utf8.decode(base64Decode(encodedInvitation)),
    );
    final directory = await Directory.systemTemp.createTemp(
      'aggregate-android-host-setup-',
    );
    final manager = AndroidHostManager(
      AndroidRuntimeStore(directory),
      pairingClient: AndroidHostPairingClient(
        identity: const AndroidHostDeviceIdentity(),
      ),
      discovery: const _NoopHostDiscovery(),
    );
    final runtime = await AndroidRuntimePort.open(
      dataDirectory: directory,
      hostManager: manager,
    );
    try {
      final receipt = await manager.requestPairing(
        invitation: invitation,
        displayName: 'LGE Android isolated fixture',
      );
      expect(receipt.deviceId, matches(RegExp(r'^device-[a-f0-9]{32}$')));
      expect(receipt.confirmationCode, matches(RegExp(r'^\d{6}$')));

      AndroidPairedHost? host;
      AndroidHostPairingException? pendingApproval;
      for (var attempt = 0; attempt < 40; attempt++) {
        try {
          host = await manager.completePairing(
            invitation: invitation,
            displayName: 'LGE Android isolated fixture',
          );
          pendingApproval = null;
          break;
        } on AndroidHostPairingException catch (error) {
          if (error.failure != AndroidHostPairingFailure.approvalRequired) {
            rethrow;
          }
          pendingApproval = error;
          await Future<void>.delayed(const Duration(milliseconds: 150));
        }
      }
      expect(
        pendingApproval,
        isNull,
        reason: 'Host fixture did not approve pairing',
      );
      expect(host!.hostId, invitation.hostId);
      expect(manager.isConnected(invitation.hostId), isTrue);

      final target = ExecutionTarget.host(invitation.hostId);
      final setup = await runtime.setupForTarget(target);
      expect(
        setup.connectionAdapters.map((adapter) => adapter.id),
        contains('netease-music'),
      );
      final executable = await (setup as ConnectionSetupExecutableSelectionPort)
          .detectExecutableSelection('netease-music');
      expect(executable?.displayLocation, 'Mac 主机 · ncm-cli');
      expect(executable?.path, isNull);

      const encodedFixtureSecret = String.fromEnvironment(
        'aggregateHostSetupFixtureSecretBase64',
      );
      expect(encodedFixtureSecret, isNotEmpty);
      final secret = utf8.decode(base64Decode(encodedFixtureSecret));
      final report = await setup.testConnectionSetup(
        ConnectionSetupDraft(
          adapterId: 'netease-music',
          executableReference: executable!.reference,
          values: {'appId': 'fixture-app', 'privateKey': secret},
          spec: ConnectionSpec(
            kind: ConnectionKind.cli,
            label: 'Android isolated physical fixture',
            executionTarget: target,
          ),
        ),
      );
      expect(report.canSave, isTrue);
      expect(report.checks.map((check) => check.label), [
        '程序与配置',
        '账号登录',
        '搜索接口',
      ]);
      expect(
        report.checks.every(
          (check) =>
              !check.detail.contains(secret) &&
              !check.detail.contains('fake-bin') &&
              !check.detail.contains('/Users/'),
        ),
        isTrue,
      );

      final connection = await setup.saveConnectionSetup(report.draftId);
      expect(
        connection.id.value,
        matches(
          RegExp(
            '^remote:${RegExp.escape(invitation.hostId)}:'
            r'connection-[0-9]+-[0-9]+$',
          ),
        ),
      );
      expect(connection.label, 'Android isolated physical fixture');
      expect(connection.executionTarget, target);
      expect(connection.location, 'Mac Host');
      expect(connection.status, ConnectionStatus.ready);
      final hostMetadata = await File('${directory.path}/hosts.json')
          .readAsString();
      expect(hostMetadata, isNot(contains(secret)));

      final remoteConnections = await runtime.listConnections();
      final savedHostConnections = remoteConnections
          .where((item) => item.executionTarget == target)
          .toList(growable: false);
      expect(savedHostConnections, hasLength(1));
      expect(savedHostConnections.single.id.value, connection.id.value);
      final hostCapabilityResponse = await manager.call(
        invitation.hostId,
        'capability.search',
        const {'query': ''},
      );
      expect(hostCapabilityResponse['capabilities'], isA<List>());
      expect(hostCapabilityResponse['capabilities']! as List, isNotEmpty);
      final remoteCapabilities = await runtime.searchCapabilities(
        const SearchQuery(''),
      );
      expect(
        remoteCapabilities.any(
          (capability) => capability.id.connection.value == connection.id.value,
        ),
        isTrue,
      );
    } finally {
      await runtime.dispose();
      await directory.delete(recursive: true);
    }
  });
}

final class _NoopHostDiscovery implements AndroidHostDiscoveryPort {
  const _NoopHostDiscovery();

  @override
  Future<List<AndroidHostEndpoint>> discover(String hostId) async => const [];
}
