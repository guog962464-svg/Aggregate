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
