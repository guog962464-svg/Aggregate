import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:aggregate_contracts/aggregate_contracts.dart';

import 'host_control_port.dart';
import 'host_pairing_authority.dart';
import 'host_rpc_protocol.dart';
import 'host_setup_rpc_dispatcher.dart';
import 'host_tls_identity.dart';
import 'host_transport_port.dart';
import '../../host/host_pairing_protocol.dart';
import '../../host/host_wss_protocol.dart';

typedef HostWssServicesLoader = Future<HostWssServices> Function();

final class HostWssServices {
  const HostWssServices({
    required this.identity,
    required this.pairing,
    required this.dispatcher,
  });

  final HostTlsIdentity identity;
  final HostPairingAuthority pairing;
  final HostRpcDispatcherPort dispatcher;
}

final class HostWssEndpoint {
  const HostWssEndpoint({
    required this.address,
    required this.port,
    required this.interfaceIndex,
  });

  final InternetAddress address;
  final int port;
  final int interfaceIndex;

  Uri get uri =>
      Uri(scheme: 'wss', host: address.address, port: port, path: hostWssPath);

  JsonMap toJson() => {'uri': uri.toString()};
}

final class HostWssPairingInvitation {
  const HostWssPairingInvitation({
    required this.invitation,
    required this.endpoints,
  });

  final HostPairingInvitation invitation;
  final List<HostWssEndpoint> endpoints;

  String get qrPayload => jsonEncode({
    'version': HostPairingProtocol.version,
    'hostId': invitation.hostId,
    'certificateSha256': invitation.certificateSha256,
    'nonce': invitation.nonce,
    'expiresAt': invitation.expiresAt.toUtc().toIso8601String(),
    'serviceType': hostBonjourServiceType,
    'endpoints': [for (final endpoint in endpoints) endpoint.toJson()],
  });
}

abstract interface class HostPairingControlPort {
  Future<HostWssPairingInvitation> createInvitation();
  Future<List<HostPendingPairing>> pendingRequests();
  Future<void> rejectPending(String deviceId);
  Future<HostDeviceGrant> approvePending(
    String deviceId, {
    Set<HostGrantScope> scopes = const {HostGrantScope.readConnections},
    Map<String, Set<PermissionLevel>> connectionPermissions = const {},
  });
  Future<HostDeviceGrant> updateDeviceGrant(
    String deviceId, {
    required Set<HostGrantScope> scopes,
    required Map<String, Set<PermissionLevel>> connectionPermissions,
  });
  Future<List<HostDeviceGrant>> pairedDevices();
  Future<void> revokeDevice(String deviceId);
}

final class HostWssBindTarget {
  const HostWssBindTarget({
    required this.address,
    required this.interfaceIndex,
  });

  final InternetAddress address;
  final int interfaceIndex;
}

abstract interface class HostWssBindAddressProvider {
  Future<List<HostWssBindTarget>> addresses();
}

/// Uses only private IPv4 addresses on physical `en*` macOS interfaces.
/// Loopback, link-local, public, bridge and tunnel interfaces are excluded.
final class PrivateMacHostWssBindAddressProvider
    implements HostWssBindAddressProvider {
  const PrivateMacHostWssBindAddressProvider();

  @override
  Future<List<HostWssBindTarget>> addresses() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    final found = <String, HostWssBindTarget>{};
    for (final interface in interfaces) {
      if (!RegExp(r'^en[0-9]+$').hasMatch(interface.name)) continue;
      for (final interfaceAddress in interface.addresses) {
        final address = interfaceAddress;
        if (_isPrivateIpv4(address)) {
          found['${interface.index}:${address.address}'] = HostWssBindTarget(
            address: address,
            interfaceIndex: interface.index,
          );
        }
      }
    }
    return List.unmodifiable(found.values.take(8));
  }

  bool _isPrivateIpv4(InternetAddress address) {
    if (address.type != InternetAddressType.IPv4 || address.isLoopback) {
      return false;
    }
    final bytes = address.rawAddress;
    if (bytes.length != 4) return false;
    final first = bytes[0];
    final second = bytes[1];
    return first == 10 ||
        (first == 172 && second >= 16 && second <= 31) ||
        (first == 192 && second == 168);
  }
}

abstract interface class HostBonjourPublisher {
  Future<void> publish({
    required String hostId,
    required int port,
    required List<int> interfaceIndices,
  });
  Future<void> stop();
}

final class NoopHostBonjourPublisher implements HostBonjourPublisher {
  const NoopHostBonjourPublisher();

  @override
  Future<void> publish({
    required String hostId,
    required int port,
    required List<int> interfaceIndices,
  }) async {}

  @override
  Future<void> stop() async {}
}

/// Pinned TLS WebSocket listener. It binds only to caller-approved interface
/// addresses; it never listens on `anyIPv4` or a public address.
final class HostWssTransport
    implements HostTransportPort, HostPairingControlPort {
  HostWssTransport({
    required this.loadServices,
    required this.bindAddressProvider,
    required this.bonjourPublisher,
    this.requestedPort = 0,
    this.maxConnections = 64,
    this.maxConnectionsPerAddress = 4,
    this.maxConnectionsPerDevice = 4,
    this.handshakeTimeout = const Duration(seconds: 10),
    this.socketPingInterval = const Duration(seconds: 30),
  }) {
    if (requestedPort < 0 ||
        requestedPort > 65535 ||
        maxConnections < 1 ||
        maxConnections > 64 ||
        maxConnectionsPerAddress < 1 ||
        maxConnectionsPerAddress > maxConnections ||
        maxConnectionsPerDevice < 1 ||
        maxConnectionsPerDevice > maxConnections ||
        handshakeTimeout <= Duration.zero ||
        socketPingInterval <= Duration.zero) {
      throw ArgumentError('Invalid Host WSS policy');
    }
  }

  final HostWssServicesLoader loadServices;
  final HostWssBindAddressProvider bindAddressProvider;
  final HostBonjourPublisher bonjourPublisher;
  final int requestedPort;
  final int maxConnections;
  final int maxConnectionsPerAddress;
  final int maxConnectionsPerDevice;
  final Duration handshakeTimeout;
  final Duration socketPingInterval;
  final List<HttpServer> _servers = [];
  final Map<WebSocket, _HostWssConnection> _connections = {};
  final Map<String, int> _connectionsByAddress = {};
  final Map<String, int> _connectionsByDevice = {};
  final Map<String, int> _pendingUpgradesByAddress = {};
  HostWssServices? _services;
  StreamSubscription<String>? _authorizationChangeSubscription;
  List<HostWssEndpoint> _endpoints = const [];
  Future<void>? _startOperation;
  Future<void>? _stopOperation;
  var _accepting = false;

  bool get isRunning => _accepting;
  List<HostWssEndpoint> get endpoints => List.unmodifiable(_endpoints);

  @override
  Future<HostWssPairingInvitation> createInvitation() async {
    final services = _services;
    if (!_accepting || services == null || _endpoints.isEmpty) {
      throw const HostControlException(
        HostControlErrorCode.pairingAuthenticationRequired,
      );
    }
    return HostWssPairingInvitation(
      invitation: await services.pairing.createInvitation(),
      endpoints: endpoints,
    );
  }

  @override
  Future<List<HostPendingPairing>> pendingRequests() async =>
      _requireServices().pairing.pendingRequests();

  @override
  Future<void> rejectPending(String deviceId) =>
      _requireServices().pairing.rejectPending(deviceId);

  @override
  Future<HostDeviceGrant> approvePending(
    String deviceId, {
    Set<HostGrantScope> scopes = const {HostGrantScope.readConnections},
    Map<String, Set<PermissionLevel>> connectionPermissions = const {},
  }) async => _requireServices().pairing.approvePending(
    deviceId,
    scopes: scopes,
    connectionPermissions: connectionPermissions,
  );

  @override
  Future<HostDeviceGrant> updateDeviceGrant(
    String deviceId, {
    required Set<HostGrantScope> scopes,
    required Map<String, Set<PermissionLevel>> connectionPermissions,
  }) => _requireServices().pairing.updateDeviceGrant(
    deviceId,
    scopes: scopes,
    connectionPermissions: connectionPermissions,
  );

  @override
  Future<List<HostDeviceGrant>> pairedDevices() async =>
      _requireServices().pairing.pairedDevices();

  @override
  Future<void> revokeDevice(String deviceId) async =>
      _requireServices().pairing.revokeDevice(deviceId);

  @override
  Future<void> start() {
    if (_accepting) return Future<void>.value();
    final existing = _startOperation;
    if (existing != null) return existing;
    final operation = _start().whenComplete(() => _startOperation = null);
    _startOperation = operation;
    return operation;
  }

  Future<void> _start() async {
    if (_accepting) return;
    final services = await loadServices();
    await services.pairing.initialize();
    final targets = await _validatedAddresses(
      await bindAddressProvider.addresses(),
    );
    if (targets.isEmpty) {
      throw const HostControlException(HostControlErrorCode.transportFailure);
    }

    final boundServers = <HttpServer>[];
    final boundEndpoints = <HostWssEndpoint>[];
    try {
      final context = services.identity.createServerContext();
      var port = requestedPort;
      for (final target in targets) {
        final server = await HttpServer.bindSecure(
          target.address,
          port,
          context,
          backlog: 32,
          shared: false,
        );
        if (port == 0) port = server.port;
        boundServers.add(server);
        boundEndpoints.add(
          HostWssEndpoint(
            address: server.address,
            port: server.port,
            interfaceIndex: target.interfaceIndex,
          ),
        );
      }

      _services = services;
      _servers.addAll(boundServers);
      _endpoints = List.unmodifiable(boundEndpoints);
      _authorizationChangeSubscription = services.pairing
          .watchAuthorizationChanges()
          .listen(_disconnectDevice);
      for (final server in boundServers) {
        server.listen(_handleRequest, onError: (Object _, StackTrace _) {});
      }
      final servicePort = boundServers.first.port;
      await bonjourPublisher.publish(
        hostId: services.identity.hostId,
        port: servicePort,
        interfaceIndices: boundEndpoints
            .map((endpoint) => endpoint.interfaceIndex)
            .toSet()
            .toList(growable: false),
      );
      _accepting = true;
    } catch (_) {
      try {
        await _authorizationChangeSubscription?.cancel();
      } catch (_) {}
      _authorizationChangeSubscription = null;
      _services = null;
      _endpoints = const [];
      _servers.clear();
      try {
        await bonjourPublisher.stop();
      } catch (_) {}
      for (final server in boundServers) {
        try {
          await server.close(force: true);
        } catch (_) {}
      }
      throw const HostControlException(HostControlErrorCode.transportFailure);
    }
  }

  @override
  Future<void> stop() {
    final existing = _stopOperation;
    if (existing != null) return existing;
    final operation = _stop().whenComplete(() => _stopOperation = null);
    _stopOperation = operation;
    return operation;
  }

  Future<void> _stop() async {
    _accepting = false;
    final connections = _connections.entries.toList();
    for (final entry in connections) {
      try {
        await entry.key.close(WebSocketStatus.goingAway, 'Host stopped');
      } catch (_) {}
      final sessionId = entry.value.authenticatedSessionId;
      if (sessionId != null) {
        await _services?.pairing.closeSession(sessionId);
        final deviceId = entry.value.deviceId;
        if (deviceId != null) {
          await _services?.dispatcher.closeSession(
            authenticatedDeviceId: deviceId,
            sessionId: sessionId,
          );
        }
      }
    }
    _connections.clear();
    _connectionsByAddress.clear();
    _connectionsByDevice.clear();
    _pendingUpgradesByAddress.clear();
    var shutdownFailed = false;
    try {
      await _authorizationChangeSubscription?.cancel();
    } catch (_) {
      shutdownFailed = true;
    }
    _authorizationChangeSubscription = null;
    try {
      await bonjourPublisher.stop();
    } catch (_) {
      shutdownFailed = true;
    }
    for (final server in _servers) {
      try {
        await server.close(force: true);
      } catch (_) {
        shutdownFailed = true;
      }
    }
    _servers.clear();
    _endpoints = const [];
    _services = null;
    if (shutdownFailed) {
      throw const HostControlException(HostControlErrorCode.transportFailure);
    }
  }

  HostWssServices _requireServices() {
    final services = _services;
    if (!_accepting || services == null) {
      throw const HostControlException(
        HostControlErrorCode.pairingAuthenticationRequired,
      );
    }
    return services;
  }

  Future<List<HostWssBindTarget>> _validatedAddresses(
    List<HostWssBindTarget> candidates,
  ) async {
    final result = <String, HostWssBindTarget>{};
    for (final candidate in candidates) {
      final address = candidate.address;
      if (address.type != InternetAddressType.IPv4 ||
          (!address.isLoopback && !_isPrivateIpv4(address))) {
        throw const HostControlException(HostControlErrorCode.transportFailure);
      }
      if (candidate.interfaceIndex < 1) {
        throw const HostControlException(HostControlErrorCode.transportFailure);
      }
      result['${candidate.interfaceIndex}:${address.address}'] = candidate;
      if (result.length > 8) {
        throw const HostControlException(HostControlErrorCode.transportFailure);
      }
    }
    return List.unmodifiable(result.values);
  }

  bool _isPrivateIpv4(InternetAddress address) {
    final bytes = address.rawAddress;
    if (bytes.length != 4) return false;
    final first = bytes[0];
    final second = bytes[1];
    return first == 10 ||
        (first == 172 && second >= 16 && second <= 31) ||
        (first == 192 && second == 168);
  }

  void _handleRequest(HttpRequest request) {
    unawaited(_serveRequest(request));
  }

  Future<void> _serveRequest(HttpRequest request) async {
    final remoteAddress =
        request.connectionInfo?.remoteAddress.address ?? 'unknown';
    if (!_accepting ||
        request.method != 'GET' ||
        request.uri.path != '/host' ||
        request.headers.value('origin') != null ||
        !WebSocketTransformer.isUpgradeRequest(request) ||
        !_hasRequiredSubprotocol(request)) {
      await _respond(request, HttpStatus.forbidden);
      return;
    }
    if (_connections.length +
                _pendingUpgradesByAddress.values.fold<int>(
                  0,
                  (sum, count) => sum + count,
                ) >=
            maxConnections ||
        (_connectionsByAddress[remoteAddress] ?? 0) +
                (_pendingUpgradesByAddress[remoteAddress] ?? 0) >=
            maxConnectionsPerAddress) {
      await _respond(request, HttpStatus.serviceUnavailable);
      return;
    }

    _pendingUpgradesByAddress.update(
      remoteAddress,
      (value) => value + 1,
      ifAbsent: () => 1,
    );
    WebSocket? socket;
    _HostWssConnection? context;
    try {
      socket = await WebSocketTransformer.upgrade(
        request,
        protocolSelector: (protocols) =>
            protocols.contains(hostWssSubprotocol) ? hostWssSubprotocol : '',
        compression: CompressionOptions.compressionOff,
        maxPayloadLength: hostRpcMaxFrameBytes,
      );
      if (!_accepting) {
        await socket.close(WebSocketStatus.goingAway, 'Host stopped');
        return;
      }
      socket.pingInterval = socketPingInterval;
      context = _HostWssConnection(socket, remoteAddress);
      _connections[socket] = context;
      _connectionsByAddress.update(
        remoteAddress,
        (value) => value + 1,
        ifAbsent: () => 1,
      );
      await _serveSocket(context);
    } catch (_) {
      if (socket != null) {
        try {
          await socket.close(WebSocketStatus.internalServerError);
        } catch (_) {}
      } else {
        try {
          request.response.statusCode = HttpStatus.badRequest;
          await request.response.close();
        } catch (_) {}
      }
    } finally {
      _decrement(_pendingUpgradesByAddress, remoteAddress);
      if (socket != null) {
        final context = _connections.remove(socket);
        if (context != null) {
          _decrement(_connectionsByAddress, remoteAddress);
          if (context.deviceSlotReserved && context.deviceId != null) {
            _decrement(_connectionsByDevice, context.deviceId!);
          }
          final sessionId = context.session?.sessionId;
          final authenticatedSessionId = context.authenticatedSessionId;
          if (sessionId != null) {
            await _services?.pairing.closeSession(sessionId);
          }
          if (authenticatedSessionId != null && context.deviceId != null) {
            await _services?.dispatcher.closeSession(
              authenticatedDeviceId: context.deviceId!,
              sessionId: authenticatedSessionId,
            );
          }
        }
      }
    }
  }

  Future<void> _serveSocket(_HostWssConnection context) async {
    final iterator = StreamIterator<Object?>(context.socket);
    try {
      if (!await iterator.moveNext().timeout(handshakeTimeout)) return;
      final first = _decodeRpcRequest(iterator.current);
      if (first.method == 'host.pair.request') {
        await _pairDevice(context.socket, first);
        return;
      }
      if (first.method != 'host.auth.begin') {
        _sendError(context.socket, first.id, HostRpcErrorCode.unauthorized);
        return;
      }

      final requestedDeviceId = first.params['deviceId']! as String;
      if (!HostPairingProtocol.isDeviceId(requestedDeviceId)) {
        _sendError(context.socket, first.id, HostRpcErrorCode.invalidParams);
        return;
      }
      if (!_reserveDeviceConnection(requestedDeviceId)) {
        _sendError(
          context.socket,
          first.id,
          HostRpcErrorCode.resourceLimitExceeded,
        );
        return;
      }
      context
        ..deviceId = requestedDeviceId
        ..deviceSlotReserved = true;

      final challenge = await _beginAuthentication(first);
      _sendSuccess(context.socket, first.id, {
        'hostId': challenge.hostId,
        'deviceId': challenge.deviceId,
        'connectionId': challenge.connectionId,
        'challenge': challenge.challenge,
        'expiresAt': challenge.expiresAt.toUtc().toIso8601String(),
      });

      if (!await iterator.moveNext().timeout(
        _services!.pairing.challengeLifetime,
      )) {
        return;
      }
      final proof = _decodeRpcRequest(iterator.current);
      if (proof.method != 'host.auth.prove' ||
          proof.params['connectionId'] != challenge.connectionId) {
        _sendError(context.socket, proof.id, HostRpcErrorCode.unauthorized);
        return;
      }
      final session = await _completeAuthentication(proof, challenge);
      context
        ..session = session
        ..authenticatedSessionId = session.sessionId;
      _sendSuccess(context.socket, proof.id, {
        'deviceId': session.deviceId,
        'sessionId': session.sessionId,
        'authenticatedAt': session.authenticatedAt.toUtc().toIso8601String(),
      });

      while (await iterator.moveNext()) {
        final frame = iterator.current;
        if (frame is! String) {
          await context.socket.close(
            WebSocketStatus.unsupportedData,
            'Text frames required',
          );
          return;
        }
        await _handleSignedRpc(context, frame);
        if (context.session == null) return;
      }
    } on TimeoutException {
      try {
        await context.socket.close(
          WebSocketStatus.policyViolation,
          'Handshake timed out',
        );
      } catch (_) {}
    } on HostRpcProtocolException catch (error) {
      _sendError(context.socket, error.requestId, error.code);
      try {
        await context.socket.close(
          WebSocketStatus.policyViolation,
          'Invalid Host frame',
        );
      } catch (_) {}
    } on HostPairingException catch (error) {
      _sendError(context.socket, null, _rpcErrorForPairing(error.error));
      try {
        await context.socket.close(
          WebSocketStatus.policyViolation,
          'Host authentication failed',
        );
      } catch (_) {}
    } catch (_) {
      try {
        await context.socket.close(
          WebSocketStatus.internalServerError,
          'Host transport failed',
        );
      } catch (_) {}
    } finally {
      await iterator.cancel();
    }
  }

  Future<void> _pairDevice(WebSocket socket, HostRpcRequest request) async {
    final params = request.params;
    try {
      final pending = await _services!.pairing.submitPairingRequest(
        HostPairingRequest(
          hostId: params['hostId']! as String,
          deviceId: params['deviceId']! as String,
          publicKeySpki: base64Decode(params['publicKeySpki']! as String),
          displayName: params['displayName']! as String,
          platform: params['platform']! as String,
          invitationNonce: params['invitationNonce']! as String,
          timestampSeconds: params['timestampSeconds']! as int,
          signatureDer: base64Decode(params['signatureDer']! as String),
        ),
      );
      _sendSuccess(socket, request.id, {
        'state': 'pendingApproval',
        'deviceId': pending.deviceId,
        'confirmationCode': pending.confirmationCode,
        'expiresAt': pending.expiresAt.toUtc().toIso8601String(),
      });
      await socket.close(WebSocketStatus.normalClosure, 'Approval pending');
    } on FormatException {
      _sendError(socket, request.id, HostRpcErrorCode.invalidParams);
      await socket.close(WebSocketStatus.policyViolation, 'Invalid pairing');
    } on HostPairingException catch (error) {
      _sendError(socket, request.id, _rpcErrorForPairing(error.error));
      await socket.close(WebSocketStatus.policyViolation, 'Pairing rejected');
    }
  }

  Future<HostAuthenticationChallenge> _beginAuthentication(
    HostRpcRequest request,
  ) => _services!.pairing.issueChallenge(request.params['deviceId']! as String);

  Future<HostAuthenticatedSession> _completeAuthentication(
    HostRpcRequest request,
    HostAuthenticationChallenge challenge,
  ) => _services!.pairing.completeChallenge(
    connectionId: challenge.connectionId,
    signatureDer: base64Decode(request.params['signatureDer']! as String),
  );

  Future<void> _handleSignedRpc(
    _HostWssConnection context,
    String frame,
  ) async {
    HostRpcRequest? rpcRequest;
    try {
      final envelopeJson = HostRpcCodec.decodeStrictObject(frame, const {
        'hostId',
        'deviceId',
        'sessionId',
        'timestampSeconds',
        'nonce',
        'payload',
        'signatureDer',
      });
      if (envelopeJson['hostId'] is! String ||
          envelopeJson['deviceId'] is! String ||
          envelopeJson['sessionId'] is! String ||
          envelopeJson['timestampSeconds'] is! int ||
          envelopeJson['nonce'] is! String ||
          envelopeJson['payload'] is! String ||
          envelopeJson['signatureDer'] is! String) {
        throw const HostRpcProtocolException(HostRpcErrorCode.invalidRequest);
      }
      final envelope = HostSignedRpcEnvelope(
        hostId: envelopeJson['hostId']! as String,
        deviceId: envelopeJson['deviceId']! as String,
        sessionId: envelopeJson['sessionId']! as String,
        timestampSeconds: envelopeJson['timestampSeconds']! as int,
        nonce: envelopeJson['nonce']! as String,
        payload: envelopeJson['payload']! as String,
        signatureDer: base64Decode(envelopeJson['signatureDer']! as String),
      );
      final authenticated = await _services!.pairing.authenticateRequest(
        envelope,
      );
      rpcRequest = HostRpcCodec.decodeRequest(authenticated.payload);
      final allowed = await _services!.pairing.isAuthorized(
        deviceId: authenticated.deviceId,
        method: rpcRequest.method,
        params: Map.unmodifiable(
          Map<String, Object?>.of(rpcRequest.params)..remove('secretValues'),
        ),
      );
      if (!allowed) {
        _sendError(
          context.socket,
          rpcRequest.id,
          HostRpcErrorCode.unauthorized,
        );
        return;
      }
      if (rpcRequest.method == 'host.hello') {
        _sendSuccess(context.socket, rpcRequest.id, {
          'protocolVersion': hostProtocolVersion,
          'hostId': _services!.identity.hostId,
          'certificateSha256': _services!.identity.certificateSha256,
        });
        return;
      }
      if (rpcRequest.method == 'host.status') {
        _sendSuccess(context.socket, rpcRequest.id, {
          'hostId': _services!.identity.hostId,
          'phase': 'running',
          'endpoints': [for (final endpoint in _endpoints) endpoint.toJson()],
        });
        return;
      }
      final response = await _services!.dispatcher.dispatch(
        authenticated.payload,
        authenticatedDeviceId: authenticated.deviceId,
        sessionId: context.authenticatedSessionId,
        notify: (notification) {
          try {
            context.socket.add(HostRpcCodec.encodeFrame(notification));
          } catch (_) {
            unawaited(
              context.socket.close(
                WebSocketStatus.messageTooBig,
                'Host event too large',
              ),
            );
          }
        },
      );
      context.socket.add(
        response ??
            HostRpcCodec.encodeError(
              rpcRequest.id,
              HostRpcErrorCode.methodNotFound,
            ),
      );
    } on HostRpcProtocolException catch (error) {
      _sendError(context.socket, error.requestId ?? rpcRequest?.id, error.code);
    } on HostPairingException catch (error) {
      _sendError(
        context.socket,
        rpcRequest?.id,
        _rpcErrorForPairing(error.error),
      );
      if (error.error == HostPairingError.unauthorized ||
          error.error == HostPairingError.replayedRequest ||
          error.error == HostPairingError.expiredSession ||
          error.error == HostPairingError.resourceLimitExceeded) {
        final sessionId = context.session?.sessionId;
        if (sessionId != null) {
          await _services?.pairing.closeSession(sessionId);
        }
        context.session = null;
        try {
          await context.socket.close(
            WebSocketStatus.policyViolation,
            'Host authentication failed',
          );
        } catch (_) {}
      }
    } on FormatException {
      _sendError(
        context.socket,
        rpcRequest?.id,
        HostRpcErrorCode.invalidParams,
      );
    } catch (_) {
      _sendError(
        context.socket,
        rpcRequest?.id,
        HostRpcErrorCode.internalError,
      );
    }
  }

  bool _hasRequiredSubprotocol(HttpRequest request) =>
      request.headers
          .value('sec-websocket-protocol')
          ?.split(',')
          .map((value) => value.trim())
          .contains(hostWssSubprotocol) ??
      false;

  HostRpcRequest _decodeRpcRequest(Object? value) {
    if (value is! String) {
      throw const HostRpcProtocolException(HostRpcErrorCode.invalidRequest);
    }
    return HostRpcCodec.decodeRequest(value);
  }

  void _sendSuccess(WebSocket socket, String id, Object? result) =>
      socket.add(HostRpcCodec.encodeSuccess(id, result));

  void _sendError(WebSocket socket, String? id, HostRpcErrorCode code) =>
      socket.add(HostRpcCodec.encodeError(id, code));

  Future<void> _respond(HttpRequest request, int status) async {
    try {
      request.response.statusCode = status;
      await request.response.close();
    } catch (_) {}
  }

  void _disconnectDevice(String deviceId) {
    unawaited(_services?.dispatcher.revokeDevice(deviceId));
    for (final entry in _connections.entries.toList()) {
      if (entry.value.deviceId != deviceId) continue;
      entry.value.session = null;
      unawaited(
        entry.key.close(
          WebSocketStatus.policyViolation,
          'Authorization changed; reconnect',
        ),
      );
    }
  }

  HostRpcErrorCode _rpcErrorForPairing(
    HostPairingError error,
  ) => switch (error) {
    HostPairingError.invalidRequest => HostRpcErrorCode.invalidParams,
    HostPairingError.invitationExpired =>
      HostRpcErrorCode.pairingInvitationExpired,
    HostPairingError.invalidProof ||
    HostPairingError.notPaired ||
    HostPairingError.unauthorized => HostRpcErrorCode.unauthorized,
    HostPairingError.approvalRequired =>
      HostRpcErrorCode.pairingApprovalRequired,
    HostPairingError.alreadyPaired => HostRpcErrorCode.deviceAlreadyPaired,
    HostPairingError.replayedRequest => HostRpcErrorCode.replayedRequest,
    HostPairingError.expiredSession => HostRpcErrorCode.expiredSession,
    HostPairingError.resourceLimitExceeded =>
      HostRpcErrorCode.resourceLimitExceeded,
    HostPairingError.storageFailure => HostRpcErrorCode.pairingStorageFailure,
    HostPairingError.revocationCleanupFailed => HostRpcErrorCode.internalError,
  };

  void _decrement(Map<String, int> values, String key) {
    final count = values[key];
    if (count == null || count <= 1) {
      values.remove(key);
    } else {
      values[key] = count - 1;
    }
  }

  bool _reserveDeviceConnection(String deviceId) {
    final count = _connectionsByDevice[deviceId] ?? 0;
    if (count >= maxConnectionsPerDevice) return false;
    _connectionsByDevice[deviceId] = count + 1;
    return true;
  }
}

final class _HostWssConnection {
  _HostWssConnection(this.socket, this.remoteAddress);

  final WebSocket socket;
  final String remoteAddress;
  String? deviceId;
  bool deviceSlotReserved = false;
  HostAuthenticatedSession? session;
  String? authenticatedSessionId;
}
