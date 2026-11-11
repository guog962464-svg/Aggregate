import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class AndroidCredentialStore {
  Future<void> write(String connectionId, String token);
  Future<String?> read(String connectionId);
  Future<void> delete(String connectionId);
  Future<void> removeOrphans(Set<String> activeIds);
}

final class SecureAndroidCredentialStore implements AndroidCredentialStore {
  const SecureAndroidCredentialStore();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(resetOnError: false),
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

  @override
  Future<void> removeOrphans(Set<String> activeIds) async {
    const prefix = 'aggregate.mcp.bearer.';
    final values = await _storage.readAll();
    for (final key in values.keys) {
      if (key.startsWith(prefix) &&
          !activeIds.contains(key.substring(prefix.length))) {
        await _storage.delete(key: key);
      }
    }
  }
}
