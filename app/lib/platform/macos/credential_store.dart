abstract interface class CredentialStore {
  Future<void> write(String connectionId, String token);
  Future<String?> read(String connectionId);
  Future<void> delete(String connectionId);
}

final class NoCredentialStore implements CredentialStore {
  const NoCredentialStore();

  @override
  Future<void> write(String connectionId, String token) =>
      Future.error(UnsupportedError('此运行环境不支持保存凭证'));

  @override
  Future<String?> read(String connectionId) async => null;

  @override
  Future<void> delete(String connectionId) async {}
}
