import 'dart:async';

import 'package:flutter/services.dart';

import '../host/host_pairing_protocol.dart';
import 'android_host_pairing_client.dart';

abstract interface class AndroidHostDiscoveryPort {
  Future<List<AndroidHostEndpoint>> discover(String hostId);
}

final class MethodChannelAndroidHostDiscovery
    implements AndroidHostDiscoveryPort {
  const MethodChannelAndroidHostDiscovery({
    this.channel = const MethodChannel('aggregate/host_discovery'),
    this.timeout = const Duration(seconds: 8),
  });

  final MethodChannel channel;
  final Duration timeout;

  @override
  Future<List<AndroidHostEndpoint>> discover(String hostId) async {
    if (!HostPairingProtocol.isHostId(hostId)) return const [];
    try {
      final values = await channel
          .invokeListMethod<String>('discover', {'hostId': hostId})
          .timeout(timeout);
      final endpoints = <AndroidHostEndpoint>[];
      for (final value in values ?? const <String>[]) {
        final uri = Uri.tryParse(value);
        if (uri == null) continue;
        endpoints.add(AndroidHostEndpoint(uri));
      }
      final target = AndroidHostTarget(
        hostId: hostId,
        certificateSha256: List<String>.filled(64, '0').join(),
        endpoints: endpoints,
      );
      try {
        target.validate();
        return target.endpoints;
      } on AndroidHostPairingException {
        return const [];
      }
    } on Object {
      // Saved endpoints remain a fallback when multicast discovery is blocked.
      return const [];
    }
  }
}
