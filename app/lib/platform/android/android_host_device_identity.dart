import 'dart:convert';

import 'package:flutter/services.dart';

abstract interface class AndroidHostIdentityPort {
  Future<AndroidHostPublicIdentity> loadOrCreate();
  Future<AndroidHostPublicIdentity> rotate();
  Future<Uint8List> sign(Uint8List message);
}

final class AndroidHostDeviceIdentity implements AndroidHostIdentityPort {
  const AndroidHostDeviceIdentity({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('aggregate/host_identity');

  final MethodChannel _channel;

  @override
  Future<AndroidHostPublicIdentity> loadOrCreate() =>
      _readIdentity('loadOrCreate');

  @override
  Future<AndroidHostPublicIdentity> rotate() => _readIdentity('rotate');

  Future<AndroidHostPublicIdentity> _readIdentity(String method) async {
    final result = await _channel.invokeMapMethod<String, Object?>(method);
    if (result == null ||
        result['deviceId'] is! String ||
        result['publicKeySpki'] is! String) {
      throw const FormatException('Android identity response is invalid');
    }
    final identity = AndroidHostPublicIdentity(
      deviceId: result['deviceId']! as String,
      publicKeySpki: base64Decode(result['publicKeySpki']! as String),
    );
    if (!RegExp(r'^device-[a-f0-9]{32}$').hasMatch(identity.deviceId) ||
        identity.publicKeySpki.isEmpty ||
        identity.publicKeySpki.length > 256) {
      throw const FormatException('Android identity response is invalid');
    }
    return identity;
  }

  @override
  Future<Uint8List> sign(Uint8List message) async {
    if (message.isEmpty || message.length > 1024 * 1024) {
      throw ArgumentError.value(message.length, 'message.length');
    }
    final signature = await _channel.invokeMethod<String>('sign', {
      'message': base64Encode(message),
    });
    if (signature == null) {
      throw const FormatException('Android signature response is missing');
    }
    final decoded = base64Decode(signature);
    if (decoded.length < 64 || decoded.length > 80) {
      throw const FormatException('Android signature response is invalid');
    }
    return Uint8List.fromList(decoded);
  }

  Future<void> delete() => _channel.invokeMethod<void>('delete');
}

final class AndroidHostPublicIdentity {
  AndroidHostPublicIdentity({
    required this.deviceId,
    required List<int> publicKeySpki,
  }) : publicKeySpki = Uint8List.fromList(publicKeySpki);

  final String deviceId;
  final Uint8List publicKeySpki;
}
