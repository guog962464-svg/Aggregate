import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

abstract interface class HostTlsIdentityProvider {
  Future<HostTlsIdentityMaterial> loadOrCreate();
  Future<HostTlsIdentityMaterial> rotate();
}

/// Retrieves the Mac TLS identity from the native Keychain-backed provider.
/// The private key is exported only into the running process for dart:io TLS.
final class MacKeychainHostTlsIdentityProvider
    implements HostTlsIdentityProvider {
  const MacKeychainHostTlsIdentityProvider({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('aggregate/host_identity');

  final MethodChannel _channel;

  @override
  Future<HostTlsIdentityMaterial> loadOrCreate() => _load('loadOrCreate');

  @override
  Future<HostTlsIdentityMaterial> rotate() => _load('rotate');

  Future<HostTlsIdentityMaterial> _load(String method) async {
    final result = await _channel.invokeMapMethod<String, Object?>(method);
    if (result == null ||
        result['hostId'] is! String ||
        result['certificatePem'] is! String ||
        result['privateKeyPem'] is! String) {
      throw const HostTlsIdentityException();
    }
    return HostTlsIdentityMaterial(
      hostId: result['hostId']! as String,
      certificatePem: result['certificatePem']! as String,
      privateKeyPem: result['privateKeyPem']! as String,
    );
  }
}

/// Validates native identity material before the Host can create a listener.
final class HostTlsIdentityStore {
  HostTlsIdentityStore({HostTlsIdentityProvider? provider})
    : _provider = provider ?? const MacKeychainHostTlsIdentityProvider();

  final HostTlsIdentityProvider _provider;

  Future<HostTlsIdentity> loadOrCreate() async =>
      _validate(await _provider.loadOrCreate());

  /// Rotates the certificate pin. Callers must first require explicit local
  /// confirmation and revoke all existing pairings.
  Future<HostTlsIdentity> rotate() async => _validate(await _provider.rotate());

  HostTlsIdentity _validate(HostTlsIdentityMaterial material) {
    try {
      if (!RegExp(r'^host-[a-f0-9]{32}$').hasMatch(material.hostId) ||
          material.certificatePem.length > 16 * 1024 ||
          material.privateKeyPem.length > 16 * 1024 ||
          !material.certificatePem.contains('-----BEGIN CERTIFICATE-----') ||
          !material.privateKeyPem.contains('-----BEGIN EC PRIVATE KEY-----')) {
        throw const HostTlsIdentityException();
      }
      final certificateDer = _decodeCertificatePem(material.certificatePem);
      final identity = HostTlsIdentity(
        hostId: material.hostId,
        certificatePem: material.certificatePem,
        privateKeyPem: material.privateKeyPem,
        certificateSha256: sha256.convert(certificateDer).toString(),
      );
      identity.createServerContext();
      return identity;
    } catch (_) {
      throw const HostTlsIdentityException();
    }
  }

  List<int> _decodeCertificatePem(String value) {
    final match = RegExp(
      r'^-----BEGIN CERTIFICATE-----\s*([A-Za-z0-9+/=\r\n]+)\s*-----END CERTIFICATE-----\s*$',
    ).firstMatch(value);
    if (match == null) throw const HostTlsIdentityException();
    return base64Decode(match.group(1)!.replaceAll(RegExp(r'\s'), ''));
  }
}

final class HostTlsIdentityMaterial {
  const HostTlsIdentityMaterial({
    required this.hostId,
    required this.certificatePem,
    required this.privateKeyPem,
  });

  final String hostId;
  final String certificatePem;
  final String privateKeyPem;
}

final class HostTlsIdentity {
  const HostTlsIdentity({
    required this.hostId,
    required this.certificatePem,
    required this.privateKeyPem,
    required this.certificateSha256,
  });

  final String hostId;
  final String certificatePem;
  final String privateKeyPem;
  final String certificateSha256;

  SecurityContext createServerContext() {
    final context = SecurityContext(withTrustedRoots: false)
      ..minimumTlsProtocolVersion = TlsProtocolVersion.tls1_2
      ..useCertificateChainBytes(utf8.encode(certificatePem))
      ..usePrivateKeyBytes(utf8.encode(privateKeyPem));
    return context;
  }
}

final class HostTlsIdentityException implements Exception {
  const HostTlsIdentityException();
}
