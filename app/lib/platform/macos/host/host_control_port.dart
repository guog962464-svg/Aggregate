import 'dart:async';

enum HostPhase { stopped, starting, running, stopping, unavailable, failed }

enum HostStatusReason {
  pairingAuthenticationRequired,
  startupFailed,
  shutdownFailed,
}

final class HostStatus {
  const HostStatus(this.phase, {this.reason});

  final HostPhase phase;
  final HostStatusReason? reason;
}

abstract interface class HostControlPort {
  HostStatus get status;
  Stream<HostStatus> watchStatus();
  Future<void> start();
  Future<void> stop();
}

enum HostControlErrorCode { pairingAuthenticationRequired, transportFailure }

final class HostControlException implements Exception {
  const HostControlException(this.code);

  final HostControlErrorCode code;

  @override
  String toString() => 'HostControlException($code)';
}
