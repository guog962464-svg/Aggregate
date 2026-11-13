import 'dart:async';

import 'package:aggregate/platform/android/android_mcp_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
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

  test(
    'operation deadline aborts the HTTP request and closes the session',
    () async {
      final server = mcp.StreamableMcpServer(
        serverFactory: (_) {
          final fixture = mcp.McpServer(
            const mcp.Implementation(
              name: 'android-timeout-cancel',
              version: '1.0.0',
            ),
            options: const mcp.McpServerOptions(
              protocol: mcp.McpProtocol.require2026,
            ),
          );
          fixture.registerTool(
            'slow',
            inputSchema: mcp.JsonSchema.object(properties: {}),
            callback: (args, extra) async {
              await Future.any([
                extra.signal.onAbort.first,
                Future<void>.delayed(const Duration(seconds: 1)),
              ]);
              return mcp.CallToolResult.fromContent([
                const mcp.TextContent(text: 'done'),
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
      final httpClient = _AbortTrackingClient();
      AndroidMcpSession? session;
      try {
        session = await AndroidMcpSession.connect(
          'a8-timeout-cancel',
          Uri.parse('http://127.0.0.1:${server.boundPort}/mcp'),
          null,
          httpClient: httpClient,
        );
        httpClient.trackNextPostAbort();

        await expectLater(
          session.call(
            'slow',
            const {},
            timeout: const Duration(milliseconds: 50),
          ),
          throwsA(isA<TimeoutException>()),
        );
        await httpClient.nextPostAborted.timeout(const Duration(seconds: 1));
        expect(httpClient.closed, isTrue);
      } finally {
        await session?.close();
        httpClient.close();
        await server.stop();
      }
    },
  );
}

final class _AbortTrackingClient extends http.BaseClient {
  final http.Client _inner = http.Client();
  Completer<void>? _nextAbortCompleter;
  Completer<void>? _lastAbortCompleter;
  bool closed = false;

  Future<void> get nextPostAborted =>
      (_lastAbortCompleter ??
              (throw StateError('No POST abort is being tracked')))
          .future;

  void trackNextPostAbort() {
    final completer = Completer<void>();
    _nextAbortCompleter = completer;
    _lastAbortCompleter = completer;
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    final completer = _nextAbortCompleter;
    if (request.method.toUpperCase() == 'POST' && completer != null) {
      _nextAbortCompleter = null;
      if (request is! http.AbortableRequest || request.abortTrigger == null) {
        throw StateError('Expected an abortable MCP POST request');
      }
      unawaited(
        request.abortTrigger!.then((_) {
          if (!completer.isCompleted) completer.complete();
        }),
      );
    }
    return _inner.send(request);
  }

  @override
  void close() {
    closed = true;
    _inner.close();
  }
}
