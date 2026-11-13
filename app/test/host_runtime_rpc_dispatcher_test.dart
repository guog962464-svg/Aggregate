import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:aggregate_connectors/aggregate_connectors.dart';
import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:aggregate/platform/macos/host/host_operation_ledger.dart';
import 'package:aggregate/platform/macos/host/host_rpc_protocol.dart';
import 'package:aggregate/platform/macos/host/host_runtime_rpc_dispatcher.dart';
import 'package:aggregate/platform/macos/host/host_setup_rpc_dispatcher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late _Runtime runtime;
  late _Authorization authorization;
  late HostRuntimeRpcDispatcher dispatcher;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'aggregate-host-runtime-rpc-',
    );
    runtime = _Runtime();
    authorization = _Authorization();
    final ledger = await FileHostOperationLedger.open(
      File('${directory.path}/operations.json'),
    );
    dispatcher = HostRuntimeRpcDispatcher(
      runtime: runtime,
      accounts: runtime,
      setupDispatcher: const _NoopDispatcher(),
      ledger: ledger,
      authorization: authorization,
    );
  });

  tearDown(() async {
    await runtime.events.close();
    for (final output in runtime.terminalOutputs.values) {
      if (!output.isClosed) await output.close();
    }
    await directory.delete(recursive: true);
  });

  Future<Map<String, Object?>> call(
    String method,
    Map<String, Object?> params, {
    String id = 'request-1',
    String? sessionId,
    void Function(JsonMap notification)? notify,
  }) async => jsonDecode(
    (await dispatcher.dispatch(
      _frame(method, params, id: id),
      authenticatedDeviceId: 'device-1',
      sessionId: sessionId,
      notify: notify,
    ))!,
  ) as Map<String, Object?>;

  Future<Capability> exposedCapability(String title) async {
    final response = await call('capability.search', {'query': ''});
    final result = response['result']! as Map<String, Object?>;
    final capabilities = result['capabilities']! as List;
    return Capability.fromJson(
      capabilities.cast<Map<String, Object?>>().singleWhere(
        (item) => item['title'] == title,
      ),
    );
  }

  test('lists safe connection metadata without returning Mac paths', () async {
    final response = await call('connection.list', const {});
    final connections =
        (response['result']! as Map<String, Object?>)['connections']! as List;
    final connection = connections.single as Map<String, Object?>;
    expect(connection['label'], 'Host CLI');
    expect(connection['location'], 'Mac 本机 CLI');
    expect(connection.toString(), isNot(contains('/Users/host')));
    expect(connection.containsKey('diagnostic'), isFalse);
  });

  test(
    'capability results use opaque IDs and redact sensitive locations',
    () async {
      final capability = await exposedCapability('Remote file');
      expect(capability.id.name, startsWith('cap-'));
      final response = await call('capability.search', {'query': ''});
      expect(response.toString(), isNot(contains('secret-value')));
      expect(response.toString(), isNot(contains('/Users/host/private')));
      expect(response.toString(), isNot(contains('resource?token=')));
    },
  );

  test('manifest editing uses an opaque executable reference', () async {
    final sourceManifest = ConnectorManifest.neteaseCli(
      '/Users/host/private/bin/cli',
    ).toJson();
    ((sourceManifest['actions']! as List).first as Map)['argv'] = [
      'search',
      '--api-key',
      'private-secret',
      '--output',
      '/Users/host/private/result.json',
    ];
    runtime.actionManifest = sourceManifest;

    final loaded = await call('manifest.get', {'connectionId': 'connection-1'});
    final loadResult = loaded['result']! as Map<String, Object?>;
    final executableRef = loadResult['executableRef']! as String;
    expect(executableRef, startsWith('exec-'));
    final manifest = loadResult['manifest']! as Map<String, Object?>;
    expect(manifest['executableRef'], executableRef);
    expect(loaded.toString(), isNot(contains('/Users/host/private')));
    expect(loaded.toString(), isNot(contains('private-secret')));
    final safeActions = manifest['actions']! as List;
    expect((safeActions.first as Map<String, Object?>)['argv'], [
      'search',
      '--api-key',
      '[已隐藏]',
      '--output',
      '[Mac 路径]',
    ]);

    final saved = await call('manifest.save', {
      'operationId': 'manifest-save-1',
      'connectionId': 'connection-1',
      'manifest': {...manifest, 'displayName': 'Edited connector'},
    });
    expect((saved['result']! as Map<String, Object?>)['saved'], isTrue);
    expect(runtime.savedActionManifest?['displayName'], 'Edited connector');
    expect(
      runtime.savedActionManifest?['executable'],
      '/Users/host/private/bin/cli',
    );
  });

  test('rejects a manifest reference issued for another connection', () async {
    final loaded = await call('manifest.get', {'connectionId': 'connection-1'});
    final result = loaded['result']! as Map<String, Object?>;
    final executableRef = result['executableRef']! as String;
    final payload =
        ConnectorManifest.neteaseCli('/Users/host/private/bin/cli').toJson()
          ..remove('executable')
          ..['executableRef'] = executableRef;
    final response = await call('manifest.save', {
      'operationId': 'manifest-save-cross-connection',
      'connectionId': 'connection-2',
      'manifest': payload,
    });
    expect(
      (response['error']! as Map<String, Object?>)['code'],
      HostRpcErrorCode.invalidParams.value,
    );
    expect(runtime.savedActionManifest, isNull);
  });

  test('runs an authorized capability once and streams later events', () async {
    final capability = await exposedCapability('Search');
    final invokeParams = {
      'operationId': 'invoke-1',
      'capability': capability.id.toJson(),
      'permissionLevel': 'read',
      'arguments': {'query': 'hello'},
    };
    final first = await call('run.invoke', invokeParams);
    final run =
        ((first['result']! as Map<String, Object?>)['run']!
                as Map<String, Object?>)['id']!
            as Map<String, Object?>;
    expect(run['value'], 'run-1');
    expect(runtime.invokeCalls, 1);
    expect(runtime.lastPermissionGranted, isTrue);

    final repeated = await call('run.invoke', invokeParams, id: 'request-2');
    expect(
      (repeated['result']! as Map<String, Object?>)['run'],
      (first['result']! as Map<String, Object?>)['run'],
    );
    expect(runtime.invokeCalls, 1);

    final notifications = <JsonMap>[];
    final subscribed = await call(
      'run.subscribe',
      {'runId': 'run-1', 'afterSequence': 0},
      id: 'request-3',
      sessionId: 'session-1',
      notify: notifications.add,
    );
    expect(
      (subscribed['result']! as Map<String, Object?>)['subscriptionId'],
      startsWith('sub-'),
    );
    runtime.events.add(
      RunEvent(
        runId: const RunId('run-1'),
        sequence: 1,
        state: RunState.succeeded,
        occurredAt: DateTime.utc(2026),
        blocks: const [
          ResultBlock(
            ResultKind.text,
            'api_key=secret-value /Users/host/private/result https://private.example/api?token=secret-value',
          ),
        ],
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(notifications, hasLength(1));
    expect(notifications.single['method'], 'run.event');
    expect(
      ((notifications.single['params']! as Map<String, Object?>)['event']!
          as Map<String, Object?>)['sequence'],
      1,
    );
    expect(notifications.single.toString(), isNot(contains('secret-value')));
    expect(notifications.single.toString(), isNot(contains('/Users/host')));

    await call('run.cancel', {'operationId': 'cancel-1', 'runId': 'run-1'});
    expect(runtime.cancelledRuns, ['run-1']);
    await dispatcher.closeSession(
      authenticatedDeviceId: 'device-1',
      sessionId: 'session-1',
    );
    runtime.events.add(
      RunEvent(
        runId: const RunId('run-1'),
        sequence: 2,
        state: RunState.succeeded,
        occurredAt: DateTime.utc(2026),
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(notifications, hasLength(1));
  });

  test(
    'rejects a capability whose declared permission was not granted',
    () async {
      final capability = await exposedCapability('Write');
      final response = await call('run.invoke', {
        'operationId': 'invoke-write-1',
        'capability': capability.id.toJson(),
        'permissionLevel': 'externalWrite',
        'arguments': const {},
      });
      expect(
        (response['error']! as Map<String, Object?>)['code'],
        HostRpcErrorCode.unauthorized.value,
      );
      expect(runtime.invokeCalls, 0);
    },
  );

  test('rejects a caller that understates a capability permission', () async {
    final capability = await exposedCapability('Write');
    final response = await call('run.invoke', {
      'operationId': 'invoke-write-2',
      'capability': capability.id.toJson(),
      'permissionLevel': 'read',
      'arguments': const {},
    });
    expect(
      (response['error']! as Map<String, Object?>)['code'],
      HostRpcErrorCode.unauthorized.value,
    );
    expect(runtime.invokeCalls, 0);
  });

  test(
    'scopes terminal and login handles to the authenticated session',
    () async {
      final notifications = <JsonMap>[];
      final opened = await call(
        'terminal.open',
        {'operationId': 'terminal-open-1', 'connectionId': 'connection-1'},
        id: 'request-terminal-open',
        sessionId: 'session-terminal-1',
        notify: notifications.add,
      );
      final result = opened['result']! as Map<String, Object?>;
      final terminalId = result['terminalId']! as String;
      expect(terminalId, startsWith('terminal-'));
      expect(terminalId, isNot('host-terminal'));
      expect(runtime.terminalOpenCalls, 1);

      final repeatedSameSession = await call(
        'terminal.open',
        {'operationId': 'terminal-open-1', 'connectionId': 'connection-1'},
        id: 'request-terminal-open-retry',
        sessionId: 'session-terminal-1',
        notify: notifications.add,
      );
      expect(
        (repeatedSameSession['result']! as Map<String, Object?>)['terminalId'],
        terminalId,
      );
      expect(runtime.terminalOpenCalls, 1);

      final repeatedAfterReconnect = await call(
        'terminal.open',
        {'operationId': 'terminal-open-1', 'connectionId': 'connection-1'},
        id: 'request-terminal-open-reconnect',
        sessionId: 'session-terminal-2',
        notify: (_) {},
      );
      final replay = repeatedAfterReconnect['result']! as Map<String, Object?>;
      expect(replay['state'], 'completed');
      expect(replay.containsKey('terminalId'), isFalse);
      expect(runtime.terminalOpenCalls, 1);

      final subscribed = await call(
        'terminal.subscribe',
        {'terminalId': terminalId},
        id: 'request-terminal-subscribe',
        sessionId: 'session-terminal-1',
        notify: notifications.add,
      );
      expect(
        (subscribed['result']! as Map<String, Object?>)['subscriptionId'],
        startsWith('sub-'),
      );
      runtime.terminalOutputs['host-terminal']!.add('prompt> ');
      await Future<void>.delayed(Duration.zero);
      expect(notifications.single['method'], 'terminal.event');
      final terminalEvent = HostTerminalEventNotification.fromJson(
        notifications.single,
      );
      expect(terminalEvent.event.text, 'prompt> ');

      final crossSession = await call(
        'terminal.write',
        {
          'operationId': 'terminal-write-cross-session',
          'terminalId': terminalId,
          'text': 'should not be written',
        },
        id: 'request-cross-session',
        sessionId: 'session-terminal-2',
        notify: notifications.add,
      );
      expect(
        (crossSession['error']! as Map<String, Object?>)['code'],
        HostRpcErrorCode.unauthorized.value,
      );
      expect(runtime.terminalWriteCalls, 0);

      await dispatcher.closeSession(
        authenticatedDeviceId: 'device-1',
        sessionId: 'session-terminal-1',
      );
      expect(runtime.terminalCloseCalls, 1);
    },
  );

  test('keeps account login in a Mac-owned terminal session', () async {
    final result = await call(
      'account.beginLogin',
      {'operationId': 'account-login-1', 'connectionId': 'connection-1'},
      id: 'request-login',
      sessionId: 'session-login-1',
      notify: (_) {},
    );
    final login = result['result']! as Map<String, Object?>;
    expect(login['terminalId'], login['sessionId']);
    expect(runtime.accountLoginCalls, 1);

    final waited = await call(
      'account.waitLogin',
      {'sessionId': login['sessionId']},
      id: 'request-login-wait',
      sessionId: 'session-login-1',
      notify: (_) {},
    );
    expect((waited['result']! as Map<String, Object?>)['exitCode'], 0);
    expect(runtime.accountWaitCalls, 1);
  });
}

String _frame(
  String method,
  Map<String, Object?> params, {
  required String id,
}) => jsonEncode({
  'jsonrpc': '2.0',
  'id': id,
  'method': method,
  'params': params,
});

final class _Authorization implements HostRpcAuthorizationPort {
  @override
  Future<bool> isAuthorized({
    required String deviceId,
    required String method,
    required JsonMap params,
  }) async {
    if (deviceId != 'device-1') return false;
    if (method == 'runtime.connection.invoke') {
      return params['permissionLevel'] == 'read';
    }
    return true;
  }
}

final class _NoopDispatcher implements HostRpcDispatcherPort {
  const _NoopDispatcher();

  @override
  Future<String?> dispatch(
    String frame, {
    required String authenticatedDeviceId,
    String? sessionId,
    void Function(JsonMap notification)? notify,
  }) async => null;

  @override
  Future<void> closeSession({
    required String authenticatedDeviceId,
    required String sessionId,
  }) async {}

  @override
  Future<void> revokeDevice(String deviceId) async {}
}

final class _Runtime implements RuntimePort, ConnectionAccountPort {
  _Runtime() : events = StreamController<RunEvent>.broadcast(sync: true);

  final StreamController<RunEvent> events;
  final List<String> cancelledRuns = [];
  final Map<String, StreamController<String>> terminalOutputs = {};
  int terminalOpenCalls = 0;
  int terminalWriteCalls = 0;
  int terminalCloseCalls = 0;
  int accountLoginCalls = 0;
  int accountWaitCalls = 0;
  final readCapability = const Capability(
    id: CapabilityId(
      ConnectionId('connection-1'),
      CapabilityKind.mcpTool,
      'search',
    ),
    title: 'Search',
    description: 'Read-only sample',
    permission: PermissionLevel.read,
  );
  final writeCapability = const Capability(
    id: CapabilityId(
      ConnectionId('connection-1'),
      CapabilityKind.mcpTool,
      'write',
    ),
    title: 'Write',
    description: 'External write sample',
    permission: PermissionLevel.externalWrite,
  );
  final resourceCapability = const Capability(
    id: CapabilityId(
      ConnectionId('connection-1'),
      CapabilityKind.mcpResource,
      'https://private.example/resource?token=secret-value',
    ),
    title: 'Remote file',
    description: 'File in /Users/host/private/project',
    permission: PermissionLevel.read,
  );
  int invokeCalls = 0;
  bool? lastPermissionGranted;
  JsonMap? actionManifest;
  JsonMap? savedActionManifest;

  @override
  bool get isPreview => false;
  @override
  RuntimeFeatures get features => RuntimeFeatures.localDesktop;
  @override
  List<String> get startupNotices => const [];
  @override
  Future<UserPreferences> loadPreferences() async => const UserPreferences();
  @override
  Future<void> savePreferences(UserPreferences preferences) async {}
  @override
  Future<void> clearActivity() async {}
  @override
  Future<List<Connection>> listConnections() async => [
    const Connection(
      id: ConnectionId('connection-1'),
      kind: ConnectionKind.cli,
      label: 'Host CLI',
      location: '/Users/host/private/bin/cli',
      diagnostic: 'private diagnostic',
    ),
  ];
  @override
  Future<Connection> addConnection(ConnectionSpec spec) async =>
      (await listConnections()).single;
  @override
  Future<void> removeConnection(ConnectionId id) async {}
  @override
  Future<void> moveConnection(ConnectionId id, int offset) async {}
  @override
  Future<Connection> refreshConnection(ConnectionId id) async =>
      (await listConnections()).single;
  @override
  Future<JsonMap?> loadActionManifest(ConnectionId id) async => actionManifest;
  @override
  Future<JsonMap> readActionManifestFile(String path) async => const {};
  @override
  Future<void> saveActionManifest(ConnectionId id, JsonMap manifest) async {
    savedActionManifest = Map.of(manifest);
  }

  @override
  Future<void> exportActionManifest(
    ConnectionId id,
    JsonMap manifest,
    String path,
  ) async {}
  @override
  Future<List<Capability>> searchCapabilities(SearchQuery query) async => [
    readCapability,
    writeCapability,
    resourceCapability,
  ];
  @override
  Future<RunHandle> invoke(
    CapabilityId id,
    JsonMap arguments, {
    bool permissionGranted = false,
  }) async {
    invokeCalls++;
    lastPermissionGranted = permissionGranted;
    return const RunHandle(RunId('run-1'));
  }

  @override
  Stream<RunEvent> watchRun(RunId id) => events.stream;
  @override
  Future<List<RunSummary>> listRecentRuns() async => const [];
  @override
  Future<void> cancel(RunId id) async => cancelledRuns.add(id.value);
  @override
  Future<List<ResultBlock>> readResource(ResourceRef ref) async => const [];
  @override
  Future<List<ResultBlock>> getPrompt(PromptRef ref, JsonMap arguments) async =>
      const [];
  @override
  Future<List<ResultBlock>> previewLocalFile(String path) async => const [];
  @override
  Future<void> revealLocalFile(String path) async {}
  @override
  Future<TerminalSession> openTerminal(CliCommand command) async {
    terminalOpenCalls++;
    return const TerminalSession('host-terminal');
  }

  @override
  Stream<String> watchTerminal(TerminalSession session) => terminalOutputs
      .putIfAbsent(
        session.id,
        () => StreamController<String>.broadcast(sync: true),
      )
      .stream;
  @override
  Future<void> writeTerminal(TerminalSession session, String text) async =>
      terminalWriteCalls++;
  @override
  Future<void> resizeTerminal(
    TerminalSession session,
    int columns,
    int rows,
  ) async {}
  @override
  Future<void> interruptTerminal(TerminalSession session) async {}
  @override
  Future<void> closeTerminal(TerminalSession session) async {
    terminalCloseCalls++;
    final output = terminalOutputs[session.id];
    if (output != null && !output.isClosed) await output.close();
  }

  @override
  Future<AccountSnapshot?> readAccount(ConnectionId connection) async => null;
  @override
  Future<TerminalSession> beginAccountLogin(ConnectionId connection) async {
    accountLoginCalls++;
    return const TerminalSession('login-terminal');
  }

  @override
  Future<int> waitAccountLogin(TerminalSession session) async {
    accountWaitCalls++;
    return 0;
  }

  @override
  Future<AccountSnapshot> logoutAccount(
    ConnectionId connection, {
    required bool confirmed,
  }) async => const AccountSnapshot(AccountState.signedOut);
}
