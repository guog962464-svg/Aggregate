import 'dart:async';

import 'package:aggregate/platform/android/android_mcp_http_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const uri = 'https://mcp.example.test';

  test('rejects a response whose declared length exceeds the limit', () async {
    final client = AndroidMcpHttpClient(
      inner: MockClient((request) async => http.Response('12345', 200)),
      maxResponseBytes: 4,
    );
    addTearDown(client.close);

    await expectLater(
      client.send(http.Request('POST', Uri.parse(uri))),
      throwsA(isA<AndroidMcpResponseTooLargeException>()),
    );
  });

  test(
    'cancels an unbounded response as soon as streamed bytes exceed limit',
    () async {
      var sourceCancelled = false;
      final source = StreamController<List<int>>(
        onCancel: () => sourceCancelled = true,
      );
      final client = AndroidMcpHttpClient(
        inner: _StreamClient((request) async {
          scheduleMicrotask(() {
            source
              ..add([1, 2, 3])
              ..add([4, 5]);
          });
          return http.StreamedResponse(source.stream, 200, request: request);
        }),
        maxResponseBytes: 4,
      );
      addTearDown(client.close);

      final response = await client.send(http.Request('POST', Uri.parse(uri)));
      await expectLater(
        response.stream.toList(),
        throwsA(isA<AndroidMcpResponseTooLargeException>()),
      );
      expect(sourceCancelled, isTrue);
    },
  );

  test(
    'rejects redirects instead of following a downgrade or new origin',
    () async {
      final client = AndroidMcpHttpClient(
        inner: _StreamClient(
          (request) async => http.StreamedResponse(
            const Stream<List<int>>.empty(),
            302,
            request: request,
            isRedirect: true,
          ),
        ),
      );
      addTearDown(client.close);

      await expectLater(
        client.send(http.Request('POST', Uri.parse(uri))),
        throwsA(isA<http.ClientException>()),
      );
    },
  );

  test('passes through a response within the limit', () async {
    final client = AndroidMcpHttpClient(
      inner: MockClient((request) async => http.Response('ok', 200)),
      maxResponseBytes: 4,
    );
    addTearDown(client.close);

    final response = await client.send(http.Request('POST', Uri.parse(uri)));
    expect((await http.Response.fromStream(response)).body, 'ok');
  });

  test(
    'forwards a stream error and still closes when the source is done',
    () async {
      final source = StreamController<List<int>>();
      final client = AndroidMcpHttpClient(
        inner: _StreamClient((request) async {
          scheduleMicrotask(() {
            source
              ..addError(StateError('connection reset'))
              ..add([1, 2])
              ..close();
          });
          return http.StreamedResponse(source.stream, 200, request: request);
        }),
        maxResponseBytes: 4,
      );
      addTearDown(client.close);

      final response = await client.send(http.Request('POST', Uri.parse(uri)));
      final received = <int>[];
      final done = Completer<void>();
      final error = Completer<Object>();
      response.stream.listen(
        received.addAll,
        onError: (Object cause, StackTrace _) => error.complete(cause),
        onDone: done.complete,
      );

      expect(await error.future, isA<StateError>());
      await done.future.timeout(const Duration(seconds: 1));
      expect(received, [1, 2]);
    },
  );
}

final class _StreamClient extends http.BaseClient {
  _StreamClient(this._send);

  final Future<http.StreamedResponse> Function(http.BaseRequest request) _send;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _send(request);
}
