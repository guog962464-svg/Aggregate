import 'dart:async';
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
    const encodedMcpInvitation = String.fromEnvironment(
      'aggregateHostMcpFixtureInvitationBase64',
    );
    expect(encodedMcpInvitation, isNotEmpty);
    final mcpInvitation = AndroidHostInvitation.fromQrPayload(
      utf8.decode(base64Decode(encodedMcpInvitation)),
    );
    expect(mcpInvitation.hostId, invitation.hostId);
    expect(mcpInvitation.certificateSha256, invitation.certificateSha256);
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
      await expectLater(
        setup.saveConnectionSetup(report.draftId),
        throwsA(isA<StateError>()),
      );
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
      final discardSelection =
          await (setup as ConnectionSetupExecutableSelectionPort)
              .detectExecutableSelection('netease-music');
      final discardedDraft = await setup.testConnectionSetup(
        ConnectionSetupDraft(
          adapterId: 'netease-music',
          executableReference: discardSelection!.reference,
          values: {'appId': 'fixture-app', 'privateKey': secret},
          spec: ConnectionSpec(
            kind: ConnectionKind.cli,
            label: 'Android isolated discarded fixture',
            executionTarget: target,
          ),
        ),
      );
      expect(discardedDraft.canSave, isTrue);
      await setup.discardConnectionSetup(discardedDraft.draftId);
      await expectLater(
        setup.saveConnectionSetup(discardedDraft.draftId),
        throwsA(isA<StateError>()),
      );
      final hostMetadata = await File('${directory.path}/hosts.json')
          .readAsString();
      expect(hostMetadata, isNot(contains(secret)));

      final remoteConnections = await runtime.listConnections();
      final savedHostConnections = remoteConnections
          .where((item) => item.executionTarget == target)
          .toList(growable: false);
      expect(savedHostConnections, hasLength(5));
      expect(
        savedHostConnections.any(
          (item) => item.id.value == connection.id.value,
        ),
        isTrue,
      );
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
      final plainCliConnection = savedHostConnections.singleWhere(
        (item) => item.label == 'Android isolated plain CLI fixture',
      );
      final plainCliCapability = remoteCapabilities.singleWhere(
        (capability) =>
            capability.id.connection.value == plainCliConnection.id.value &&
            capability.title == 'Fixture CLI echo',
      );
      expect(plainCliCapability.permission, PermissionLevel.externalWrite);
      final ungrantedCliRun = await runtime.invoke(
        plainCliCapability.id,
        const {'value': 'ungranted'},
        permissionGranted: true,
      );
      final ungrantedCliResult = await runtime
          .watchRun(ungrantedCliRun.id)
          .firstWhere((event) => event.state == RunState.failed)
          .timeout(const Duration(seconds: 10));
      expect(
        ungrantedCliResult.failure?.code,
        RuntimeErrorCode.permissionDenied,
      );
      for (final fixture in [
        (
          label: 'Android isolated HTTP MCP fixture',
          text: 'http-fixture-resource',
        ),
        (
          label: 'Android isolated stdio MCP fixture',
          text: 'stdio-fixture-resource',
        ),
      ]) {
        final fixtureConnection = savedHostConnections.singleWhere(
          (item) => item.label == fixture.label,
        );
        final resource = remoteCapabilities.singleWhere(
          (capability) =>
              capability.id.connection.value == fixtureConnection.id.value &&
              capability.id.kind == CapabilityKind.mcpResource,
        );
        final blocks = await runtime.readResource(
          ResourceRef(resource.id, Uri.parse(resource.id.name)),
        );
        expect(
          blocks.map((block) => '${block.value}').join('\n'),
          contains(fixture.text),
        );
        final prompt = remoteCapabilities.singleWhere(
          (capability) =>
              capability.id.connection.value == fixtureConnection.id.value &&
              capability.id.kind == CapabilityKind.mcpPrompt,
        );
        final promptBlocks = await runtime.getPrompt(
          PromptRef(prompt.id),
          const {},
        );
        expect(
          promptBlocks.map((block) => '${block.value}').join('\n'),
          contains('prompt-fixture:${fixture.text}'),
        );
      }

      final ncmFixtureConnection = savedHostConnections.singleWhere(
        (item) => item.label == 'Android isolated Netease CLI fixture',
      );
      final stateCapability = remoteCapabilities.singleWhere(
        (capability) =>
            capability.id.connection.value == ncmFixtureConnection.id.value &&
            capability.presentation == 'music.state',
      );
      final stateRun = await runtime.invoke(stateCapability.id, const {});
      final stateResult = await runtime
          .watchRun(stateRun.id)
          .firstWhere(
            (event) => const {
              RunState.succeeded,
              RunState.failed,
              RunState.cancelled,
              RunState.timedOut,
              RunState.outcomeUnknown,
            }.contains(event.state),
          )
          .timeout(const Duration(seconds: 15));
      expect(
        stateResult.state,
        RunState.succeeded,
        reason: stateResult.failure?.message ?? 'Host CLI action failed',
      );
      expect(
        stateResult.blocks.map((block) => '${block.value}').join('\n'),
        contains('fixture-playback-idle'),
      );

      expect(
        (await runtime.readAccount(ncmFixtureConnection.id))?.state,
        AccountState.signedOut,
      );
      final login = await runtime.beginAccountLogin(ncmFixtureConnection.id);
      final loginOutput = await runtime
          .watchTerminal(login)
          .first
          .timeout(const Duration(seconds: 15));
      expect(loginOutput, contains('fixture login is disabled'));
      expect(await runtime.waitAccountLogin(login), 1);
      await runtime.closeTerminal(login);

      final terminal = await runtime.openTerminal(
        CliCommand(ncmFixtureConnection.id, const ['fixture-tui']),
      );
      final terminalOutput = StringBuffer();
      final terminalReady = Completer<void>();
      final terminalEchoed = Completer<void>();
      final terminalResized = Completer<void>();
      final terminalSubscription = runtime.watchTerminal(terminal).listen((
        chunk,
      ) {
        terminalOutput.write(chunk);
        if (chunk.contains('FIXTURE_TUI_READY') && !terminalReady.isCompleted) {
          terminalReady.complete();
        }
        if (terminalOutput.toString().contains(
              'FIXTURE_TUI_ECHO:fixture-input',
            ) &&
            !terminalEchoed.isCompleted) {
          terminalEchoed.complete();
        }
        if (terminalOutput.toString().contains('FIXTURE_TUI_SIZE:96x32') &&
            !terminalResized.isCompleted) {
          terminalResized.complete();
        }
      });
      try {
        await terminalReady.future.timeout(const Duration(seconds: 15));
        await runtime.resizeTerminal(terminal, 96, 32);
        await runtime.writeTerminal(terminal, 'fixture-input\n');
        await terminalEchoed.future.timeout(const Duration(seconds: 15));
        await terminalResized.future.timeout(const Duration(seconds: 15));
        expect(
          terminalOutput.toString(),
          contains('FIXTURE_TUI_ECHO:fixture-input'),
        );
        expect(terminalOutput.toString(), contains('FIXTURE_TUI_SIZE:96x32'));
      } finally {
        await runtime.closeTerminal(terminal);
        await terminalSubscription.cancel();
      }

      final interruptedTerminal = await runtime.openTerminal(
        CliCommand(ncmFixtureConnection.id, const ['fixture-terminal-held']),
      );
      final interruptedReady = Completer<void>();
      final interruptedSubscription = runtime
          .watchTerminal(interruptedTerminal)
          .listen((chunk) {
            if (chunk.contains('FIXTURE_TUI_HELD_READY') &&
                !interruptedReady.isCompleted) {
              interruptedReady.complete();
            }
          });
      try {
        await interruptedReady.future.timeout(const Duration(seconds: 15));
        await manager.disconnect(invitation.hostId);
        expect(manager.statusFor(invitation.hostId), AndroidHostStatus.offline);
        final disconnectedConnections = (await runtime.listConnections())
            .where((item) => item.executionTarget == target)
            .toList(growable: false);
        expect(disconnectedConnections, hasLength(5));
        expect(
          disconnectedConnections.every(
            (item) => item.status == ConnectionStatus.unavailable,
          ),
          isTrue,
        );
        await runtime.closeTerminal(interruptedTerminal);
      } finally {
        await interruptedSubscription.cancel();
      }

      final rotatedIdentity = await manager.rotateDeviceIdentity();
      expect(rotatedIdentity.localHostRecordsCleared, isTrue);
      expect(rotatedIdentity.deviceId, isNot(receipt.deviceId));
      await manager.requestPairing(
        invitation: mcpInvitation,
        displayName: 'Android MCP integration fixture',
      );
      AndroidPairedHost? mcpHost;
      AndroidHostPairingException? mcpPendingApproval;
      for (var attempt = 0; attempt < 40; attempt++) {
        try {
          mcpHost = await manager.completePairing(
            invitation: mcpInvitation,
            displayName: 'Android MCP integration fixture',
          );
          mcpPendingApproval = null;
          break;
        } on AndroidHostPairingException catch (error) {
          if (error.failure != AndroidHostPairingFailure.approvalRequired) {
            rethrow;
          }
          mcpPendingApproval = error;
          await Future<void>.delayed(const Duration(milliseconds: 150));
        }
      }
      expect(
        mcpPendingApproval,
        isNull,
        reason: 'Host fixture did not approve the isolated MCP identity',
      );
      final pairedMcpHost = mcpHost!;
      expect(pairedMcpHost.hostId, mcpInvitation.hostId);

      final mcpConnections = (await runtime.listConnections())
          .where((item) => item.executionTarget == target)
          .toList(growable: false);
      expect(mcpConnections, hasLength(4));
      for (final label in [
        'Android isolated Netease CLI fixture',
        'Android isolated plain CLI fixture',
        'Android isolated HTTP MCP fixture',
        'Android isolated stdio MCP fixture',
      ]) {
        expect(mcpConnections.any((item) => item.label == label), isTrue);
      }
      final mcpCapabilities = await runtime.searchCapabilities(
        const SearchQuery(''),
      );
      final plainCli = mcpConnections.singleWhere(
        (item) => item.label == 'Android isolated plain CLI fixture',
      );
      final plainCliTool = mcpCapabilities.singleWhere(
        (capability) =>
            capability.id.connection.value == plainCli.id.value &&
            capability.title == 'Fixture CLI echo',
      );
      expect(plainCliTool.permission, PermissionLevel.externalWrite);
      final unconfirmedCliRun = await runtime.invoke(plainCliTool.id, const {
        'value': 'unconfirmed',
      });
      final unconfirmedCli = await runtime
          .watchRun(unconfirmedCliRun.id)
          .firstWhere((event) => event.state == RunState.failed)
          .timeout(const Duration(seconds: 10));
      expect(unconfirmedCli.failure?.code, RuntimeErrorCode.permissionDenied);
      final confirmedCliRun = await runtime.invoke(plainCliTool.id, const {
        'value': 'android-call',
      }, permissionGranted: true);
      final confirmedCli = await runtime
          .watchRun(confirmedCliRun.id)
          .firstWhere(
            (event) => const {
              RunState.succeeded,
              RunState.failed,
              RunState.cancelled,
              RunState.timedOut,
              RunState.outcomeUnknown,
            }.contains(event.state),
          )
          .timeout(const Duration(seconds: 15));
      expect(
        confirmedCli.state,
        RunState.succeeded,
        reason: confirmedCli.failure?.message ?? 'CLI action call failed',
      );
      expect(
        confirmedCli.blocks.map((block) => '${block.value}').join('\n'),
        contains('plain-cli:android-call'),
      );
      for (final connection in mcpConnections.where(
        (item) =>
            item.kind == ConnectionKind.mcpHttp ||
            item.kind == ConnectionKind.mcpStdio,
      )) {
        final tool = mcpCapabilities.singleWhere(
          (capability) =>
              capability.id.connection.value == connection.id.value &&
              capability.id.kind == CapabilityKind.mcpTool &&
              capability.title == 'fixture_echo',
        );
        expect(tool.permission, PermissionLevel.externalWrite);
        final unconfirmedRun = await runtime.invoke(tool.id, const {
          'value': 'unconfirmed',
        });
        final unconfirmed = await runtime
            .watchRun(unconfirmedRun.id)
            .firstWhere((event) => event.state == RunState.failed)
            .timeout(const Duration(seconds: 10));
        expect(unconfirmed.failure?.code, RuntimeErrorCode.permissionDenied);

        final confirmedRun = await runtime.invoke(tool.id, const {
          'value': 'android-call',
        }, permissionGranted: true);
        final confirmed = await runtime
            .watchRun(confirmedRun.id)
            .firstWhere(
              (event) => const {
                RunState.succeeded,
                RunState.failed,
                RunState.cancelled,
                RunState.timedOut,
                RunState.outcomeUnknown,
              }.contains(event.state),
            )
            .timeout(const Duration(seconds: 15));
        expect(
          confirmed.state,
          RunState.succeeded,
          reason: confirmed.failure?.message ?? 'MCP tool call failed',
        );
        expect(
          confirmed.blocks.map((block) => '${block.value}').join('\n'),
          contains('tool-fixture:android-call'),
        );
      }

      const dropControlPort = int.fromEnvironment(
        'aggregateHostSetupFixtureDropControlPort',
      );
      expect(dropControlPort, inInclusiveRange(1, 65535));
      final abruptDrop = manager.statusChanges.firstWhere(
        (change) =>
            change.hostId == pairedMcpHost.hostId &&
            change.status == AndroidHostStatus.offline,
      );
      final abruptReconnect = manager.statusChanges.firstWhere(
        (change) =>
            change.hostId == pairedMcpHost.hostId &&
            change.status == AndroidHostStatus.online,
      );
      final controlClient = HttpClient();
      try {
        final request = await controlClient
            .postUrl(
              Uri(
                scheme: 'http',
                host: '127.0.0.1',
                port: dropControlPort,
                path: '/drop-active-tunnels',
              ),
            )
            .timeout(const Duration(seconds: 5));
        final response = await request.close().timeout(
          const Duration(seconds: 5),
        );
        expect(response.statusCode, HttpStatus.noContent);
        await response.drain<void>();
      } finally {
        controlClient.close(force: true);
      }
      await abruptDrop.timeout(const Duration(seconds: 10));
      expect(
        manager.statusFor(pairedMcpHost.hostId),
        AndroidHostStatus.offline,
      );
      expect(manager.isConnected(pairedMcpHost.hostId), isFalse);
      final unexpectedlyOfflineConnections = (await runtime.listConnections())
          .where((item) => item.executionTarget == target)
          .toList(growable: false);
      expect(unexpectedlyOfflineConnections, hasLength(4));
      expect(
        unexpectedlyOfflineConnections.every(
          (item) => item.status == ConnectionStatus.unavailable,
        ),
        isTrue,
      );

      await abruptReconnect.timeout(const Duration(seconds: 30));
      expect(manager.statusFor(pairedMcpHost.hostId), AndroidHostStatus.online);
      expect(manager.isConnected(pairedMcpHost.hostId), isTrue);
      final afterAbruptReconnect = (await runtime.listConnections())
          .where((item) => item.executionTarget == target)
          .toList(growable: false);
      expect(afterAbruptReconnect, hasLength(4));
      expect(
        afterAbruptReconnect.every(
          (item) => item.status == ConnectionStatus.ready,
        ),
        isTrue,
      );

      await manager.disconnect(pairedMcpHost.hostId);
      expect(
        manager.statusFor(pairedMcpHost.hostId),
        AndroidHostStatus.offline,
      );
      final offlineConnections = (await runtime.listConnections())
          .where((item) => item.executionTarget == target)
          .toList(growable: false);
      expect(offlineConnections, hasLength(4));
      expect(
        offlineConnections.every(
          (item) => item.status == ConnectionStatus.unavailable,
        ),
        isTrue,
      );
      final reconnectedHost = await manager.connect(pairedMcpHost.hostId);
      expect(reconnectedHost.hostId, pairedMcpHost.hostId);
      expect(manager.isConnected(pairedMcpHost.hostId), isTrue);
      final reconnectedConnections = (await runtime.listConnections())
          .where((item) => item.executionTarget == target)
          .toList(growable: false);
      expect(reconnectedConnections, hasLength(4));
      expect(
        reconnectedConnections.every(
          (item) => item.status == ConnectionStatus.ready,
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
