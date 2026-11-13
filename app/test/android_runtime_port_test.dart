import 'dart:async';
import 'dart:io';

import 'package:aggregate/platform/android/android_runtime_port.dart';
import 'package:aggregate/platform/android/android_host_manager.dart';
import 'package:aggregate/platform/android/android_host_pairing_client.dart';
import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Android runtime keeps local HTTP MCP and Host terminal separate',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'aggregate-android-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final runtime = await AndroidRuntimePort.open(dataDirectory: directory);
      addTearDown(runtime.dispose);
      expect(runtime.isPreview, isFalse);
      expect(runtime.features.connectionKinds, {ConnectionKind.mcpHttp});
      expect(runtime.connectionAdapters.map((item) => item.id), ['mcp-http']);
      expect(runtime.features.terminal, isTrue);
      expect(runtime.features.localFilePreview, isFalse);
      expect(runtime.features.localFileReveal, isFalse);
      expect(await runtime.listConnections(), isEmpty);
      expect(await runtime.searchCapabilities(const SearchQuery('')), isEmpty);
      expect(await runtime.listRecentRuns(), isEmpty);
      await expectLater(
        runtime.addConnection(
          const ConnectionSpec(
            kind: ConnectionKind.cli,
            label: 'Unavailable',
            executable: '/bin/sh',
          ),
        ),
        throwsStateError,
      );
      await expectLater(
        runtime.readActionManifestFile('/Users/guo/Desktop/actions.json'),
        throwsUnsupportedError,
      );
      await expectLater(
        runtime.previewLocalFile('/Users/guo/Desktop/output.txt'),
        throwsUnsupportedError,
      );
      await expectLater(
        runtime.revealLocalFile('/Users/guo/Desktop/output.txt'),
        throwsUnsupportedError,
      );
    },
  );

  test(
    'routes paired Host capabilities and streams remote run events',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'aggregate-android-host-runtime-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final manager = _FakeRemoteHostManager();
      final runtime = await AndroidRuntimePort.open(
        dataDirectory: directory,
        hostManager: manager,
      );
      addTearDown(runtime.dispose);

      final connections = await runtime.listConnections();
      expect(connections, hasLength(1));
      expect(connections.single.executionTarget, ExecutionTarget.host(_hostId));
      expect(connections.single.id.value, 'remote:$_hostId:mac-cli');

      final capabilities = await runtime.searchCapabilities(
        const SearchQuery('search'),
      );
      expect(capabilities, hasLength(1));
      expect(
        capabilities.single.id.connection.value,
        connections.single.id.value,
      );
      expect(
        manager.methods,
        containsAll(['connection.list', 'capability.search']),
      );

      final handle = await runtime.invoke(capabilities.single.id, const {});
      final completed = await runtime
          .watchRun(handle.id)
          .firstWhere((event) => event.state == RunState.succeeded);
      expect(completed.runId, handle.id);
      expect(completed.blocks.single.value, 'done on Mac');
      expect(manager.methods, containsAll(['run.invoke', 'run.subscribe']));
      expect(
        manager.lastInvocationCapability,
        manager.hostCapability.id.toJson(),
      );
      expect(
        (await runtime.listRecentRuns()).single.latest.state,
        RunState.succeeded,
      );

      final runtimeChanged = runtime.changes.first;
      await manager.disconnect(_hostId);
      await runtimeChanged;
      final offlineConnection = (await runtime.listConnections()).single;
      expect(offlineConnection.status, ConnectionStatus.unavailable);
      expect(offlineConnection.diagnostic, contains('离线'));
      expect(
        await runtime.searchCapabilities(const SearchQuery('search')),
        isEmpty,
      );
      final offlineRun = await runtime.invoke(capabilities.single.id, const {});
      final offlineResult = await runtime
          .watchRun(offlineRun.id)
          .firstWhere((event) => event.state == RunState.failed);
      expect(offlineResult.failure?.code, RuntimeErrorCode.connectionFailed);
      expect(
        manager.methods.where((method) => method == 'run.invoke'),
        hasLength(1),
      );
    },
  );

  test(
    'revoked Host authorization never reroutes a connection to Android',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'aggregate-android-host-revoked-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final manager = _FakeRemoteHostManager();
      final runtime = await AndroidRuntimePort.open(
        dataDirectory: directory,
        hostManager: manager,
      );
      addTearDown(runtime.dispose);

      final connection = (await runtime.listConnections()).single;
      final capability = (await runtime.searchCapabilities(
        const SearchQuery('search'),
      )).single;
      expect(connection.executionTarget, ExecutionTarget.host(_hostId));

      final changed = runtime.changes.first;
      manager.revokeAuthorization();
      await changed;

      final unavailable = (await runtime.listConnections()).single;
      expect(unavailable.id.value, connection.id.value);
      expect(unavailable.executionTarget, ExecutionTarget.host(_hostId));
      expect(unavailable.status, ConnectionStatus.unavailable);
      expect(unavailable.diagnostic, contains('认证'));
      expect(
        await runtime.searchCapabilities(const SearchQuery('search')),
        isEmpty,
      );

      final run = await runtime.invoke(capability.id, const {});
      final result = await runtime
          .watchRun(run.id)
          .firstWhere((event) => event.state == RunState.failed);
      expect(result.failure?.code, RuntimeErrorCode.connectionFailed);
      expect(manager.methods, isNot(contains('run.invoke')));
      expect(await runtime.listConnections(), hasLength(1));
    },
  );

  test(
    'routes Host activity, account, and terminal APIs by source ID',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'aggregate-android-host-target-runtime-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final manager = _FakeRemoteHostManager();
      final remoteRunId = const RunId('mac-history-1');
      final occurredAt = DateTime.utc(2026, 11, 14, 1, 2, 3);
      manager.recentRuns = [
        RunSummary(
          remoteRunId,
          manager.hostCapability.id,
          RunEvent(
            runId: remoteRunId,
            sequence: 4,
            state: RunState.succeeded,
            occurredAt: occurredAt,
          ),
        ),
      ];
      final runtime = await AndroidRuntimePort.open(
        dataDirectory: directory,
        hostManager: manager,
      );
      addTearDown(runtime.dispose);

      final connection = (await runtime.listConnections()).single;
      final activity = await runtime.listRecentRuns();
      expect(activity, hasLength(1));
      expect(activity.single.id.value, 'remote-run:$_hostId:mac-history-1');
      expect(activity.single.capability.connection.value, connection.id.value);
      expect(activity.single.latest.occurredAt, occurredAt);
      expect(
        runtime.capabilityDisplayName(activity.single.capability),
        'search',
      );
      expect(runtime.connectionDisplayName(connection.id), 'Music CLI');
      expect(manager.methods, contains('run.listRecent'));

      final account = await runtime.readAccount(connection.id);
      expect(account?.state, AccountState.signedIn);
      expect(account?.nickname, 'listener');
      await expectLater(
        runtime.logoutAccount(connection.id, confirmed: false),
        throwsStateError,
      );
      expect(manager.methods, isNot(contains('account.logout')));
      expect(
        (await runtime.logoutAccount(connection.id, confirmed: true)).state,
        AccountState.signedOut,
      );
      final login = await runtime.beginAccountLogin(connection.id);
      expect(await runtime.waitAccountLogin(login), 0);
      expect(manager.lastAccountConnectionId, 'mac-cli');
      expect(manager.lastAccountSessionId, 'terminal-account-1');

      final loginOutput = await runtime.watchTerminal(login).first;
      expect(loginOutput, 'ready:terminal-account-1');
      await runtime.closeTerminal(login);

      final terminal = await runtime.openTerminal(
        CliCommand(connection.id, const ['search', '--format', 'json']),
      );
      final terminalOutput = await runtime.watchTerminal(terminal).first;
      expect(terminalOutput, 'ready:terminal-cli-1');
      expect(manager.lastTerminalOpen?['connectionId'], 'mac-cli');
      expect(manager.lastTerminalOpen?['arguments'], [
        'search',
        '--format',
        'json',
      ]);
      await runtime.writeTerminal(terminal, 'query');
      await runtime.resizeTerminal(terminal, 101, 37);
      await runtime.interruptTerminal(terminal);
      await runtime.closeTerminal(terminal);
      expect(
        manager.methods,
        containsAll([
          'terminal.open',
          'terminal.subscribe',
          'terminal.write',
          'terminal.resize',
          'terminal.interrupt',
          'terminal.close',
        ]),
      );
      expect(
        manager.sideEffectCalls,
        containsAll([
          'account.beginLogin',
          'account.logout',
          'terminal.open',
          'terminal.write',
          'terminal.resize',
          'terminal.interrupt',
          'terminal.close',
        ]),
      );
      expect(manager.sideEffectCalls, isNot(contains('terminal.subscribe')));
      await runtime.clearActivity();
      expect(manager.methods, isNot(contains('activity.clear')));
      expect(await runtime.listRecentRuns(), hasLength(1));

      final interrupted = await runtime.openTerminal(
        CliCommand(connection.id, const []),
      );
      final interruptedOutput = <String>[];
      final terminalSubscription = runtime
          .watchTerminal(interrupted)
          .listen(interruptedOutput.add);
      await Future<void>.delayed(Duration.zero);
      final changed = runtime.changes.first;
      await manager.disconnect(_hostId);
      await changed;
      await Future<void>.delayed(Duration.zero);
      expect(interruptedOutput.join(), contains('Mac Host 连接已断开'));
      await expectLater(
        runtime.writeTerminal(interrupted, 'must not route'),
        throwsStateError,
      );
      await terminalSubscription.cancel();
    },
  );

  test(
    'loads Host setup fields and keeps executable paths on the Host',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'aggregate-android-host-setup-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final manager = _FakeRemoteHostManager();
      final runtime = await AndroidRuntimePort.open(
        dataDirectory: directory,
        hostManager: manager,
      );
      addTearDown(runtime.dispose);

      final targets = await runtime.listSetupTargets();
      expect(targets, hasLength(2));
      expect(targets.first.target, ExecutionTarget.device);
      expect(targets.last.target, ExecutionTarget.host(_hostId));
      final localSetup = await runtime.setupForTarget(ExecutionTarget.device);
      expect(localSetup.connectionAdapters.map((item) => item.id), [
        'mcp-http',
      ]);

      final hostSetup = await runtime.setupForTarget(
        ExecutionTarget.host(_hostId),
      );
      expect(hostSetup.connectionAdapters.map((item) => item.id), [
        'netease-music',
        'cli',
        'mcp-stdio',
        'mcp-http',
      ]);
      final executable =
          await (hostSetup as ConnectionSetupExecutableSelectionPort)
              .detectExecutableSelection('cli', executableName: 'custom-cli');
      expect(executable?.reference, 'opaque-executable-ref');
      expect(executable?.path, isNull);

      final report = await hostSetup.testConnectionSetup(
        ConnectionSetupDraft(
          adapterId: 'cli',
          executableReference: executable!.reference,
          spec: ConnectionSpec(
            kind: ConnectionKind.cli,
            label: 'Custom CLI',
            executionTarget: ExecutionTarget.host(_hostId),
            arguments: const ['--version'],
          ),
        ),
      );
      expect(report.canSave, isTrue);
      expect(
        manager.lastSetupTestDraft?['executableRef'],
        executable.reference,
      );
      expect(manager.lastSetupTestDraft.toString(), isNot(contains('/Users/')));

      final connection = await hostSetup.saveConnectionSetup(report.draftId);
      expect(connection.id.value, 'remote:$_hostId:mac-custom-cli');
      expect(connection.executionTarget, ExecutionTarget.host(_hostId));
      expect(connection.location, 'Mac Host');

      manager.failSetupSave = true;
      final unknownReport = await hostSetup.testConnectionSetup(
        ConnectionSetupDraft(
          adapterId: 'cli',
          executableReference: executable.reference,
          spec: ConnectionSpec(
            kind: ConnectionKind.cli,
            label: 'Uncertain CLI',
            executionTarget: ExecutionTarget.host(_hostId),
          ),
        ),
      );
      await expectLater(
        hostSetup.saveConnectionSetup(unknownReport.draftId),
        throwsA(isA<ConnectionSetupOutcomeUnknown>()),
      );
      await expectLater(
        hostSetup.saveConnectionSetup(unknownReport.draftId),
        throwsA(isA<ConnectionSetupOutcomeUnknown>()),
      );
      expect(
        manager.methods.where((method) => method == 'setup.save'),
        hasLength(2),
      );
    },
  );

  test(
    'a scoped Host permission denial does not disable other Host scopes',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'aggregate-android-host-scoped-permission-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final manager = _FakeRemoteHostManager()
        ..status = AndroidHostStatus.permissionDenied;
      final runtime = await AndroidRuntimePort.open(
        dataDirectory: directory,
        hostManager: manager,
      );
      addTearDown(runtime.dispose);

      final hostTarget = (await runtime.listSetupTargets()).last;
      expect(hostTarget.selectable, isTrue);
      expect(
        (await runtime.setupForTarget(hostTarget.target)).connectionAdapters,
        hasLength(4),
      );
    },
  );

  test('rejects malformed optional Host adapter metadata', () async {
    final directory = await Directory.systemTemp.createTemp(
      'aggregate-android-host-invalid-adapter-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final manager = _FakeRemoteHostManager()
      ..invalidAdapterOptionalField = true;
    final runtime = await AndroidRuntimePort.open(
      dataDirectory: directory,
      hostManager: manager,
    );
    addTearDown(runtime.dispose);

    await expectLater(
      runtime.setupForTarget(ExecutionTarget.host(_hostId)),
      throwsFormatException,
    );
  });
}

const _hostId = 'host-0123456789abcdef0123456789abcdef';

final class _FakeRemoteHostManager implements AndroidHostManagerPort {
  final _notifications = StreamController<Map<String, Object?>>.broadcast(
    sync: true,
  );
  final _statusChanges = StreamController<AndroidHostStatusChange>.broadcast();
  final hostCapability = const Capability(
    id: CapabilityId(
      ConnectionId('mac-cli'),
      CapabilityKind.mcpTool,
      'cap-opaque-token',
    ),
    title: 'search',
    description: 'Search on Mac',
    permission: PermissionLevel.read,
  );
  final methods = <String>[];
  final sideEffectCalls = <String>[];
  var connected = true;
  var authorizationRevoked = false;
  var failSetupSave = false;
  var invalidAdapterOptionalField = false;
  AndroidHostStatus status = AndroidHostStatus.online;
  Map<String, Object?>? lastInvocationCapability;
  Map<String, Object?>? lastSetupTestDraft;
  Map<String, Object?>? lastTerminalOpen;
  String? lastAccountConnectionId;
  String? lastAccountSessionId;
  List<RunSummary> recentRuns = const [];

  @override
  List<AndroidPairedHost> get hosts => [
    AndroidPairedHost(
      hostId: _hostId,
      displayName: 'Office Mac',
      certificateSha256: List.filled(64, 'a').join(),
      endpoints: [
        AndroidHostEndpoint(Uri.parse('wss://192.168.1.10:47321/host')),
      ],
      pairedAt: DateTime.utc(2026),
      lastConnectedAt: DateTime.utc(2026),
    ),
  ];

  @override
  bool isConnected(String hostId) => connected && hostId == _hostId;

  @override
  AndroidHostStatus statusFor(String hostId) => hostId == _hostId
      ? authorizationRevoked
            ? AndroidHostStatus.authenticationInvalid
            : connected
            ? status
            : AndroidHostStatus.offline
      : AndroidHostStatus.offline;

  @override
  Stream<AndroidHostStatusChange> get statusChanges => _statusChanges.stream;

  @override
  Future<Map<String, Object?>> call(
    String hostId,
    String method,
    Map<String, Object?> params, {
    bool sideEffect = false,
  }) async {
    expect(hostId, _hostId);
    methods.add(method);
    if (sideEffect) sideEffectCalls.add(method);
    switch (method) {
      case 'connection.list':
        return {
          'connections': [
            const Connection(
              id: ConnectionId('mac-cli'),
              kind: ConnectionKind.cli,
              label: 'Music CLI',
              location: 'Mac 本机 CLI',
            ).toJson(),
          ],
        };
      case 'capability.search':
        return {
          'capabilities': [hostCapability.toJson()],
        };
      case 'run.invoke':
        lastInvocationCapability = (params['capability']! as Map)
            .cast<String, Object?>();
        return {'run': const RunHandle(RunId('mac-run-1')).toJson()};
      case 'run.subscribe':
        _notifications.add({
          'jsonrpc': '2.0',
          'method': 'run.event',
          'params': {
            'subscriptionId': 'sub-opaque',
            'sequence': 3,
            'event': RunEvent(
              runId: const RunId('mac-run-1'),
              sequence: 3,
              state: RunState.succeeded,
              occurredAt: DateTime.now().toUtc(),
              blocks: const [ResultBlock(ResultKind.text, 'done on Mac')],
            ).toJson(),
          },
        });
        return {
          'subscriptionId': 'sub-opaque',
          'runId': {'value': 'mac-run-1'},
        };
      case 'run.listRecent':
        return {
          'runs': [for (final run in recentRuns) run.toJson()],
        };
      case 'account.read':
        lastAccountConnectionId = params['connectionId']! as String;
        return {
          'snapshot': {'state': 'signedIn', 'nickname': 'listener'},
        };
      case 'account.beginLogin':
        lastAccountConnectionId = params['connectionId']! as String;
        return {
          'terminalId': 'terminal-account-1',
          'sessionId': 'terminal-account-1',
        };
      case 'account.waitLogin':
        lastAccountSessionId = params['sessionId']! as String;
        return {'exitCode': 0};
      case 'account.logout':
        return {
          'snapshot': {'state': 'signedOut'},
        };
      case 'terminal.open':
        lastTerminalOpen = Map.unmodifiable(params);
        return {'terminalId': 'terminal-cli-1', 'sessionId': 'terminal-cli-1'};
      case 'terminal.subscribe':
        final terminalId = params['terminalId']! as String;
        final subscriptionId = 'sub-$terminalId';
        _notifications.add({
          'jsonrpc': '2.0',
          'method': 'terminal.event',
          'params': {
            'subscriptionId': subscriptionId,
            'sequence': 0,
            'event': {
              'terminalId': terminalId,
              'sequence': 0,
              'kind': 'output',
              'text': 'ready:$terminalId',
            },
          },
        });
        return {'subscriptionId': subscriptionId, 'terminalId': terminalId};
      case 'setup.adapters':
        return {
          'adapters': [
            {
              'id': 'netease-music',
              'label': '网易云音乐',
              'kind': 'cli',
              'fields': [
                {
                  'key': 'appId',
                  'label': 'App ID',
                  'kind': 'text',
                  'required': true,
                  'readFileContent': false,
                },
                {
                  'key': 'privateKey',
                  'label': 'Private Key',
                  'kind': 'secret',
                  'required': true,
                  'readFileContent': true,
                },
              ],
              'defaultLabel': invalidAdapterOptionalField ? 42 : '网易云音乐',
              'description': '在 Mac Host 配置',
              'showGenericCliFields': false,
              'autoDetectExecutable': true,
            },
            for (final adapter in [
              ('cli', '自定义 CLI', 'cli', true),
              ('mcp-stdio', 'stdio MCP', 'mcpStdio', true),
              ('mcp-http', 'HTTP MCP', 'mcpHttp', false),
            ])
              {
                'id': adapter.$1,
                'label': adapter.$2,
                'kind': adapter.$3,
                'fields': <Object?>[],
                'showGenericCliFields': adapter.$4,
                'autoDetectExecutable': false,
              },
          ],
        };
      case 'setup.resolveExecutable':
        return {
          'detected': true,
          'executableRef': 'opaque-executable-ref',
          'displayLocation': 'Mac 主机 · CLI 程序',
          'expiresAt': DateTime.now()
              .add(const Duration(minutes: 10))
              .toUtc()
              .toIso8601String(),
        };
      case 'setup.test':
        lastSetupTestDraft = (params['draft']! as Map).cast<String, Object?>();
        return {
          'canSave': true,
          'draftHandle': 'opaque-setup-draft',
          'checks': [
            {'label': '程序检查', 'status': 'passed', 'detail': '检查通过。'},
          ],
        };
      case 'setup.save':
        if (failSetupSave) throw const AndroidHostRpcException(-32004);
        return {
          'connectionId': 'mac-custom-cli',
          'kind': 'cli',
          'label': 'Custom CLI',
          'status': 'ready',
          'executionLocation': 'Mac 主机',
        };
      case 'setup.discard':
        return const {'discarded': true};
      default:
        return const {};
    }
  }

  @override
  Stream<Map<String, Object?>> watchNotifications(String hostId) =>
      _notifications.stream;

  @override
  Future<AndroidHostPairingReceipt> requestPairing({
    required AndroidHostInvitation invitation,
    required String displayName,
  }) => throw UnimplementedError();

  @override
  Future<AndroidPairedHost> completePairing({
    required AndroidHostInvitation invitation,
    required String displayName,
  }) => throw UnimplementedError();

  @override
  Future<AndroidPairedHost> connect(String hostId) =>
      throw UnimplementedError();

  @override
  Future<void> disconnect(String hostId) async {
    connected = false;
    status = AndroidHostStatus.offline;
    _statusChanges.add(
      AndroidHostStatusChange(hostId, AndroidHostStatus.offline),
    );
  }

  void revokeAuthorization() {
    connected = false;
    authorizationRevoked = true;
    _statusChanges.add(
      AndroidHostStatusChange(_hostId, AndroidHostStatus.authenticationInvalid),
    );
  }

  @override
  Future<void> remove(String hostId) async => disconnect(hostId);

  @override
  Future<void> dispose() async {
    await _notifications.close();
    await _statusChanges.close();
  }
}
