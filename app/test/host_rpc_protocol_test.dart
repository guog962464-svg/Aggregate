import 'dart:convert';
import 'dart:io';

import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:aggregate/platform/macos/host/host_jcs.dart';
import 'package:aggregate/platform/macos/host/host_operation_ledger.dart';
import 'package:aggregate/platform/macos/host/host_rpc_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Host JSON canonicalization', () {
    test('matches RFC 8785 number, string, and object ordering examples', () {
      final value = jsonDecode(
        r'''{"numbers":[333333333.33333329,1E30,4.50,2e-3,0.000000000000000000000000001],"string":"\u20ac$\u000f\u000aA'\u0042\u0022\u005c\\\"\/","literals":[null,true,false]}''',
      );
      expect(
        canonicalizeHostJson(value),
        r'''{"literals":[null,true,false],"numbers":[333333333.3333333,1e+30,4.5,0.002,1e-27],"string":"€$\u000f\nA'B\"\\\\\"/"}''',
      );
    });

    test('uses ECMAScript number thresholds and UTF-16 key ordering', () {
      expect(canonicalizeHostJson(1e-6), '0.000001');
      expect(canonicalizeHostJson(1e-7), '1e-7');
      expect(canonicalizeHostJson(1e20), '100000000000000000000');
      expect(canonicalizeHostJson(1e21), '1e+21');
      expect(canonicalizeHostJson(-0.0), '0');
      expect(canonicalizeHostJson(double.minPositive), '5e-324');
      expect(canonicalizeHostJson(double.maxFinite), '1.7976931348623157e+308');
      expect(canonicalizeHostJson(1424953923781206.25), '1424953923781206.2');
      expect(canonicalizeHostJson({'\uE000': 2, '💩': 1}), '{"💩":1,"":2}');
      expect(
        canonicalizeHostJson(jsonDecode('9007199254740993')),
        '9007199254740992',
      );
    });

    test('rejects invalid Unicode and hashes UTF-8 canonical JSON', () {
      expect(
        () => canonicalizeHostJson({'invalid': String.fromCharCode(0xd800)}),
        throwsFormatException,
      );
      expect(
        hashHostOperationPayload({'a': 1}),
        '015abd7f5cc57a2dd94b7590f04ad8084273905ee33ec5cebeae62276a97f862',
      );
    });
  });

  group('Host RPC v1', () {
    test('accepts only the declared method and named parameter schema', () {
      final request = HostRpcCodec.decodeRequest(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': 'req-1',
          'method': 'run.invoke',
          'params': {
            'operationId': 'op-1',
            'capability': {
              'connection': {'value': 'connection-1'},
              'kind': 'mcpTool',
              'name': 'search',
            },
            'arguments': {'query': 'hello'},
          },
        }),
      );

      expect(request.id, 'req-1');
      expect(request.operationId, 'op-1');
      expect(request.method, 'run.invoke');
      expect(request.operationPayload['params'], {
        'capability': {
          'connection': {'value': 'connection-1'},
          'kind': 'mcpTool',
          'name': 'search',
        },
        'arguments': {'query': 'hello'},
      });
      expect(hostRpcMethodCatalog.keys, hasLength(34));
      expect(
        hostRpcMethodCatalog['operation.read']!.requiresOperationId,
        isFalse,
      );
      final statusRequest = HostRpcCodec.decodeRequest(
        '{"jsonrpc":"2.0","id":"req-2","method":"operation.read","params":{"operationId":"op-1"}}',
      );
      expect(statusRequest.operationId, 'op-1');
      expect(statusRequest.operationPayload['params'], isEmpty);
      expect(
        () => hostRpcMethodCatalog['arbitrary.shell'] =
            const HostRpcMethodDefinition('arbitrary.shell', []),
        throwsUnsupportedError,
      );
    });

    test(
      'rejects JSON-RPC notifications, batches, extra fields and methods',
      () {
        for (final request in [
          '{"jsonrpc":"2.0","method":"host.status","params":{}}',
          '[{"jsonrpc":"2.0","id":"req-1","method":"host.status","params":{}}]',
          '{"jsonrpc":"2.0","id":"req-1","method":"host.status","params":{},"trace":true}',
        ]) {
          expect(
            () => HostRpcCodec.decodeRequest(request),
            throwsA(isA<HostRpcProtocolException>()),
          );
        }
        expect(
          () => HostRpcCodec.decodeRequest(
            '{"jsonrpc":"2.0","id":"req-1","method":"shell.exec","params":{}}',
          ),
          throwsA(
            isA<HostRpcProtocolException>().having(
              (error) => error.code,
              'code',
              HostRpcErrorCode.methodNotFound,
            ),
          ),
        );
      },
    );

    test(
      'rejects duplicate JSON property names, including escaped aliases',
      () {
        for (final request in [
          '{"jsonrpc":"2.0","id":"req-1","method":"host.status","params":{"x":1,"x":2}}',
          '{"jsonrpc":"2.0","id":"req-1","method":"host.status","params":{"x":1,"\\u0078":2}}',
        ]) {
          expect(
            () => HostRpcCodec.decodeRequest(request),
            throwsA(
              isA<HostRpcProtocolException>().having(
                (error) => error.code,
                'code',
                HostRpcErrorCode.invalidRequest,
              ),
            ),
          );
        }
      },
    );

    test('rejects unsupported versions and invalid method parameters', () {
      expect(
        HostRpcCodec.decodeRequest(
          '{"jsonrpc":"2.0","id":"req-0","method":"host.hello","params":{"protocolVersion":1}}',
        ).method,
        'host.hello',
      );
      expect(
        () => HostRpcCodec.decodeRequest(
          '{"jsonrpc":"2.0","id":"req-1","method":"host.hello","params":{"protocolVersion":2}}',
        ),
        throwsA(
          isA<HostRpcProtocolException>()
              .having(
                (error) => error.code,
                'code',
                HostRpcErrorCode.unsupportedVersion,
              )
              .having((error) => error.requestId, 'requestId', 'req-1'),
        ),
      );
      for (final params in [
        <String, Object?>{
          'operationId': 'op-1',
          'capability': {},
          'arguments': {},
        },
        <String, Object?>{
          'operationId': 'op-1',
          'capability': {
            'connection': {'value': 'connection-1'},
            'kind': 'mcpTool',
            'name': 'search',
            'path': '/tmp/ignored',
          },
          'arguments': {},
        },
        <String, Object?>{
          'operationId': 'bad id',
          'capability': {},
          'arguments': {},
        },
      ]) {
        expect(
          () => HostRpcCodec.decodeRequest(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': 'req-1',
              'method': 'run.invoke',
              'params': params,
            }),
          ),
          throwsA(
            isA<HostRpcProtocolException>().having(
              (error) => error.code,
              'code',
              HostRpcErrorCode.invalidParams,
            ),
          ),
        );
      }
    });

    test('constrains connection moves to one position', () {
      String encodeMove(int offset) => jsonEncode({
        'jsonrpc': '2.0',
        'id': 'req-1',
        'method': 'connection.move',
        'params': {
          'operationId': 'op-1',
          'connectionId': 'connection-1',
          'offset': offset,
        },
      });
      expect(HostRpcCodec.decodeRequest(encodeMove(-1)).params['offset'], -1);
      expect(
        () => HostRpcCodec.decodeRequest(encodeMove(2)),
        throwsA(isA<HostRpcProtocolException>()),
      );
    });

    test('setup drafts accept opaque references and reject host paths', () {
      final encoded = jsonEncode({
        'jsonrpc': '2.0',
        'id': 'req-1',
        'method': 'setup.test',
        'params': {
          'operationId': 'op-1',
          'draft': {
            'adapterId': 'cli',
            'label': 'Git',
            'fieldValues': {'mode': 'safe'},
            'executableRef': 'exec-1',
          },
        },
      });
      final request = HostRpcCodec.decodeRequest(encoded);
      final draft = HostSetupDraftPayload.fromJson(request.params['draft']);
      expect(draft.executableRef, 'exec-1');
      expect(draft.fieldValues, {'mode': 'safe'});

      expect(
        () => HostRpcCodec.decodeRequest(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': 'req-1',
            'method': 'setup.test',
            'params': {
              'operationId': 'op-1',
              'draft': {
                'adapterId': 'cli',
                'label': 'Git',
                'fieldValues': {},
                'executable': '/usr/bin/git',
              },
            },
          }),
        ),
        throwsA(isA<HostRpcProtocolException>()),
      );

      expect(
        () => HostRpcCodec.decodeRequest(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': 'req-1',
            'method': 'setup.test',
            'params': {
              'operationId': 'op-1',
              'draft': {
                'adapterId': 'cli',
                'label': 'Git',
                'fieldValues': {},
                'arguments': List<String>.filled(257, 'arg'),
              },
            },
          }),
        ),
        throwsA(isA<HostRpcProtocolException>()),
      );
    });

    test('keeps setup URLs public and secret values in a bounded side map', () {
      final request = HostRpcCodec.decodeRequest(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': 'req-1',
          'method': 'setup.test',
          'params': {
            'operationId': 'op-1',
            'draft': {
              'adapterId': 'mcp-http',
              'label': 'Remote MCP',
              'fieldValues': {},
              'url': 'https://mcp.example.test/api',
            },
            'secretValues': {'authToken': 's' * (32 * 1024)},
          },
        }),
      );
      final draft = HostSetupDraftPayload.fromJson(request.params['draft']);
      expect(draft.url, 'https://mcp.example.test/api');
      expect(request.params['secretValues'], isA<Map>());

      for (final invalid in [
        {
          'adapterId': 'mcp-http',
          'label': 'Remote MCP',
          'fieldValues': <String, String>{},
          'url': 'https://user:password@mcp.example.test/api',
        },
        {
          'adapterId': 'mcp-http',
          'label': 'Remote MCP',
          'fieldValues': <String, String>{},
          'url': 'file:///Users/host/secret',
        },
      ]) {
        expect(
          () => HostRpcCodec.decodeRequest(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': 'req-1',
              'method': 'setup.test',
              'params': {'operationId': 'op-1', 'draft': invalid},
            }),
          ),
          throwsA(isA<HostRpcProtocolException>()),
        );
      }
      expect(
        () => HostRpcCodec.decodeRequest(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': 'req-1',
            'method': 'setup.test',
            'params': {
              'operationId': 'op-1',
              'draft': {
                'adapterId': 'mcp-http',
                'label': 'Remote MCP',
                'fieldValues': {},
                'url': 'https://mcp.example.test/api',
              },
              'secretValues': {'authToken': 's' * (32 * 1024 + 1)},
            },
          }),
        ),
        throwsA(isA<HostRpcProtocolException>()),
      );
    });

    test('manifest DTOs carry executable references instead of Mac paths', () {
      final manifest = <String, Object?>{
        'schemaVersion': 1,
        'id': 'example-cli',
        'displayName': 'Example CLI',
        'platforms': ['macos'],
        'executableRef': 'exec-1',
        'actions': [
          {
            'id': 'echo',
            'title': 'Echo',
            'argv': ['echo', '{{text}}'],
            'inputSchema': {
              'type': 'object',
              'properties': {
                'text': {'type': 'string', 'title': 'Text'},
              },
              'required': ['text'],
              'additionalProperties': false,
            },
            'output': 'text',
            'permission': 'read',
            'timeoutMs': 30000,
          },
        ],
      };
      final request = HostRpcCodec.decodeRequest(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': 'req-1',
          'method': 'manifest.save',
          'params': {
            'operationId': 'op-1',
            'connectionId': 'connection-1',
            'manifest': manifest,
          },
        }),
      );
      final dto = HostConnectorManifestPayload.fromJson(
        request.params['manifest'],
      );
      expect(dto.executableRef, 'exec-1');
      expect(dto.toJson().containsKey('executable'), isFalse);

      final rawPathManifest = Map<String, Object?>.of(manifest)
        ..remove('executableRef')
        ..['executable'] = '/bin/sh';
      expect(
        () => HostRpcCodec.decodeRequest(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': 'req-1',
            'method': 'manifest.save',
            'params': {
              'operationId': 'op-1',
              'connectionId': 'connection-1',
              'manifest': rawPathManifest,
            },
          }),
        ),
        throwsA(isA<HostRpcProtocolException>()),
      );
    });

    test('returns only stable JSON-RPC error fields', () {
      final response = jsonDecode(
        HostRpcCodec.encodeError('req-1', HostRpcErrorCode.unauthorized),
      ) as Map<String, Object?>;
      expect(response, {
        'jsonrpc': '2.0',
        'id': 'req-1',
        'error': {
          'code': HostRpcErrorCode.unauthorized.value,
          'message': HostRpcErrorCode.unauthorized.message,
        },
      });
    });

    test('round trips nonnegative event sequence cursors', () {
      const cursor = HostEventCursor(17);
      expect(HostEventCursor.fromJson(cursor.toJson()).sequence, 17);
      expect(
        () => HostEventCursor.fromJson({'sequence': -1}),
        throwsFormatException,
      );
      expect(
        () => HostEventCursor.fromJson({'sequence': 2, 'path': '/tmp/x'}),
        throwsFormatException,
      );
    });

    test('round trips run and terminal event notifications with sequences', () {
      final runNotification = HostRunEventNotification(
        subscriptionId: 'sub-1',
        event: RunEvent(
          runId: const RunId('run-1'),
          sequence: 4,
          state: RunState.running,
          occurredAt: DateTime.utc(2026, 11, 13),
        ),
      );
      final runFrame = runNotification.toJson();
      final parsedRun = HostRunEventNotification.fromJson(runFrame);
      expect(parsedRun.subscriptionId, 'sub-1');
      expect(parsedRun.event.sequence, 4);

      final inconsistentRunParams = Map<String, Object?>.of(
        runFrame['params']! as Map<String, Object?>,
      )..['sequence'] = 5;
      final inconsistentRunFrame = Map<String, Object?>.of(runFrame)
        ..['params'] = inconsistentRunParams;
      expect(
        () => HostRunEventNotification.fromJson(inconsistentRunFrame),
        throwsFormatException,
      );

      const terminalNotification = HostTerminalEventNotification(
        subscriptionId: 'sub-2',
        event: HostTerminalEvent(
          terminalId: 'terminal-1',
          sequence: 9,
          kind: HostTerminalEventKind.output,
          text: 'ready',
        ),
      );
      final parsedTerminal = HostTerminalEventNotification.fromJson(
        terminalNotification.toJson(),
      );
      expect(parsedTerminal.event.sequence, 9);
      expect(parsedTerminal.event.text, 'ready');
      expect(
        () => HostTerminalEvent.fromJson({
          'terminalId': 'terminal-1',
          'sequence': 10,
          'kind': 'closed',
          'text': 'unexpected output',
        }),
        throwsFormatException,
      );
    });

    test('caps RPC frames by UTF-8 byte length', () {
      final oversized = 'x' * (hostRpcMaxFrameBytes + 1);
      expect(
        () => HostRpcCodec.decodeRequest(oversized),
        throwsA(
          isA<HostRpcProtocolException>().having(
            (error) => error.code,
            'code',
            HostRpcErrorCode.payloadTooLarge,
          ),
        ),
      );
      expect(
        () => HostRpcCodec.encodeSuccess('req-1', {'value': oversized}),
        throwsA(
          isA<HostRpcProtocolException>().having(
            (error) => error.code,
            'code',
            HostRpcErrorCode.payloadTooLarge,
          ),
        ),
      );
    });

    test('caps JSON nesting depth before decoding', () {
      final open = '[' * 65;
      final close = ']' * 65;
      final nested = '$open 0 $close';
      expect(
        () => HostRpcCodec.decodeRequest(nested),
        throwsA(
          isA<HostRpcProtocolException>().having(
            (error) => error.code,
            'code',
            HostRpcErrorCode.invalidRequest,
          ),
        ),
      );
      Object? nestedValue = 0;
      for (var depth = 0; depth < 65; depth++) {
        nestedValue = [nestedValue];
      }
      expect(
        () => HostRpcCodec.encodeSuccess('req-1', nestedValue),
        throwsA(
          isA<HostRpcProtocolException>().having(
            (error) => error.code,
            'code',
            HostRpcErrorCode.payloadTooLarge,
          ),
        ),
      );
    });
  });

  group('Host operation ledger', () {
    test('deduplicates operations and rejects payload conflicts', () async {
      final directory = await Directory.systemTemp.createTemp(
        'aggregate-host-ledger-',
      );
      final ledgerFile = File('${directory.path}/host/operations.json');
      final ledger = await FileHostOperationLedger.open(ledgerFile);
      try {
        final first = await ledger.begin(
          deviceId: 'device-1',
          operationId: 'op-1',
          payloadHash: _hashA,
        );
        expect(first.shouldExecute, isTrue);
        expect(first.record.state, HostOperationState.started);

        final retry = await ledger.begin(
          deviceId: 'device-1',
          operationId: 'op-1',
          payloadHash: _hashA,
        );
        expect(retry.shouldExecute, isFalse);
        expect(retry.record.state, HostOperationState.started);
        await expectLater(
          ledger.begin(
            deviceId: 'device-1',
            operationId: 'op-1',
            payloadHash: _hashB,
          ),
          throwsA(
            isA<HostOperationLedgerException>().having(
              (error) => error.code,
              'code',
              HostRpcErrorCode.idempotencyConflict,
            ),
          ),
        );

        final completed = await ledger.complete(
          deviceId: 'device-1',
          operationId: 'op-1',
        );
        expect(completed.state, HostOperationState.completed);
        final completedRetry = await ledger.begin(
          deviceId: 'device-1',
          operationId: 'op-1',
          payloadHash: _hashA,
        );
        expect(completedRetry.shouldExecute, isFalse);
        expect(completedRetry.record.state, HostOperationState.completed);
      } finally {
        await directory.delete(recursive: true);
      }
    });

    test('recovers an interrupted operation as outcome unknown', () async {
      final directory = await Directory.systemTemp.createTemp(
        'aggregate-host-recovery-',
      );
      final ledgerFile = File('${directory.path}/operations.json');
      try {
        final firstProcess = await FileHostOperationLedger.open(ledgerFile);
        await firstProcess.begin(
          deviceId: 'device-1',
          operationId: 'op-1',
          payloadHash: _hashA,
        );

        final restarted = await FileHostOperationLedger.open(ledgerFile);
        final retry = await restarted.begin(
          deviceId: 'device-1',
          operationId: 'op-1',
          payloadHash: _hashA,
        );
        expect(retry.shouldExecute, isFalse);
        expect(retry.record.state, HostOperationState.outcomeUnknown);
        await expectLater(
          restarted.complete(deviceId: 'device-1', operationId: 'op-1'),
          throwsA(
            isA<HostOperationLedgerException>().having(
              (error) => error.code,
              'code',
              HostRpcErrorCode.outcomeUnknown,
            ),
          ),
        );
      } finally {
        await directory.delete(recursive: true);
      }
    });

    test('operation identifiers are scoped to the paired device', () async {
      final directory = await Directory.systemTemp.createTemp(
        'aggregate-host-device-scope-',
      );
      final ledger = await FileHostOperationLedger.open(
        File('${directory.path}/operations.json'),
      );
      try {
        final firstDevice = await ledger.begin(
          deviceId: 'device-1',
          operationId: 'op-1',
          payloadHash: _hashA,
        );
        final secondDevice = await ledger.begin(
          deviceId: 'device-2',
          operationId: 'op-1',
          payloadHash: _hashA,
        );
        expect(firstDevice.shouldExecute, isTrue);
        expect(secondDevice.shouldExecute, isTrue);
      } finally {
        await directory.delete(recursive: true);
      }
    });
  });
}

const _hashA =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _hashB =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
