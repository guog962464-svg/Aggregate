import 'dart:io';

import 'host_device_signature_verifier.dart';
import 'host_operation_ledger.dart';
import 'host_pairing_authority.dart';
import 'host_setup_coordinator.dart';
import 'host_setup_rpc_dispatcher.dart';
import 'host_tls_identity.dart';
import 'host_transport_port.dart';
import 'host_wss_transport.dart';
import '../mac_runtime.dart';
import 'mac_host_bonjour_publisher.dart';
import '../../host/host_wss_protocol.dart';

HostTransportPort createMacHostWssTransport({
  required MacRuntime runtime,
  required HostSetupCoordinator setupCoordinator,
  HostWssBindAddressProvider bindAddressProvider =
      const PrivateMacHostWssBindAddressProvider(),
  HostBonjourPublisher? bonjourPublisher,
  HostTlsIdentityStore? identityStore,
  HostPairingStore? pairingStore,
  HostDeviceSignatureVerifier? signatureVerifier,
  int requestedPort = hostWssDefaultPort,
}) {
  final tlsIdentityStore = identityStore ?? HostTlsIdentityStore();
  final hostPairingStore = pairingStore ?? const MacKeychainHostPairingStore();
  final deviceSignatureVerifier =
      signatureVerifier ?? const MacHostDeviceSignatureVerifier();
  final discoveryPublisher =
      bonjourPublisher ?? const MacHostBonjourPublisher();

  return HostWssTransport(
    loadServices: () async {
      final identity = await tlsIdentityStore.loadOrCreate();
      final pairing = HostPairingAuthority(
        identity: identity,
        store: hostPairingStore,
        signatureVerifier: deviceSignatureVerifier,
        setupCoordinator: setupCoordinator,
      );
      final hostDirectory = Directory('${runtime.dataDirectory.path}/host');
      await hostDirectory.create(recursive: true);
      final ledger = await FileHostOperationLedger.open(
        File('${hostDirectory.path}/operations.json'),
      );
      return HostWssServices(
        identity: identity,
        pairing: pairing,
        dispatcher: HostSetupRpcDispatcher(
          setup: setupCoordinator,
          ledger: ledger,
          authorization: pairing,
        ),
      );
    },
    bindAddressProvider: bindAddressProvider,
    bonjourPublisher: discoveryPublisher,
    requestedPort: requestedPort,
  );
}
