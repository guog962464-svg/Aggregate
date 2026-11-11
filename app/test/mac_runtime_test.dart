import 'dart:convert';
import 'dart:io';

import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:aggregate/platform/macos/mac_runtime.dart';
import 'package:aggregate/platform/macos/credential_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('macOS runtime rejects a connection owned by another Host', () async {
    final directory = await Directory.systemTemp.createTemp('aggregate-owner-');
    final runtime = await MacRuntime.open(dataDirectory: directory);
    try {
      await expectLater(
        runtime.addConnection(
          ConnectionSpec(
            kind: ConnectionKind.cli,
            label: 'Remote Git',
            executable: '/usr/bin/git',
            executionTarget: ExecutionTarget.host('paired-mac-1'),
          ),
        ),
        throwsFormatException,
      );
      expect(await runtime.listConnections(), isEmpty);
    } finally {
      await runtime.dispose();
      await directory.delete(recursive: true);
    }
  });

  test(
    'registers an unknown CLI, blocks unapproved calls, runs and persists',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'aggregate-runtime-',
      );
      final runtime = await MacRuntime.open(dataDirectory: directory);
      try {
        final connection = await runtime.addConnection(
          const ConnectionSpec(
            kind: ConnectionKind.cli,
            label: 'Print fixture',
            executable: '/usr/bin/printf',
          ),
        );
        expect(connection.status, ConnectionStatus.ready);
        final capabilities = await runtime.searchCapabilities(
          const SearchQuery('Print fixture'),
        );
        expect(capabilities, hasLength(1));
        final id = capabilities.single.id;

        final denied = await runtime.invoke(id, {
          'argv': ['hello'],
        });
        expect(
          (await runtime
                  .watchRun(denied.id)
                  .firstWhere((event) => event.state == RunState.failed))
              .failure
              ?.code,
          RuntimeErrorCode.permissionDenied,
        );

        final invalid = await runtime.invoke(id, {
          'argv': [17],
        }, permissionGranted: true);
        expect(
          (await runtime
                  .watchRun(invalid.id)
                  .firstWhere((event) => event.state == RunState.failed))
              .failure
              ?.code,
          RuntimeErrorCode.invalidArguments,
        );

        final approved = await runtime.invoke(id, {
          'argv': ['hello'],
        }, permissionGranted: true);
        final result = await runtime
            .watchRun(approved.id)
            .firstWhere(
              (event) =>
                  event.state == RunState.succeeded ||
                  event.state == RunState.failed,
            )
            .timeout(const Duration(seconds: 5));
        expect(result.state, RunState.succeeded);
        expect(result.blocks.first.value, 'hello');
        expect((await runtime.listRecentRuns()).first.latest.blocks, isEmpty);
      } finally {
        await runtime.dispose();
      }
      final restored = await MacRuntime.open(dataDirectory: directory);
      try {
        expect(await restored.listConnections(), hasLength(1));
        expect(await restored.listRecentRuns(), isNotEmpty);
      } finally {
        await restored.dispose();
        await directory.delete(recursive: true);
      }
    },
  );

  test(
    'stores HTTP token outside config and removes it with connection',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'aggregate-credentials-',
      );
      final credentials = _MemoryCredentials();
      final runtime = await MacRuntime.open(
        dataDirectory: directory,
        credentialStore: credentials,
      );
      try {
        await expectLater(
          runtime.addConnection(
            const ConnectionSpec(
              kind: ConnectionKind.mcpHttp,
              label: 'Unsafe',
              url: 'http://example.com/mcp',
              authToken: 'secret-token',
            ),
          ),
          throwsFormatException,
        );
        final connection = await runtime.addConnection(
          const ConnectionSpec(
            kind: ConnectionKind.mcpHttp,
            label: 'Local fixture',
            url: 'http://127.0.0.1:1/mcp',
            authToken: 'secret-token',
          ),
        );
        expect(connection.status, ConnectionStatus.unavailable);
        expect(credentials.values[connection.id.value], 'secret-token');
        final config = await File('${directory.path}/connections.json')
            .readAsString();
        expect(config, contains('hasCredential'));
        expect(config, isNot(contains('secret-token')));
        await runtime.removeConnection(connection.id);
        expect(credentials.values, isEmpty);
      } finally {
        await runtime.dispose();
        await directory.delete(recursive: true);
      }
    },
  );

  test('CLI action timeout produces a terminal run state', () async {
    final directory = await Directory.systemTemp.createTemp(
      'aggregate-timeout-',
    );
    final manifest = File('${directory.path}/sleep.json');
    await manifest.writeAsString(
      jsonEncode({
        'schemaVersion': 1,
        'id': 'sleep',
        'displayName': 'Sleep fixture',
        'platforms': ['macos'],
        'executable': '/bin/sleep',
        'actions': [
          {
            'id': 'pause',
            'title': 'Pause',
            'argv': ['5'],
            'inputSchema': {
              'type': 'object',
              'properties': <String, Object?>{},
            },
            'output': 'text',
            'permission': 'read',
            'timeoutMs': 100,
          },
        ],
      }),
    );
    final runtime = await MacRuntime.open(dataDirectory: directory);
    try {
      final connection = await runtime.addConnection(
        ConnectionSpec(
          kind: ConnectionKind.cli,
          label: 'Sleep fixture',
          executable: '/bin/sleep',
          manifestPath: manifest.path,
        ),
      );
      expect(connection.status, ConnectionStatus.ready);
      final action = (await runtime.searchCapabilities(
        const SearchQuery('Pause'),
      )).single;
      expect(action.permission, PermissionLevel.unknown);
      final handle = await runtime.invoke(
        action.id,
        {},
        permissionGranted: true,
      );
      final event = await runtime
          .watchRun(handle.id)
          .firstWhere((event) => event.state == RunState.timedOut)
          .timeout(const Duration(seconds: 3));
      expect(event.failure?.code, RuntimeErrorCode.timedOut);
    } finally {
      await runtime.dispose();
      await directory.delete(recursive: true);
    }
  });

  test(
    'unconfirmed music play runs once and reports unknown outcome',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'aggregate-music-unknown-',
      );
      final counter = File('${directory.path}/calls');
      final executable = File('${directory.path}/music-fixture');
      await executable.writeAsString(
        '#!/bin/sh\necho call >> "${counter.path}"\nexit 0\n',
      );
      expect(
        (await Process.run('/bin/chmod', ['+x', executable.path])).exitCode,
        0,
      );
      final manifest = File('${directory.path}/music.json');
      await manifest.writeAsString(
        jsonEncode({
          'schemaVersion': 1,
          'id': 'music-fixture',
          'displayName': 'Music fixture',
          'platforms': ['macos'],
          'executable': executable.path,
          'actions': [
            {
              'id': 'play',
              'title': 'Play',
              'argv': ['play'],
              'inputSchema': {
                'type': 'object',
                'properties': <String, Object?>{},
              },
              'output': 'json',
              'permission': 'localControl',
              'timeoutMs': 1000,
              'presentation': 'music.play',
            },
          ],
        }),
      );
      final runtime = await MacRuntime.open(
        dataDirectory: Directory('${directory.path}/data'),
      );
      try {
        final connection = await runtime.addConnection(
          ConnectionSpec(
            kind: ConnectionKind.cli,
            label: 'Music fixture',
            executable: executable.path,
            manifestPath: manifest.path,
          ),
        );
        expect(connection.status, ConnectionStatus.ready);
        final capability = (await runtime.searchCapabilities(
          const SearchQuery('Play'),
        )).single;
        final handle = await runtime.invoke(
          capability.id,
          {},
          permissionGranted: true,
        );
        final event = await runtime
            .watchRun(handle.id)
            .firstWhere((event) => event.state == RunState.outcomeUnknown)
            .timeout(const Duration(seconds: 5));
        expect(event.failure?.code, RuntimeErrorCode.outcomeUnknown);
        await Future<void>.delayed(const Duration(milliseconds: 700));
        expect(await counter.readAsLines(), hasLength(1));
      } finally {
        await runtime.dispose();
        await directory.delete(recursive: true);
      }
    },
  );

  test('long CLI run can be cancelled without waiting for exit', () async {
    final directory = await Directory.systemTemp.createTemp(
      'aggregate-cancel-',
    );
    final runtime = await MacRuntime.open(dataDirectory: directory);
    try {
      await runtime.addConnection(
        const ConnectionSpec(
          kind: ConnectionKind.cli,
          label: 'Sleep cancel fixture',
          executable: '/bin/sleep',
        ),
      );
      final id = (await runtime.searchCapabilities(
        const SearchQuery('Sleep cancel fixture'),
      )).single.id;
      final handle = await runtime.invoke(id, {
        'argv': ['5'],
      }, permissionGranted: true);
      await runtime
          .watchRun(handle.id)
          .firstWhere((event) => event.state == RunState.running)
          .timeout(const Duration(seconds: 3));
      await runtime.cancel(handle.id);
      final cancelled = await runtime
          .watchRun(handle.id)
          .firstWhere((event) => event.state == RunState.cancelled)
          .timeout(const Duration(seconds: 3));
      expect(cancelled.failure?.code, RuntimeErrorCode.cancelled);
    } finally {
      await runtime.dispose();
      await directory.delete(recursive: true);
    }
  });

  test(
    'bundled launcher stops CLI descendants on cancel and dispose',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'aggregate-cli-group-',
      );
      final source = File('app/macos/Runner/cli_launcher.c').existsSync()
          ? File('app/macos/Runner/cli_launcher.c')
          : File('macos/Runner/cli_launcher.c');
      final launcher = File('${directory.path}/aggregate-cli-launcher');
      final compile = await Process.run('/usr/bin/xcrun', [
        'clang',
        source.path,
        '-o',
        launcher.path,
      ]);
      expect(compile.exitCode, 0, reason: '${compile.stderr}');
      final script = File('${directory.path}/spawn-child');
      await script.writeAsString(
        '#!/bin/sh\nsleep 30 &\nchild=\$!\nprintf "%s\\n" "\$child" > "\$1"\nwait "\$child"\n',
      );
      expect(
        (await Process.run('/bin/chmod', ['+x', script.path])).exitCode,
        0,
      );
      final runtime = await MacRuntime.open(
        dataDirectory: Directory('${directory.path}/data'),
        cliLauncher: launcher,
      );
      var disposed = false;
      final children = <int>[];
      Future<bool> running(int pid) async {
        final state = await Process.run('/bin/ps', [
          '-o',
          'stat=',
          '-p',
          '$pid',
        ]);
        return state.exitCode == 0 && !'${state.stdout}'.trim().startsWith('Z');
      }

      Future<(RunHandle, int)> spawn(
        File pidFile,
        CapabilityId capability,
      ) async {
        final handle = await runtime.invoke(capability, {
          'argv': [pidFile.path],
        }, permissionGranted: true);
        for (
          var attempt = 0;
          attempt < 30 && !await pidFile.exists();
          attempt++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        expect(await pidFile.exists(), isTrue);
        final pid = int.parse((await pidFile.readAsString()).trim());
        children.add(pid);
        expect(await running(pid), isTrue);
        return (handle, pid);
      }

      Future<void> expectStopped(int pid) async {
        for (var attempt = 0; attempt < 30 && await running(pid); attempt++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        expect(await running(pid), isFalse);
      }

      try {
        await runtime.addConnection(
          ConnectionSpec(
            kind: ConnectionKind.cli,
            label: 'Child fixture',
            executable: script.path,
          ),
        );
        final capability = (await runtime.searchCapabilities(
          const SearchQuery('Child fixture'),
        )).single.id;
        final (firstHandle, firstPid) = await spawn(
          File('${directory.path}/first.pid'),
          capability,
        );
        await runtime.cancel(firstHandle.id);
        await expectStopped(firstPid);

        final timeoutManifest = File('${directory.path}/timeout.json');
        await timeoutManifest.writeAsString(
          jsonEncode({
            'schemaVersion': 1,
            'id': 'child-timeout',
            'displayName': 'Child timeout fixture',
            'platforms': ['macos'],
            'executable': script.path,
            'actions': [
              {
                'id': 'wait',
                'title': 'Wait for child',
                'argv': [File('${directory.path}/timeout.pid').path],
                'inputSchema': {
                  'type': 'object',
                  'properties': <String, Object?>{},
                },
                'output': 'text',
                'permission': 'read',
                'timeoutMs': 500,
              },
            ],
          }),
        );
        await runtime.addConnection(
          ConnectionSpec(
            kind: ConnectionKind.cli,
            label: 'Child timeout fixture',
            executable: script.path,
            manifestPath: timeoutManifest.path,
          ),
        );
        final timeoutCapability = (await runtime.searchCapabilities(
          const SearchQuery('Wait for child'),
        )).single.id;
        final timeoutHandle = await runtime.invoke(
          timeoutCapability,
          {},
          permissionGranted: true,
        );
        final timeoutPidFile = File('${directory.path}/timeout.pid');
        for (
          var attempt = 0;
          attempt < 30 && !await timeoutPidFile.exists();
          attempt++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        expect(await timeoutPidFile.exists(), isTrue);
        final timeoutPid = int.parse(
          (await timeoutPidFile.readAsString()).trim(),
        );
        children.add(timeoutPid);
        expect(
          (await runtime
                  .watchRun(timeoutHandle.id)
                  .firstWhere((event) => event.state == RunState.timedOut))
              .failure
              ?.code,
          RuntimeErrorCode.timedOut,
        );
        await expectStopped(timeoutPid);

        final (_, secondPid) = await spawn(
          File('${directory.path}/second.pid'),
          capability,
        );
        await runtime.dispose();
        disposed = true;
        await expectStopped(secondPid);
      } finally {
        if (!disposed) await runtime.dispose();
        for (final pid in children) {
          if (await running(pid)) Process.killPid(pid, ProcessSignal.sigkill);
        }
        await directory.delete(recursive: true);
      }
    },
  );

  test('preferences persist and clearing activity is durable', () async {
    final directory = await Directory.systemTemp.createTemp('aggregate-prefs-');
    final runtime = await MacRuntime.open(dataDirectory: directory);
    try {
      await runtime.savePreferences(
        const UserPreferences(
          appearance: AppearancePreference.light,
          activityRetentionDays: 7,
          favoriteCapabilityKeys: ['favorite-one'],
          preferredConnectionId: 'example-cli',
        ),
      );
      await runtime.clearActivity();
      expect(await runtime.listRecentRuns(), isEmpty);
    } finally {
      await runtime.dispose();
    }
    final restored = await MacRuntime.open(dataDirectory: directory);
    try {
      final preferences = await restored.loadPreferences();
      expect(preferences.appearance, AppearancePreference.light);
      expect(preferences.activityRetentionDays, 7);
      expect(preferences.favoriteCapabilityKeys, ['favorite-one']);
      expect(preferences.preferredConnectionId, 'example-cli');
      expect(await restored.listRecentRuns(), isEmpty);
    } finally {
      await restored.dispose();
      await directory.delete(recursive: true);
    }
  });

  test('damaged startup config is backed up and reported', () async {
    final directory = await Directory.systemTemp.createTemp(
      'aggregate-damaged-config-',
    );
    await File('${directory.path}/preferences.json').writeAsString('{bad');
    await File('${directory.path}/connections.json')
        .writeAsString('{"schemaVersion":2,"connections":[]}');
    final runtime = await MacRuntime.open(dataDirectory: directory);
    try {
      expect(runtime.startupNotices, hasLength(2));
      expect(runtime.startupNotices.join(), contains('已备份'));
      expect(await runtime.listConnections(), isEmpty);
      expect(
        (await runtime.loadPreferences()).appearance,
        AppearancePreference.system,
      );
      expect(
        directory.listSync().where((item) => item.path.contains('.damaged-')),
        hasLength(2),
      );
      expect(
        jsonDecode(
          await File('${directory.path}/connections.json').readAsString(),
        )['schemaVersion'],
        1,
      );
    } finally {
      await runtime.dispose();
    }
    final restarted = await MacRuntime.open(dataDirectory: directory);
    try {
      expect(restarted.startupNotices, isEmpty);
    } finally {
      await restarted.dispose();
      await directory.delete(recursive: true);
    }
  });

  test('action manifest can be saved, exported, and restored', () async {
    final directory = await Directory.systemTemp.createTemp(
      'aggregate-actions-',
    );
    final runtime = await MacRuntime.open(dataDirectory: directory);
    late ConnectionId id;
    try {
      final connection = await runtime.addConnection(
        const ConnectionSpec(
          kind: ConnectionKind.cli,
          label: 'Print actions',
          executable: '/usr/bin/printf',
        ),
      );
      id = connection.id;
      expect(await runtime.loadActionManifest(id), isNull);
      final manifest = <String, Object?>{
        'schemaVersion': 1,
        'id': 'print-actions',
        'displayName': 'Print actions',
        'platforms': ['macos'],
        'executable': '/usr/bin/printf',
        'actions': [
          {
            'id': 'say',
            'title': 'Say',
            'argv': ['%s', '{{text}}'],
            'inputSchema': {
              'type': 'object',
              'properties': {
                'text': {'type': 'string'},
              },
              'required': ['text'],
            },
            'output': 'text',
            'permission': 'read',
            'timeoutMs': 30000,
          },
        ],
      };
      await runtime.saveActionManifest(id, manifest);
      expect((await runtime.loadActionManifest(id))?['id'], 'print-actions');
      final exported = File('${directory.path}/export.json');
      await runtime.exportActionManifest(id, manifest, exported.path);
      expect(
        (await runtime.readActionManifestFile(exported.path))['id'],
        'print-actions',
      );
      final action = (await runtime.searchCapabilities(
        const SearchQuery('Say'),
      )).single;
      final handle = await runtime.invoke(action.id, {
        'text': 'hello',
      }, permissionGranted: true);
      final event = await runtime
          .watchRun(handle.id)
          .firstWhere((event) => event.state == RunState.succeeded);
      expect(event.blocks.first.value, 'hello');
      await expectLater(
        runtime.saveActionManifest(id, {...manifest, 'schemaVersion': 2}),
        throwsFormatException,
      );
    } finally {
      await runtime.dispose();
    }
    final restored = await MacRuntime.open(dataDirectory: directory);
    try {
      expect((await restored.loadActionManifest(id))?['id'], 'print-actions');
      expect(
        (await restored.searchCapabilities(const SearchQuery('Say'))),
        hasLength(1),
      );
    } finally {
      await restored.dispose();
      await directory.delete(recursive: true);
    }
  });

  test('connection order survives a restart', () async {
    final directory = await Directory.systemTemp.createTemp('aggregate-order-');
    final runtime = await MacRuntime.open(dataDirectory: directory);
    late ConnectionId second;
    try {
      await runtime.addConnection(
        const ConnectionSpec(
          kind: ConnectionKind.cli,
          label: 'First',
          executable: '/usr/bin/printf',
        ),
      );
      second = (await runtime.addConnection(
        const ConnectionSpec(
          kind: ConnectionKind.cli,
          label: 'Second',
          executable: '/usr/bin/printf',
        ),
      )).id;
      await runtime.moveConnection(second, -1);
      expect((await runtime.listConnections()).first.label, 'Second');
    } finally {
      await runtime.dispose();
    }
    final restored = await MacRuntime.open(dataDirectory: directory);
    try {
      expect((await restored.listConnections()).first.id.value, second.value);
    } finally {
      await restored.dispose();
      await directory.delete(recursive: true);
    }
  });

  test('a failed preference write does not block later writes', () async {
    final directory = await Directory.systemTemp.createTemp(
      'aggregate-write-recovery-',
    );
    final runtime = await MacRuntime.open(dataDirectory: directory);
    final occupied = Directory('${directory.path}/preferences.json');
    try {
      await occupied.create();
      await expectLater(
        runtime.savePreferences(
          const UserPreferences(appearance: AppearancePreference.dark),
        ),
        throwsA(isA<FileSystemException>()),
      );
      await occupied.delete();
      await runtime.savePreferences(
        const UserPreferences(appearance: AppearancePreference.light),
      );
      expect(
        jsonDecode(await File(occupied.path).readAsString())['appearance'],
        'light',
      );
    } finally {
      await runtime.dispose();
      await directory.delete(recursive: true);
    }
  });

  test(
    'file preview reads bounded text and rejects unsupported files',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'aggregate-file-preview-',
      );
      final runtime = await MacRuntime.open(dataDirectory: directory);
      try {
        final textFile = File('${directory.path}/result.txt');
        await textFile.writeAsString('preview fixture');
        final preview = await runtime.previewLocalFile(textFile.path);
        expect(preview.single.kind, ResultKind.text);
        expect(preview.single.value, 'preview fixture');
        final unsupported = File('${directory.path}/program.sh');
        await unsupported.writeAsString('echo unsafe');
        await expectLater(
          runtime.previewLocalFile(unsupported.path),
          throwsFormatException,
        );
      } finally {
        await runtime.dispose();
        await directory.delete(recursive: true);
      }
    },
  );

  test('HTTP auth failures give safe repair steps', () async {
    final directory = await Directory.systemTemp.createTemp('aggregate-auth-');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var status = HttpStatus.unauthorized;
    final subscription = server.listen((request) async {
      request.response.statusCode = status;
      if (status == HttpStatus.ok) {
        request.response.headers.contentType = ContentType.text;
        request.response.write('not an MCP response');
      }
      await request.response.close();
    });
    final runtime = await MacRuntime.open(
      dataDirectory: directory,
      credentialStore: _MemoryCredentials(),
    );
    try {
      final connection = await runtime.addConnection(
        ConnectionSpec(
          kind: ConnectionKind.mcpHttp,
          label: 'Auth fixture',
          url: 'http://127.0.0.1:${server.port}/mcp',
          authToken: 'private-test-token',
        ),
      );
      expect(connection.status, ConnectionStatus.unavailable);
      expect(connection.diagnostic, contains('认证'));
      expect(connection.diagnostic, isNot(contains('private-test-token')));
      status = HttpStatus.forbidden;
      final forbidden = await runtime.refreshConnection(connection.id);
      expect(forbidden.status, ConnectionStatus.unavailable);
      expect(forbidden.diagnostic, contains('权限'));
      status = HttpStatus.ok;
      final incompatible = await runtime.refreshConnection(connection.id);
      expect(incompatible.status, ConnectionStatus.unavailable);
      expect(incompatible.diagnostic, contains('协议不兼容'));
    } finally {
      await runtime.dispose();
      await subscription.cancel();
      await server.close(force: true);
      await directory.delete(recursive: true);
    }
  });

  test('repeated CLI runs survive errors and output overflow', () async {
    final directory = await Directory.systemTemp.createTemp('aggregate-load-');
    final runtime = await MacRuntime.open(dataDirectory: directory);
    try {
      await runtime.addConnection(
        const ConnectionSpec(
          kind: ConnectionKind.cli,
          label: 'Print load',
          executable: '/usr/bin/printf',
        ),
      );
      final printId = (await runtime.searchCapabilities(
        const SearchQuery('Print load'),
      )).single.id;
      for (var index = 0; index < 12; index++) {
        final run = await runtime.invoke(printId, {
          'argv': ['run-$index'],
        }, permissionGranted: true);
        final event = await runtime
            .watchRun(run.id)
            .firstWhere((item) => item.state == RunState.succeeded)
            .timeout(const Duration(seconds: 5));
        expect(event.blocks.first.value, 'run-$index');
      }
      await runtime.addConnection(
        const ConnectionSpec(
          kind: ConnectionKind.cli,
          label: 'False load',
          executable: '/usr/bin/false',
        ),
      );
      final failId = (await runtime.searchCapabilities(
        const SearchQuery('False load'),
      )).single.id;
      final failRun = await runtime.invoke(failId, {
        'argv': <String>[],
      }, permissionGranted: true);
      final failed = await runtime
          .watchRun(failRun.id)
          .firstWhere((item) => item.state == RunState.failed)
          .timeout(const Duration(seconds: 5));
      expect(failed.failure?.message, contains('退出码'));
      await runtime.addConnection(
        const ConnectionSpec(
          kind: ConnectionKind.cli,
          label: 'Yes load',
          executable: '/usr/bin/yes',
        ),
      );
      final noisyId = (await runtime.searchCapabilities(
        const SearchQuery('Yes load'),
      )).single.id;
      final noisyRun = await runtime.invoke(noisyId, {
        'argv': <String>[],
      }, permissionGranted: true);
      final overflow = await runtime
          .watchRun(noisyRun.id)
          .firstWhere((item) => item.state == RunState.failed)
          .timeout(const Duration(seconds: 5));
      expect(overflow.failure?.code, RuntimeErrorCode.outputLimitExceeded);
    } finally {
      await runtime.dispose();
      await directory.delete(recursive: true);
    }
  });
}

final class _MemoryCredentials implements CredentialStore {
  final values = <String, String>{};

  @override
  Future<void> write(String connectionId, String token) async {
    values[connectionId] = token;
  }

  @override
  Future<String?> read(String connectionId) async => values[connectionId];

  @override
  Future<void> delete(String connectionId) async {
    values.remove(connectionId);
  }
}
