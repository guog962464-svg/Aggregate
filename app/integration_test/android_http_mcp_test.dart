import 'dart:io';

import 'package:aggregate/platform/android/android_runtime_port.dart';
import 'package:aggregate/features/connections/connection_setup_dialog.dart';
import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mcp_dart/mcp_dart.dart' as mcp;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const externalEndpoint = String.fromEnvironment('A2_EXTERNAL_MCP_URL');
  const switchWifi = bool.fromEnvironment('A2_WIFI_SWITCH_TEST');

  testWidgets('physical Android remote HTTPS MCP and network recovery', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final runtime = await AndroidRuntimePort.open();
      ConnectionId? added;
      try {
        final report = await runtime.testConnectionSetup(
          const ConnectionSetupDraft(
            adapterId: 'mcp-http',
            spec: ConnectionSpec(
              kind: ConnectionKind.mcpHttp,
              label: 'A2 外部服务临时测试',
              url: externalEndpoint,
            ),
          ),
        );
        expect(report.canSave, isTrue, reason: report.checks.last.detail);
        final connection = await runtime.saveConnectionSetup(report.draftId);
        added = connection.id;
        expect(connection.status, ConnectionStatus.ready);
        final tool = (await runtime.searchCapabilities(
          const SearchQuery('get_site_info'),
        )).singleWhere((item) => item.id.connection.value == added!.value);
        Future<void> call() async {
          final handle = await runtime.invoke(
            tool.id,
            {},
            permissionGranted: true,
          );
          final result = await runtime
              .watchRun(handle.id)
              .firstWhere(
                (event) =>
                    event.state == RunState.succeeded ||
                    event.state == RunState.failed ||
                    event.state == RunState.outcomeUnknown,
              );
          expect(
            result.state,
            RunState.succeeded,
            reason: result.failure?.message,
          );
          expect(result.blocks, isNotEmpty);
        }

        await call();
        if (switchWifi) {
          // The host runner toggles device Wi-Fi after each printed marker.
          // The device has no SIM, so recovery returns to the same Wi-Fi.
          // ignore: avoid_print
          print('A2_WIFI_OFF_READY');
          await Future<void>.delayed(const Duration(seconds: 8));
          expect(
            (await runtime.refreshConnection(connection.id)).status,
            ConnectionStatus.unavailable,
          );
          // ignore: avoid_print
          print('A2_WIFI_ON_READY');
          await Future<void>.delayed(const Duration(seconds: 8));
          Connection? restored;
          for (var attempt = 0; attempt < 5; attempt++) {
            restored = await runtime.refreshConnection(connection.id);
            if (restored.status == ConnectionStatus.ready) break;
            await Future<void>.delayed(const Duration(seconds: 2));
          }
          expect(restored?.status, ConnectionStatus.ready);
          await call();
        }
      } finally {
        if (added != null) await runtime.removeConnection(added);
        await runtime.dispose();
      }
    });
  }, skip: externalEndpoint.isEmpty);

  testWidgets('physical Android HTTP MCP and secure storage round trip', (
    tester,
  ) async {
    expect(Platform.isAndroid, isTrue);
    await tester.runAsync(() async {
      final server = mcp.StreamableMcpServer(
        serverFactory: (_) {
          final fixture = mcp.McpServer(
            const mcp.Implementation(name: 'android-a2', version: '1.0.0'),
            options: const mcp.McpServerOptions(
              protocol: mcp.McpProtocol.stable,
            ),
          );
          fixture.registerTool(
            'echo',
            description: 'Echo a value',
            inputSchema: mcp.JsonSchema.object(
              properties: {'text': mcp.JsonSchema.string()},
              required: ['text'],
            ),
            callback: (args, extra) async => mcp.CallToolResult.fromContent([
              mcp.TextContent(text: 'Android: ${args['text']}'),
            ]),
          );
          fixture.registerTool(
            'slow',
            inputSchema: mcp.JsonSchema.object(properties: {}),
            callback: (args, extra) async {
              await Future<void>.delayed(const Duration(seconds: 3));
              return mcp.CallToolResult.fromContent([
                mcp.TextContent(text: 'late response'),
              ]);
            },
          );
          return fixture;
        },
        host: '127.0.0.1',
        port: 0,
        path: '/mcp',
        allowedHosts: const {'127.0.0.1'},
      );
      await server.start();
      var runtime = await AndroidRuntimePort.open();
      ConnectionId? added;
      try {
        final report = await runtime.testConnectionSetup(
          ConnectionSetupDraft(
            adapterId: 'mcp-http',
            spec: ConnectionSpec(
              kind: ConnectionKind.mcpHttp,
              label: 'A2 真机临时服务',
              url: 'http://127.0.0.1:${server.boundPort}/mcp',
              authToken: 'device-test-token',
            ),
          ),
        );
        expect(report.canSave, isTrue, reason: report.checks.last.detail);
        final connection = await runtime.saveConnectionSetup(report.draftId);
        added = connection.id;
        expect(connection.status, ConnectionStatus.ready);
        final echo = (await runtime.searchCapabilities(
          const SearchQuery('echo'),
        )).singleWhere((item) => item.id.connection.value == added!.value);
        final handle = await runtime.invoke(echo.id, {
          'text': 'ok',
        }, permissionGranted: true);
        final result = await runtime
            .watchRun(handle.id)
            .firstWhere((event) => event.state == RunState.succeeded);
        expect(result.blocks.first.value, 'Android: ok');
        final slow = (await runtime.searchCapabilities(
          const SearchQuery('slow'),
        )).singleWhere((item) => item.id.connection.value == added!.value);
        final pending = await runtime.invoke(
          slow.id,
          {},
          permissionGranted: true,
        );
        await runtime.cancel(pending.id);
        expect(
          (await runtime.listRecentRuns()).first.latest.state,
          RunState.outcomeUnknown,
        );
        expect(
          (await runtime.refreshConnection(connection.id)).status,
          ConnectionStatus.ready,
        );
        await runtime.dispose();
        runtime = await AndroidRuntimePort.open();
        expect(
          (await runtime.listConnections())
              .singleWhere((item) => item.id.value == added!.value)
              .status,
          ConnectionStatus.ready,
        );
      } finally {
        if (added != null) await runtime.removeConnection(added);
        await runtime.dispose();
        await server.stop();
      }
    });
  });

  testWidgets('physical Android rejects 401 and times out a silent server', (
    tester,
  ) async {
    expect(Platform.isAndroid, isTrue);
    await tester.runAsync(() async {
      final runtime = await AndroidRuntimePort.open();
      final unauthorized = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      unauthorized.listen((request) async {
        request.response.statusCode = 401;
        await request.response.close();
      });
      final silent = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      silent.listen((request) {
        // Deliberately hold the response until the client times out.
      });
      try {
        final denied = await runtime.testConnectionSetup(
          ConnectionSetupDraft(
            adapterId: 'mcp-http',
            spec: ConnectionSpec(
              kind: ConnectionKind.mcpHttp,
              label: 'A2 错误 Token 测试',
              url: 'http://127.0.0.1:${unauthorized.port}/mcp',
              authToken: 'not-a-real-token',
            ),
          ),
        );
        expect(denied.canSave, isFalse);
        expect(denied.checks.single.detail, contains('认证失败'));
        expect(
          denied.checks.single.detail,
          isNot(contains('not-a-real-token')),
        );
        final timedOut = await runtime.testConnectionSetup(
          ConnectionSetupDraft(
            adapterId: 'mcp-http',
            spec: ConnectionSpec(
              kind: ConnectionKind.mcpHttp,
              label: 'A2 无响应测试',
              url: 'http://127.0.0.1:${silent.port}/mcp',
            ),
          ),
        );
        expect(timedOut.canSave, isFalse);
        expect(timedOut.checks.single.detail, contains('超时'));
      } finally {
        await runtime.dispose();
        await unauthorized.close(force: true);
        await silent.close(force: true);
      }
    });
  });

  testWidgets('physical Android setup form saves a tested HTTP connection', (
    tester,
  ) async {
    late mcp.StreamableMcpServer server;
    late AndroidRuntimePort runtime;
    await tester.runAsync(() async {
      server = mcp.StreamableMcpServer(
        serverFactory: (_) {
          final fixture = mcp.McpServer(
            const mcp.Implementation(name: 'android-ui-a2', version: '1.0.0'),
            options: const mcp.McpServerOptions(
              protocol: mcp.McpProtocol.stable,
            ),
          );
          fixture.registerTool(
            'hello',
            inputSchema: mcp.JsonSchema.object(properties: {}),
            callback: (args, extra) async =>
                mcp.CallToolResult.fromContent([mcp.TextContent(text: 'ok')]),
          );
          return fixture;
        },
        host: '127.0.0.1',
        port: 0,
        path: '/mcp',
        allowedHosts: const {'127.0.0.1'},
      );
      await server.start();
      runtime = await AndroidRuntimePort.open();
    });
    Connection? saved;
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: FilledButton(
                  onPressed: () async {
                    saved = await showDialog<Connection>(
                      context: context,
                      builder: (_) => ConnectionSetupDialog(
                        setup: runtime,
                        initialKind: ConnectionKind.mcpHttp,
                        allowedKinds: const {ConnectionKind.mcpHttp},
                      ),
                    );
                  },
                  child: const Text('添加连接'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('添加连接'));
      await tester.pumpAndSettle();
      expect(find.text('HTTP MCP'), findsOneWidget);
      expect(find.byType(TextField), findsNWidgets(3));
      await tester.enterText(find.byType(TextField).at(0), 'A2 界面测试');
      await tester.enterText(
        find.byType(TextField).at(1),
        'http://127.0.0.1:${server.boundPort}/mcp',
      );
      await tester.tap(find.text('测试连接'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 2)),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('MCP 握手与功能发现成功'), findsOneWidget);
      await tester.tap(find.text('保存连接'));
      await tester.runAsync(() async {
        for (var attempt = 0; attempt < 20 && saved == null; attempt++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      });
      await tester.pumpAndSettle();
      expect(saved?.status, ConnectionStatus.ready);
    } finally {
      await tester.runAsync(() async {
        if (saved != null) await runtime.removeConnection(saved!.id);
        await runtime.dispose();
        await server.stop();
      });
    }
  });
}
