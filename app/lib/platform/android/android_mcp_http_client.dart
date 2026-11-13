import 'dart:async';

import 'package:http/http.dart' as http;

const androidMcpMaxResponseBytes = 8 * 1024 * 1024;
const androidMcpMaxConcurrentPostRequests = 16;

final class AndroidMcpRequestLimiter {
  AndroidMcpRequestLimiter({
    this.maxConcurrentRequests = androidMcpMaxConcurrentPostRequests,
  }) {
    if (maxConcurrentRequests < 1) {
      throw ArgumentError.value(maxConcurrentRequests, 'maxConcurrentRequests');
    }
  }

  final int maxConcurrentRequests;
  int _activeRequests = 0;

  int get activeRequests => _activeRequests;

  bool tryAcquire() {
    if (_activeRequests >= maxConcurrentRequests) return false;
    _activeRequests++;
    return true;
  }

  void release() {
    if (_activeRequests == 0) {
      throw StateError('No Android MCP request permit is active');
    }
    _activeRequests--;
  }
}

final androidMcpRequestLimiter = AndroidMcpRequestLimiter();

/// Bounds each response before `mcp_dart` decodes JSON or SSE events.
final class AndroidMcpHttpClient extends http.BaseClient {
  AndroidMcpHttpClient({
    http.Client? inner,
    this.maxResponseBytes = androidMcpMaxResponseBytes,
    AndroidMcpRequestLimiter? requestLimiter,
  }) : _inner = inner ?? http.Client(),
       _requestLimiter = requestLimiter ?? androidMcpRequestLimiter {
    if (maxResponseBytes < 1) {
      throw ArgumentError.value(maxResponseBytes, 'maxResponseBytes');
    }
  }

  final http.Client _inner;
  final AndroidMcpRequestLimiter _requestLimiter;
  final Set<void Function()> _activePostReleases = {};
  final int maxResponseBytes;
  bool _closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (_closed) {
      throw http.ClientException('MCP HTTP client is closed', request.url);
    }
    request.followRedirects = false;
    final countsAgainstLimit = request.method.toUpperCase() == 'POST';
    if (countsAgainstLimit && !_requestLimiter.tryAcquire()) {
      throw AndroidMcpConcurrencyLimitException(
        _requestLimiter.maxConcurrentRequests,
      );
    }

    var released = false;
    void releaseRequest() {
      if (released) return;
      released = true;
      _activePostReleases.remove(releaseRequest);
      if (countsAgainstLimit) _requestLimiter.release();
    }

    if (countsAgainstLimit) _activePostReleases.add(releaseRequest);
    try {
      final response = await _inner.send(request);
      if (response.isRedirect) {
        try {
          await _cancel(response.stream);
        } finally {
          releaseRequest();
        }
        throw http.ClientException(
          'MCP endpoint redirects are disabled',
          request.url,
        );
      }
      final contentLength = response.contentLength;
      if (contentLength != null && contentLength > maxResponseBytes) {
        try {
          await _cancel(response.stream);
        } finally {
          releaseRequest();
        }
        throw AndroidMcpResponseTooLargeException(maxResponseBytes);
      }
      return http.StreamedResponse(
        _limit(response.stream, releaseRequest),
        response.statusCode,
        contentLength: contentLength,
        request: response.request,
        headers: response.headers,
        isRedirect: response.isRedirect,
        persistentConnection: response.persistentConnection,
        reasonPhrase: response.reasonPhrase,
      );
    } catch (_) {
      releaseRequest();
      rethrow;
    }
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    _inner.close();
    for (final release in _activePostReleases.toList()) {
      release();
    }
  }

  Future<void> _cancel(Stream<List<int>> stream) async {
    final subscription = stream.listen(null);
    await subscription.cancel();
  }

  Stream<List<int>> _limit(
    Stream<List<int>> source,
    void Function() onSettled,
  ) => Stream<List<int>>.multi((controller) {
    var byteCount = 0;
    var completed = false;
    var settled = false;
    var cancelAfterListen = false;
    StreamSubscription<List<int>>? subscription;

    void settle() {
      if (settled) return;
      settled = true;
      onSettled();
    }

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
      settle();
      controller.close();
    }

    controller.onCancel = () async {
      await cancelSource();
      settle();
    };
    subscription = source.listen(
      (chunk) {
        if (completed) return;
        if (chunk.length > maxResponseBytes - byteCount) {
          completed = true;
          controller.addError(
            AndroidMcpResponseTooLargeException(maxResponseBytes),
          );
          controller.close();
          unawaited(cancelSource().whenComplete(settle));
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

final class AndroidMcpConcurrencyLimitException implements Exception {
  const AndroidMcpConcurrencyLimitException(this.limit);

  final int limit;

  @override
  String toString() =>
      'Too many concurrent Android MCP requests (limit: $limit)';
}

final class AndroidMcpResponseTooLargeException implements Exception {
  const AndroidMcpResponseTooLargeException(this.limit);

  final int limit;

  @override
  String toString() => 'MCP response exceeds the $limit byte limit';
}
