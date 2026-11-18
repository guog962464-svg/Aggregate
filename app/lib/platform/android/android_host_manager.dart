import 'dart:async';

import 'android_host_device_identity.dart';
import 'android_host_discovery.dart';
import 'android_host_pairing_client.dart';
import 'android_runtime_store.dart';

enum AndroidHostStatus {
  offline,
  connecting,
  online,
  authenticationInvalid,
  versionIncompatible,
  permissionDenied,
  timedOut,
  outcomeUnknown,
}

const _defaultReconnectDelays = [
  Duration(seconds: 1),
  Duration(seconds: 2),
  Duration(seconds: 4),
  Duration(seconds: 8),
  Duration(seconds: 16),
];

final class AndroidHostStatusChange {
  const AndroidHostStatusChange(this.hostId, this.status);

  final String hostId;
  final AndroidHostStatus status;
}

final class AndroidHostIdentityRotationResult {
  const AndroidHostIdentityRotationResult({
    required this.deviceId,
    required this.localHostRecordsCleared,
  });

  final String deviceId;
  final bool localHostRecordsCleared;
}

abstract interface class AndroidHostManagerPort {
  List<AndroidPairedHost> get hosts;
  bool isConnected(String hostId);
  AndroidHostStatus statusFor(String hostId);
  Stream<AndroidHostStatusChange> get statusChanges;
  Future<Map<String, Object?>> call(
    String hostId,
    String method,
    Map<String, Object?> params, {
    bool sideEffect = false,
  });
  Stream<Map<String, Object?>> watchNotifications(String hostId);

  Future<AndroidHostPairingReceipt> requestPairing({
    required AndroidHostInvitation invitation,
    required String displayName,
  });

  Future<AndroidPairedHost> completePairing({
    required AndroidHostInvitation invitation,
    required String displayName,
  });

  Future<AndroidPairedHost> connect(String hostId);
  Future<void> disconnect(String hostId);
  Future<void> remove(String hostId);
  Future<AndroidHostIdentityRotationResult> rotateDeviceIdentity();
  Future<void> dispose();
}

final class AndroidPairedHost {
  AndroidPairedHost({
    required this.hostId,
    required this.displayName,
    required this.certificateSha256,
    required List<AndroidHostEndpoint> endpoints,
    required this.pairedAt,
    required this.lastConnectedAt,
  }) : endpoints = List.unmodifiable(endpoints);

  final String hostId;
  final String displayName;
  final String certificateSha256;
  final List<AndroidHostEndpoint> endpoints;
  final DateTime pairedAt;
  final DateTime? lastConnectedAt;

  AndroidHostTarget get target => AndroidHostTarget(
    hostId: hostId,
    certificateSha256: certificateSha256,
    endpoints: endpoints,
  );

  AndroidPairedHost withLastConnectedAt(DateTime value) => AndroidPairedHost(
    hostId: hostId,
    displayName: displayName,
    certificateSha256: certificateSha256,
    endpoints: endpoints,
    pairedAt: pairedAt,
    lastConnectedAt: value,
  );

  AndroidPairedHost withConnection({
    required List<AndroidHostEndpoint> endpoints,
    required DateTime lastConnectedAt,
  }) => AndroidPairedHost(
    hostId: hostId,
    displayName: displayName,
    certificateSha256: certificateSha256,
    endpoints: endpoints,
    pairedAt: pairedAt,
    lastConnectedAt: lastConnectedAt,
  );

  Map<String, Object?> toJson() => {
    'hostId': hostId,
    'displayName': displayName,
    'certificateSha256': certificateSha256,
    'endpoints': endpoints.map((endpoint) => endpoint.toJson()).toList(),
    'pairedAt': pairedAt.toUtc().toIso8601String(),
    'lastConnectedAt': lastConnectedAt?.toUtc().toIso8601String(),
  };

  factory AndroidPairedHost.fromJson(Object? value) {
    if (value is! Map || value.keys.any((key) => key is! String)) {
      throw const FormatException('Mac Host 记录无效');
    }
    final json = value.cast<String, Object?>();
    const keys = {
      'hostId',
      'displayName',
      'certificateSha256',
      'endpoints',
      'pairedAt',
      'lastConnectedAt',
    };
    if (json.keys.toSet().difference(keys).isNotEmpty ||
        keys.difference(json.keys.toSet()).isNotEmpty ||
        json['hostId'] is! String ||
        json['displayName'] is! String ||
        json['certificateSha256'] is! String ||
        json['endpoints'] is! List ||
        json['pairedAt'] is! String ||
        (json['lastConnectedAt'] != null &&
            json['lastConnectedAt'] is! String)) {
      throw const FormatException('Mac Host 记录无效');
    }
    final endpoints = <AndroidHostEndpoint>[];
    for (final item in json['endpoints']! as List) {
      if (item is! String) throw const FormatException('Mac Host 地址无效');
      final uri = Uri.tryParse(item);
      if (uri == null) throw const FormatException('Mac Host 地址无效');
      endpoints.add(AndroidHostEndpoint(uri));
    }
    final pairedAt = DateTime.tryParse(json['pairedAt']! as String);
    final lastConnectedAt = json['lastConnectedAt'] == null
        ? null
        : DateTime.tryParse(json['lastConnectedAt']! as String);
    if (pairedAt == null ||
        (json['lastConnectedAt'] != null && lastConnectedAt == null)) {
      throw const FormatException('Mac Host 时间字段无效');
    }
    final host = AndroidPairedHost(
      hostId: json['hostId']! as String,
      displayName: json['displayName']! as String,
      certificateSha256: json['certificateSha256']! as String,
      endpoints: endpoints,
      pairedAt: pairedAt.toUtc(),
      lastConnectedAt: lastConnectedAt?.toUtc(),
    );
    host.target.validate();
    if (host.displayName.trim().isEmpty || host.displayName.length > 80) {
      throw const FormatException('Mac Host 名称无效');
    }
    if (RegExp(r'[\x00-\x1f\x7f]').hasMatch(host.displayName)) {
      throw const FormatException('Mac Host 名称无效');
    }
    return host;
  }
}

/// Stores only public Host metadata. The Android signing key remains in the
/// platform Keystore behind [AndroidHostDeviceIdentity].
final class AndroidHostManager implements AndroidHostManagerPort {
  AndroidHostManager(
    this._store, {
    AndroidHostPairingClient? pairingClient,
    AndroidHostDiscoveryPort? discovery,
    DateTime Function()? now,
    List<Duration> reconnectDelays = _defaultReconnectDelays,
  }) : pairingClient =
           pairingClient ??
           AndroidHostPairingClient(
             identity: const AndroidHostDeviceIdentity(),
           ),
       discovery = discovery ?? const MethodChannelAndroidHostDiscovery(),
       now = now ?? DateTime.now,
       reconnectDelays = List.unmodifiable(reconnectDelays) {
    if (this.reconnectDelays.length > 8 ||
        this.reconnectDelays.any((delay) => delay.isNegative)) {
      throw ArgumentError.value(
        reconnectDelays,
        'reconnectDelays',
        'must contain at most eight nonnegative delays',
      );
    }
  }

  final AndroidRuntimeStore _store;
  final AndroidHostPairingClient pairingClient;
  final AndroidHostDiscoveryPort discovery;
  final DateTime Function() now;
  final List<Duration> reconnectDelays;
  final Map<String, AndroidPairedHost> _hosts = {};
  final Map<String, AndroidHostAuthenticatedSession> _sessions = {};
  final Map<String, StreamSubscription<Map<String, Object?>>> _sessionWatches =
      {};
  final Map<String, Timer> _reconnectTimers = {};
  final Map<String, Timer> _stableSessionTimers = {};
  final Map<String, int> _reconnectAttempts = {};
  final Map<String, int> _connectionGenerations = {};
  final Map<String, AndroidHostStatus> _statuses = {};
  final _statusChanges = StreamController<AndroidHostStatusChange>.broadcast(
    sync: true,
  );
  final List<String> notices = [];
  Future<void> _tail = Future<void>.value();
  var _disposed = false;

  Future<T> _mutate<T>(Future<T> Function() action) async {
    final previous = _tail;
    final done = Completer<void>();
    _tail = done.future;
    await previous;
    try {
      return await action();
    } finally {
      done.complete();
    }
  }

  @override
  List<AndroidPairedHost> get hosts => List.unmodifiable(
    _hosts.values.toList()..sort(
      (left, right) => left.displayName.toLowerCase().compareTo(
        right.displayName.toLowerCase(),
      ),
    ),
  );

  @override
  bool isConnected(String hostId) => _sessions[hostId]?.isOpen ?? false;

  @override
  AndroidHostStatus statusFor(String hostId) {
    final status = _statuses[hostId] ?? AndroidHostStatus.offline;
    if (status == AndroidHostStatus.online && !isConnected(hostId)) {
      return AndroidHostStatus.offline;
    }
    return status;
  }

  @override
  Stream<AndroidHostStatusChange> get statusChanges => _statusChanges.stream;

  Future<void> load() async {
    try {
      final raw = await _store.read('hosts');
      if (raw == null) return;
      if (raw is! Map || raw.keys.any((key) => key is! String)) {
        throw const FormatException('Mac Host 注册表无效');
      }
      final json = raw.cast<String, Object?>();
      if (json.length != 2 ||
          json['schemaVersion'] != 1 ||
          json['hosts'] is! List) {
        throw const FormatException('Mac Host 注册表版本无效');
      }
      final loaded = <String, AndroidPairedHost>{};
      for (final value in json['hosts']! as List) {
        final host = AndroidPairedHost.fromJson(value);
        if (loaded.length >= 128 || loaded.containsKey(host.hostId)) {
          throw const FormatException('Mac Host 数量或标识无效');
        }
        loaded[host.hostId] = host;
      }
      _hosts
        ..clear()
        ..addAll(loaded);
    } on Object {
      try {
        await _store.backupDamaged('hosts');
      } on Object {
        // Keep startup available even when the backup cannot be written.
      }
      _hosts.clear();
      notices.add('Mac Host 配对列表无法读取，已备份原文件。');
    }
  }

  @override
  Future<AndroidHostPairingReceipt> requestPairing({
    required AndroidHostInvitation invitation,
    required String displayName,
  }) => pairingClient.requestPairing(
    invitation: invitation,
    displayName: displayName,
  );

  @override
  Future<AndroidPairedHost> completePairing({
    required AndroidHostInvitation invitation,
    required String displayName,
  }) async {
    _validateDisplayName(displayName);
    _cancelReconnect(hostId: invitation.hostId, resetAttempts: true);
    final generation = _advanceConnectionGeneration(invitation.hostId);
    _setStatus(invitation.hostId, AndroidHostStatus.connecting);
    try {
      final session = await pairingClient.authenticate(
        AndroidHostTarget.fromInvitation(invitation),
      );
      final previous = _hosts[invitation.hostId];
      final host = AndroidPairedHost(
        hostId: invitation.hostId,
        displayName: displayName.trim(),
        certificateSha256: invitation.certificateSha256,
        endpoints: invitation.endpoints,
        pairedAt: previous?.pairedAt ?? now().toUtc(),
        lastConnectedAt: now().toUtc(),
      );
      await _installSession(host, session, generation: generation);
      return host;
    } on Object catch (error) {
      if (_isGenerationCurrent(invitation.hostId, generation)) {
        _setStatus(invitation.hostId, _statusForFailure(error));
      }
      rethrow;
    }
  }

  @override
  Future<AndroidPairedHost> connect(String hostId) async {
    _cancelReconnect(hostId: hostId, resetAttempts: true);
    final generation = _advanceConnectionGeneration(hostId);
    try {
      return await _connectHost(hostId, generation: generation);
    } on Object catch (error) {
      if (_isGenerationCurrent(hostId, generation) &&
          _isTransientReconnectFailure(error)) {
        _scheduleReconnect(hostId);
      }
      rethrow;
    }
  }

  Future<AndroidPairedHost> _connectHost(
    String hostId, {
    required int generation,
  }) async {
    final host = _hosts[hostId];
    if (host == null) {
      throw const AndroidHostPairingException(
        AndroidHostPairingFailure.invalidInvitation,
      );
    }
    if (!_isGenerationCurrent(hostId, generation)) {
      throw const AndroidHostPairingException(
        AndroidHostPairingFailure.transportClosed,
      );
    }
    _setStatus(hostId, AndroidHostStatus.connecting);
    try {
      final discoveredEndpoints = await discovery.discover(hostId);
      final target = AndroidHostTarget(
        hostId: host.hostId,
        certificateSha256: host.certificateSha256,
        endpoints: discoveredEndpoints.isEmpty
            ? host.endpoints
            : discoveredEndpoints,
      );
      final session = await pairingClient.authenticate(target);
      final connected = host.withConnection(
        endpoints: target.endpoints,
        lastConnectedAt: now().toUtc(),
      );
      await _installSession(connected, session, generation: generation);
      return connected;
    } on Object catch (error) {
      if (_isGenerationCurrent(hostId, generation)) {
        _setStatus(hostId, _statusForFailure(error));
      }
      rethrow;
    }
  }

  Future<void> _installSession(
    AndroidPairedHost host,
    AndroidHostAuthenticatedSession session, {
    required int generation,
  }) => _mutate(() async {
    if (!_isGenerationCurrent(host.hostId, generation)) {
      await session.close();
      throw const AndroidHostPairingException(
        AndroidHostPairingFailure.transportClosed,
      );
    }
    if (!_hosts.containsKey(host.hostId) && _hosts.length >= 128) {
      await session.close();
      throw const AndroidHostPairingException(
        AndroidHostPairingFailure.storageFailure,
      );
    }
    final existing = _hosts[host.hostId];
    _hosts[host.hostId] = host;
    try {
      await _persist();
    } on Object {
      if (existing == null) {
        _hosts.remove(host.hostId);
      } else {
        _hosts[host.hostId] = existing;
      }
      await session.close();
      throw const AndroidHostPairingException(
        AndroidHostPairingFailure.storageFailure,
      );
    }
    if (!_isGenerationCurrent(host.hostId, generation)) {
      await session.close();
      throw const AndroidHostPairingException(
        AndroidHostPairingFailure.transportClosed,
      );
    }
    final previousSession = _sessions[host.hostId];
    await _sessionWatches.remove(host.hostId)?.cancel();
    _reconnectTimers.remove(host.hostId)?.cancel();
    _sessions[host.hostId] = session;
    _setStatus(host.hostId, AndroidHostStatus.online);
    _scheduleStableRetryReset(host.hostId, session);
    _sessionWatches[host.hostId] = session.notifications.listen(
      (_) {},
      onDone: () {
        if (identical(_sessions[host.hostId], session)) {
          _sessions.remove(host.hostId);
          _sessionWatches.remove(host.hostId);
          _stableSessionTimers.remove(host.hostId)?.cancel();
          _setStatus(host.hostId, AndroidHostStatus.offline);
          _scheduleReconnect(host.hostId);
        }
      },
    );
    await previousSession?.close();
  });

  @override
  Future<Map<String, Object?>> call(
    String hostId,
    String method,
    Map<String, Object?> params, {
    bool sideEffect = false,
  }) async {
    final session = _sessions[hostId];
    if (session == null || !session.isOpen) {
      _setStatus(hostId, AndroidHostStatus.offline);
      throw const AndroidHostPairingException(
        AndroidHostPairingFailure.transportClosed,
      );
    }
    try {
      final result = await session.call(method, params);
      _markRpcSuccess(hostId);
      return result;
    } on AndroidHostRpcException catch (error) {
      final status = sideEffect && {-32004, -32603}.contains(error.code)
          ? AndroidHostStatus.outcomeUnknown
          : _statusForRpc(error.code);
      _setStatus(hostId, status);
      rethrow;
    } on AndroidHostPairingException catch (error) {
      final status = error.failure == AndroidHostPairingFailure.requestTimedOut
          ? sideEffect
                ? AndroidHostStatus.outcomeUnknown
                : AndroidHostStatus.timedOut
          : _statusForFailure(error);
      _setStatus(hostId, status);
      rethrow;
    }
  }

  @override
  Stream<Map<String, Object?>> watchNotifications(String hostId) {
    final session = _sessions[hostId];
    if (session == null || !session.isOpen) {
      return Stream.error(
        const AndroidHostPairingException(
          AndroidHostPairingFailure.transportClosed,
        ),
      );
    }
    return session.notifications;
  }

  int _advanceConnectionGeneration(String hostId) {
    final generation = (_connectionGenerations[hostId] ?? 0) + 1;
    _connectionGenerations[hostId] = generation;
    return generation;
  }

  bool _isGenerationCurrent(String hostId, int generation) =>
      !_disposed && _connectionGenerations[hostId] == generation;

  void _cancelReconnect({required String hostId, bool resetAttempts = false}) {
    _reconnectTimers.remove(hostId)?.cancel();
    _stableSessionTimers.remove(hostId)?.cancel();
    if (resetAttempts) _reconnectAttempts.remove(hostId);
  }

  void _scheduleStableRetryReset(
    String hostId,
    AndroidHostAuthenticatedSession session,
  ) {
    _stableSessionTimers.remove(hostId)?.cancel();
    late final Timer timer;
    timer = Timer(const Duration(seconds: 30), () {
      if (identical(_stableSessionTimers[hostId], timer)) {
        _stableSessionTimers.remove(hostId);
      }
      if (identical(_sessions[hostId], session) && session.isOpen) {
        _reconnectAttempts.remove(hostId);
      }
    });
    _stableSessionTimers[hostId] = timer;
  }

  void _scheduleReconnect(String hostId) {
    if (_disposed ||
        !_hosts.containsKey(hostId) ||
        _sessions[hostId]?.isOpen == true ||
        _reconnectTimers.containsKey(hostId)) {
      return;
    }
    final attempt = _reconnectAttempts[hostId] ?? 0;
    if (attempt >= reconnectDelays.length) return;
    final generation = _connectionGenerations[hostId] ?? 0;
    _reconnectAttempts[hostId] = attempt + 1;
    late final Timer timer;
    timer = Timer(reconnectDelays[attempt], () {
      if (identical(_reconnectTimers[hostId], timer)) {
        _reconnectTimers.remove(hostId);
      }
      if (!_isGenerationCurrent(hostId, generation) ||
          !_hosts.containsKey(hostId) ||
          _sessions[hostId]?.isOpen == true) {
        return;
      }
      unawaited(_retryReconnect(hostId, generation));
    });
    _reconnectTimers[hostId] = timer;
  }

  Future<void> _retryReconnect(String hostId, int generation) async {
    try {
      await _connectHost(hostId, generation: generation);
    } on Object catch (error) {
      if (!_isGenerationCurrent(hostId, generation) ||
          !_hosts.containsKey(hostId)) {
        return;
      }
      if (_isTransientReconnectFailure(error)) {
        _scheduleReconnect(hostId);
      } else {
        _cancelReconnect(hostId: hostId, resetAttempts: true);
      }
    }
  }

  bool _isTransientReconnectFailure(Object error) =>
      error is AndroidHostPairingException &&
      {
        AndroidHostPairingFailure.hostUnavailable,
        AndroidHostPairingFailure.requestTimedOut,
        AndroidHostPairingFailure.transportClosed,
      }.contains(error.failure);

  void _setStatus(String hostId, AndroidHostStatus status) {
    if (_statuses[hostId] == status) return;
    _statuses[hostId] = status;
    if (!_statusChanges.isClosed) {
      _statusChanges.add(AndroidHostStatusChange(hostId, status));
    }
  }

  void _markRpcSuccess(String hostId) {
    if ({
      AndroidHostStatus.authenticationInvalid,
      AndroidHostStatus.versionIncompatible,
      AndroidHostStatus.outcomeUnknown,
    }.contains(_statuses[hostId])) {
      return;
    }
    _setStatus(hostId, AndroidHostStatus.online);
  }

  AndroidHostStatus _statusForFailure(Object error) {
    if (error is AndroidHostPairingException) {
      return switch (error.failure) {
        AndroidHostPairingFailure.protocolMismatch =>
          AndroidHostStatus.versionIncompatible,
        AndroidHostPairingFailure.requestTimedOut => AndroidHostStatus.timedOut,
        AndroidHostPairingFailure.transportClosed ||
        AndroidHostPairingFailure.hostUnavailable => AndroidHostStatus.offline,
        AndroidHostPairingFailure.invalidDeviceIdentity ||
        AndroidHostPairingFailure.tlsPinMismatch ||
        AndroidHostPairingFailure.invitationExpired ||
        AndroidHostPairingFailure.approvalRequired ||
        AndroidHostPairingFailure.pairingRejected ||
        AndroidHostPairingFailure.alreadyPaired =>
          AndroidHostStatus.authenticationInvalid,
        _ => AndroidHostStatus.offline,
      };
    }
    return AndroidHostStatus.offline;
  }

  AndroidHostStatus _statusForRpc(int? code) => switch (code) {
    -32001 || -32601 => AndroidHostStatus.versionIncompatible,
    -32002 => AndroidHostStatus.permissionDenied,
    -32004 => AndroidHostStatus.outcomeUnknown,
    -32013 ||
    -32010 ||
    -32011 ||
    -32012 ||
    -32015 => AndroidHostStatus.authenticationInvalid,
    _ => AndroidHostStatus.offline,
  };

  @override
  Future<void> disconnect(String hostId) async {
    _cancelReconnect(hostId: hostId, resetAttempts: true);
    _advanceConnectionGeneration(hostId);
    await _sessionWatches.remove(hostId)?.cancel();
    final session = _sessions.remove(hostId);
    await session?.close();
    _setStatus(hostId, AndroidHostStatus.offline);
  }

  @override
  Future<void> remove(String hostId) async {
    _cancelReconnect(hostId: hostId, resetAttempts: true);
    _advanceConnectionGeneration(hostId);
    await _mutate(() async {
      final existing = _hosts.remove(hostId);
      if (existing == null) return;
      try {
        await _persist();
      } on Object {
        _hosts[hostId] = existing;
        throw const AndroidHostPairingException(
          AndroidHostPairingFailure.storageFailure,
        );
      }
      await _sessionWatches.remove(hostId)?.cancel();
      final session = _sessions.remove(hostId);
      await session?.close();
      _setStatus(hostId, AndroidHostStatus.offline);
    });
  }

  @override
  Future<AndroidHostIdentityRotationResult> rotateDeviceIdentity() =>
      _mutate(() async {
        final identity = await pairingClient.rotateDeviceIdentity();
        var localHostRecordsCleared = true;
        try {
          await _store.write('hosts', {
            'schemaVersion': 1,
            'hosts': const <Object?>[],
          });
        } on Object {
          localHostRecordsCleared = false;
        }

        final hostIds = _hosts.keys.toList();
        for (final hostId in hostIds) {
          _cancelReconnect(hostId: hostId, resetAttempts: true);
          _advanceConnectionGeneration(hostId);
        }
        for (final watch in _sessionWatches.values.toList()) {
          try {
            await watch.cancel();
          } on Object {
            // Continue closing all sessions after a failed stream cleanup.
          }
        }
        _sessionWatches.clear();
        for (final session in _sessions.values.toList()) {
          try {
            await session.close();
          } on Object {
            // The identity has changed; no previous session may remain active.
          }
        }
        _sessions.clear();
        _hosts.clear();
        for (final hostId in hostIds) {
          _setStatus(hostId, AndroidHostStatus.offline);
        }
        if (!localHostRecordsCleared) {
          notices.add('手机身份已轮换，但 Host 列表没有写入清理结果；请移除可能重新出现的旧记录。');
        }
        return AndroidHostIdentityRotationResult(
          deviceId: identity.deviceId,
          localHostRecordsCleared: localHostRecordsCleared,
        );
      });

  Future<void> _persist() async {
    try {
      await _store.write('hosts', {
        'schemaVersion': 1,
        'hosts': hosts.map((host) => host.toJson()).toList(),
      });
    } on Object {
      throw const AndroidHostPairingException(
        AndroidHostPairingFailure.storageFailure,
      );
    }
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    for (final hostId in _reconnectTimers.keys.toList()) {
      _cancelReconnect(hostId: hostId, resetAttempts: true);
    }
    for (final timer in _stableSessionTimers.values) {
      timer.cancel();
    }
    _stableSessionTimers.clear();
    await _tail;
    await Future.wait(_sessionWatches.values.map((watch) => watch.cancel()));
    _sessionWatches.clear();
    final sessions = _sessions.values.toList();
    _sessions.clear();
    await Future.wait(sessions.map((session) => session.close()));
    await _statusChanges.close();
    await _store.flush();
  }

  void _validateDisplayName(String displayName) {
    final value = displayName.trim();
    if (value.isEmpty ||
        value.length > 80 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(value)) {
      throw const AndroidHostPairingException(
        AndroidHostPairingFailure.invalidDisplayName,
      );
    }
  }
}
