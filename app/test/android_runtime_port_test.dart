import 'dart:async';
import 'dart:io';

import 'package:aggregate/platform/android/android_runtime_port.dart';
import 'package:aggregate/platform/android/android_host_manager.dart';
import 'package:aggregate/platform/android/android_host_pairing_client.dart';
import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('A2 Android runtime advertises only HTTP MCP', () async {
    final directory = await Directory.systemTemp.createTemp(
      'aggregate-android-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final runtime = await AndroidRuntimePort.open(dataDirectory: directory);
    addTearDown(runtime.dispose);
    expect(runtime.isPreview, isFalse);
    expect(runtime.features.connectionKinds, {ConnectionKind.mcpHttp});
    expect(runtime.connectionAdapters.map((item) => item.id), ['mcp-http']);
    expect(runtime.features.terminal, isFalse);
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
  });

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
  var connected = true;
  Map<String, Object?>? lastInvocationCapability;

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
  AndroidHostStatus statusFor(String hostId) => isConnected(hostId)
      ? AndroidHostStatus.online
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
    _statusChanges.add(
      AndroidHostStatusChange(hostId, AndroidHostStatus.offline),
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
