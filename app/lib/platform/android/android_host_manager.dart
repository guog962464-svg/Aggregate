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

final class AndroidHostStatusChange {
  const AndroidHostStatusChange(this.hostId, this.status);

  final String hostId;
  final AndroidHostStatus status;
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
  }) : pairingClient =
           pairingClient ??
           AndroidHostPairingClient(
             identity: const AndroidHostDeviceIdentity(),
           ),
       discovery = discovery ?? const MethodChannelAndroidHostDiscovery(),
       now = now ?? DateTime.now;

  final AndroidRuntimeStore _store;
  final AndroidHostPairingClient pairingClient;
  final AndroidHostDiscoveryPort discovery;
  final DateTime Function() now;
  final Map<String, AndroidPairedHost> _hosts = {};
  final Map<String, AndroidHostAuthenticatedSession> _sessions = {};
  final Map<String, StreamSubscription<Map<String, Object?>>> _sessionWatches =
      {};
  final Map<String, AndroidHostStatus> _statuses = {};
  final _statusChanges = StreamController<AndroidHostStatusChange>.broadcast(
    sync: true,
  );
  final List<String> notices = [];
  Future<void> _tail = Future<void>.value();

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
      await _installSession(host, session);
      return host;
    } on Object catch (error) {
      _setStatus(invitation.hostId, _statusForFailure(error));
      rethrow;
    }
  }

  @override
  Future<AndroidPairedHost> connect(String hostId) async {
    final host = _hosts[hostId];
    if (host == null) {
      throw const AndroidHostPairingException(
        AndroidHostPairingFailure.invalidInvitation,
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
      await _installSession(connected, session);
      return connected;
    } on Object catch (error) {
      _setStatus(hostId, _statusForFailure(error));
      rethrow;
    }
  }

  Future<void> _installSession(
    AndroidPairedHost host,
    AndroidHostAuthenticatedSession session,
  ) => _mutate(() async {
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
    final previousSession = _sessions[host.hostId];
    await _sessionWatches.remove(host.hostId)?.cancel();
    _sessions[host.hostId] = session;
    _setStatus(host.hostId, AndroidHostStatus.online);
    _sessionWatches[host.hostId] = session.notifications.listen(
      (_) {},
      onDone: () {
        if (identical(_sessions[host.hostId], session)) {
          _setStatus(host.hostId, AndroidHostStatus.offline);
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
    await _sessionWatches.remove(hostId)?.cancel();
    final session = _sessions.remove(hostId);
    await session?.close();
    _setStatus(hostId, AndroidHostStatus.offline);
  }

  @override
  Future<void> remove(String hostId) => _mutate(() async {
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
