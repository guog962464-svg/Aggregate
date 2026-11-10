import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'credential_store.dart';

/// Uses the legacy macOS Keychain for direct distribution.
final class KeychainCredentialStore implements CredentialStore {
  const KeychainCredentialStore();

  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    mOptions: MacOsOptions(usesDataProtectionKeychain: false),
  );

  String _key(String id) => 'aggregate.mcp.bearer.$id';

  @override
  Future<void> write(String connectionId, String token) =>
      _storage.write(key: _key(connectionId), value: token);

  @override
  Future<String?> read(String connectionId) =>
      _storage.read(key: _key(connectionId));

  @override
  Future<void> delete(String connectionId) =>
      _storage.delete(key: _key(connectionId));
}
