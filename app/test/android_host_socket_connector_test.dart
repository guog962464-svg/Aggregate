import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:aggregate/platform/android/android_host_pairing_client.dart';
import 'package:aggregate/platform/host/host_wss_protocol.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('accepts a legitimate Host WSS frame below the frame limit', () async {
    final frame = jsonEncode({'jsonrpc': '2.0', 'method': 'host.hello'});
    await _expectServerFrame(frame, accepted: true);
  });

  test('accepts a Host WSS frame at the frame limit', () async {
    final frame = List<String>.filled(hostWssMaxFrameBytes, 'x').join();
    await _expectServerFrame(frame, accepted: true);
  });

  test('rejects an oversized text Host WSS frame', () async {
    final frame = List<String>.filled(hostWssMaxFrameBytes + 1, 'x').join();
    await _expectServerFrame(frame, accepted: false);
  });

  test('rejects an oversized binary Host WSS frame', () async {
    final frame = Uint8List(hostWssMaxFrameBytes + 1);
    await _expectServerFrame(frame, accepted: false);
  });
}

Future<void> _expectServerFrame(Object frame, {required bool accepted}) async {
  final certificate = File('test/fixtures/host_test_cert.pem');
  final privateKey = File('test/fixtures/host_test_key.pem');
  final tlsContext = SecurityContext()
    ..useCertificateChain(certificate.path)
    ..usePrivateKey(privateKey.path);
  final server = await HttpServer.bindSecure(
    InternetAddress.loopbackIPv4,
    0,
    tlsContext,
  );
  final frameSent = Completer<void>();
  final serverSockets = <WebSocket>[];
  final serverSubscription = server.listen((request) async {
    final socket = await WebSocketTransformer.upgrade(
      request,
      protocolSelector: (protocols) =>
          protocols.contains('aggregate-host.v1') ? 'aggregate-host.v1' : '',
      compression: CompressionOptions.compressionOff,
    );
    serverSockets.add(socket);
    socket.listen(null, onError: (Object _) {});
    socket.add(frame);
    frameSent.complete();
  });
  AndroidHostSocket? clientSocket;
  try {
    final pin = sha256
        .convert(
          base64.decode(
            certificate
                .readAsStringSync()
                .split('\n')
                .where((line) => !line.startsWith('-----'))
                .join(),
          ),
        )
        .toString();
    clientSocket = await const PinnedAndroidHostSocketConnector().connect(
      Uri.parse('wss://127.0.0.1:${server.port}/host'),
      certificateSha256: pin,
    );
    final firstMessage = clientSocket.messages.first.timeout(
      const Duration(seconds: 3),
    );
    if (accepted) {
      await frameSent.future.timeout(const Duration(seconds: 3));
      final received = await firstMessage;
      final receivedExpectedFrame = frame is String
          ? received == frame
          : received is List<int> &&
                received.length == (frame as List<int>).length;
      expect(receivedExpectedFrame, isTrue);
    } else {
      var delivered = false;
      Object? receiveError;
      final readMessage = firstMessage.then<void>(
        (_) {
          delivered = true;
        },
        onError: (Object error, StackTrace _) {
          receiveError = error;
        },
      );
      await frameSent.future.timeout(const Duration(seconds: 3));
      await readMessage.timeout(const Duration(seconds: 3));
      expect(
        receiveError != null && !delivered,
        isTrue,
        reason:
            'oversized frame must be rejected; error=${receiveError?.runtimeType}',
      );
    }
  } finally {
    try {
      await clientSocket?.close();
    } on Object {
      // An oversized frame may already have closed the connection.
    }
    for (final socket in serverSockets) {
      try {
        await socket.close();
      } on Object {
        // The peer may have closed after rejecting an oversized frame.
      }
    }
    await serverSubscription.cancel();
    await server.close(force: true);
  }
}
