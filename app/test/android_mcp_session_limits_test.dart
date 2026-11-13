import 'package:aggregate/platform/android/android_mcp_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcp_dart/mcp_dart.dart' as mcp;

void main() {
  test(
    'rejects MCP tool catalogs above the Android capability limit',
    () async {
      final server = mcp.StreamableMcpServer(
        serverFactory: (_) {
          final fixture = mcp.McpServer(
            const mcp.Implementation(
              name: 'android-catalog-limit',
              version: '1.0.0',
            ),
            options: const mcp.McpServerOptions(
              protocol: mcp.McpProtocol.stable,
            ),
          );
          for (var index = 0; index <= 1000; index++) {
            fixture.registerTool(
              'tool-$index',
              inputSchema: mcp.JsonSchema.object(properties: {}),
              callback: (args, extra) async => mcp.CallToolResult.fromContent([
                const mcp.TextContent(text: 'ok'),
              ]),
            );
          }
          return fixture;
        },
        host: '127.0.0.1',
        port: 0,
        path: '/mcp',
        allowedHosts: const {'127.0.0.1'},
      );
      await server.start();
      try {
        await expectLater(
          AndroidMcpSession.connect(
            'a8-catalog-limit',
            Uri.parse('http://127.0.0.1:${server.boundPort}/mcp'),
            null,
          ),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              'MCP 功能目录超过 Android 限制',
            ),
          ),
        );
      } finally {
        await server.stop();
      }
    },
  );
}
