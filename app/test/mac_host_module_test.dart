import 'dart:async';
import 'dart:io';

import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:aggregate/platform/macos/host/host_control_port.dart';
import 'package:aggregate/platform/macos/host/host_rpc_protocol.dart';
import 'package:aggregate/platform/macos/host/host_transport_port.dart';
import 'package:aggregate/platform/macos/host/mac_host_module.dart';
import 'package:aggregate/platform/macos/local_runtime_port.dart';
import 'package:aggregate/platform/macos/mac_runtime.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('serializes start and stop and replays lifecycle status', () async {
    final runtime = _UnusedRuntime();
    final transport = _FakeHostTransport()..startGate = Completer<void>();
    final module = MacHostModule(
      runtimeBindings: MacHostRuntimeBindings(
        runtime: runtime,
        connectionSetup: runtime,
        accounts: runtime,
      ),
      hostTransport: transport,
    );
    expect(identical(module.runtimeBindings.runtime, runtime), isTrue);
    expect(identical(module.runtimeBindings.connectionSetup, runtime), isTrue);
    expect(identical(module.runtimeBindings.accounts, runtime), isTrue);
    final observed = <HostStatus>[];
    final subscription = module.watchStatus().listen(observed.add);
    await Future<void>.delayed(Duration.zero);

    final firstStart = module.start();
    final secondStart = module.start();
    await Future<void>.delayed(Duration.zero);
    expect(transport.startCalls, 1);
    transport.startGate!.complete();
    await Future.wait([firstStart, secondStart]);
    expect(module.status.phase, HostPhase.running);

    await module.stop();
    await Future<void>.delayed(Duration.zero);
    expect(transport.stopCalls, 1);
    expect(module.status.phase, HostPhase.stopped);
    expect(observed.map((status) => status.phase), [
      HostPhase.stopped,
      HostPhase.starting,
      HostPhase.running,
      HostPhase.stopping,
      HostPhase.stopped,
    ]);
    await subscription.cancel();
  });

  test(
    'rolls back a failed transport start and records a safe status',
    () async {
      final runtime = _UnusedRuntime();
      final transport = _FakeHostTransport()
        ..startError = StateError('private host path');
      final module = MacHostModule(
        runtimeBindings: MacHostRuntimeBindings(
          runtime: runtime,
          connectionSetup: runtime,
          accounts: runtime,
        ),
        hostTransport: transport,
      );

      await expectLater(
        module.start(),
        throwsA(
          isA<HostControlException>()
              .having(
                (error) => error.code,
                'code',
                HostControlErrorCode.transportFailure,
              )
              .having(
                (error) => error.toString(),
                'safe error',
                isNot(contains('private host path')),
              ),
        ),
      );
      expect(transport.startCalls, 1);
      expect(transport.stopCalls, 1);
      expect(module.status.phase, HostPhase.failed);
      expect(module.status.reason, HostStatusReason.startupFailed);
    },
  );

  test('maps shutdown failures to a stable error code', () async {
    final runtime = _UnusedRuntime();
    final transport = _FakeHostTransport()
      ..stopError = StateError('private certificate detail');
    final module = MacHostModule(
      runtimeBindings: MacHostRuntimeBindings(
        runtime: runtime,
        connectionSetup: runtime,
        accounts: runtime,
      ),
      hostTransport: transport,
    );
    await module.start();

    await expectLater(
      module.stop(),
      throwsA(
        isA<HostControlException>()
            .having(
              (error) => error.code,
              'code',
              HostControlErrorCode.transportFailure,
            )
            .having(
              (error) => error.toString(),
              'safe error',
              isNot(contains('private certificate detail')),
            ),
      ),
    );
    expect(module.status.phase, HostPhase.failed);
    expect(module.status.reason, HostStatusReason.shutdownFailed);
  });

  test(
    'production transport stays closed until pairing authentication',
    () async {
      final runtime = _UnusedRuntime();
      final module = MacHostModule(
        runtimeBindings: MacHostRuntimeBindings(
          runtime: runtime,
          connectionSetup: runtime,
          accounts: runtime,
        ),
        hostTransport: const PairingRequiredHostTransport(),
      );

      await expectLater(
        module.start(),
        throwsA(
          isA<HostControlException>().having(
            (error) => error.code,
            'code',
            HostControlErrorCode.pairingAuthenticationRequired,
          ),
        ),
      );
      expect(module.status.phase, HostPhase.unavailable);
      expect(
        module.status.reason,
        HostStatusReason.pairingAuthenticationRequired,
      );
      await module.stop();
      expect(module.status.phase, HostPhase.stopped);
    },
  );

  test('Host stop discards its device-bound setup drafts', () async {
    final runtime = _UnusedRuntime();
    final module = MacHostModule(
      runtimeBindings: MacHostRuntimeBindings(
        runtime: runtime,
        connectionSetup: runtime,
        accounts: runtime,
      ),
      hostTransport: _FakeHostTransport(),
    );
    await module.start();
    final executable = await module.setupCoordinator.detectExecutable(
      deviceId: 'device-1',
      adapterId: 'cli',
    );
    final tested = await module.setupCoordinator.testConnectionSetup(
      deviceId: 'device-1',
      draft: HostSetupDraftPayload(
        adapterId: 'cli',
        label: 'CLI',
        fieldValues: const {},
        executableRef: executable!.executableRef,
      ),
    );

    await module.stop();
    expect(runtime.discardedSetupDrafts, ['setup-draft-1']);
    await expectLater(
      module.setupCoordinator.saveConnectionSetup(
        deviceId: 'device-1',
        draftHandle: tested.draftHandle!,
      ),
      throwsA(
        isA<HostRpcProtocolException>().having(
          (error) => error.code,
          'code',
          HostRpcErrorCode.operationNotFound,
        ),
      ),
    );
  });

  test('Host stop leaves the app-owned MacRuntime usable', () async {
    final directory = await Directory.systemTemp.createTemp(
      'aggregate-mac-host-',
    );
    final runtime = await MacRuntime.open(dataDirectory: directory);
    final transport = _FakeHostTransport();
    final localPort = LocalRuntimePort.live(runtime, hostTransport: transport);
    try {
      final connection = await runtime.addConnection(
        const ConnectionSpec(
          kind: ConnectionKind.cli,
          label: 'printf fixture',
          executable: '/usr/bin/printf',
        ),
      );
      await localPort.hostControl.start();
      await localPort.hostControl.stop();

      final capability = (await localPort.searchCapabilities(
        const SearchQuery('printf fixture'),
      )).single;
      expect(capability.id.connection.value, connection.id.value);
      final run = await localPort.invoke(capability.id, {
        'argv': ['host-stop-kept-runtime'],
      }, permissionGranted: true);
      final result = await localPort
          .watchRun(run.id)
          .firstWhere(
            (event) =>
                event.state == RunState.succeeded ||
                event.state == RunState.failed,
          )
          .timeout(const Duration(seconds: 5));
      expect(result.state, RunState.succeeded);
      expect(result.blocks.first.value, 'host-stop-kept-runtime');
    } finally {
      await runtime.dispose();
      await directory.delete(recursive: true);
    }
  });
}

final class _FakeHostTransport implements HostTransportPort {
  int startCalls = 0;
  int stopCalls = 0;
  Completer<void>? startGate;
  Object? startError;
  Object? stopError;

  @override
  Future<void> start() async {
    startCalls++;
    if (startGate case final gate?) await gate.future;
    if (startError case final error?) throw error;
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    if (stopError case final error?) throw error;
  }
}

final class _UnusedRuntime
    implements RuntimePort, ConnectionSetupPort, ConnectionAccountPort {
  final discardedSetupDrafts = <String>[];

  @override
  List<ConnectionAdapter> get connectionAdapters => const [
    ConnectionAdapter(
      id: 'cli',
      label: 'CLI',
      kind: ConnectionKind.cli,
      autoDetectExecutable: true,
    ),
  ];

  @override
  Future<String?> detectExecutable(String adapterId) async => '/usr/bin/printf';

  @override
  Future<ConnectionSetupReport> testConnectionSetup(
    ConnectionSetupDraft draft,
  ) async => const ConnectionSetupReport(
    draftId: 'setup-draft-1',
    checks: [],
    canSave: true,
  );

  @override
  Future<Connection> saveConnectionSetup(String draftId) async =>
      const Connection(
        id: ConnectionId('connection-1'),
        kind: ConnectionKind.cli,
        label: 'CLI',
        location: '/usr/bin/printf',
      );

  @override
  Future<void> discardConnectionSetup(String draftId) async {
    discardedSetupDrafts.add(draftId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
