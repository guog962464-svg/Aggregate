import 'dart:async';

import 'package:http/http.dart' as http;

const androidMcpMaxResponseBytes = 8 * 1024 * 1024;

/// Bounds each response before `mcp_dart` decodes JSON or SSE events.
final class AndroidMcpHttpClient extends http.BaseClient {
  AndroidMcpHttpClient({
    http.Client? inner,
    this.maxResponseBytes = androidMcpMaxResponseBytes,
  }) : _inner = inner ?? http.Client() {
    if (maxResponseBytes < 1) {
      throw ArgumentError.value(maxResponseBytes, 'maxResponseBytes');
    }
  }

  final http.Client _inner;
  final int maxResponseBytes;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    request.followRedirects = false;
    final response = await _inner.send(request);
    if (response.isRedirect) {
      await _cancel(response.stream);
      throw http.ClientException(
        'MCP endpoint redirects are disabled',
        request.url,
      );
    }
    final contentLength = response.contentLength;
    if (contentLength != null && contentLength > maxResponseBytes) {
      await _cancel(response.stream);
      throw AndroidMcpResponseTooLargeException(maxResponseBytes);
    }
    return http.StreamedResponse(
      _limit(response.stream),
      response.statusCode,
      contentLength: contentLength,
      request: response.request,
      headers: response.headers,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
    );
  }

  @override
  void close() => _inner.close();

  Future<void> _cancel(Stream<List<int>> stream) async {
    final subscription = stream.listen(null);
    await subscription.cancel();
  }

  Stream<List<int>> _limit(Stream<List<int>> source) =>
      Stream<List<int>>.multi((controller) {
        var byteCount = 0;
        var completed = false;
        var cancelAfterListen = false;
        StreamSubscription<List<int>>? subscription;

        Future<void> cancelSource() async {
          final current = subscription;
          if (current == null) {
            cancelAfterListen = true;
            return;
          }
          try {
            await current.cancel();
          } on Object {
            // The public response has already been closed or cancelled.
          }
        }

        void finish() {
          if (completed) return;
          completed = true;
          controller.close();
        }

        controller.onCancel = cancelSource;
        subscription = source.listen(
          (chunk) {
            if (completed) return;
            if (chunk.length > maxResponseBytes - byteCount) {
              completed = true;
              controller.addError(
                AndroidMcpResponseTooLargeException(maxResponseBytes),
              );
              controller.close();
              unawaited(cancelSource());
              return;
            }
            byteCount += chunk.length;
            controller.add(chunk);
          },
          onError: (Object error, StackTrace stackTrace) {
            if (completed) return;
            // Stream errors are not necessarily terminal. Forward the error
            // and let a later onDone close the wrapper, or allow subsequent
            // data/errors to follow the source stream's contract.
            controller.addError(error, stackTrace);
          },
          onDone: finish,
          cancelOnError: false,
        );
        if (cancelAfterListen) unawaited(cancelSource());
      });
}

final class AndroidMcpResponseTooLargeException implements Exception {
  const AndroidMcpResponseTooLargeException(this.limit);

  final int limit;

  @override
  String toString() => 'MCP response exceeds the $limit byte limit';
}
