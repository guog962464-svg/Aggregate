import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Byte-exact signing inputs shared by the Android client and macOS Host.
abstract final class HostPairingProtocol {
  static const version = 1;
  static final _hostIdPattern = RegExp(r'^host-[a-f0-9]{32}$');
  static final _deviceIdPattern = RegExp(r'^device-[a-f0-9]{32}$');
  static final _tokenPattern = RegExp(r'^[A-Za-z0-9_-]{22,86}$');

  /// Matches AndroidHostDeviceIdentity's first 16 bytes of SHA-256(SPKI).
  static String deviceIdForPublicKey(List<int> publicKeySpki) {
    if (publicKeySpki.isEmpty || publicKeySpki.length > 256) {
      throw const FormatException('Host device public key is invalid');
    }
    final suffix = sha256
        .convert(publicKeySpki)
        .bytes
        .take(16)
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return 'device-$suffix';
  }

  static Uint8List pairingProof({
    required String hostId,
    required String deviceId,
    required String invitationNonce,
    required int timestampSeconds,
  }) {
    _validateHostDevice(hostId, deviceId);
    _validateToken(invitationNonce, 'invitation nonce');
    _validateTimestamp(timestampSeconds);
    return Uint8List.fromList(
      utf8.encode(
        'aggregate-host-pair-v$version\n'
        '$hostId\n$deviceId\n$invitationNonce\n$timestampSeconds',
      ),
    );
  }

  static Uint8List authenticationProof({
    required String hostId,
    required String deviceId,
    required String connectionId,
    required String challenge,
  }) {
    _validateHostDevice(hostId, deviceId);
    _validateToken(connectionId, 'connection ID');
    _validateToken(challenge, 'challenge');
    return Uint8List.fromList(
      utf8.encode(
        'aggregate-host-auth-v$version\n'
        '$hostId\n$deviceId\n$connectionId\n$challenge',
      ),
    );
  }

  static Uint8List rpcRequestProof({
    required String hostId,
    required String deviceId,
    required String sessionId,
    required int timestampSeconds,
    required String nonce,
    required List<int> payloadBytes,
  }) {
    _validateHostDevice(hostId, deviceId);
    _validateToken(sessionId, 'session ID');
    _validateToken(nonce, 'request nonce');
    _validateTimestamp(timestampSeconds);
    if (payloadBytes.isEmpty || payloadBytes.length > 1024 * 1024) {
      throw const FormatException('Host RPC payload is invalid');
    }
    final payloadHash = sha256.convert(payloadBytes);
    return Uint8List.fromList(
      utf8.encode(
        'aggregate-host-v$version\n'
        '$hostId\n$deviceId\n$sessionId\n$timestampSeconds\n'
        '$nonce\n$payloadHash',
      ),
    );
  }

  static String confirmationCode({
    required String hostId,
    required String deviceId,
    required String invitationNonce,
  }) {
    _validateHostDevice(hostId, deviceId);
    _validateToken(invitationNonce, 'invitation nonce');
    final bytes = sha256
        .convert(
          utf8.encode(
            'aggregate-host-code-v$version\n'
            '$hostId\n$deviceId\n$invitationNonce',
          ),
        )
        .bytes;
    final value = ((bytes[0] << 16) | (bytes[1] << 8) | bytes[2]) % 1000000;
    return value.toString().padLeft(6, '0');
  }

  static bool isHostId(String value) => _hostIdPattern.hasMatch(value);
  static bool isDeviceId(String value) => _deviceIdPattern.hasMatch(value);
  static bool isToken(String value) => _tokenPattern.hasMatch(value);

  static void _validateHostDevice(String hostId, String deviceId) {
    if (!isHostId(hostId) || !isDeviceId(deviceId)) {
      throw const FormatException('Host identity is invalid');
    }
  }

  static void _validateToken(String value, String label) {
    if (!isToken(value)) throw FormatException('Host $label is invalid');
  }

  static void _validateTimestamp(int timestampSeconds) {
    if (timestampSeconds < 0 || timestampSeconds > 9007199254740991) {
      throw const FormatException('Host timestamp is invalid');
    }
  }
}
