import 'dart:async';
import 'dart:io';

import 'package:aggregate/platform/android/android_credential_store.dart';
import 'package:aggregate/platform/android/android_runtime_port.dart';
import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:mcp_dart/mcp_dart.dart' as mcp;

final class _MemoryCredentials implements AndroidCredentialStore {
  final values = <String, String>{};
  bool rejectWrite = false;
  Completer<void>? writeStarted;
  Completer<void>? allowWrite;

  @override
  Future<void> write(String connectionId, String token) async {
    if (rejectWrite) throw StateError('secure storage unavailable');
    final started = writeStarted;
    final release = allowWrite;
    if (started != null && release != null) {
      started.complete();
      await release.future;
    }
    values[connectionId] = token;
  }

  @override
  Future<String?> read(String connectionId) async => values[connectionId];

  @override
  Future<void> delete(String connectionId) async {
    values.remove(connectionId);
  }

  @override
  Future<void> removeOrphans(Set<String> activeIds) async {
    values.removeWhere((key, _) => !activeIds.contains(key));
  }
}

mcp.McpServer _server() {
  final server = mcp.McpServer(
    const mcp.Implementation(name: 'aggregate-a2-fixture', version: '1.0.0'),
    options: const mcp.McpServerOptions(protocol: mcp.McpProtocol.stable),
  );
  server.registerTool(
    'echo',
    description: 'Echo a short message',
    inputSchema: mcp.JsonSchema.object(
      properties: {'text': mcp.JsonSchema.string()},
      required: ['text'],
    ),
    callback: (args, extra) async => mcp.CallToolResult.fromContent([
      mcp.TextContent(text: 'Echo: ${args['text']}'),
    ]),
  );
  server.registerTool(
    'slow',
    description: 'A cancellable wait fixture',
    inputSchema: mcp.JsonSchema.object(properties: {}),
    callback: (args, extra) async {
      await Future<void>.delayed(const Duration(seconds: 2));
      return mcp.CallToolResult.fromContent([
        mcp.TextContent(text: 'late result'),
      ]);
    },
  );
  server.registerResource(
    'fixture-resource',
    'https://example.test/a2-resource',
    (mimeType: 'text/plain', description: null),
    (uri, extra) async => mcp.ReadResourceResult(
      contents: [
        mcp.ResourceContents.fromJson({
          'uri': 'https://example.test/a2-resource',
          'text': 'resource body',
          'mimeType': 'text/plain',
        }),
      ],
    ),
  );
  server.registerPrompt(
    'fixture-prompt',
    argsSchema: {'name': const mcp.PromptArgumentDefinition(required: true)},
    callback: (args, extra) async => mcp.GetPromptResult(
      messages: [
        mcp.PromptMessage(
          role: mcp.PromptMessageRole.user,
          content: mcp.TextContent(text: 'Hello ${args!['name']}'),
        ),
      ],
    ),
  );
  return server;
}

void main() {
  test('Android does not persist Mac targets or connector profiles', () async {
    final root = await Directory.systemTemp.createTemp(
      'aggregate-android-profile-boundary-',
    );
    final credentials = _MemoryCredentials();
    final runtime = await AndroidRuntimePort.open(
      dataDirectory: root,
      credentialStore: credentials,
    );
    try {
      for (final spec in [
        const ConnectionSpec(
          kind: ConnectionKind.mcpHttp,
          label: 'Mac profile',
          url: 'https://example.test/mcp',
          authToken: 'private-token',
          profileId: 'mac-profile-1',
        ),
        ConnectionSpec(
          kind: ConnectionKind.mcpHttp,
          label: 'Wrong target',
          url: 'https://example.test/mcp',
          authToken: 'private-token',
          executionTarget: ExecutionTarget.host(
            'host-0123456789abcdef0123456789abcdef',
          ),
        ),
      ]) {
        final report = await runtime.testConnectionSetup(
          ConnectionSetupDraft(adapterId: 'mcp-http', spec: spec),
        );
        expect(report.canSave, isFalse);
        expect(report.checks.single.detail, isNot(contains('private-token')));
      }

      expect(await runtime.listConnections(), isEmpty);
      expect(credentials.values, isEmpty);
      expect(await File('${root.path}/connections.json').exists(), isFalse);
      expect(
        await Directory('${root.path}/connector-profiles').exists(),
        isFalse,
      );
    } finally {
      await runtime.dispose();
      await root.delete(recursive: true);
    }
  });

  test(
    'draft expires and is discarded on background or process restart',
    () async {
      final root = await Directory.systemTemp.createTemp('aggregate-a2-ttl-');
      final credentials = _MemoryCredentials();
      final server = mcp.StreamableMcpServer(
        serverFactory: (_) => _server(),
        host: '127.0.0.1',
        port: 0,
        path: '/mcp',
        allowedHosts: const {'127.0.0.1'},
      );
      await server.start();
      var runtime = await AndroidRuntimePort.open(
        dataDirectory: root,
        credentialStore: credentials,
        draftTtl: const Duration(milliseconds: 50),
      );
      final spec = ConnectionSpec(
        kind: ConnectionKind.mcpHttp,
        label: '草稿生命周期',
        url: 'http://127.0.0.1:${server.boundPort}/mcp',
      );
      Future<ConnectionSetupReport> probe() => runtime.testConnectionSetup(
        ConnectionSetupDraft(adapterId: 'mcp-http', spec: spec),
      );
      try {
        final expired = await probe();
        expect(expired.canSave, isTrue);
        await Future<void>.delayed(const Duration(milliseconds: 90));
        await expectLater(
          runtime.saveConnectionSetup(expired.draftId),
          throwsStateError,
        );

        final backgrounded = await probe();
        runtime.didChangeAppLifecycleState(AppLifecycleState.paused);
        await expectLater(
          runtime.saveConnectionSetup(backgrounded.draftId),
          throwsStateError,
        );

        final restarted = await probe();
        await runtime.dispose();
        runtime = await AndroidRuntimePort.open(
          dataDirectory: root,
          credentialStore: credentials,
          draftTtl: const Duration(milliseconds: 50),
        );
        await expectLater(
          runtime.saveConnectionSetup(restarted.draftId),
          throwsStateError,
        );
        expect(await runtime.listConnections(), isEmpty);
        expect(credentials.values, isEmpty);
      } finally {
        await runtime.dispose();
        await server.stop();
        await root.delete(recursive: true);
      }
    },
  );

  test(
    'discard during save rolls back token and preserves concurrent save',
    () async {
      final root = await Directory.systemTemp.createTemp('aggregate-a2-race-');
      final credentials = _MemoryCredentials();
      final server = mcp.StreamableMcpServer(
        serverFactory: (_) => _server(),
        host: '127.0.0.1',
        port: 0,
        path: '/mcp',
        allowedHosts: const {'127.0.0.1'},
      );
      await server.start();
      final runtime = await AndroidRuntimePort.open(
        dataDirectory: root,
        credentialStore: credentials,
      );
      try {
        final spec = ConnectionSpec(
          kind: ConnectionKind.mcpHttp,
          label: '并发测试',
          url: 'http://127.0.0.1:${server.boundPort}/mcp',
          authToken: 'secret',
        );
        Future<ConnectionSetupReport> probe() => runtime.testConnectionSetup(
          ConnectionSetupDraft(adapterId: 'mcp-http', spec: spec),
        );
        final first = await probe();
        final second = await probe();
        expect(first.canSave, isTrue);
        expect(second.canSave, isTrue);
        credentials.writeStarted = Completer<void>();
        credentials.allowWrite = Completer<void>();
        final savingFirst = runtime.saveConnectionSetup(first.draftId);
        final firstFailure = expectLater(savingFirst, throwsStateError);
        await credentials.writeStarted!.future;
        await expectLater(
          runtime.saveConnectionSetup(first.draftId),
          throwsStateError,
        );
        final savingSecond = runtime.saveConnectionSetup(second.draftId);
        await runtime.discardConnectionSetup(first.draftId);
        credentials.writeStarted = null;
        final release = credentials.allowWrite!;
        credentials.allowWrite = null;
        release.complete();
        await firstFailure;
        final saved = await savingSecond;
        expect(
          (await runtime.listConnections()).single.id.value,
          saved.id.value,
        );
        expect(credentials.values, {saved.id.value: 'secret'});
        final json = await File('${root.path}/connections.json').readAsString();
        expect(json, isNot(contains('secret')));
      } finally {
        await runtime.dispose();
        await server.stop();
        await root.delete(recursive: true);
      }
    },
  );

  test('HTTP setup, call, restart and delete keep token out of JSON', () async {
    final root = await Directory.systemTemp.createTemp('aggregate-a2-http-');
    final credentials = _MemoryCredentials();
    final server = mcp.StreamableMcpServer(
      serverFactory: (_) => _server(),
      host: '127.0.0.1',
      port: 0,
      path: '/mcp',
      allowedHosts: const {'127.0.0.1'},
    );
    await server.start();
    var runtime = await AndroidRuntimePort.open(
      dataDirectory: root,
      credentialStore: credentials,
    );
    try {
      final spec = ConnectionSpec(
        kind: ConnectionKind.mcpHttp,
        label: '本地测试',
        url: 'http://127.0.0.1:${server.boundPort}/mcp',
        authToken: 'private-token',
      );
      final discarded = await runtime.testConnectionSetup(
        ConnectionSetupDraft(adapterId: 'mcp-http', spec: spec),
      );
      expect(discarded.canSave, isTrue, reason: discarded.checks.last.detail);
      expect(await runtime.listConnections(), isEmpty);
      await runtime.discardConnectionSetup(discarded.draftId);
      await expectLater(
        runtime.saveConnectionSetup(discarded.draftId),
        throwsStateError,
      );

      final tested = await runtime.testConnectionSetup(
        ConnectionSetupDraft(adapterId: 'mcp-http', spec: spec),
      );
      expect(tested.canSave, isTrue);
      credentials.rejectWrite = true;
      await expectLater(
        runtime.saveConnectionSetup(tested.draftId),
        throwsStateError,
      );
      expect(await runtime.listConnections(), isEmpty);
      expect(await File('${root.path}/connections.json').exists(), isFalse);
      credentials.rejectWrite = false;
      final connection = await runtime.saveConnectionSetup(tested.draftId);
      expect(connection.status, ConnectionStatus.ready);
      await expectLater(
        runtime.saveConnectionSetup(tested.draftId),
        throwsStateError,
      );
      final saved = await File('${root.path}/connections.json').readAsString();
      expect(saved, isNot(contains('private-token')));
      expect(saved, contains('hasCredential'));
      expect(credentials.values[connection.id.value], 'private-token');

      final capabilities = await runtime.searchCapabilities(
        const SearchQuery('echo'),
      );
      expect(capabilities.map((item) => item.id.name), ['echo']);
      final resource = (await runtime.searchCapabilities(
        const SearchQuery('', kind: CapabilityKind.mcpResource),
      )).single;
      final resourceBlocks = await runtime.readResource(
        ResourceRef(resource.id, Uri.parse(resource.id.name)),
      );
      expect(resourceBlocks.single.value.toString(), contains('resource body'));
      final prompt = (await runtime.searchCapabilities(
        const SearchQuery('', kind: CapabilityKind.mcpPrompt),
      )).single;
      final promptBlocks = await runtime.getPrompt(PromptRef(prompt.id), {
        'name': 'A2',
      });
      expect(promptBlocks.single.value.toString(), contains('Hello A2'));
      final handle = await runtime.invoke(capabilities.single.id, {
        'text': 'hello',
      }, permissionGranted: true);
      final terminal = await runtime
          .watchRun(handle.id)
          .firstWhere((event) => event.state == RunState.succeeded);
      expect(terminal.blocks.first.value, 'Echo: hello');
      expect((await runtime.listRecentRuns()).single.latest.blocks, isEmpty);

      credentials.values.remove(connection.id.value);
      expect(
        (await runtime.refreshConnection(connection.id)).status,
        ConnectionStatus.unavailable,
      );
      expect(
        (await runtime.listConnections()).single.diagnostic,
        contains('凭证已丢失'),
      );
      credentials.values[connection.id.value] = 'private-token';
      expect(
        (await runtime.refreshConnection(connection.id)).status,
        ConnectionStatus.ready,
      );

      final invalid = await runtime.invoke(
        capabilities.single.id,
        {},
        permissionGranted: true,
      );
      expect(
        (await runtime
                .watchRun(invalid.id)
                .firstWhere((event) => event.state == RunState.failed))
            .failure
            ?.code,
        RuntimeErrorCode.invalidArguments,
      );

      final slow = (await runtime.searchCapabilities(const SearchQuery('slow')))
          .single;
      final waiting = await runtime.invoke(
        slow.id,
        {},
        permissionGranted: true,
      );
      await runtime.cancel(waiting.id);
      expect(
        (await runtime.listRecentRuns()).first.latest.state,
        RunState.outcomeUnknown,
      );
      expect(
        (await runtime.listConnections()).single.status,
        ConnectionStatus.unavailable,
      );

      await runtime.dispose();
      runtime = await AndroidRuntimePort.open(
        dataDirectory: root,
        credentialStore: credentials,
      );
      expect(
        (await runtime.listConnections()).single.status,
        ConnectionStatus.ready,
      );
      expect(
        await runtime.searchCapabilities(const SearchQuery('echo')),
        hasLength(1),
      );
      await runtime.removeConnection(connection.id);
      expect(await runtime.listConnections(), isEmpty);
      expect(credentials.values, isEmpty);
    } finally {
      await runtime.dispose();
      await server.stop();
      await root.delete(recursive: true);
    }
  });

  test(
    'invalid and offline drafts never create a connection or credential',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'aggregate-a2-failure-',
      );
      final credentials = _MemoryCredentials();
      final runtime = await AndroidRuntimePort.open(
        dataDirectory: root,
        credentialStore: credentials,
      );
      try {
        final invalid = await runtime.testConnectionSetup(
          const ConnectionSetupDraft(
            adapterId: 'mcp-http',
            spec: ConnectionSpec(
              kind: ConnectionKind.mcpHttp,
              label: 'Invalid',
              url: 'http://example.com/mcp',
              authToken: 'private-token',
            ),
          ),
        );
        expect(invalid.canSave, isFalse);
        expect(invalid.checks.single.detail, isNot(contains('private-token')));
        final listener = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final port = listener.port;
        await listener.close();
        final offline = await runtime.testConnectionSetup(
          ConnectionSetupDraft(
            adapterId: 'mcp-http',
            spec: ConnectionSpec(
              kind: ConnectionKind.mcpHttp,
              label: 'Offline',
              url: 'http://127.0.0.1:$port/mcp',
            ),
          ),
        );
        expect(offline.canSave, isFalse);
        final unauthorized = await HttpServer.bind(
          InternetAddress.loopbackIPv4,
          0,
        );
        unauthorized.listen((request) async {
          request.response.statusCode = 401;
          await request.response.close();
        });
        try {
          final denied = await runtime.testConnectionSetup(
            ConnectionSetupDraft(
              adapterId: 'mcp-http',
              spec: ConnectionSpec(
                kind: ConnectionKind.mcpHttp,
                label: 'Denied',
                url: 'http://127.0.0.1:${unauthorized.port}/mcp',
                authToken: 'private-token',
              ),
            ),
          );
          expect(denied.canSave, isFalse);
          expect(denied.checks.single.detail, contains('认证失败'));
          expect(denied.checks.single.detail, isNot(contains('private-token')));
        } finally {
          await unauthorized.close(force: true);
        }
        expect(await runtime.listConnections(), isEmpty);
        expect(credentials.values, isEmpty);
        expect(await File('${root.path}/connections.json').exists(), isFalse);
      } finally {
        await runtime.dispose();
        await root.delete(recursive: true);
      }
    },
  );

  test('drafts clear on background and preferences survive restart', () async {
    final root = await Directory.systemTemp.createTemp('aggregate-a2-pref-');
    final credentials = _MemoryCredentials()..values['orphan'] = 'old';
    var runtime = await AndroidRuntimePort.open(
      dataDirectory: root,
      credentialStore: credentials,
    );
    try {
      expect(credentials.values, isEmpty);
      await runtime.savePreferences(
        const UserPreferences(appearance: AppearancePreference.dark),
      );
      runtime.didChangeAppLifecycleState(AppLifecycleState.paused);
      await runtime.dispose();
      runtime = await AndroidRuntimePort.open(
        dataDirectory: root,
        credentialStore: credentials,
      );
      expect(
        (await runtime.loadPreferences()).appearance,
        AppearancePreference.dark,
      );
    } finally {
      await runtime.dispose();
      await root.delete(recursive: true);
    }
  });

  test(
    'damaged connection JSON is backed up without deleting credentials',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'aggregate-a2-damaged-',
      );
      final credentials = _MemoryCredentials()..values['existing'] = 'keep';
      await File('${root.path}/connections.json').writeAsString('{broken');
      final runtime = await AndroidRuntimePort.open(
        dataDirectory: root,
        credentialStore: credentials,
      );
      try {
        expect(await runtime.listConnections(), isEmpty);
        expect(credentials.values['existing'], 'keep');
        expect(runtime.startupNotices.join(), contains('已备份'));
        expect(
          root.listSync().where((item) => item.path.contains('.damaged-')),
          hasLength(1),
        );
      } finally {
        await runtime.dispose();
        await root.delete(recursive: true);
      }
    },
  );
}
