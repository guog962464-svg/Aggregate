import 'dart:convert';

import 'package:flutter/services.dart';

abstract interface class HostDeviceSignatureVerifier {
  Future<bool> verify({
    required List<int> publicKeySpki,
    required List<int> message,
    required List<int> signatureDer,
  });
}

/// Verifies Android Keystore P-256/SHA-256 signatures in CryptoKit.
final class MacHostDeviceSignatureVerifier
    implements HostDeviceSignatureVerifier {
  const MacHostDeviceSignatureVerifier({MethodChannel? channel})
    : _channel =
          channel ?? const MethodChannel('aggregate/host_authentication');

  final MethodChannel _channel;

  @override
  Future<bool> verify({
    required List<int> publicKeySpki,
    required List<int> message,
    required List<int> signatureDer,
  }) async {
    if (publicKeySpki.isEmpty ||
        publicKeySpki.length > 256 ||
        message.isEmpty ||
        message.length > 1024 * 1024 ||
        signatureDer.isEmpty ||
        signatureDer.length > 80) {
      return false;
    }
    return await _channel.invokeMethod<bool>('verifyDeviceSignature', {
          'publicKeySpki': base64Encode(publicKeySpki),
          'message': base64Encode(message),
          'signature': base64Encode(signatureDer),
        }) ??
        false;
  }
}
