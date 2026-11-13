import 'dart:async';

import 'package:aggregate_contracts/aggregate_contracts.dart';

import 'host_control_port.dart';
import 'host_pairing_authority.dart';
import 'host_setup_coordinator.dart';
import 'host_transport_port.dart';
import 'host_wss_transport.dart';

/// Runtime capabilities the Host will dispatch through in later A5 stages.
/// These ports must refer to the same app-owned runtime instance.
final class MacHostRuntimeBindings {
  MacHostRuntimeBindings({
    required this.runtime,
    required this.connectionSetup,
    required this.accounts,
  }) {
    if (!identical(runtime, connectionSetup) || !identical(runtime, accounts)) {
      throw ArgumentError('Host ports must share one Mac runtime instance');
    }
  }

  final RuntimePort runtime;
  final ConnectionSetupPort connectionSetup;
  final ConnectionAccountPort accounts;
}

/// Host lifecycle and ownership boundary for the existing macOS runtime.
///
/// Stopping this module closes only Host-owned transport resources. The local
/// UI continues to own and dispose the runtime.
final class MacHostModule implements HostControlPort, HostPairingControlPort {
  MacHostModule({
    required this.runtimeBindings,
    required this.hostTransport,
    HostSetupCoordinator? setupCoordinator,
  }) : setupCoordinator =
           setupCoordinator ??
           HostSetupCoordinator(setup: runtimeBindings.connectionSetup);

  final MacHostRuntimeBindings runtimeBindings;
  final HostTransportPort hostTransport;
  final HostSetupCoordinator setupCoordinator;
  final _changes = StreamController<HostStatus>.broadcast(sync: true);
  HostStatus _status = const HostStatus(HostPhase.stopped);
  Future<void> _operationTail = Future<void>.value();

  HostPairingControlPort get _pairingControl {
    final transport = hostTransport;
    if (transport is HostPairingControlPort) {
      return transport as HostPairingControlPort;
    }
    throw const HostControlException(
      HostControlErrorCode.pairingAuthenticationRequired,
    );
  }

  @override
  Future<HostWssPairingInvitation> createInvitation() =>
      _pairingControl.createInvitation();

  @override
  Future<List<HostPendingPairing>> pendingRequests() =>
      _pairingControl.pendingRequests();

  @override
  Future<void> rejectPending(String deviceId) =>
      _pairingControl.rejectPending(deviceId);

  @override
  Future<HostDeviceGrant> approvePending(
    String deviceId, {
    Set<HostGrantScope> scopes = const {HostGrantScope.readConnections},
    Map<String, Set<PermissionLevel>> connectionPermissions = const {},
  }) => _pairingControl.approvePending(
    deviceId,
    scopes: scopes,
    connectionPermissions: connectionPermissions,
  );

  @override
  Future<List<HostDeviceGrant>> pairedDevices() =>
      _pairingControl.pairedDevices();

  @override
  Future<void> revokeDevice(String deviceId) =>
      _pairingControl.revokeDevice(deviceId);

  @override
  HostStatus get status => _status;

  @override
  Stream<HostStatus> watchStatus() => Stream<HostStatus>.multi((sink) {
    sink.add(_status);
    final subscription = _changes.stream.listen(
      sink.add,
      onError: sink.addError,
    );
    sink.onCancel = subscription.cancel;
  });

  @override
  Future<void> start() => _serialize(() async {
    if (_status.phase == HostPhase.running) return;
    _publish(const HostStatus(HostPhase.starting));
    try {
      await hostTransport.start();
      _publish(const HostStatus(HostPhase.running));
    } catch (error) {
      var rollbackFailed = false;
      try {
        await hostTransport.stop();
      } catch (_) {
        rollbackFailed = true;
      }
      if (rollbackFailed) {
        _publish(
          const HostStatus(
            HostPhase.failed,
            reason: HostStatusReason.startupFailed,
          ),
        );
      } else if (error is HostControlException &&
          error.code == HostControlErrorCode.pairingAuthenticationRequired) {
        _publish(
          const HostStatus(
            HostPhase.unavailable,
            reason: HostStatusReason.pairingAuthenticationRequired,
          ),
        );
      } else {
        _publish(
          const HostStatus(
            HostPhase.failed,
            reason: HostStatusReason.startupFailed,
          ),
        );
      }
      throw rollbackFailed || error is! HostControlException
          ? const HostControlException(HostControlErrorCode.transportFailure)
          : error;
    }
  });

  @override
  Future<void> stop() => _serialize(() async {
    if (_status.phase == HostPhase.stopped) {
      await setupCoordinator.closeAll();
      return;
    }
    _publish(const HostStatus(HostPhase.stopping));
    try {
      await hostTransport.stop();
      await setupCoordinator.closeAll();
      _publish(const HostStatus(HostPhase.stopped));
    } catch (_) {
      _publish(
        const HostStatus(
          HostPhase.failed,
          reason: HostStatusReason.shutdownFailed,
        ),
      );
      throw const HostControlException(HostControlErrorCode.transportFailure);
    }
  });

  Future<void> _serialize(Future<void> Function() action) {
    final result = _operationTail.then((_) => action());
    _operationTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  void _publish(HostStatus next) {
    if (_status.phase == next.phase && _status.reason == next.reason) return;
    _status = next;
    _changes.add(next);
  }
}
