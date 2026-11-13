import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:mcp_dart/mcp_dart.dart' as mcp;
// The pinned SDK keeps schema validation internal; isolate this in the adapter.
// ignore: implementation_imports
import 'package:mcp_dart/src/shared/json_schema/json_schema_validator.dart';

import 'android_credential_store.dart';
import 'android_host_manager.dart';
import 'android_host_pairing_client.dart';
import 'android_mcp_session.dart';
import 'android_runtime_store.dart';

/// Android runtime combining local HTTP MCP and paired Mac Host execution.
final class AndroidRuntimePort
    with WidgetsBindingObserver
    implements
        RuntimePort,
        ConnectionAccountPort,
        ConnectionSetupPort,
        ConnectionSetupTargetPort,
        RuntimeChangeSource,
        RuntimePresentationPort {
  AndroidRuntimePort._(
    AndroidRuntimeStore store,
    this._credentials,
    this._draftTtl,
    this.hostManager,
  ) : _store = store {
    _hostStatusSubscription = hostManager.statusChanges.listen(
      _onHostStatusChange,
    );
  }

  void _onHostStatusChange(AndroidHostStatusChange change) {
    if (!hostManager.hosts.any((host) => host.hostId == change.hostId)) {
      _closeRemoteTerminalsForHost(change.hostId, 'Mac Host 配对已移除，终端会话已结束。');
      _remoteConnectionsByHost.remove(change.hostId);
      _remoteConnections.removeWhere((_, item) => item.hostId == change.hostId);
      _remoteCapabilities.removeWhere(
        (_, capability) => capability.hostId == change.hostId,
      );
    } else if (!hostManager.isConnected(change.hostId)) {
      _closeRemoteTerminalsForHost(change.hostId, 'Mac Host 连接已断开，终端会话已结束。');
    }
    if (!_changes.isClosed) _changes.add(null);
  }

  static Future<AndroidRuntimePort> open({
    Directory? dataDirectory,
    AndroidCredentialStore? credentialStore,
    AndroidHostManagerPort? hostManager,
    Duration draftTtl = const Duration(minutes: 10),
  }) async {
    WidgetsFlutterBinding.ensureInitialized();
    final directory = dataDirectory ?? await getApplicationSupportDirectory();
    final store = AndroidRuntimeStore(directory);
    final manager = hostManager ?? AndroidHostManager(store);
    final runtime = AndroidRuntimePort._(
      store,
      credentialStore ?? const SecureAndroidCredentialStore(),
      draftTtl,
      manager,
    );
    if (manager case final AndroidHostManager concrete) await concrete.load();
    await runtime._load();
    WidgetsBinding.instance.addObserver(runtime);
    return runtime;
  }

  final AndroidRuntimeStore _store;
  final AndroidCredentialStore _credentials;
  final Duration _draftTtl;
  final AndroidHostManagerPort hostManager;
  final _entries = <String, _AndroidEntry>{};
  final _drafts = <String, _AndroidDraft>{};
  final _savingDrafts = <String>{};
  final _runs = <String, _AndroidRun>{};
  final _activity = <RunSummary>[];
  final _events = StreamController<RunEvent>.broadcast(sync: true);
  final _changes = StreamController<void>.broadcast(sync: true);
  late final StreamSubscription<AndroidHostStatusChange>
  _hostStatusSubscription;
  final _remoteConnections = <String, _AndroidRemoteConnection>{};
  final _remoteConnectionsByHost =
      <String, Map<String, _AndroidRemoteConnection>>{};
  final _remoteCapabilities = <String, _AndroidRemoteCapability>{};
  final _remoteTerminals = <String, _AndroidRemoteTerminal>{};
  final _notices = <String>[];
  UserPreferences _preferences = const UserPreferences();
  int _serial = 0;
  Future<void> _mutationTail = Future<void>.value();

  Future<T> _mutate<T>(Future<T> Function() action) async {
    final previous = _mutationTail;
    final done = Completer<void>();
    _mutationTail = done.future;
    await previous;
    try {
      return await action();
    } finally {
      done.complete();
    }
  }

  Future<void> dispose() async {
    WidgetsBinding.instance.removeObserver(this);
    _clearDrafts();
    await _mutationTail;
    for (final run in _runs.values) {
      await run.remoteNotifications?.cancel();
    }
    for (final terminal in _remoteTerminals.values.toList()) {
      await _closeRemoteTerminal(terminal);
    }
    _remoteTerminals.clear();
    for (final entry in _entries.values) {
      await entry.session?.close();
    }
    await _hostStatusSubscription.cancel();
    await hostManager.dispose();
    await _store.flush();
    await _events.close();
    await _changes.close();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _clearDrafts();
    }
  }

  void _clearDrafts() {
    for (final draft in _drafts.values) {
      draft.discarded = true;
      draft.timer.cancel();
    }
    _drafts.clear();
  }

  Never _unavailable() => throw UnsupportedError('此功能尚未在 Android 上开放');

  @override
  bool get isPreview => false;

  @override
  RuntimeFeatures get features => const RuntimeFeatures(
    connectionKinds: {ConnectionKind.mcpHttp},
    terminal: true,
    localFilePreview: false,
    localFileReveal: false,
  );

  @override
  List<String> get startupNotices => List.unmodifiable(_notices);

  @override
  Stream<void> get changes => _changes.stream;

  @override
  List<ConnectionAdapter> get connectionAdapters => const [
    ConnectionAdapter(
      id: 'mcp-http',
      label: 'HTTP MCP',
      kind: ConnectionKind.mcpHttp,
    ),
  ];

  @override
  Future<List<ConnectionSetupTargetOption>> listSetupTargets() async => [
    const ConnectionSetupTargetOption(
      target: ExecutionTarget.device,
      label: '此 Android 设备',
      detail: '本机 HTTP MCP 连接',
    ),
    for (final host in hostManager.hosts) _hostSetupTargetOption(host),
  ];

  ConnectionSetupTargetOption _hostSetupTargetOption(AndroidPairedHost host) {
    final status = hostManager.statusFor(host.hostId);
    final selectable =
        hostManager.isConnected(host.hostId) &&
        !{
          AndroidHostStatus.authenticationInvalid,
          AndroidHostStatus.versionIncompatible,
          AndroidHostStatus.outcomeUnknown,
        }.contains(status);
    final detail = switch (status) {
      AndroidHostStatus.online => 'Mac Host 在线 · 由 Mac 执行配置检查',
      AndroidHostStatus.connecting => '正在连接 Mac Host',
      AndroidHostStatus.authenticationInvalid => '认证失效 · 请重新连接或配对',
      AndroidHostStatus.versionIncompatible => '版本不兼容 · 请升级两端应用',
      AndroidHostStatus.permissionDenied => '部分 Host 权限受限 · 可尝试仍获准的功能',
      AndroidHostStatus.timedOut => '上次请求超时 · 请重新连接后使用',
      AndroidHostStatus.outcomeUnknown => '上次保存结果未知 · 请先检查 Mac',
      AndroidHostStatus.offline => 'Mac Host 离线 · 请先连接',
    };
    return ConnectionSetupTargetOption(
      target: ExecutionTarget.host(host.hostId),
      label: host.displayName,
      detail: detail,
      selectable: selectable,
    );
  }

  @override
  Future<ConnectionSetupPort> setupForTarget(ExecutionTarget target) async {
    if (target.kind == ExecutionTargetKind.device) return this;
    final hostId = target.hostId!;
    final host = hostManager.hosts
        .where((item) => item.hostId == hostId)
        .firstOrNull;
    if (host == null) throw StateError('配对的 Mac Host 不存在');
    if (!hostManager.isConnected(hostId)) {
      throw StateError(_hostStatusDiagnostic(hostManager.statusFor(hostId)));
    }
    try {
      final response = await hostManager.call(
        hostId,
        'setup.adapters',
        const {},
      );
      final rawAdapters = response['adapters'];
      if (rawAdapters is! List) {
        throw const FormatException('Mac Host 适配器目录无效');
      }
      final adapters = rawAdapters
          .map((raw) => _decodeHostConnectionAdapter(raw, hostId))
          .toList(growable: false);
      if (adapters.isEmpty) throw StateError('Mac Host 没有可用的连接适配器');
      return _AndroidHostConnectionSetupPort(this, host, adapters);
    } on AndroidHostRpcException catch (error) {
      if (error.code == -32002) {
        throw StateError('Mac Host 尚未授权“连接向导”，请在 Mac 上更新此设备的权限。');
      }
      rethrow;
    }
  }

  Future<void> _load() async {
    await _store.directory.create(recursive: true);
    var connectionsValid = true;
    try {
      final preferences = await _store.read('preferences');
      if (preferences != null) {
        _preferences = UserPreferences.fromJson(preferences);
      }
    } on FormatException {
      await _store.backupDamaged('preferences');
      _notices.add('偏好设置无法读取，已恢复默认值。');
    } on TypeError {
      await _store.backupDamaged('preferences');
      _notices.add('偏好设置无法读取，已恢复默认值。');
    }
    try {
      for (final row in await _store.loadConnections()) {
        _validateSpec(row.spec, saved: true);
        _entries[row.id] = _AndroidEntry(row.id, row.spec);
      }
    } on FormatException {
      connectionsValid = false;
      _entries.clear();
      await _store.backupDamaged('connections');
      _notices.add('连接配置无法读取，已备份原文件，请检查数据后重新添加。');
    } on TypeError {
      connectionsValid = false;
      _entries.clear();
      await _store.backupDamaged('connections');
      _notices.add('连接配置无法读取，请检查数据后重新添加。');
    }
    if (connectionsValid) {
      try {
        await _credentials.removeOrphans(_entries.keys.toSet());
      } catch (_) {
        _notices.add('连接凭证清理失败，请检查设备安全存储。');
      }
    }
    try {
      final raw = await _store.read('activity');
      if (raw is List) _activity.addAll(raw.map(RunSummary.fromJson));
    } on FormatException {
      await _store.backupDamaged('activity');
      _notices.add('活动记录无法读取，已备份原文件。');
    } on TypeError {
      await _store.backupDamaged('activity');
      _notices.add('活动记录无法读取。');
    }
    _pruneActivity();
    await Future.wait(_entries.values.map(_refresh));
  }

  @override
  Future<UserPreferences> loadPreferences() async => _preferences;

  @override
  Future<void> savePreferences(UserPreferences preferences) async {
    await _store.write('preferences', preferences.toJson());
    _preferences = preferences;
    _pruneActivity();
    await _persistActivity();
  }

  @override
  Future<void> clearActivity() async {
    await _store.write('activity', const []);
    _activity.clear();
  }

  @override
  Future<List<Connection>> listConnections() async {
    final remoteByHost = await Future.wait(
      hostManager.hosts.map(_loadRemoteConnections),
    );
    return [
      for (final entry in _entries.values) entry.toConnection(),
      for (final hostConnections in remoteByHost)
        for (final remote in hostConnections) remote.connection,
    ];
  }

  @override
  Future<List<Capability>> searchCapabilities(SearchQuery query) async {
    final text = query.text.trim().toLowerCase();
    final results = <Capability>[
      for (final entry in _entries.values)
        if (entry.status == ConnectionStatus.ready)
          for (final capability in entry.capabilities)
            if ((query.kind == null || capability.id.kind == query.kind) &&
                (text.isEmpty ||
                    capability.title.toLowerCase().contains(text) ||
                    capability.description.toLowerCase().contains(text) ||
                    capability.id.name.toLowerCase().contains(text)))
              capability,
    ];
    final remoteByHost = await Future.wait(
      hostManager.hosts
          .where((host) => hostManager.isConnected(host.hostId))
          .map((host) => _searchRemoteCapabilities(host, query)),
    );
    for (final capabilities in remoteByHost) {
      results.addAll(capabilities);
    }
    return results;
  }

  Future<List<_AndroidRemoteConnection>> _loadRemoteConnections(
    AndroidPairedHost host,
  ) async {
    final cache = _remoteConnectionsByHost[host.hostId];
    if (!hostManager.isConnected(host.hostId)) {
      if (cache == null) return const [];
      final diagnostic = _hostStatusDiagnostic(
        hostManager.statusFor(host.hostId),
      );
      for (final item in cache.values) {
        item.setAvailability(ConnectionStatus.unavailable, diagnostic);
      }
      return cache.values.toList(growable: false);
    }
    try {
      final response = await hostManager.call(
        host.hostId,
        'connection.list',
        const {},
      );
      final rawConnections = response['connections'];
      if (rawConnections is! List) {
        throw const FormatException('Host connection list is invalid');
      }
      final next = <String, _AndroidRemoteConnection>{};
      for (final raw in rawConnections) {
        final remote = Connection.fromJson(raw);
        final mapped = _AndroidRemoteConnection(
          hostId: host.hostId,
          remoteId: remote.id.value,
          connection: _mapRemoteConnection(host, remote),
        );
        next[remote.id.value] = mapped;
        _remoteConnections[mapped.connection.id.value] = mapped;
      }
      if (cache != null) {
        for (final previous in cache.values) {
          if (!next.containsKey(previous.remoteId)) {
            _remoteConnections.remove(previous.connection.id.value);
            _remoteCapabilities.removeWhere(
              (_, capability) =>
                  capability.hostId == host.hostId &&
                  capability.remoteId.connection.value == previous.remoteId,
            );
          }
        }
      }
      _remoteConnectionsByHost[host.hostId] = next;
      return next.values.toList(growable: false);
    } on Object {
      if (cache == null) return const [];
      final diagnostic = _hostStatusDiagnostic(
        hostManager.statusFor(host.hostId),
      );
      for (final item in cache.values) {
        item.setAvailability(ConnectionStatus.unavailable, diagnostic);
      }
      return cache.values.toList(growable: false);
    }
  }

  Connection _mapRemoteConnection(AndroidPairedHost host, Connection remote) =>
      Connection(
        id: ConnectionId(_remoteConnectionKey(host.hostId, remote.id.value)),
        kind: remote.kind,
        label: remote.label,
        location: remote.location,
        executionTarget: ExecutionTarget.host(host.hostId),
        status: remote.status,
        protocolVersion: remote.protocolVersion,
        diagnostic: remote.diagnostic,
      );

  Connection _acceptHostSetupResult(
    AndroidPairedHost host,
    ConnectionAdapter adapter,
    Map<String, Object?> result,
  ) {
    final remoteId = result['connectionId'];
    final label = result['label'];
    final kindName = result['kind'];
    final statusName = result['status'];
    if (remoteId is! String ||
        !RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$').hasMatch(remoteId) ||
        label is! String ||
        label.trim().isEmpty ||
        label.length > 100 ||
        kindName != adapter.kind.name ||
        statusName is! String) {
      throw const FormatException('Mac Host 保存连接结果无效');
    }
    final status = ConnectionStatus.values
        .where((value) => value.name == statusName)
        .firstOrNull;
    if (status == null) throw const FormatException('Mac Host 连接状态无效');
    final remote = _AndroidRemoteConnection(
      hostId: host.hostId,
      remoteId: remoteId,
      connection: Connection(
        id: ConnectionId(_remoteConnectionKey(host.hostId, remoteId)),
        kind: adapter.kind,
        label: label,
        location: 'Mac Host',
        executionTarget: ExecutionTarget.host(host.hostId),
        status: status,
      ),
    );
    _remoteConnections[remote.connection.id.value] = remote;
    _remoteConnectionsByHost.putIfAbsent(host.hostId, () => {})[remoteId] =
        remote;
    if (!_changes.isClosed) _changes.add(null);
    return remote.connection;
  }

  String _remoteConnectionKey(String hostId, String connectionId) =>
      'remote:$hostId:$connectionId';

  @override
  String? connectionDisplayName(ConnectionId connection) =>
      _remoteConnections[connection.value]?.connection.label ??
      _entries[connection.value]?.spec.label ??
      (connection.value.startsWith('remote:') ? 'Mac Host' : null);

  @override
  String? capabilityDisplayName(CapabilityId capability) {
    final remote = _remoteCapabilities[capability.key];
    if (remote != null) return remote.capability.title;
    if (capability.connection.value.startsWith('remote:')) return 'Mac 功能';
    for (final entry in _entries.values) {
      for (final item in entry.capabilities) {
        if (item.id.key == capability.key) return item.title;
      }
    }
    return null;
  }

  Future<List<Capability>> _searchRemoteCapabilities(
    AndroidPairedHost host,
    SearchQuery query,
  ) async {
    await _loadRemoteConnections(host);
    try {
      final response = await hostManager.call(
        host.hostId,
        'capability.search',
        {'query': query.text},
      );
      final rawCapabilities = response['capabilities'];
      if (rawCapabilities is! List) {
        throw const FormatException('Host capability list is invalid');
      }
      final result = <Capability>[];
      for (final raw in rawCapabilities) {
        final remote = Capability.fromJson(raw);
        if (query.kind != null && remote.id.kind != query.kind) continue;
        final connection =
            _remoteConnectionsByHost[host.hostId]?[remote.id.connection.value];
        if (connection == null) continue;
        final visible = Capability(
          id: CapabilityId(
            connection.connection.id,
            remote.id.kind,
            remote.id.name,
          ),
          title: remote.title,
          description: remote.description,
          permission: remote.permission,
          inputSchema: remote.inputSchema,
          presentation: remote.presentation,
        );
        _remoteCapabilities[visible.id.key] = _AndroidRemoteCapability(
          hostId: host.hostId,
          remoteId: remote.id,
          capability: visible,
        );
        result.add(visible);
      }
      return result;
    } on Object {
      return const [];
    }
  }

  String _hostStatusDiagnostic(AndroidHostStatus status) => switch (status) {
    AndroidHostStatus.offline => 'Mac Host 离线，请检查网络并重新连接。',
    AndroidHostStatus.connecting => '正在连接 Mac Host。',
    AndroidHostStatus.online => 'Mac Host 在线。',
    AndroidHostStatus.authenticationInvalid => 'Mac Host 认证失效，请重新连接或配对。',
    AndroidHostStatus.versionIncompatible => 'Mac Host 协议版本不兼容，请升级两端应用。',
    AndroidHostStatus.permissionDenied => 'Mac Host 拒绝了此设备的访问权限。',
    AndroidHostStatus.timedOut => 'Mac Host 请求超时，请检查网络与服务状态。',
    AndroidHostStatus.outcomeUnknown => '远端执行结果未知，请先在 Mac 上确认执行状态。',
  };

  @override
  Future<List<RunSummary>> listRecentRuns() async {
    final summaries = [..._activity];
    final hosts = hostManager.hosts
        .where((host) => hostManager.isConnected(host.hostId))
        .toList(growable: false);
    await Future.wait(
      hosts.map((host) async {
        try {
          await _loadRemoteConnections(host);
          // Host activity contains only opaque capability references. Search
          // first so every displayed item can be mapped back to a visible,
          // source-qualified Android capability ID.
          await _searchRemoteCapabilities(host, const SearchQuery(''));
          final response = await hostManager.call(
            host.hostId,
            'run.listRecent',
            const {'limit': 100},
          );
          final rawRuns = response['runs'];
          if (rawRuns is! List) {
            throw const FormatException('Mac Host activity list is invalid');
          }
          for (final raw in rawRuns) {
            final summary = RunSummary.fromJson(raw);
            final capability = _remoteCapabilities.values
                .where(
                  (item) =>
                      item.hostId == host.hostId &&
                      item.remoteId.key == summary.capability.key,
                )
                .firstOrNull
                ?.capability;
            if (capability == null) continue;
            final runId = RunId(_remoteRunKey(host.hostId, summary.id.value));
            if (summaries.any((item) => item.id.value == runId.value) ||
                _matchesCachedRemoteActivity(summaries, capability, summary)) {
              continue;
            }
            summaries.add(
              RunSummary(
                runId,
                capability.id,
                RunEvent(
                  runId: runId,
                  sequence: summary.latest.sequence,
                  state: summary.latest.state,
                  occurredAt: summary.latest.occurredAt,
                  failure: summary.latest.failure,
                ),
              ),
            );
          }
        } on Object {
          // A Host may deny activity access or disconnect while another
          // source remains usable. Keep its local cache and other Hosts.
        }
      }),
    );
    summaries.sort(
      (a, b) => b.latest.occurredAt.compareTo(a.latest.occurredAt),
    );
    return List.unmodifiable(summaries.take(100));
  }

  String _remoteRunKey(String hostId, String remoteRunId) =>
      'remote-run:$hostId:$remoteRunId';

  bool _matchesCachedRemoteActivity(
    List<RunSummary> cached,
    Capability capability,
    RunSummary remote,
  ) => cached.any(
    (item) =>
        item.capability.connection.value == capability.id.connection.value &&
        item.capability.kind == capability.id.kind &&
        item.latest.sequence == remote.latest.sequence &&
        item.latest.state == remote.latest.state &&
        item.latest.occurredAt.isAtSameMomentAs(remote.latest.occurredAt),
  );

  @override
  Future<Connection> addConnection(ConnectionSpec spec) async {
    final report = await testConnectionSetup(
      ConnectionSetupDraft(adapterId: 'mcp-http', spec: spec),
    );
    if (!report.canSave) throw StateError(report.checks.last.detail);
    return saveConnectionSetup(report.draftId);
  }

  @override
  Future<void> removeConnection(ConnectionId id) async {
    final remote = _remoteConnections[id.value];
    if (remote != null) {
      await hostManager.call(remote.hostId, 'connection.remove', {
        'operationId': _newHostOperationId(),
        'connectionId': remote.remoteId,
      }, sideEffect: true);
      _remoteConnections.remove(id.value);
      _remoteConnectionsByHost[remote.hostId]?.remove(remote.remoteId);
      _remoteCapabilities.removeWhere(
        (_, capability) =>
            capability.hostId == remote.hostId &&
            capability.remoteId.connection.value == remote.remoteId,
      );
      return;
    }
    await _mutate(() async {
      final entry = _entries[id.value];
      if (entry == null) return;
      final token = entry.spec.hasCredential
          ? await _credentials.read(id.value)
          : null;
      if (entry.spec.hasCredential) await _credentials.delete(id.value);
      try {
        await _persistConnections(excluding: id.value);
      } catch (_) {
        if (token != null) await _credentials.write(id.value, token);
        rethrow;
      }
      _entries.remove(id.value);
      final session = entry.session;
      entry.session = null;
      await session?.close();
    });
  }

  @override
  Future<void> moveConnection(ConnectionId id, int offset) async {
    final remote = _remoteConnections[id.value];
    if (remote != null) {
      await hostManager.call(remote.hostId, 'connection.move', {
        'operationId': _newHostOperationId(),
        'connectionId': remote.remoteId,
        'offset': offset.clamp(-1, 1),
      }, sideEffect: true);
      return;
    }
    await _mutate(() async {
      final entries = _entries.values.toList();
      final from = entries.indexWhere((entry) => entry.id == id.value);
      if (from < 0) return;
      final to = (from + offset).clamp(0, entries.length - 1);
      if (from == to) return;
      final item = entries.removeAt(from);
      entries.insert(to, item);
      await _store.saveConnections([
        for (final entry in entries) (id: entry.id, spec: entry.spec),
      ]);
      _entries
        ..clear()
        ..addEntries(entries.map((entry) => MapEntry(entry.id, entry)));
    });
  }

  @override
  Future<Connection> refreshConnection(ConnectionId id) async {
    final remote = _remoteConnections[id.value];
    if (remote != null) {
      final host = hostManager.hosts
          .where((item) => item.hostId == remote.hostId)
          .firstOrNull;
      if (host == null) throw ArgumentError('Mac Host 不存在');
      final response = await hostManager.call(
        remote.hostId,
        'connection.refresh',
        {'operationId': _newHostOperationId(), 'connectionId': remote.remoteId},
      );
      final decoded = Connection.fromJson(response);
      remote.setConnection(_mapRemoteConnection(host, decoded));
      return remote.connection;
    }
    final entry = _entries[id.value];
    if (entry == null) throw ArgumentError('连接不存在');
    await _refresh(entry);
    return entry.toConnection();
  }

  void _validateSpec(ConnectionSpec spec, {bool saved = false}) {
    if (spec.kind != ConnectionKind.mcpHttp ||
        spec.executionTarget.kind != ExecutionTargetKind.device ||
        spec.executable != null ||
        spec.arguments.isNotEmpty ||
        spec.workingDirectory != null ||
        spec.manifestPath != null ||
        spec.profileId != null) {
      throw const FormatException('Android 当前仅支持本机 HTTP MCP 连接');
    }
    if (spec.label.trim().isEmpty || spec.label.length > 100) {
      throw const FormatException('连接名称应为 1–100 个字符');
    }
    if (!saved &&
        spec.hasCredential &&
        (spec.authToken == null || spec.authToken!.isEmpty)) {
      throw const FormatException('新连接需要重新输入 Bearer Token');
    }
    final uri = Uri.tryParse(spec.url ?? '');
    if (uri == null ||
        !uri.hasAuthority ||
        !{'http', 'https'}.contains(uri.scheme) ||
        uri.userInfo.isNotEmpty ||
        uri.fragment.isNotEmpty) {
      throw const FormatException('请输入有效的 HTTP(S) MCP 地址，且不要把凭证写入 URL');
    }
    if (spec.authToken?.trim().isNotEmpty == true &&
        uri.scheme == 'http' &&
        uri.host != 'localhost' &&
        !(InternetAddress.tryParse(uri.host)?.isLoopback ?? false)) {
      throw const FormatException('带凭证的远程 MCP 地址必须使用 HTTPS');
    }
  }

  ConnectionSpec _storedSpec(ConnectionSpec spec) => ConnectionSpec(
    kind: ConnectionKind.mcpHttp,
    label: spec.label.trim(),
    url: spec.url,
    hasCredential: spec.authToken?.isNotEmpty == true || spec.hasCredential,
  );

  String _newId(String prefix) =>
      '$prefix-${DateTime.now().microsecondsSinceEpoch}-${++_serial}';

  void _expireDrafts() {
    final now = DateTime.now();
    _drafts.removeWhere((_, draft) {
      if (!now.isAfter(draft.expiresAt)) return false;
      draft.discarded = true;
      draft.timer.cancel();
      return true;
    });
  }

  @override
  Future<String?> detectExecutable(String adapterId) async => null;

  @override
  Future<ConnectionSetupReport> testConnectionSetup(
    ConnectionSetupDraft draft,
  ) async {
    _expireDrafts();
    final id = _newId('setup');
    if (draft.adapterId != 'mcp-http' || draft.values.isNotEmpty) {
      throw const FormatException('请选择受支持的 HTTP MCP 连接类型');
    }
    try {
      _validateSpec(draft.spec);
      final session = await AndroidMcpSession.connect(
        id,
        Uri.parse(draft.spec.url!),
        draft.spec.authToken,
      );
      await session.close();
      late final _AndroidDraft staged;
      staged = _AndroidDraft(
        draft.spec,
        DateTime.now().add(_draftTtl),
        Timer(_draftTtl, () {
          staged.discarded = true;
          _drafts.remove(id);
        }),
      );
      _drafts[id] = staged;
      return ConnectionSetupReport(
        draftId: id,
        checks: const [
          SetupCheck('连通性', SetupCheckStatus.passed, 'MCP 握手与功能发现成功。'),
        ],
        canSave: true,
      );
    } catch (cause) {
      return ConnectionSetupReport(
        draftId: id,
        checks: [
          SetupCheck('连接测试', SetupCheckStatus.failed, _safeFailure(cause)),
        ],
        canSave: false,
      );
    }
  }

  @override
  Future<Connection> saveConnectionSetup(String draftId) async {
    _expireDrafts();
    final draft = _drafts[draftId];
    if (draft == null) throw StateError('连接测试已过期，请重新测试');
    if (!_savingDrafts.add(draftId)) {
      throw StateError('连接正在保存，请等待当前操作完成');
    }
    try {
      return await _mutate(() async {
        if (!_draftIsCurrent(draftId, draft)) {
          throw StateError('连接测试已取消或过期，请重新测试');
        }
        final id = _newId('android-http');
        final spec = _storedSpec(draft.spec);
        final token = draft.spec.authToken;
        var tokenWritten = false;
        var configWritten = false;
        _AndroidEntry? entry;
        try {
          if (token != null && token.isNotEmpty) {
            await _credentials.write(id, token);
            tokenWritten = true;
          }
          if (!_draftIsCurrent(draftId, draft)) {
            throw StateError('连接测试已取消或过期，请重新测试');
          }
          await _store.saveConnections([
            for (final item in _entries.values) (id: item.id, spec: item.spec),
            (id: id, spec: spec),
          ]);
          configWritten = true;
          entry = _AndroidEntry(id, spec);
          _entries[id] = entry;
          await _refresh(entry);
          if (!_draftIsCurrent(draftId, draft)) {
            throw StateError('连接测试已取消或过期，请重新测试');
          }
          _drafts.remove(draftId)?.timer.cancel();
          return entry.toConnection();
        } catch (_) {
          if (configWritten) {
            _entries.remove(id);
            await _persistConnections();
          }
          final session = entry?.session;
          if (entry != null) entry.session = null;
          await session?.close();
          if (tokenWritten) await _credentials.delete(id);
          rethrow;
        }
      });
    } finally {
      _savingDrafts.remove(draftId);
    }
  }

  bool _draftIsCurrent(String id, _AndroidDraft draft) =>
      identical(_drafts[id], draft) &&
      !draft.discarded &&
      DateTime.now().isBefore(draft.expiresAt);

  @override
  Future<void> discardConnectionSetup(String draftId) async {
    final draft = _drafts.remove(draftId);
    if (draft == null) return;
    draft.discarded = true;
    draft.timer.cancel();
  }

  Future<void> _persistConnections({String? excluding}) =>
      _store.saveConnections([
        for (final entry in _entries.values)
          if (entry.id != excluding) (id: entry.id, spec: entry.spec),
      ]);

  Future<void> _refresh(_AndroidEntry entry) async {
    final previous = entry.session;
    entry.session = null;
    await previous?.close();
    entry.capabilities = const [];
    entry.status = ConnectionStatus.connecting;
    try {
      final token = entry.spec.hasCredential
          ? await _credentials.read(entry.id)
          : null;
      if (entry.spec.hasCredential && (token == null || token.isEmpty)) {
        throw StateError('连接凭证缺失');
      }
      final session = await AndroidMcpSession.connect(
        entry.id,
        Uri.parse(entry.spec.url!),
        token,
      );
      entry.session = session;
      session.client.onclose = () {
        if (!identical(entry.session, session)) return;
        entry.session = null;
        entry.capabilities = const [];
        entry.status = ConnectionStatus.unavailable;
        entry.diagnostic = 'MCP 连接已断开，请检查网络后刷新连接。';
      };
      entry.capabilities = session.capabilities;
      entry.version = session.protocolVersion;
      entry.status = ConnectionStatus.ready;
      entry.diagnostic = null;
    } catch (cause) {
      entry.status = ConnectionStatus.unavailable;
      entry.diagnostic = _safeFailure(cause);
    }
  }

  void _pruneActivity() {
    final cutoff = DateTime.now().toUtc().subtract(
      Duration(days: _preferences.activityRetentionDays),
    );
    _activity.removeWhere((run) => run.latest.occurredAt.isBefore(cutoff));
    if (_activity.length > 100) _activity.removeRange(100, _activity.length);
  }

  Future<void> _persistActivity() => _store.write('activity', [
    for (final summary in _activity) summary.toJson(),
  ]);

  String _safeFailure(Object cause) {
    if (cause is FormatException) {
      const safeMessages = {
        'Android 当前仅支持本机 HTTP MCP 连接',
        '连接名称应为 1–100 个字符',
        '新连接需要重新输入 Bearer Token',
        '请输入有效的 HTTP(S) MCP 地址，且不要把凭证写入 URL',
        '带凭证的远程 MCP 地址必须使用 HTTPS',
      };
      if (safeMessages.contains(cause.message)) return cause.message;
    }
    if (cause is TimeoutException) return '连接超时，请检查网络与服务状态。';
    if (cause is SocketException || cause is HttpException) {
      return '网络或服务连接中断，请检查地址与网络。';
    }
    final text = '$cause'.toLowerCase();
    if (text.contains('401') || text.contains('unauthorized')) {
      return 'MCP 认证失败，请检查 Bearer Token。';
    }
    if (text.contains('403') || text.contains('forbidden')) {
      return 'MCP 服务拒绝访问，请检查账号权限。';
    }
    if (text.contains('连接凭证缺失')) {
      return 'MCP 凭证已丢失，请删除连接后重新添加。';
    }
    return 'MCP 连接失败，请检查地址、协议与服务状态。';
  }

  @override
  Future<JsonMap?> loadActionManifest(ConnectionId id) async => _unavailable();

  @override
  Future<JsonMap> readActionManifestFile(String path) async => _unavailable();

  @override
  Future<void> saveActionManifest(ConnectionId id, JsonMap manifest) async =>
      _unavailable();

  @override
  Future<void> exportActionManifest(
    ConnectionId id,
    JsonMap manifest,
    String path,
  ) async => _unavailable();

  @override
  Future<RunHandle> invoke(
    CapabilityId id,
    JsonMap arguments, {
    bool permissionGranted = false,
  }) async {
    final remote = _remoteCapabilities[id.key];
    if (remote != null) {
      return _startRemoteInvocation(
        id,
        remote,
        arguments,
        permissionGranted: permissionGranted,
      );
    }
    final entry = _entries[id.connection.value];
    if (entry?.session == null) throw StateError('连接不可用，请先刷新');
    final matches = entry!.capabilities.where((item) => item.id.key == id.key);
    if (matches.isEmpty || id.kind != CapabilityKind.mcpTool) {
      throw ArgumentError('工具不存在，请刷新连接');
    }
    final run = _AndroidRun(RunId(_newId('run')), id);
    _runs[run.id.value] = run;
    _emit(run, RunState.created);
    _emit(run, RunState.validating);
    if (matches.single.permission != PermissionLevel.read &&
        !permissionGranted) {
      _emit(
        run,
        RunState.failed,
        failure: const RuntimeFailure(
          RuntimeErrorCode.permissionDenied,
          '需要确认此功能的执行权限',
          phase: 'permission',
        ),
      );
      return RunHandle(run.id);
    }
    try {
      final schema = matches.single.inputSchema;
      if (schema.isNotEmpty) {
        compileJsonSchemaValidator(
          mcp.JsonSchema.fromJson(Map<String, dynamic>.from(schema)),
        )(arguments);
      }
    } catch (_) {
      _emit(
        run,
        RunState.failed,
        failure: const RuntimeFailure(
          RuntimeErrorCode.invalidArguments,
          '参数不符合工具要求，请检查字段与类型',
          phase: 'validation',
        ),
      );
      return RunHandle(run.id);
    }
    _emit(run, RunState.running);
    unawaited(_call(run, entry.session!, arguments));
    return RunHandle(run.id);
  }

  Future<RunHandle> _startRemoteInvocation(
    CapabilityId id,
    _AndroidRemoteCapability remote,
    JsonMap arguments, {
    required bool permissionGranted,
  }) async {
    final run = _AndroidRun(RunId(_newId('run')), id);
    _runs[run.id.value] = run;
    _emit(run, RunState.created);
    _emit(run, RunState.validating);
    if (remote.capability.permission != PermissionLevel.read &&
        !permissionGranted) {
      _emit(
        run,
        RunState.failed,
        failure: const RuntimeFailure(
          RuntimeErrorCode.permissionDenied,
          '需要确认此功能的执行权限',
          phase: 'permission',
        ),
      );
      return RunHandle(run.id);
    }
    try {
      final schema = remote.capability.inputSchema;
      if (schema.isNotEmpty) {
        compileJsonSchemaValidator(
          mcp.JsonSchema.fromJson(Map<String, dynamic>.from(schema)),
        )(arguments);
      }
    } catch (_) {
      _emit(
        run,
        RunState.failed,
        failure: const RuntimeFailure(
          RuntimeErrorCode.invalidArguments,
          '参数不符合工具要求，请检查字段与类型',
          phase: 'validation',
        ),
      );
      return RunHandle(run.id);
    }
    _emit(run, RunState.running);
    unawaited(_invokeRemote(run, remote, arguments));
    return RunHandle(run.id);
  }

  Future<void> _invokeRemote(
    _AndroidRun run,
    _AndroidRemoteCapability remote,
    JsonMap arguments,
  ) async {
    if (!hostManager.isConnected(remote.hostId)) {
      _emit(
        run,
        RunState.failed,
        failure: RuntimeFailure(
          RuntimeErrorCode.connectionFailed,
          _hostStatusDiagnostic(hostManager.statusFor(remote.hostId)),
          phase: 'remote',
        ),
      );
      return;
    }
    run.remoteHostId = remote.hostId;
    try {
      final response = await hostManager.call(remote.hostId, 'run.invoke', {
        'operationId': _newHostOperationId(),
        'capability': remote.remoteId.toJson(),
        'permissionLevel': remote.capability.permission.name,
        'arguments': arguments,
      }, sideEffect: true);
      final rawRun = response['run'];
      if (rawRun is! Map) {
        _emit(
          run,
          RunState.outcomeUnknown,
          failure: const RuntimeFailure(
            RuntimeErrorCode.outcomeUnknown,
            'Mac Host 未返回运行编号，执行结果未知；请先在 Mac 上确认状态。',
            phase: 'invoke',
          ),
        );
        return;
      }
      final remoteRun = RunHandle.fromJson(rawRun);
      run.remoteHostId = remote.hostId;
      run.remoteRunId = remoteRun.id.value;
      run.remoteNotifications = hostManager
          .watchNotifications(remote.hostId)
          .listen(
            (notification) => _acceptRemoteNotification(run, notification),
            onError: (Object error) =>
                _failRemoteRun(run, error, afterDispatch: true),
            onDone: () {
              if (!run.terminal) {
                _failRemoteRun(
                  run,
                  const AndroidHostPairingException(
                    AndroidHostPairingFailure.transportClosed,
                  ),
                  afterDispatch: true,
                );
              }
            },
          );
      final subscription = await hostManager.call(
        remote.hostId,
        'run.subscribe',
        {'runId': remoteRun.id.value},
      );
      final subscriptionId = subscription['subscriptionId'];
      if (subscriptionId is! String || subscriptionId.isEmpty) {
        throw const FormatException('Mac Host run subscription is invalid');
      }
      if (run.remoteSubscriptionId != null &&
          run.remoteSubscriptionId != subscriptionId) {
        throw const FormatException('Mac Host run subscription did not match');
      }
      run.remoteSubscriptionId = subscriptionId;
      if (run.terminal) await run.remoteNotifications?.cancel();
    } on Object catch (error) {
      _failRemoteRun(run, error, afterDispatch: run.remoteHostId != null);
    }
  }

  void _acceptRemoteNotification(
    _AndroidRun run,
    Map<String, Object?> notification,
  ) {
    if (run.terminal ||
        notification['method'] != 'run.event' ||
        notification['params'] is! Map) {
      return;
    }
    try {
      final params = jsonObject(notification['params'], 'notification.params');
      final event = RunEvent.fromJson(params['event']);
      final notificationSequence = params['sequence'];
      if (event.runId.value != run.remoteRunId ||
          notificationSequence != event.sequence) {
        return;
      }
      final subscriptionId = params['subscriptionId'];
      if (subscriptionId is! String || subscriptionId.isEmpty) return;
      if (run.remoteSubscriptionId != null &&
          run.remoteSubscriptionId != subscriptionId) {
        return;
      }
      run.remoteSubscriptionId ??= subscriptionId;
      if (event.sequence <= (run.remoteSequence ?? -1)) return;
      run.remoteSequence = event.sequence;
      if (event.state == RunState.created ||
          event.state == RunState.validating) {
        return;
      }
      _emit(
        run,
        event.state,
        blocks: event.blocks,
        failure: event.failure,
        occurredAt: event.occurredAt,
      );
      if (run.terminal) unawaited(run.remoteNotifications?.cancel());
    } on Object {
      // Ignore malformed notifications; the authenticated RPC remains open.
    }
  }

  void _failRemoteRun(
    _AndroidRun run,
    Object error, {
    required bool afterDispatch,
  }) {
    if (run.terminal) return;
    final status = hostManager.statusFor(run.remoteHostId ?? '');
    final permissionDenied =
        status == AndroidHostStatus.permissionDenied ||
        error is AndroidHostRpcException && error.code == -32002;
    final unknown =
        afterDispatch &&
        (run.remoteRunId != null ||
            status == AndroidHostStatus.outcomeUnknown ||
            error is AndroidHostPairingException &&
                error.failure == AndroidHostPairingFailure.requestTimedOut ||
            error is AndroidHostRpcException && error.code == -32004 ||
            error is AndroidHostRpcException && error.code == -32603 ||
            error is AndroidHostPairingException &&
                error.failure == AndroidHostPairingFailure.transportClosed);
    if (unknown) {
      _emit(
        run,
        RunState.outcomeUnknown,
        failure: const RuntimeFailure(
          RuntimeErrorCode.outcomeUnknown,
          'Mac Host 连接中断，执行结果未知；请先在 Mac 上确认状态。',
          phase: 'remote',
        ),
      );
    } else {
      _emit(
        run,
        RunState.failed,
        failure: RuntimeFailure(
          permissionDenied
              ? RuntimeErrorCode.permissionDenied
              : error is AndroidHostPairingException &&
                    error.failure == AndroidHostPairingFailure.requestTimedOut
              ? RuntimeErrorCode.timedOut
              : RuntimeErrorCode.connectionFailed,
          permissionDenied
              ? 'Mac Host 拒绝了此设备的访问权限。'
              : _hostStatusDiagnostic(status),
          phase: 'remote',
        ),
      );
    }
    unawaited(run.remoteNotifications?.cancel());
  }

  String _newHostOperationId() =>
      'android-op-${DateTime.now().toUtc().millisecondsSinceEpoch}-${++_serial}';

  Future<void> _call(
    _AndroidRun run,
    AndroidMcpSession session,
    JsonMap arguments,
  ) async {
    try {
      final result = await session.call(run.capability.name, arguments);
      if (run.terminal) return;
      _emit(
        run,
        result.isError ? RunState.failed : RunState.succeeded,
        blocks: result.blocks,
        failure: result.isError
            ? const RuntimeFailure(
                RuntimeErrorCode.protocolError,
                'MCP 工具返回错误',
                phase: 'call',
              )
            : null,
      );
    } on TimeoutException {
      if (!run.terminal) {
        _emit(
          run,
          RunState.outcomeUnknown,
          failure: const RuntimeFailure(
            RuntimeErrorCode.outcomeUnknown,
            '等待 MCP 响应超时，远端是否执行成功尚不确定',
            phase: 'call',
          ),
        );
      }
    } catch (cause) {
      if (!run.terminal) {
        _emit(
          run,
          RunState.outcomeUnknown,
          failure: RuntimeFailure(
            RuntimeErrorCode.outcomeUnknown,
            'MCP 调用中断，结果待确认：${_safeFailure(cause)}',
            phase: 'call',
          ),
        );
      }
      final entry = _entries[run.capability.connection.value];
      if (entry != null && identical(entry.session, session)) {
        entry.session = null;
        entry.capabilities = const [];
        entry.status = ConnectionStatus.unavailable;
        entry.diagnostic = _safeFailure(cause);
        unawaited(session.close());
      }
    }
  }

  void _emit(
    _AndroidRun run,
    RunState state, {
    List<ResultBlock> blocks = const [],
    RuntimeFailure? failure,
    DateTime? occurredAt,
  }) {
    if (run.terminal) return;
    run.state = state;
    final event = RunEvent(
      runId: run.id,
      sequence: run.history.length,
      state: state,
      occurredAt: occurredAt ?? DateTime.now().toUtc(),
      blocks: blocks,
      failure: failure,
    );
    run.history.add(event);
    _events.add(event);
    if (run.terminal) {
      _activity.insert(
        0,
        RunSummary(
          _activityRunId(run),
          run.capability,
          RunEvent(
            runId: _activityRunId(run),
            sequence: event.sequence,
            state: state,
            occurredAt: event.occurredAt,
            failure: failure,
          ),
        ),
      );
      _pruneActivity();
      unawaited(
        _persistActivity().catchError((Object _) {
          _notices.add('活动记录保存失败。');
        }),
      );
    }
  }

  @override
  Stream<RunEvent> watchRun(RunId id) {
    final run = _runs[id.value];
    if (run == null) throw ArgumentError('运行不存在');
    return Stream.multi((controller) {
      final subscription = _events.stream
          .where((event) => event.runId.value == id.value)
          .listen(controller.add);
      for (final event in run.history) {
        controller.add(event);
      }
      controller.onCancel = subscription.cancel;
    });
  }

  @override
  Future<void> cancel(RunId id) async {
    final run = _runs[id.value];
    if (run == null || run.terminal) return;
    if (run.remoteHostId case final hostId?) {
      try {
        final remoteRunId = run.remoteRunId;
        if (remoteRunId == null) {
          _emit(
            run,
            RunState.outcomeUnknown,
            failure: const RuntimeFailure(
              RuntimeErrorCode.outcomeUnknown,
              'Mac Host 尚未确认运行编号，执行结果未知。',
              phase: 'cancel',
            ),
          );
          return;
        }
        await hostManager.call(hostId, 'run.cancel', {
          'operationId': _newHostOperationId(),
          'runId': remoteRunId,
        }, sideEffect: true);
        _emit(
          run,
          RunState.outcomeUnknown,
          failure: const RuntimeFailure(
            RuntimeErrorCode.outcomeUnknown,
            '已向 Mac Host 请求停止；远端最终状态仍需确认。',
            phase: 'cancel',
          ),
        );
      } on Object catch (error) {
        _failRemoteRun(run, error, afterDispatch: true);
      } finally {
        await run.remoteNotifications?.cancel();
      }
      return;
    }
    _emit(
      run,
      RunState.outcomeUnknown,
      failure: const RuntimeFailure(
        RuntimeErrorCode.outcomeUnknown,
        '已停止等待；远端是否执行成功尚不确定',
        phase: 'cancel',
      ),
    );
    final entry = _entries[run.capability.connection.value];
    await entry?.session?.close();
    if (entry != null) {
      entry.session = null;
      entry.status = ConnectionStatus.unavailable;
      entry.capabilities = const [];
    }
  }

  RunId _activityRunId(_AndroidRun run) {
    final hostId = run.remoteHostId;
    final remoteRunId = run.remoteRunId;
    if (hostId == null || remoteRunId == null) return run.id;
    return RunId(_remoteRunKey(hostId, remoteRunId));
  }

  @override
  Future<List<ResultBlock>> readResource(ResourceRef ref) async {
    final remote = _remoteCapabilities[ref.capability.key];
    if (remote != null) {
      final response = await hostManager.call(remote.hostId, 'resource.read', {
        'ref': ResourceRef(
          remote.remoteId,
          Uri.parse(remote.remoteId.name),
        ).toJson(),
      });
      return _resultBlocks(response['blocks']);
    }
    final entry = _entries[ref.capability.connection.value];
    if (entry?.session == null ||
        !entry!.capabilities.any(
          (item) =>
              item.id.key == ref.capability.key &&
              ref.capability.kind == CapabilityKind.mcpResource,
        )) {
      throw StateError('资源连接不可用，请刷新');
    }
    try {
      return await entry.session!.readResource(ref.uri);
    } catch (cause) {
      throw StateError(_safeFailure(cause));
    }
  }

  @override
  Future<List<ResultBlock>> getPrompt(PromptRef ref, JsonMap arguments) async {
    final remote = _remoteCapabilities[ref.capability.key];
    if (remote != null) {
      final response = await hostManager.call(remote.hostId, 'prompt.get', {
        'ref': PromptRef(remote.remoteId).toJson(),
        'arguments': arguments,
      });
      return _resultBlocks(response['blocks']);
    }
    final entry = _entries[ref.capability.connection.value];
    if (entry?.session == null ||
        !entry!.capabilities.any(
          (item) =>
              item.id.key == ref.capability.key &&
              ref.capability.kind == CapabilityKind.mcpPrompt,
        )) {
      throw StateError('提示连接不可用，请刷新');
    }
    try {
      return await entry.session!.getPrompt(ref.capability.name, arguments);
    } catch (cause) {
      throw StateError(_safeFailure(cause));
    }
  }

  List<ResultBlock> _resultBlocks(Object? raw) {
    if (raw is! List) {
      throw const FormatException('Host result blocks are invalid');
    }
    return raw.map(ResultBlock.fromJson).toList(growable: false);
  }

  @override
  Future<List<ResultBlock>> previewLocalFile(String path) async =>
      _unavailable();

  @override
  Future<void> revealLocalFile(String path) async => _unavailable();

  @override
  Future<AccountSnapshot?> readAccount(ConnectionId connection) async {
    final remote = _remoteConnectionFor(connection);
    if (remote == null) return null;
    return _decodeAccountSnapshot(
      await hostManager.call(remote.hostId, 'account.read', {
        'connectionId': remote.remoteId,
      }),
    );
  }

  @override
  Future<TerminalSession> beginAccountLogin(ConnectionId connection) async {
    final remote = _remoteConnectionFor(connection);
    if (remote == null) {
      throw UnsupportedError('账号登录仅支持配对 Mac Host 上的连接');
    }
    final response = await hostManager.call(
      remote.hostId,
      'account.beginLogin',
      {'operationId': _newHostOperationId(), 'connectionId': remote.remoteId},
      sideEffect: true,
    );
    return _registerRemoteTerminal(remote, response, accountLogin: true);
  }

  @override
  Future<int> waitAccountLogin(TerminalSession session) async {
    final remote = _remoteTerminal(session);
    final sessionId = remote.accountSessionId;
    if (!remote.accountLogin || sessionId == null) {
      throw ArgumentError('终端会话不是账号登录会话');
    }
    final response = await hostManager.call(
      remote.hostId,
      'account.waitLogin',
      {'sessionId': sessionId},
    );
    final exitCode = response['exitCode'];
    if (exitCode is! int) {
      throw const FormatException('Mac Host account login result is invalid');
    }
    return exitCode;
  }

  @override
  Future<AccountSnapshot> logoutAccount(
    ConnectionId connection, {
    required bool confirmed,
  }) async {
    if (!confirmed) throw StateError('退出账号需要明确确认');
    final remote = _remoteConnectionFor(connection);
    if (remote == null) {
      throw UnsupportedError('账号管理仅支持配对 Mac Host 上的连接');
    }
    final response = await hostManager.call(remote.hostId, 'account.logout', {
      'operationId': _newHostOperationId(),
      'connectionId': remote.remoteId,
      'confirmed': true,
    }, sideEffect: true);
    final snapshot = _decodeAccountSnapshot(response);
    if (snapshot == null) {
      throw const FormatException('Mac Host account logout result is invalid');
    }
    return snapshot;
  }

  AccountSnapshot? _decodeAccountSnapshot(Map<String, Object?> response) {
    final raw = response['snapshot'];
    if (raw == null) return null;
    final json = jsonObject(raw, 'accountSnapshot');
    if (json.keys.toSet().difference(const {
      'state',
      'nickname',
      'message',
    }).isNotEmpty) {
      throw const FormatException('Mac Host account snapshot is invalid');
    }
    final state = AccountState.values
        .where((item) => item.name == json['state'])
        .firstOrNull;
    final nickname = json['nickname'];
    final message = json['message'];
    if (state == null ||
        nickname != null && (nickname is! String || nickname.length > 256) ||
        message != null && (message is! String || message.length > 512)) {
      throw const FormatException('Mac Host account snapshot is invalid');
    }
    return AccountSnapshot(
      state,
      nickname: nickname as String?,
      message: message as String?,
    );
  }

  _AndroidRemoteConnection? _remoteConnectionFor(ConnectionId id) {
    final remote = _remoteConnections[id.value];
    if (remote == null) return null;
    if (!hostManager.isConnected(remote.hostId)) {
      throw StateError(
        _hostStatusDiagnostic(hostManager.statusFor(remote.hostId)),
      );
    }
    return remote;
  }

  @override
  Future<TerminalSession> openTerminal(CliCommand command) async {
    final remote = _remoteConnectionFor(command.connection);
    if (remote == null) {
      throw UnsupportedError('终端仅支持配对 Mac Host 上的 CLI 连接');
    }
    if (remote.connection.kind != ConnectionKind.cli) {
      throw ArgumentError('只有 CLI 连接可以打开终端');
    }
    if (command.arguments.length > 256 ||
        command.arguments.any(
          (argument) => argument.length > 4096 || argument.contains('\u0000'),
        )) {
      throw const FormatException('终端参数无效');
    }
    final response = await hostManager.call(remote.hostId, 'terminal.open', {
      'operationId': _newHostOperationId(),
      'connectionId': remote.remoteId,
      'arguments': command.arguments,
    }, sideEffect: true);
    return _registerRemoteTerminal(remote, response, accountLogin: false);
  }

  @override
  Stream<String> watchTerminal(TerminalSession session) {
    final remote = _remoteTerminals[session.id];
    if (remote == null) return Stream.error(ArgumentError('终端会话不存在'));
    if (!remote.closed) {
      remote.subscriptionFuture ??= _subscribeRemoteTerminal(remote);
    }
    return remote.output.stream;
  }

  @override
  Future<void> writeTerminal(TerminalSession session, String text) async {
    final remote = _activeRemoteTerminal(session);
    if (text.length > 1024 * 1024 || text.contains('\u0000')) {
      throw const FormatException('终端输入无效');
    }
    await hostManager.call(remote.hostId, 'terminal.write', {
      'operationId': _newHostOperationId(),
      'terminalId': remote.terminalId,
      'text': text,
    }, sideEffect: true);
  }

  @override
  Future<void> resizeTerminal(
    TerminalSession session,
    int columns,
    int rows,
  ) async {
    final remote = _activeRemoteTerminal(session);
    if (columns < 1 || columns > 400 || rows < 1 || rows > 200) {
      throw const FormatException('终端尺寸无效');
    }
    await hostManager.call(remote.hostId, 'terminal.resize', {
      'operationId': _newHostOperationId(),
      'terminalId': remote.terminalId,
      'columns': columns,
      'rows': rows,
    }, sideEffect: true);
  }

  @override
  Future<void> interruptTerminal(TerminalSession session) async {
    final remote = _activeRemoteTerminal(session);
    await hostManager.call(remote.hostId, 'terminal.interrupt', {
      'operationId': _newHostOperationId(),
      'terminalId': remote.terminalId,
    }, sideEffect: true);
  }

  @override
  Future<void> closeTerminal(TerminalSession session) async {
    final remote = _remoteTerminals[session.id];
    if (remote == null || remote.closeRequested) return;
    remote.closeRequested = true;
    try {
      if (hostManager.isConnected(remote.hostId)) {
        await hostManager.call(remote.hostId, 'terminal.close', {
          'operationId': _newHostOperationId(),
          'terminalId': remote.terminalId,
        }, sideEffect: true);
      }
    } finally {
      _remoteTerminals.remove(session.id);
      await _closeRemoteTerminal(remote);
    }
  }

  _AndroidRemoteTerminal _remoteTerminal(TerminalSession session) =>
      _remoteTerminals[session.id] ?? (throw ArgumentError('终端会话不存在'));

  _AndroidRemoteTerminal _activeRemoteTerminal(TerminalSession session) {
    final remote = _remoteTerminal(session);
    if (remote.closed || !hostManager.isConnected(remote.hostId)) {
      throw StateError('Mac Host 终端会话已结束，请重新打开。');
    }
    return remote;
  }

  TerminalSession _registerRemoteTerminal(
    _AndroidRemoteConnection connection,
    Map<String, Object?> response, {
    required bool accountLogin,
  }) {
    final terminalId = response['terminalId'];
    final sessionId = response['sessionId'];
    if (terminalId is! String ||
        sessionId is! String ||
        !_validHostOpaqueId(terminalId) ||
        !_validHostOpaqueId(sessionId)) {
      throw const FormatException('Mac Host terminal session is invalid');
    }
    final localId = _newId('remote-terminal');
    _remoteTerminals[localId] = _AndroidRemoteTerminal(
      hostId: connection.hostId,
      terminalId: terminalId,
      accountSessionId: accountLogin ? sessionId : null,
      accountLogin: accountLogin,
    );
    return TerminalSession(localId);
  }

  bool _validHostOpaqueId(String value) =>
      value.length <= 128 &&
      RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$').hasMatch(value);

  Future<void> _subscribeRemoteTerminal(_AndroidRemoteTerminal remote) async {
    try {
      // Listen before subscribe: the Host can replay buffered output before
      // the RPC response containing its subscription ID arrives.
      remote.notifications = hostManager
          .watchNotifications(remote.hostId)
          .listen(
            (notification) =>
                _receiveRemoteTerminalNotification(remote, notification),
            onError: (_) => _closeRemoteTerminal(remote, 'Mac Host 终端连接已中断。'),
            onDone: () => _closeRemoteTerminal(remote, 'Mac Host 终端连接已关闭。'),
          );
      final response = await hostManager.call(
        remote.hostId,
        'terminal.subscribe',
        {'terminalId': remote.terminalId},
      );
      final subscriptionId = response['subscriptionId'];
      if (subscriptionId is! String ||
          !_validHostOpaqueId(subscriptionId) ||
          response['terminalId'] != remote.terminalId) {
        throw const FormatException(
          'Mac Host terminal subscription is invalid',
        );
      }
      remote.subscriptionId = subscriptionId;
      final pending = List<Map<String, Object?>>.of(
        remote.pendingNotifications,
      );
      remote.pendingNotifications.clear();
      for (final notification in pending) {
        _receiveRemoteTerminalNotification(remote, notification);
      }
    } on Object {
      _closeRemoteTerminal(remote, 'Mac Host 终端订阅失败，请检查权限和连接状态。');
    }
  }

  void _receiveRemoteTerminalNotification(
    _AndroidRemoteTerminal remote,
    Map<String, Object?> notification,
  ) {
    if (remote.closed || notification['method'] != 'terminal.event') return;
    try {
      final params = jsonObject(notification['params'], 'terminal.params');
      final event = jsonObject(params['event'], 'terminal.event');
      if (event['terminalId'] != remote.terminalId) return;
      final subscriptionId = params['subscriptionId'];
      if (subscriptionId is! String || !_validHostOpaqueId(subscriptionId)) {
        throw const FormatException(
          'Mac Host terminal notification is invalid',
        );
      }
      final sequence = event['sequence'];
      final kind = event['kind'];
      final text = event['text'];
      if (sequence is! int ||
          sequence < 0 ||
          sequence > 9007199254740991 ||
          params['sequence'] != sequence ||
          kind is! String ||
          !const {'output', 'closed', 'failed'}.contains(kind) ||
          (kind == 'output') != (text is String) ||
          text != null && text is! String ||
          text is String &&
              (utf8.encode(text).length > 1024 * 1024 ||
                  text.contains('\u0000'))) {
        throw const FormatException(
          'Mac Host terminal notification is invalid',
        );
      }
      if (remote.subscriptionId == null) {
        final pendingBytes = utf8.encode(text as String? ?? '').length;
        if (remote.pendingNotifications.length >= 256 ||
            remote.pendingNotificationBytes + pendingBytes > 1024 * 1024) {
          throw const FormatException('Mac Host sent too many terminal events');
        }
        remote.pendingNotifications.add(Map.unmodifiable(notification));
        remote.pendingNotificationBytes += pendingBytes;
        return;
      }
      if (subscriptionId != remote.subscriptionId) return;
      if (sequence <= remote.sequence) return;
      remote.sequence = sequence;
      if (kind == 'output') {
        if (!remote.output.isClosed) remote.output.add(text! as String);
      } else if (kind == 'failed') {
        _closeRemoteTerminal(remote, 'Mac Host 终端进程异常结束。');
      } else {
        _closeRemoteTerminal(remote);
      }
    } on Object catch (error) {
      if (error is FormatException) {
        _closeRemoteTerminal(remote, 'Mac Host 终端数据无效，会话已结束。');
      }
      // Other authenticated Host notifications are unrelated to this stream.
    }
  }

  void _closeRemoteTerminalsForHost(String hostId, String message) {
    for (final terminal in _remoteTerminals.values.toList()) {
      if (terminal.hostId == hostId) {
        unawaited(_closeRemoteTerminal(terminal, message));
      }
    }
  }

  Future<void> _closeRemoteTerminal(
    _AndroidRemoteTerminal remote, [
    String? message,
  ]) async {
    if (remote.closed) return;
    remote.closed = true;
    await remote.notifications?.cancel();
    if (remote.output.isClosed) return;
    if (message != null) remote.output.add('\r\n[$message]\r\n');
    await remote.output.close();
  }
}

final class _AndroidEntry {
  _AndroidEntry(this.id, this.spec);
  final String id;
  final ConnectionSpec spec;
  AndroidMcpSession? session;
  List<Capability> capabilities = const [];
  ConnectionStatus status = ConnectionStatus.unavailable;
  String? version;
  String? diagnostic;

  Connection toConnection() => Connection(
    id: ConnectionId(id),
    kind: ConnectionKind.mcpHttp,
    label: spec.label,
    location: spec.url!,
    status: status,
    protocolVersion: version,
    diagnostic: diagnostic,
  );
}

final class _AndroidDraft {
  _AndroidDraft(this.spec, this.expiresAt, this.timer);
  final ConnectionSpec spec;
  final DateTime expiresAt;
  final Timer timer;
  bool discarded = false;
}

final class _AndroidRun {
  _AndroidRun(this.id, this.capability);
  final RunId id;
  final CapabilityId capability;
  final List<RunEvent> history = [];
  RunState state = RunState.created;
  String? remoteHostId;
  String? remoteRunId;
  String? remoteSubscriptionId;
  int? remoteSequence;
  StreamSubscription<Map<String, Object?>>? remoteNotifications;
  bool get terminal => {
    RunState.succeeded,
    RunState.failed,
    RunState.cancelled,
    RunState.timedOut,
    RunState.outcomeUnknown,
  }.contains(state);
}

final class _AndroidRemoteTerminal {
  _AndroidRemoteTerminal({
    required this.hostId,
    required this.terminalId,
    required this.accountSessionId,
    required this.accountLogin,
  });

  final String hostId;
  final String terminalId;
  final String? accountSessionId;
  final bool accountLogin;
  final StreamController<String> output = StreamController<String>.broadcast(
    sync: true,
  );
  final List<Map<String, Object?>> pendingNotifications = [];
  int pendingNotificationBytes = 0;
  StreamSubscription<Map<String, Object?>>? notifications;
  Future<void>? subscriptionFuture;
  String? subscriptionId;
  int sequence = -1;
  bool closed = false;
  bool closeRequested = false;
}

final class _AndroidRemoteConnection {
  _AndroidRemoteConnection({
    required this.hostId,
    required this.remoteId,
    required this.connection,
  });

  final String hostId;
  final String remoteId;
  Connection connection;

  void setConnection(Connection value) => connection = value;

  void setAvailability(ConnectionStatus status, String diagnostic) {
    connection = Connection(
      id: connection.id,
      kind: connection.kind,
      label: connection.label,
      location: connection.location,
      executionTarget: connection.executionTarget,
      status: status,
      protocolVersion: connection.protocolVersion,
      diagnostic: diagnostic,
    );
  }
}

final class _AndroidRemoteCapability {
  const _AndroidRemoteCapability({
    required this.hostId,
    required this.remoteId,
    required this.capability,
  });

  final String hostId;
  final CapabilityId remoteId;
  final Capability capability;
}

final class _AndroidHostConnectionSetupPort
    implements ConnectionSetupPort, ConnectionSetupExecutableSelectionPort {
  _AndroidHostConnectionSetupPort(this.runtime, this.host, this.adapters);

  final AndroidRuntimePort runtime;
  final AndroidPairedHost host;
  final List<ConnectionAdapter> adapters;
  final Map<String, Set<String>> _executableReferences = {};
  final Map<String, _AndroidHostSetupDraft> _drafts = {};

  @override
  List<ConnectionAdapter> get connectionAdapters => adapters;

  @override
  Future<String?> detectExecutable(String adapterId) async =>
      (await detectExecutableSelection(adapterId))?.path;

  @override
  Future<DetectedExecutableSelection?> detectExecutableSelection(
    String adapterId, {
    String? executableName,
  }) async {
    final adapter = _adapter(adapterId);
    final String method;
    final Map<String, Object?> params;
    if (executableName != null) {
      if (!{
            ConnectionKind.cli,
            ConnectionKind.mcpStdio,
          }.contains(adapter.kind) ||
          adapter.autoDetectExecutable) {
        throw const FormatException('此适配器不支持按命令名称查找');
      }
      method = 'setup.resolveExecutable';
      params = {'adapterId': adapterId, 'executableName': executableName};
    } else {
      if (!adapter.autoDetectExecutable) return null;
      method = 'setup.detectExecutable';
      params = {'adapterId': adapterId};
    }
    final response = await runtime.hostManager.call(
      host.hostId,
      method,
      params,
    );
    if (response['detected'] != true) return null;
    final reference = response['executableRef'];
    final displayLocation = response['displayLocation'];
    final expiresAtValue = response['expiresAt'];
    if (reference is! String ||
        !RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$').hasMatch(reference) ||
        displayLocation is! String ||
        displayLocation.isEmpty ||
        displayLocation.length > 200 ||
        expiresAtValue is! String) {
      throw const FormatException('Mac Host 程序查找结果无效');
    }
    final expiresAt = DateTime.tryParse(expiresAtValue);
    if (expiresAt == null || !expiresAt.isAfter(DateTime.now())) {
      throw const FormatException('Mac Host 程序引用已过期');
    }
    _executableReferences.putIfAbsent(adapterId, () => {}).add(reference);
    return DetectedExecutableSelection(
      displayLocation: displayLocation,
      reference: reference,
    );
  }

  @override
  Future<ConnectionSetupReport> testConnectionSetup(
    ConnectionSetupDraft draft,
  ) async {
    final adapter = _adapter(draft.adapterId);
    if (draft.spec.executionTarget != ExecutionTarget.host(host.hostId) ||
        draft.spec.kind != adapter.kind ||
        draft.spec.executable != null ||
        draft.spec.workingDirectory != null ||
        draft.spec.manifestPath != null ||
        draft.spec.profileId != null) {
      throw const FormatException('Host 连接表单包含不支持的运行端字段');
    }
    if (adapter.kind != ConnectionKind.mcpHttp &&
        (draft.executableReference == null ||
            !_executableReferences[adapter.id]!.contains(
              draft.executableReference,
            ))) {
      throw const FormatException('请先通过 Mac Host 查找并确认程序');
    }
    final fieldKeys = adapter.fields.map((field) => field.key).toSet();
    if (draft.values.keys.any((key) => !fieldKeys.contains(key))) {
      throw const FormatException('连接表单包含未知字段');
    }
    final publicValues = <String, String>{};
    final secretValues = <String, String>{};
    for (final field in adapter.fields) {
      final value = draft.values[field.key];
      if (value == null) continue;
      if (field.kind == SetupFieldKind.secret) {
        secretValues[field.key] = value;
      } else {
        publicValues[field.key] = value;
      }
    }
    if (adapter.kind == ConnectionKind.mcpHttp &&
        draft.spec.authToken?.isNotEmpty == true) {
      secretValues['authToken'] = draft.spec.authToken!;
    }
    final payload = <String, Object?>{
      'adapterId': adapter.id,
      'label': draft.spec.label,
      'fieldValues': publicValues,
      if (adapter.kind == ConnectionKind.mcpHttp) 'url': draft.spec.url,
      if (draft.executableReference != null)
        'executableRef': draft.executableReference,
      if (draft.spec.arguments.isNotEmpty) 'arguments': draft.spec.arguments,
    };
    final response = await runtime.hostManager.call(host.hostId, 'setup.test', {
      'operationId': runtime._newHostOperationId(),
      'draft': payload,
      if (secretValues.isNotEmpty) 'secretValues': secretValues,
    }, sideEffect: true);
    final canSave = response['canSave'];
    final rawChecks = response['checks'];
    if (canSave is! bool || rawChecks is! List) {
      throw const FormatException('Mac Host 连接测试结果无效');
    }
    final checks = rawChecks.map(_decodeHostSetupCheck).toList(growable: false);
    if (!canSave) {
      return ConnectionSetupReport(
        draftId: runtime._newId('host-setup'),
        checks: checks,
        canSave: false,
      );
    }
    final handle = response['draftHandle'];
    if (handle is! String ||
        !RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$').hasMatch(handle)) {
      throw const FormatException('Mac Host 测试草稿引用无效');
    }
    final localDraftId = runtime._newId('host-setup');
    _drafts[localDraftId] = _AndroidHostSetupDraft(
      adapter: adapter,
      handle: handle,
      expiresAt: DateTime.now().add(const Duration(minutes: 10)),
    );
    return ConnectionSetupReport(
      draftId: localDraftId,
      checks: checks,
      canSave: true,
    );
  }

  @override
  Future<Connection> saveConnectionSetup(String draftId) async {
    final draft = _drafts[draftId];
    if (draft == null) throw StateError('Mac Host 测试草稿已过期，请重新测试');
    if (draft.savedConnection case final connection?) return connection;
    if (draft.saveOutcomeUnknown) {
      throw const ConnectionSetupOutcomeUnknown();
    }
    if (!draft.expiresAt.isAfter(DateTime.now())) {
      _drafts.remove(draftId);
      throw StateError('Mac Host 测试草稿已过期，请重新测试');
    }
    final operationId = draft.saveOperationId ??= runtime._newHostOperationId();
    try {
      final response = await runtime.hostManager.call(
        host.hostId,
        'setup.save',
        {'operationId': operationId, 'draftHandle': draft.handle},
        sideEffect: true,
      );
      if (response['replayed'] == true) {
        throw const ConnectionSetupOutcomeUnknown();
      }
      draft.savedConnection = runtime._acceptHostSetupResult(
        host,
        draft.adapter,
        response,
      );
      _drafts.remove(draftId);
      return draft.savedConnection!;
    } on AndroidHostRpcException catch (error) {
      if ({-32004, -32603}.contains(error.code)) {
        draft.saveOutcomeUnknown = true;
        throw const ConnectionSetupOutcomeUnknown();
      }
      await discardConnectionSetup(draftId);
      rethrow;
    } on ConnectionSetupOutcomeUnknown {
      draft.saveOutcomeUnknown = true;
      throw const ConnectionSetupOutcomeUnknown();
    } on Object {
      draft.saveOutcomeUnknown = true;
      throw const ConnectionSetupOutcomeUnknown();
    }
  }

  @override
  Future<void> discardConnectionSetup(String draftId) async {
    final draft = _drafts.remove(draftId);
    if (draft == null || draft.saveOutcomeUnknown) return;
    try {
      await runtime.hostManager.call(host.hostId, 'setup.discard', {
        'operationId': runtime._newHostOperationId(),
        'draftHandle': draft.handle,
      }, sideEffect: true);
    } on Object {
      // The Host expires unclaimed setup drafts and never stores client secrets.
    }
  }

  ConnectionAdapter _adapter(String adapterId) =>
      adapters.where((adapter) => adapter.id == adapterId).firstOrNull ??
      (throw const FormatException('Mac Host 适配器不存在'));
}

final class _AndroidHostSetupDraft {
  _AndroidHostSetupDraft({
    required this.adapter,
    required this.handle,
    required this.expiresAt,
  });

  final ConnectionAdapter adapter;
  final String handle;
  final DateTime expiresAt;
  String? saveOperationId;
  Connection? savedConnection;
  bool saveOutcomeUnknown = false;
}

ConnectionAdapter _decodeHostConnectionAdapter(Object? value, String hostId) {
  if (value is! Map || value.keys.any((key) => key is! String)) {
    throw const FormatException('Mac Host 适配器条目无效');
  }
  final json = value.cast<String, Object?>();
  final id = json['id'];
  final label = json['label'];
  final kindName = json['kind'];
  final defaultLabel = json['defaultLabel'];
  final description = json['description'];
  final allowedKinds = const {
    'netease-music': ConnectionKind.cli,
    'cli': ConnectionKind.cli,
    'mcp-stdio': ConnectionKind.mcpStdio,
    'mcp-http': ConnectionKind.mcpHttp,
  };
  final expectedKind = id is String ? allowedKinds[id] : null;
  if (id is! String ||
      expectedKind == null ||
      kindName != expectedKind.name ||
      label is! String ||
      label.trim().isEmpty ||
      label.length > 100 ||
      defaultLabel != null &&
          (defaultLabel is! String ||
              defaultLabel.trim().isEmpty ||
              defaultLabel.length > 100) ||
      description != null &&
          (description is! String || description.length > 500) ||
      json['fields'] is! List ||
      json['showGenericCliFields'] is! bool ||
      json['autoDetectExecutable'] is! bool) {
    throw const FormatException('Mac Host 适配器元数据无效');
  }
  final fields = <SetupField>[];
  final fieldKeys = <String>{};
  for (final rawField in json['fields']! as List) {
    if (rawField is! Map || rawField.keys.any((key) => key is! String)) {
      throw const FormatException('Mac Host 字段元数据无效');
    }
    final field = rawField.cast<String, Object?>();
    final key = field['key'];
    final fieldLabel = field['label'];
    final kindValue = field['kind'];
    final required = field['required'];
    final readFileContent = field['readFileContent'];
    final kind = SetupFieldKind.values
        .where((candidate) => candidate.name == kindValue)
        .firstOrNull;
    if (key is! String ||
        key.isEmpty ||
        key.length > 128 ||
        !fieldKeys.add(key) ||
        fieldLabel is! String ||
        fieldLabel.trim().isEmpty ||
        fieldLabel.length > 100 ||
        kind == null ||
        required is! bool ||
        readFileContent is! bool ||
        kind == SetupFieldKind.file && !readFileContent ||
        field['hint'] != null &&
            (field['hint'] is! String ||
                (field['hint'] as String).length > 500)) {
      throw const FormatException('Mac Host 字段元数据无效');
    }
    fields.add(
      SetupField(
        key: key,
        label: fieldLabel,
        kind: kind,
        required: required,
        hint: field['hint'] as String?,
        readFileContent: readFileContent,
      ),
    );
  }
  return ConnectionAdapter(
    id: id,
    label: label,
    kind: expectedKind,
    executionTarget: ExecutionTarget.host(hostId),
    fields: List.unmodifiable(fields),
    defaultLabel: defaultLabel as String?,
    description: description as String?,
    showGenericCliFields: json['showGenericCliFields']! as bool,
    autoDetectExecutable: json['autoDetectExecutable']! as bool,
  );
}

SetupCheck _decodeHostSetupCheck(Object? value) {
  if (value is! Map || value.keys.any((key) => key is! String)) {
    throw const FormatException('Mac Host 检查项无效');
  }
  final json = value.cast<String, Object?>();
  final label = json['label'];
  final statusName = json['status'];
  final detail = json['detail'];
  final status = SetupCheckStatus.values
      .where((candidate) => candidate.name == statusName)
      .firstOrNull;
  if (label is! String ||
      detail is! String ||
      status == null ||
      label.length > 100 ||
      detail.length > 500) {
    throw const FormatException('Mac Host 检查项无效');
  }
  return SetupCheck(label, status, detail);
}
