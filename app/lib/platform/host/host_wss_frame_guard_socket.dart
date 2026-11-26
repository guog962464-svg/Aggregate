import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'host_wss_protocol.dart';

/// Rejects fragmented or oversized Host WSS frames before dart:io buffers them.
///
/// [serverSide] is the role passed to `WebSocket.fromUpgradedSocket`: server
/// sockets receive masked client frames, while client sockets receive unmasked
/// server frames.
final class HostWssFrameGuardSocket extends Stream<Uint8List>
    implements Socket {
  HostWssFrameGuardSocket(this._socket, {required this.serverSide}) {
    _incoming = StreamController<Uint8List>(
      sync: true,
      onListen: () {
        _subscription = _socket.listen(
          _handleData,
          onError: _handleError,
          onDone: _handleDone,
        );
      },
      onPause: ([resumeSignal]) => _subscription?.pause(resumeSignal),
      onResume: () => _subscription?.resume(),
      onCancel: () => _subscription?.cancel(),
    );
  }

  final Socket _socket;
  final bool serverSide;
  late final StreamController<Uint8List> _incoming;
  StreamSubscription<Uint8List>? _subscription;
  int _frameState = 0;
  int _opcode = -1;
  bool _frameMasked = false;
  int _lengthBytesRemaining = 0;
  int _maskBytesRemaining = 0;
  int _payloadBytesRemaining = 0;
  int _frameLength = 0;

  void _handleData(Uint8List bytes) {
    try {
      _validateFrames(bytes);
      _incoming.add(bytes);
    } on Object catch (error, stackTrace) {
      _incoming.addError(error, stackTrace);
      unawaited(_incoming.close());
      _socket.destroy();
    }
  }

  void _handleError(Object error, [StackTrace? stackTrace]) {
    _incoming.addError(error, stackTrace);
  }

  void _handleDone() {
    unawaited(_incoming.close());
  }

  void _validateFrames(Uint8List bytes) {
    var index = 0;
    while (index < bytes.length) {
      switch (_frameState) {
        case 0:
          final first = bytes[index++];
          final fin = (first & 0x80) != 0;
          _opcode = first & 0x0f;
          if ((first & 0x70) != 0 ||
              !fin ||
              !const {1, 2, 8, 9, 10}.contains(_opcode)) {
            throw const WebSocketException(
              'Host WSS requires unfragmented, uncompressed frames',
            );
          }
          _frameState = 1;
        case 1:
          final second = bytes[index++];
          final masked = (second & 0x80) != 0;
          _frameMasked = masked;
          final lengthCode = second & 0x7f;
          if (masked != serverSide) {
            throw const WebSocketException('Invalid Host WSS frame mask');
          }
          if (_opcode >= 8 && lengthCode > 125) {
            throw const WebSocketException('Invalid Host control frame');
          }
          if (lengthCode < 126) {
            _startFramePayload(lengthCode, masked);
          } else {
            _lengthBytesRemaining = lengthCode == 126 ? 2 : 8;
            _frameLength = 0;
            _frameState = 2;
          }
        case 2:
          final byte = bytes[index++];
          if (_lengthBytesRemaining == 8 && _frameLength == 0 && byte > 0x7f) {
            throw const WebSocketException('Invalid Host frame length');
          }
          _frameLength = (_frameLength << 8) | byte;
          _lengthBytesRemaining--;
          if (_frameLength > hostWssMaxFrameBytes) {
            throw const WebSocketException('Host frame exceeds size limit');
          }
          if (_lengthBytesRemaining == 0) {
            _startFramePayload(_frameLength, _frameMasked);
          }
        case 3:
          final consumed = min(bytes.length - index, _maskBytesRemaining);
          index += consumed;
          _maskBytesRemaining -= consumed;
          if (_maskBytesRemaining == 0) {
            _frameState = _payloadBytesRemaining == 0 ? 0 : 4;
          }
        case 4:
          final consumed = min(bytes.length - index, _payloadBytesRemaining);
          index += consumed;
          _payloadBytesRemaining -= consumed;
          if (_payloadBytesRemaining == 0) _frameState = 0;
      }
    }
  }

  void _startFramePayload(int length, bool masked) {
    if (_opcode < 8 && length > hostWssMaxFrameBytes) {
      throw const WebSocketException('Host frame exceeds size limit');
    }
    _payloadBytesRemaining = length;
    _maskBytesRemaining = masked ? 4 : 0;
    if (_maskBytesRemaining > 0) {
      _frameState = 3;
    } else {
      _frameState = length == 0 ? 0 : 4;
    }
  }

  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _incoming.stream.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  Encoding get encoding => _socket.encoding;

  @override
  set encoding(Encoding value) => _socket.encoding = value;

  @override
  void add(List<int> data) => _socket.add(data);

  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      _socket.addError(error, stackTrace);

  @override
  Future<void> addStream(Stream<List<int>> stream) => _socket.addStream(stream);

  @override
  Future<void> flush() => _socket.flush();

  @override
  Future<void> close() => _socket.close();

  @override
  Future<void> get done => _socket.done;

  @override
  void write(Object? object) => _socket.write(object);

  @override
  void writeAll(Iterable objects, [String separator = '']) =>
      _socket.writeAll(objects, separator);

  @override
  void writeln([Object? object = '']) => _socket.writeln(object);

  @override
  void writeCharCode(int charCode) => _socket.writeCharCode(charCode);

  @override
  void destroy() {
    _socket.destroy();
    unawaited(_incoming.close());
  }

  @override
  bool setOption(SocketOption option, bool enabled) =>
      _socket.setOption(option, enabled);

  @override
  Uint8List getRawOption(RawSocketOption option) =>
      _socket.getRawOption(option);

  @override
  void setRawOption(RawSocketOption option) => _socket.setRawOption(option);

  @override
  int get port => _socket.port;

  @override
  int get remotePort => _socket.remotePort;

  @override
  InternetAddress get address => _socket.address;

  @override
  InternetAddress get remoteAddress => _socket.remoteAddress;
}
