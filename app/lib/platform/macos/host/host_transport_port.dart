import 'host_control_port.dart';

/// Owns only the transport lifecycle. It never owns or disposes the runtime.
abstract interface class HostTransportPort {
  Future<void> start();
  Future<void> stop();
}

/// The production network listener stays closed until device authentication
/// and pairing approval are implemented.
final class PairingRequiredHostTransport implements HostTransportPort {
  const PairingRequiredHostTransport();

  @override
  Future<void> start() async {
    throw const HostControlException(
      HostControlErrorCode.pairingAuthenticationRequired,
    );
  }

  @override
  Future<void> stop() async {}
}
