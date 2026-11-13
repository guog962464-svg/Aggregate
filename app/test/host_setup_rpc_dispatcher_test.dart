import 'dart:convert';
import 'dart:io';

import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:aggregate/platform/macos/host/host_operation_ledger.dart';
import 'package:aggregate/platform/macos/host/host_rpc_protocol.dart';
import 'package:aggregate/platform/macos/host/host_setup_coordinator.dart';
import 'package:aggregate/platform/macos/host/host_setup_rpc_dispatcher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late _SetupFixture setupPort;
  late HostSetupCoordinator setup;
  late FileHostOperationLedger ledger;
  late _Authorizer authorizer;
  late HostSetupRpcDispatcher dispatcher;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('aggregate-host-rpc-');
    setupPort = _SetupFixture();
    setup = HostSetupCoordinator(setup: setupPort);
    ledger = await FileHostOperationLedger.open(
      File('${directory.path}/operations.json'),
    );
    authorizer = _Authorizer();
    dispatcher = HostSetupRpcDispatcher(
      setup: setup,
      ledger: ledger,
      authorization: authorizer,
    );
  });

  Future<Map<String, Object?>> dispatchFrame(String frame) async => jsonDecode(
    (await dispatcher.dispatch(frame, authenticatedDeviceId: 'device-1'))!,
  ) as Map<String, Object?>;

  Future<Map<String, Object?>> dispatch(
    String method,
    Map<String, Object?> params,
  ) => dispatchFrame(_frame(method, params));

  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test(
    'dispatches only authorized setup methods and returns opaque refs',
    () async {
      final adaptersResponse = await dispatch('setup.adapters', const {});
      final adapters = adaptersResponse['result']! as Map<String, Object?>;
      expect(adapters['adapters'], hasLength(1));

      final detectedResponse = await dispatch('setup.detectExecutable', {
        'adapterId': 'netease-music',
      });
      final detected = detectedResponse['result']! as Map<String, Object?>;
      expect(detected['detected'], isTrue);
      expect(detected.toString(), isNot(contains(_SetupFixture.path)));
      expect(authorizer.lastParams!.containsKey('secretValues'), isFalse);

      expect(
        await dispatcher.dispatch(
          _frame('host.status', const {}),
          authenticatedDeviceId: 'device-1',
        ),
        isNull,
      );
      expect(authorizer.methods, ['setup.adapters', 'setup.detectExecutable']);
    },
  );

  test(
    'runs a setup operation once and exposes its status for recovery',
    () async {
      final detected = await dispatch('setup.detectExecutable', {
        'adapterId': 'netease-music',
      });
      final executable =
          (detected['result']! as Map<String, Object?>)['executableRef']!
              as String;
      const privateKey = '-----BEGIN PRIVATE KEY-----\nsecret-data\n';
      final params = {
        'operationId': 'op-test-1',
        'draft': {
          'adapterId': 'netease-music',
          'label': 'Music',
          'fieldValues': {'appId': 'app-123'},
          'executableRef': executable,
        },
        'secretValues': {'privateKey': privateKey},
      };
      final frame = _frame('setup.test', params);
      final first = await dispatchFrame(frame);
      final firstResult = first['result']! as Map<String, Object?>;
      expect(firstResult['canSave'], isTrue);
      expect(firstResult['draftHandle'], isA<String>());
      expect(first.toString(), isNot(contains(privateKey)));
      expect(first.toString(), isNot(contains(_SetupFixture.path)));
      expect(setupPort.testCount, 1);
      expect(authorizer.lastParams!.containsKey('secretValues'), isFalse);

      final repeated = await dispatchFrame(frame);
      expect(repeated['result'], {
        'operationId': 'op-test-1',
        'state': 'completed',
        'replayed': true,
      });
      expect(setupPort.testCount, 1);

      final state = await dispatch('operation.read', {
        'operationId': 'op-test-1',
      });
      expect(
        (state['result']! as Map<String, Object?>)['state'],
        HostOperationState.completed.name,
      );

      final conflicting = _frame('setup.test', {
        ...params,
        'draft': {
          ...params['draft']! as Map<String, Object?>,
          'label': 'Different payload',
        },
      });
      final conflict = await dispatchFrame(conflicting);
      expect(
        (conflict['error']! as Map<String, Object?>)['code'],
        HostRpcErrorCode.idempotencyConflict.value,
      );
      expect(setupPort.testCount, 1);
    },
  );

  test('marks a failed save outcome unknown and never retries it', () async {
    final detected = await dispatch('setup.detectExecutable', {
      'adapterId': 'netease-music',
    });
    final executable =
        (detected['result']! as Map<String, Object?>)['executableRef']!
            as String;
    final tested = await dispatch('setup.test', {
      'operationId': 'op-test-save',
      'draft': {
        'adapterId': 'netease-music',
        'label': 'Music',
        'fieldValues': {'appId': 'app-123'},
        'executableRef': executable,
      },
      'secretValues': {'privateKey': 'private'},
    });
    final draftHandle =
        (tested['result']! as Map<String, Object?>)['draftHandle']! as String;
    setupPort.failSave = true;
    final saveFrame = _frame('setup.save', {
      'operationId': 'op-save-1',
      'draftHandle': draftHandle,
    });

    final first = await dispatchFrame(saveFrame);
    expect(
      (first['error']! as Map<String, Object?>)['code'],
      HostRpcErrorCode.outcomeUnknown.value,
    );
    final operation = await ledger.read(
      deviceId: 'device-1',
      operationId: 'op-save-1',
    );
    expect(operation!.state, HostOperationState.outcomeUnknown);

    final retry = await dispatchFrame(saveFrame);
    expect(
      (retry['result']! as Map<String, Object?>)['state'],
      HostOperationState.outcomeUnknown.name,
    );
    expect(setupPort.saveCount, 1);
    expect(setupPort.discardedDrafts, isEmpty);
  });

  test(
    'denies before touching setup or ledger and sanitizes parse errors',
    () async {
      authorizer.allowed = false;
      final denied = await dispatch('setup.detectExecutable', {
        'adapterId': 'netease-music',
      });
      expect(
        (denied['error']! as Map<String, Object?>)['code'],
        HostRpcErrorCode.unauthorized.value,
      );
      expect(setupPort.detectCount, 0);

      final malformed = await dispatcher.dispatch(
        '{bad json',
        authenticatedDeviceId: 'device-1',
      );
      expect((jsonDecode(malformed!) as Map<String, Object?>)['error'], {
        'code': HostRpcErrorCode.parseError.value,
        'message': 'Parse error',
      });
    },
  );
}

String _frame(String method, Map<String, Object?> params) => jsonEncode({
  'jsonrpc': '2.0',
  'id': 'req-1',
  'method': method,
  'params': params,
});

final class _Authorizer implements HostRpcAuthorizationPort {
  bool allowed = true;
  final methods = <String>[];
  JsonMap? lastParams;

  @override
  Future<bool> isAuthorized({
    required String deviceId,
    required String method,
    required JsonMap params,
  }) async {
    methods.add(method);
    lastParams = params;
    return allowed && deviceId == 'device-1';
  }
}

final class _SetupFixture implements ConnectionSetupPort {
  static const path = '/Users/host/bin/ncm-cli';
  var detectCount = 0;
  var testCount = 0;
  var saveCount = 0;
  var failSave = false;
  final discardedDrafts = <String>[];

  @override
  List<ConnectionAdapter> get connectionAdapters => const [
    ConnectionAdapter(
      id: 'netease-music',
      label: '网易云音乐',
      kind: ConnectionKind.cli,
      fields: [
        SetupField(key: 'appId', label: 'App ID'),
        SetupField(
          key: 'privateKey',
          label: 'Private Key',
          kind: SetupFieldKind.secret,
        ),
      ],
      autoDetectExecutable: true,
      showGenericCliFields: false,
    ),
  ];

  @override
  Future<String?> detectExecutable(String adapterId) async {
    detectCount++;
    return adapterId == 'netease-music' ? path : null;
  }

  @override
  Future<ConnectionSetupReport> testConnectionSetup(
    ConnectionSetupDraft draft,
  ) async {
    testCount++;
    return const ConnectionSetupReport(
      draftId: 'runtime-draft-1',
      checks: [
        SetupCheck('程序检查', SetupCheckStatus.passed, path),
        SetupCheck('账号登录', SetupCheckStatus.actionRequired, 'secret'),
      ],
      canSave: true,
    );
  }

  @override
  Future<Connection> saveConnectionSetup(String draftId) async {
    saveCount++;
    if (failSave) throw StateError('private path save failure');
    return const Connection(
      id: ConnectionId('connection-1'),
      kind: ConnectionKind.cli,
      label: 'Music',
      location: path,
    );
  }

  @override
  Future<void> discardConnectionSetup(String draftId) async {
    discardedDrafts.add(draftId);
  }
}
