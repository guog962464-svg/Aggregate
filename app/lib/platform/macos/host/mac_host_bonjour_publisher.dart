import 'package:flutter/services.dart';

import 'host_control_port.dart';
import 'host_wss_transport.dart';

final class MacHostBonjourPublisher implements HostBonjourPublisher {
  const MacHostBonjourPublisher({
    this._channel = const MethodChannel('aggregate/host_bonjour'),
  });

  final MethodChannel _channel;

  @override
  Future<void> publish({
    required String hostId,
    required int port,
    required List<int> interfaceIndices,
  }) async {
    if (!RegExp(r'^host-[a-f0-9]{32}$').hasMatch(hostId) ||
        port < 1 ||
        port > 65535 ||
        interfaceIndices.isEmpty ||
        interfaceIndices.length > 8 ||
        interfaceIndices.any((index) => index < 1) ||
        interfaceIndices.toSet().length != interfaceIndices.length) {
      throw const HostControlException(HostControlErrorCode.transportFailure);
    }
    try {
      await _channel.invokeMethod<void>('publish', {
        'hostId': hostId,
        'port': port,
        'interfaceIndices': interfaceIndices,
      });
    } on PlatformException {
      throw const HostControlException(HostControlErrorCode.transportFailure);
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _channel.invokeMethod<void>('stop');
    } on PlatformException {
      throw const HostControlException(HostControlErrorCode.transportFailure);
    }
  }
}
