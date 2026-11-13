import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../host/host_pairing_protocol.dart';
import '../host/host_wss_protocol.dart';
import 'android_host_device_identity.dart';

const _maxInvitationBytes = 16 * 1024;
const _maxInvitationEndpoints = 8;
const _maxDisplayNameLength = 80;
const _maxHostRpcPayloadBytes = 512 * 1024;
const _defaultSocketTimeout = Duration(seconds: 8);
const _defaultHandshakeTimeout = Duration(seconds: 10);
const _defaultRpcTimeout = Duration(seconds: 30);
final _hostIdPattern = RegExp(r'^host-[a-f0-9]{32}$');
final _sha256Pattern = RegExp(r'^[a-f0-9]{64}$');
final _controlCharacters = RegExp(r'[\x00-\x1f\x7f]');

enum AndroidHostPairingFailure {
  invalidInvitation,
  invitationExpired,
  invalidDisplayName,
  invalidDeviceIdentity,
  tlsPinMismatch,
  hostUnavailable,
  protocolMismatch,
  approvalRequired,
  alreadyPaired,
  pairingRejected,
  responseInvalid,
  requestTimedOut,
  transportClosed,
  storageFailure,
}

final class AndroidHostPairingException implements Exception {
  const AndroidHostPairingException(this.failure, {this.rpcCode});

  final AndroidHostPairingFailure failure;
  final int? rpcCode;

  @override
  String toString() => 'AndroidHostPairingException(${failure.name})';
}

final class AndroidHostEndpoint {
  const AndroidHostEndpoint(this.uri);

  final Uri uri;

  String toJson() => uri.toString();
}

final class AndroidHostTarget {
  AndroidHostTarget({
    required this.hostId,
    required this.certificateSha256,
    required List<AndroidHostEndpoint> endpoints,
  }) : endpoints = List.unmodifiable(endpoints);

  factory AndroidHostTarget.fromInvitation(AndroidHostInvitation invitation) =>
      AndroidHostTarget(
        hostId: invitation.hostId,
        certificateSha256: invitation.certificateSha256,
        endpoints: invitation.endpoints,
      );

  final String hostId;
  final String certificateSha256;
  final List<AndroidHostEndpoint> endpoints;

  void validate() {
    if (!_hostIdPattern.hasMatch(hostId) ||
        !_sha256Pattern.hasMatch(certificateSha256) ||
        endpoints.isEmpty ||
        endpoints.length > _maxInvitationEndpoints ||
        endpoints.any(
          (endpoint) => !AndroidHostInvitation._isAllowedHostUri(endpoint.uri),
        ) ||
        endpoints.map((endpoint) => endpoint.uri.toString()).toSet().length !=
            endpoints.length) {
      throw const AndroidHostPairingException(
        AndroidHostPairingFailure.invalidInvitation,
      );
    }
  }
}

final class AndroidHostInvitation {
  const AndroidHostInvitation({
    required this.hostId,
    required this.certificateSha256,
    required this.nonce,
    required this.expiresAt,
    required this.endpoints,
  });

  final String hostId;
  final String certificateSha256;
  final String nonce;
  final DateTime expiresAt;
  final List<AndroidHostEndpoint> endpoints;

  factory AndroidHostInvitation.fromQrPayload(
    String payload, {
    DateTime Function()? now,
  }) {
    if (payload.isEmpty || utf8.encode(payload).length > _maxInvitationBytes) {
      throw const AndroidHostPairingException(
        AndroidHostPairingFailure.invalidInvitation,
      );
    }
    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map || decoded.keys.any((key) => key is! String)) {
        throw const FormatException();
      }
      final json = decoded.cast<String, Object?>();
      if (!_onlyKeys(json, const {
            'version',
            'hostId',
            'certificateSha256',
            'nonce',
            'expiresAt',
            'serviceType',
            'endpoints',
          }) ||
          json['version'] != HostPairingProtocol.version ||
          json['hostId'] is! String ||
          !_hostIdPattern.hasMatch(json['hostId']! as String) ||
          json['certificateSha256'] is! String ||
          !_sha256Pattern.hasMatch(json['certificateSha256']! as String) ||
          json['nonce'] is! String ||
          !HostPairingProtocol.isToken(json['nonce']! as String) ||
          json['expiresAt'] is! String ||
          json['serviceType'] != hostBonjourServiceType ||
          json['endpoints'] is! List) {
        throw const FormatException();
      }
      final expiresAt = DateTime.tryParse(json['expiresAt']! as String);
      final nowUtc = (now ?? DateTime.now)().toUtc();
      if (expiresAt == null ||
          expiresAt.isBefore(nowUtc.subtract(const Duration(seconds: 30)))) {
        throw const AndroidHostPairingException(
          AndroidHostPairingFailure.invitationExpired,
        );
      }
      if (expiresAt.isAfter(nowUtc.add(const Duration(minutes: 10)))) {
        throw const FormatException();
      }
      final rawEndpoints = json['endpoints']! as List;
      if (rawEndpoints.isEmpty ||
          rawEndpoints.length > _maxInvitationEndpoints) {
        throw const FormatException();
      }
      final endpoints = <AndroidHostEndpoint>[];
      final unique = <String>{};
      for (final item in rawEndpoints) {
        if (item is! Map || item.keys.any((key) => key is! String)) {
          throw const FormatException();
        }
        final endpointJson = item.cast<String, Object?>();
        if (!_onlyKeys(endpointJson, const {'uri'}) ||
            endpointJson['uri'] is! String) {
          throw const FormatException();
        }
        final uri = Uri.tryParse(endpointJson['uri']! as String);
        if (uri == null || !_isAllowedHostUri(uri)) {
          throw const FormatException();
        }
        final endpoint = AndroidHostEndpoint(uri);
        if (!unique.add(uri.toString())) throw const FormatException();
        endpoints.add(endpoint);
      }
      return AndroidHostInvitation(
        hostId: json['hostId']! as String,
        certificateSha256: json['certificateSha256']! as String,
        nonce: json['nonce']! as String,
        expiresAt: expiresAt.toUtc(),
        endpoints: List.unmodifiable(endpoints),
      );
    } on AndroidHostPairingException {
      rethrow;
    } on Object {
      throw const AndroidHostPairingException(
        AndroidHostPairingFailure.invalidInvitation,
      );
    }
  }

  static bool _isAllowedHostUri(Uri uri) {
    if (uri.scheme != 'wss' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.port < 1 ||
        uri.port > 65535 ||
        uri.path != hostWssPath ||
        uri.hasQuery ||
        uri.hasFragment) {
      return false;
    }
    final ip = InternetAddress.tryParse(uri.host);
    if (ip == null || ip.type != InternetAddressType.IPv4) return false;
    if (ip.isLoopback) return true;
    final bytes = ip.rawAddress;
    return bytes.length == 4 &&
        (bytes[0] == 10 ||
            (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) ||
            (bytes[0] == 192 && bytes[1] == 168));
  }
}

final class AndroidHostPairingReceipt {
  const AndroidHostPairingReceipt({
    required this.hostId,
    required this.deviceId,
    required this.confirmationCode,
    required this.expiresAt,
  });

  final String hostId;
  final String deviceId;
  final String confirmationCode;
  final DateTime expiresAt;
}

abstract interface class AndroidHostSocket {
  Stream<Object?> get messages;
  String? get protocol;
  set pingInterval(Duration interval);
  void send(String frame);
  Future<void> close();
}

abstract interface class AndroidHostSocketConnector {
  Future<AndroidHostSocket> connect(
    Uri uri, {
    required String certificateSha256,
  });
}

final class PinnedAndroidHostSocketConnector
    implements AndroidHostSocketConnector {
  const PinnedAndroidHostSocketConnector({
    this.timeout = _defaultSocketTimeout,
  });

  final Duration timeout;

  @override
  Future<AndroidHostSocket> connect(
    Uri uri, {
    required String certificateSha256,
  }) async {
    if (!_sha256Pattern.hasMatch(certificateSha256) ||
        !AndroidHostInvitation._isAllowedHostUri(uri)) {
      throw const AndroidHostPairingException(
        AndroidHostPairingFailure.invalidInvitation,
      );
    }
    final context = SecurityContext(withTrustedRoots: false)
      ..minimumTlsProtocolVersion = TlsProtocolVersion.tls1_2;
    final client = HttpClient(context: context)..connectionTimeout = timeout;
    var pinMismatch = false;
    client.badCertificateCallback = (certificate, host, port) {
      if (host != uri.host || port != uri.port) {
        pinMismatch = true;
        return false;
      }
      final now = DateTime.now();
      if (now.isBefore(certificate.startValidity) ||
          now.isAfter(certificate.endValidity)) {
        pinMismatch = true;
        return false;
      }
      final matches =
          sha256.convert(certificate.der).toString() == certificateSha256;
      if (!matches) pinMismatch = true;
      return matches;
    };
    try {
      final socket = await WebSocket.connect(
        uri.toString(),
        protocols: const [hostWssSubprotocol],
        compression: CompressionOptions.compressionOff,
        customClient: client,
      ).timeout(timeout);
      if (socket.protocol != hostWssSubprotocol) {
        await socket.close(
          WebSocketStatus.protocolError,
          'Subprotocol required',
        );
        client.close(force: true);
        throw const AndroidHostPairingException(
          AndroidHostPairingFailure.protocolMismatch,
        );
      }
      return _IoAndroidHostSocket(socket, client);
    } on AndroidHostPairingException {
      rethrow;
    } on TimeoutException {
      client.close(force: true);
      throw const AndroidHostPairingException(
        AndroidHostPairingFailure.requestTimedOut,
      );
    } on Object {
      client.close(force: true);
      if (pinMismatch) {
        throw const AndroidHostPairingException(
          AndroidHostPairingFailure.tlsPinMismatch,
        );
      }
      throw const AndroidHostPairingException(
        AndroidHostPairingFailure.hostUnavailable,
      );
    }
  }
}

final class _IoAndroidHostSocket implements AndroidHostSocket {
  _IoAndroidHostSocket(this._socket, this._client);

  final WebSocket _socket;
  final HttpClient _client;

  @override
  Stream<Object?> get messages => _socket.cast<Object?>();

  @override
  String? get protocol => _socket.protocol;

  @override
  set pingInterval(Duration interval) => _socket.pingInterval = interval;

  @override
  void send(String frame) => _socket.add(frame);

  @override
  Future<void> close() async {
    try {
      await _socket.close();
    } finally {
      _client.close(force: true);
    }
  }
}

final class AndroidHostPairingClient {
  AndroidHostPairingClient({
    required this.identity,
    AndroidHostSocketConnector? connector,
    DateTime Function()? now,
    Random? random,
    this.handshakeTimeout = _defaultHandshakeTimeout,
    this.rpcTimeout = _defaultRpcTimeout,
  }) : connector = connector ?? const PinnedAndroidHostSocketConnector(),
       now = now ?? DateTime.now,
       random = random ?? Random.secure();

  final AndroidHostIdentityPort identity;
  final AndroidHostSocketConnector connector;
  final DateTime Function() now;
  final Random random;
  final Duration handshakeTimeout;
  final Duration rpcTimeout;

  Future<AndroidHostPairingReceipt> requestPairing({
    required AndroidHostInvitation invitation,
    required String displayName,
  }) async {
    _validateInvitationCurrent(invitation);
    _validateDisplayName(displayName);
    final device = await _loadDeviceIdentity();
    final socketAndIterator = await _connect(
      AndroidHostTarget.fromInvitation(invitation),
    );
    final socket = socketAndIterator.$1;
    final iterator = socketAndIterator.$2;
    final requestId = _newId('pair');
    try {
      final timestampSeconds = now().toUtc().millisecondsSinceEpoch ~/ 1000;
      final proof = HostPairingProtocol.pairingProof(
        hostId: invitation.hostId,
        deviceId: device.deviceId,
        invitationNonce: invitation.nonce,
        timestampSeconds: timestampSeconds,
      );
      final signature = await _sign(proof);
      socket.send(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': requestId,
          'method': 'host.pair.request',
          'params': {
            'hostId': invitation.hostId,
            'deviceId': device.deviceId,
            'publicKeySpki': base64Encode(device.publicKeySpki),
            'displayName': displayName.trim(),
            'platform': 'android',
            'invitationNonce': invitation.nonce,
            'timestampSeconds': timestampSeconds,
            'signatureDer': base64Encode(signature),
          },
        }),
      );
      final result = await _readRpcResult(iterator, requestId);
      if (result['state'] != 'pendingApproval' ||
          result['deviceId'] != device.deviceId ||
          result['confirmationCode'] is! String ||
          !RegExp(r'^\d{6}$').hasMatch(result['confirmationCode']! as String) ||
          result['expiresAt'] is! String) {
        throw const AndroidHostPairingException(
          AndroidHostPairingFailure.responseInvalid,
        );
      }
      final expiresAt = DateTime.tryParse(result['expiresAt']! as String);
      if (expiresAt == null ||
          expiresAt.isBefore(
            now().toUtc().subtract(const Duration(seconds: 30)),
          )) {
        throw const AndroidHostPairingException(
          AndroidHostPairingFailure.invitationExpired,
        );
      }
      return AndroidHostPairingReceipt(
        hostId: invitation.hostId,
        deviceId: device.deviceId,
        confirmationCode: result['confirmationCode']! as String,
        expiresAt: expiresAt.toUtc(),
      );
    } on AndroidHostPairingException {
      rethrow;
    } on Object {
      throw const AndroidHostPairingException(
        AndroidHostPairingFailure.hostUnavailable,
      );
    } finally {
      await _closeHandshake(socket, iterator);
    }
  }

  Future<AndroidHostAuthenticatedSession> authenticate(
    AndroidHostTarget target,
  ) async {
    _validateTarget(target);
    final device = await _loadDeviceIdentity();
    final connection = await _connect(target);
    final socket = connection.$1;
    final iterator = connection.$2;
    AndroidHostAuthenticatedSession? session;
    var handedOff = false;
    try {
      final beginId = _newId('auth');
      socket.send(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': beginId,
          'method': 'host.auth.begin',
          'params': {'deviceId': device.deviceId},
        }),
      );
      final challenge = await _readRpcResult(iterator, beginId);
      if (challenge['hostId'] != target.hostId ||
          challenge['deviceId'] != device.deviceId ||
          challenge['connectionId'] is! String ||
          challenge['challenge'] is! String ||
          challenge['expiresAt'] is! String) {
        throw const AndroidHostPairingException(
          AndroidHostPairingFailure.responseInvalid,
        );
      }
      final expiresAt = DateTime.tryParse(challenge['expiresAt']! as String);
      final connectionId = challenge['connectionId']! as String;
      final challengeToken = challenge['challenge']! as String;
      if (expiresAt == null ||
          expiresAt.isBefore(now().toUtc()) ||
          !HostPairingProtocol.isToken(connectionId) ||
          !HostPairingProtocol.isToken(challengeToken)) {
        throw const AndroidHostPairingException(
          AndroidHostPairingFailure.requestTimedOut,
        );
      }
      final proof = HostPairingProtocol.authenticationProof(
        hostId: target.hostId,
        deviceId: device.deviceId,
        connectionId: connectionId,
        challenge: challengeToken,
      );
      final signature = await _sign(proof);
      final proveId = _newId('prove');
      socket.send(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': proveId,
          'method': 'host.auth.prove',
          'params': {
            'connectionId': connectionId,
            'signatureDer': base64Encode(signature),
          },
        }),
      );
      final authenticated = await _readRpcResult(iterator, proveId);
      if (authenticated['deviceId'] != device.deviceId ||
          authenticated['sessionId'] is! String ||
          !HostPairingProtocol.isToken(authenticated['sessionId']! as String)) {
        throw const AndroidHostPairingException(
          AndroidHostPairingFailure.responseInvalid,
        );
      }
      socket.pingInterval = const Duration(seconds: 30);
      session = AndroidHostAuthenticatedSession._(
        socket,
        iterator,
        identity,
        target.hostId,
        target.certificateSha256,
        device.deviceId,
        authenticated['sessionId']! as String,
        random,
        now,
        rpcTimeout,
      );
      final hello = await session.call('host.hello', {
        'protocolVersion': hostProtocolVersion,
      });
      if (hello['protocolVersion'] != hostProtocolVersion ||
          hello['hostId'] != target.hostId ||
          hello['certificateSha256'] != target.certificateSha256) {
        throw const AndroidHostPairingException(
          AndroidHostPairingFailure.protocolMismatch,
        );
      }
      handedOff = true;
      return session;
    } on AndroidHostPairingException {
      rethrow;
    } on Object {
      throw const AndroidHostPairingException(
        AndroidHostPairingFailure.hostUnavailable,
      );
    } finally {
      if (!handedOff) {
        if (session != null) {
          await session.close();
        } else {
          await _closeHandshake(socket, iterator);
        }
      }
    }
  }

  Future<AndroidHostPublicIdentity> _loadDeviceIdentity() async {
    try {
      final device = await identity.loadOrCreate();
      if (HostPairingProtocol.deviceIdForPublicKey(device.publicKeySpki) !=
          device.deviceId) {
        throw const FormatException();
      }
      return device;
    } on Object {
      throw const AndroidHostPairingException(
        AndroidHostPairingFailure.invalidDeviceIdentity,
      );
    }
  }

  Future<List<int>> _sign(Uint8List proof) async {
    try {
      return await identity.sign(proof);
    } on Object {
      throw const AndroidHostPairingException(
        AndroidHostPairingFailure.invalidDeviceIdentity,
      );
    }
  }

  Future<(AndroidHostSocket, StreamIterator<Object?>)> _connect(
    AndroidHostTarget target,
  ) async {
    _validateTarget(target);
    AndroidHostPairingException? lastFailure;
    AndroidHostPairingException? pinFailure;
    for (final endpoint in target.endpoints) {
      AndroidHostSocket? socket;
      try {
        socket = await connector.connect(
          endpoint.uri,
          certificateSha256: target.certificateSha256,
        );
        if (socket.protocol != hostWssSubprotocol) {
          throw const AndroidHostPairingException(
            AndroidHostPairingFailure.protocolMismatch,
          );
        }
        return (socket, StreamIterator<Object?>(socket.messages));
      } on AndroidHostPairingException catch (error) {
        if (error.failure == AndroidHostPairingFailure.tlsPinMismatch) {
          pinFailure = error;
        }
        lastFailure = error;
        try {
          await socket?.close();
        } on Object {
          // Try the next invitation endpoint after a failed socket cleanup.
        }
      } on Object {
        lastFailure = const AndroidHostPairingException(
          AndroidHostPairingFailure.hostUnavailable,
        );
        try {
          await socket?.close();
        } on Object {
          // Try the next invitation endpoint after a failed socket cleanup.
        }
      }
    }
    throw pinFailure ??
        lastFailure ??
        const AndroidHostPairingException(
          AndroidHostPairingFailure.hostUnavailable,
        );
  }

  void _validateInvitationCurrent(AndroidHostInvitation invitation) {
    if (invitation.expiresAt.isBefore(
      now().toUtc().subtract(const Duration(seconds: 30)),
    )) {
      throw const AndroidHostPairingException(
        AndroidHostPairingFailure.invitationExpired,
      );
    }
  }

  void _validateTarget(AndroidHostTarget target) {
    target.validate();
  }

  Future<void> _closeHandshake(
    AndroidHostSocket socket,
    StreamIterator<Object?> iterator,
  ) async {
    try {
      await iterator.cancel();
    } on Object {
      // Continue releasing the transport even if stream cancellation fails.
    }
    try {
      await socket.close();
    } on Object {
      // Request cleanup must not hide the protocol result.
    }
  }

  Future<Map<String, Object?>> _readRpcResult(
    StreamIterator<Object?> iterator,
    String requestId,
  ) async {
    late final bool hasMessage;
    try {
      hasMessage = await iterator.moveNext().timeout(handshakeTimeout);
    } on TimeoutException {
      throw const AndroidHostPairingException(
        AndroidHostPairingFailure.requestTimedOut,
      );
    }
    if (!hasMessage || iterator.current is! String) {
      throw const AndroidHostPairingException(
        AndroidHostPairingFailure.responseInvalid,
      );
    }
    Object? decoded;
    try {
      decoded = jsonDecode(iterator.current! as String);
    } on Object {
      throw const AndroidHostPairingException(
        AndroidHostPairingFailure.responseInvalid,
      );
    }
    if (decoded is! Map ||
        decoded.keys.any((key) => key is! String) ||
        decoded['jsonrpc'] != '2.0') {
      throw const AndroidHostPairingException(
        AndroidHostPairingFailure.responseInvalid,
      );
    }
    final response = decoded.cast<String, Object?>();
    if (response['id'] != requestId) {
      throw const AndroidHostPairingException(
        AndroidHostPairingFailure.responseInvalid,
      );
    }
    if (response['error'] is Map) {
      final error = (response['error']! as Map).cast<String, Object?>();
      final code = error['code'];
      if (code is int) _throwRpcFailure(code);
      throw const AndroidHostPairingException(
        AndroidHostPairingFailure.responseInvalid,
      );
    }
    if (response['result'] is! Map) {
      throw const AndroidHostPairingException(
        AndroidHostPairingFailure.responseInvalid,
      );
    }
    final result = (response['result']! as Map).cast<String, Object?>();
    return Map.unmodifiable(result);
  }

  Never _throwRpcFailure(int code) {
    throw switch (code) {
      -32010 => const AndroidHostPairingException(
        AndroidHostPairingFailure.invitationExpired,
        rpcCode: -32010,
      ),
      -32011 || -32002 => AndroidHostPairingException(
        AndroidHostPairingFailure.approvalRequired,
        rpcCode: code,
      ),
      -32012 => const AndroidHostPairingException(
        AndroidHostPairingFailure.alreadyPaired,
        rpcCode: -32012,
      ),
      -32015 => const AndroidHostPairingException(
        AndroidHostPairingFailure.storageFailure,
        rpcCode: -32015,
      ),
      _ => AndroidHostPairingException(
        AndroidHostPairingFailure.pairingRejected,
        rpcCode: code,
      ),
    };
  }

  void _validateDisplayName(String displayName) {
    final value = displayName.trim();
    if (value.isEmpty ||
        value.length > _maxDisplayNameLength ||
        _controlCharacters.hasMatch(value)) {
      throw const AndroidHostPairingException(
        AndroidHostPairingFailure.invalidDisplayName,
      );
    }
  }

  String _newId(String prefix) {
    final bytes = List<int>.generate(12, (_) => random.nextInt(256));
    return '$prefix-${base64UrlEncode(bytes).replaceAll('=', '')}';
  }
}

final class AndroidHostAuthenticatedSession {
  AndroidHostAuthenticatedSession._(
    this._socket,
    this._iterator,
    this.identity,
    this.hostId,
    this.certificateSha256,
    this.deviceId,
    this.sessionId,
    this._random,
    this._now,
    this._rpcTimeout,
  ) {
    _reader = _readLoop();
  }

  final AndroidHostSocket _socket;
  final StreamIterator<Object?> _iterator;
  final AndroidHostIdentityPort identity;
  final String hostId;
  final String certificateSha256;
  final String deviceId;
  final String sessionId;
  final Random _random;
  final DateTime Function() _now;
  final Duration _rpcTimeout;
  final Map<String, Completer<Map<String, Object?>>> _pending = {};
  final _notifications = StreamController<Map<String, Object?>>.broadcast(
    sync: true,
  );
  late final Future<void> _reader;
  var _closed = false;
  var _nextRequest = 0;
  Future<void>? _socketCloseFuture;
  Future<void>? _closeFuture;

  bool get isOpen => !_closed;

  Stream<Map<String, Object?>> get notifications => _notifications.stream;

  Future<Map<String, Object?>> call(
    String method,
    Map<String, Object?> params,
  ) async {
    if (_closed) {
      throw const AndroidHostPairingException(
        AndroidHostPairingFailure.transportClosed,
      );
    }
    final requestId = 'rpc-${++_nextRequest}';
    final payload = jsonEncode({
      'jsonrpc': '2.0',
      'id': requestId,
      'method': method,
      'params': params,
    });
    final payloadBytes = utf8.encode(payload);
    if (payloadBytes.isEmpty || payloadBytes.length > _maxHostRpcPayloadBytes) {
      throw const AndroidHostPairingException(
        AndroidHostPairingFailure.responseInvalid,
      );
    }
    final timestampSeconds = _now().toUtc().millisecondsSinceEpoch ~/ 1000;
    final nonceBytes = List<int>.generate(24, (_) => _random.nextInt(256));
    final nonce = base64UrlEncode(nonceBytes).replaceAll('=', '');
    final proof = HostPairingProtocol.rpcRequestProof(
      hostId: hostId,
      deviceId: deviceId,
      sessionId: sessionId,
      timestampSeconds: timestampSeconds,
      nonce: nonce,
      payloadBytes: payloadBytes,
    );
    late final List<int> signature;
    try {
      signature = await identity.sign(proof);
    } on Object {
      throw const AndroidHostPairingException(
        AndroidHostPairingFailure.invalidDeviceIdentity,
      );
    }
    final response = Completer<Map<String, Object?>>();
    _pending[requestId] = response;
    try {
      _socket.send(
        jsonEncode({
          'hostId': hostId,
          'deviceId': deviceId,
          'sessionId': sessionId,
          'timestampSeconds': timestampSeconds,
          'nonce': nonce,
          'payload': payload,
          'signatureDer': base64Encode(signature),
        }),
      );
      return await response.future.timeout(_rpcTimeout);
    } on TimeoutException {
      throw const AndroidHostPairingException(
        AndroidHostPairingFailure.requestTimedOut,
      );
    } on AndroidHostRpcException {
      rethrow;
    } on AndroidHostPairingException {
      rethrow;
    } on Object {
      throw const AndroidHostPairingException(
        AndroidHostPairingFailure.transportClosed,
      );
    } finally {
      _pending.remove(requestId);
    }
  }

  Future<void> _readLoop() async {
    try {
      while (await _iterator.moveNext()) {
        final frame = _iterator.current;
        if (frame is! String) continue;
        final response = _decodeResponse(frame);
        final requestId = response['id'];
        if (requestId == null && !response.containsKey('id')) {
          final method = response['method'];
          final params = response['params'];
          if (method is String &&
              params is Map &&
              params.keys.every((key) => key is String)) {
            _notifications.add(Map.unmodifiable(response));
          }
          continue;
        }
        if (requestId is! String) continue;
        final pending = _pending.remove(requestId);
        if (pending == null || pending.isCompleted) continue;
        if (response['error'] is Map) {
          final error = (response['error']! as Map).cast<String, Object?>();
          final code = error['code'];
          pending.completeError(
            AndroidHostRpcException(code is int ? code : null),
          );
        } else if (response['result'] is Map) {
          pending.complete(
            Map.unmodifiable(
              (response['result']! as Map).cast<String, Object?>(),
            ),
          );
        } else {
          pending.completeError(
            const AndroidHostPairingException(
              AndroidHostPairingFailure.responseInvalid,
            ),
          );
        }
      }
    } on Object {
      // The pending requests receive the stable transport error below.
    } finally {
      _closed = true;
      for (final pending in _pending.values) {
        if (!pending.isCompleted) {
          pending.completeError(
            const AndroidHostPairingException(
              AndroidHostPairingFailure.transportClosed,
            ),
          );
        }
      }
      _pending.clear();
      await _notifications.close();
      try {
        await _closeSocket();
      } on Object {
        // Reader termination still needs to settle if socket close fails.
      }
    }
  }

  Map<String, Object?> _decodeResponse(String frame) {
    try {
      final decoded = jsonDecode(frame);
      if (decoded is Map &&
          decoded.keys.every((key) => key is String) &&
          decoded['jsonrpc'] == '2.0') {
        return decoded.cast<String, Object?>();
      }
    } on Object {
      // Ignore invalid or unrelated server frames without exposing payloads.
    }
    return const {};
  }

  Future<void> _closeSocket() => _socketCloseFuture ??= _socket.close();

  Future<void> close() {
    final existing = _closeFuture;
    if (existing != null) return existing;
    _closed = true;
    final operation = () async {
      try {
        await _iterator.cancel();
      } on Object {
        // Closing the socket below also terminates a stalled stream iterator.
      }
      try {
        await _closeSocket();
      } on Object {
        // Wait for the reader even if transport close reports a failure.
      }
      await _reader;
    }();
    _closeFuture = operation;
    return operation;
  }
}

final class AndroidHostRpcException implements Exception {
  const AndroidHostRpcException(this.code);

  final int? code;

  @override
  String toString() => 'AndroidHostRpcException($code)';
}

bool _onlyKeys(Map<String, Object?> value, Set<String> expected) =>
    value.keys.toSet().difference(expected).isEmpty &&
    expected.difference(value.keys.toSet()).isEmpty;
