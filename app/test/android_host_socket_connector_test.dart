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

  test('rejects a bad Sec-WebSocket-Accept value', () async {
    await _expectHandshakeFailure(invalidAccept: true);
  });

  test('rejects an unexpected WebSocket subprotocol', () async {
    await _expectHandshakeFailure(invalidProtocol: true);
  });

  test('reports a TLS certificate pin mismatch', () async {
    await _expectHandshakeFailure(wrongPin: true);
  });

  test('rejects fragmented text messages', () async {
    await _expectFragmentedServerMessage();
  });

  test('rejects fragmented binary messages', () async {
    await _expectFragmentedServerMessage(binary: true);
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

Future<void> _expectFragmentedServerMessage({bool binary = false}) async {
  const firstFragmentBytes = 600000;
  final totalBytes = hostWssMaxFrameBytes + 1;
  final secondFragmentBytes = totalBytes - firstFragmentBytes;
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
  final framesSent = Completer<void>();
  final serverSockets = <Socket>[];
  final serverSubscription = server.listen((request) async {
    try {
      final key = request.headers.value('Sec-WebSocket-Key')!;
      final accept = base64Encode(
        sha1.convert(utf8.encode('$key$hostWssWebSocketGuid')).bytes,
      );
      final response = request.response
        ..statusCode = HttpStatus.switchingProtocols;
      response.headers
        ..set(HttpHeaders.connectionHeader, 'Upgrade')
        ..set(HttpHeaders.upgradeHeader, 'websocket')
        ..set('Sec-WebSocket-Accept', accept)
        ..set('Sec-WebSocket-Protocol', hostWssSubprotocol);
      final socket = await response.detachSocket();
      serverSockets.add(socket);
      socket.add(
        _serverFrame(
          opcode: binary ? 2 : 1,
          fin: false,
          payload: List<int>.filled(firstFragmentBytes, 0x78),
        ),
      );
      socket.add(
        _serverFrame(
          opcode: 0,
          fin: true,
          payload: List<int>.filled(secondFragmentBytes, 0x78),
        ),
      );
      framesSent.complete();
      await socket.flush();
    } on Object catch (error, stackTrace) {
      if (!framesSent.isCompleted) framesSent.completeError(error, stackTrace);
    }
  });
  AndroidHostSocket? clientSocket;
  try {
    final pin = _certificatePin(certificate);
    clientSocket = await const PinnedAndroidHostSocketConnector().connect(
      Uri.parse('wss://127.0.0.1:${server.port}/host'),
      certificateSha256: pin,
    );
    final firstMessage = clientSocket.messages.first.timeout(
      const Duration(seconds: 3),
    );
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
    await framesSent.future.timeout(const Duration(seconds: 3));
    await readMessage.timeout(const Duration(seconds: 3));
    expect(
      receiveError != null && !delivered,
      isTrue,
      reason: 'fragmented messages must be rejected before delivery',
    );
  } finally {
    final clientClose = clientSocket?.close();
    for (final socket in serverSockets) {
      socket.destroy();
    }
    try {
      await clientClose?.timeout(const Duration(milliseconds: 300));
    } on Object {
      // The raw fixture closes the peer socket instead of completing a WS close handshake.
    }
    await serverSubscription.cancel();
    await server.close(force: true);
  }
}

Future<void> _expectHandshakeFailure({
  bool invalidAccept = false,
  bool invalidProtocol = false,
  bool wrongPin = false,
}) async {
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
  final sockets = <Socket>[];
  final subscription = server.listen((request) async {
    final key = request.headers.value('Sec-WebSocket-Key')!;
    final accept = base64Encode(
      sha1.convert(utf8.encode('$key$hostWssWebSocketGuid')).bytes,
    );
    final response = request.response
      ..statusCode = HttpStatus.switchingProtocols;
    response.headers
      ..set(HttpHeaders.connectionHeader, 'Upgrade')
      ..set(HttpHeaders.upgradeHeader, 'websocket')
      ..set('Sec-WebSocket-Accept', invalidAccept ? 'invalid' : accept)
      ..set(
        'Sec-WebSocket-Protocol',
        invalidProtocol ? 'unexpected.v1' : hostWssSubprotocol,
      );
    sockets.add(await response.detachSocket());
  });
  try {
    final validPin = _certificatePin(certificate);
    await expectLater(
      const PinnedAndroidHostSocketConnector().connect(
        Uri.parse('wss://127.0.0.1:${server.port}/host'),
        certificateSha256: wrongPin ? List.filled(64, '0').join() : validPin,
      ),
      throwsA(
        isA<AndroidHostPairingException>().having(
          (error) => error.failure,
          'failure',
          wrongPin
              ? AndroidHostPairingFailure.tlsPinMismatch
              : AndroidHostPairingFailure.protocolMismatch,
        ),
      ),
    );
  } finally {
    for (final socket in sockets) {
      socket.destroy();
    }
    await subscription.cancel();
    await server.close(force: true);
  }
}

Uint8List _serverFrame({
  required int opcode,
  required bool fin,
  required List<int> payload,
}) {
  final bytes = <int>[(fin ? 0x80 : 0) | opcode];
  if (payload.length < 126) {
    bytes.add(payload.length);
  } else if (payload.length <= 0xffff) {
    bytes
      ..add(126)
      ..add((payload.length >> 8) & 0xff)
      ..add(payload.length & 0xff);
  } else {
    bytes.add(127);
    var length = payload.length;
    final extendedLength = List<int>.filled(8, 0);
    for (var index = extendedLength.length - 1; index >= 0; index--) {
      extendedLength[index] = length & 0xff;
      length >>= 8;
    }
    bytes.addAll(extendedLength);
  }
  return Uint8List.fromList([...bytes, ...payload]);
}

String _certificatePin(File certificate) => sha256
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
