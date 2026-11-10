import 'models.dart';

enum AccountState { signedIn, signedOut, unknown }

final class AccountSnapshot {
  const AccountSnapshot(this.state, {this.nickname, this.message});

  final AccountState state;
  final String? nickname;
  final String? message;
}

/// Optional account controls for connections with a verified provider adapter.
/// Implementations keep credentials and provider-specific processes outside UI.
abstract interface class ConnectionAccountPort {
  /// Returns null when this connection has no supported account adapter.
  Future<AccountSnapshot?> readAccount(ConnectionId connection);

  /// Opens the provider's interactive login in a terminal session.
  Future<TerminalSession> beginAccountLogin(ConnectionId connection);

  /// Waits for login to finish; callers must verify [readAccount] afterwards.
  Future<int> waitAccountLogin(TerminalSession session);

  /// Confirmation is required because this changes the CLI's stored account.
  Future<AccountSnapshot> logoutAccount(
    ConnectionId connection, {
    required bool confirmed,
  });
}
