import 'dart:async';
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
import 'android_mcp_session.dart';
import 'android_runtime_store.dart';

/// Android local HTTP MCP runtime; Node and Host remain separate stages.
final class AndroidRuntimePort
    with WidgetsBindingObserver
    implements RuntimePort, ConnectionSetupPort {
  AndroidRuntimePort._(
    AndroidRuntimeStore store,
    this._credentials,
    this._draftTtl,
  ) : _store = store,
      hostManager = AndroidHostManager(store);

  static Future<AndroidRuntimePort> open({
    Directory? dataDirectory,
    AndroidCredentialStore? credentialStore,
    Duration draftTtl = const Duration(minutes: 10),
  }) async {
    WidgetsFlutterBinding.ensureInitialized();
    final directory = dataDirectory ?? await getApplicationSupportDirectory();
    final store = AndroidRuntimeStore(directory);
    final runtime = AndroidRuntimePort._(
      store,
      credentialStore ?? const SecureAndroidCredentialStore(),
      draftTtl,
    );
    await runtime.hostManager.load();
    await runtime._load();
    WidgetsBinding.instance.addObserver(runtime);
    return runtime;
  }

  final AndroidRuntimeStore _store;
  final AndroidCredentialStore _credentials;
  final Duration _draftTtl;
  final AndroidHostManager hostManager;
  final _entries = <String, _AndroidEntry>{};
  final _drafts = <String, _AndroidDraft>{};
  final _savingDrafts = <String>{};
  final _runs = <String, _AndroidRun>{};
  final _activity = <RunSummary>[];
  final _events = StreamController<RunEvent>.broadcast(sync: true);
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
    for (final entry in _entries.values) {
      await entry.session?.close();
    }
    await hostManager.dispose();
    await _store.flush();
    await _events.close();
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
  RuntimeFeatures get features => RuntimeFeatures.httpOnly;

  @override
  List<String> get startupNotices => List.unmodifiable(_notices);

  @override
  List<ConnectionAdapter> get connectionAdapters => const [
    ConnectionAdapter(
      id: 'mcp-http',
      label: 'HTTP MCP',
      kind: ConnectionKind.mcpHttp,
    ),
  ];

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
  Future<List<Connection>> listConnections() async => [
    for (final entry in _entries.values) entry.toConnection(),
  ];

  @override
  Future<List<Capability>> searchCapabilities(SearchQuery query) async {
    final text = query.text.trim().toLowerCase();
    return [
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
  }

  @override
  Future<List<RunSummary>> listRecentRuns() async =>
      List.unmodifiable(_activity);

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
  }) {
    if (run.terminal) return;
    run.state = state;
    final event = RunEvent(
      runId: run.id,
      sequence: run.history.length,
      state: state,
      occurredAt: DateTime.now().toUtc(),
      blocks: blocks,
      failure: failure,
    );
    run.history.add(event);
    _events.add(event);
    if (run.terminal) {
      _activity.insert(
        0,
        RunSummary(
          run.id,
          run.capability,
          RunEvent(
            runId: run.id,
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

  @override
  Future<List<ResultBlock>> readResource(ResourceRef ref) async {
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

  @override
  Future<List<ResultBlock>> previewLocalFile(String path) async =>
      _unavailable();

  @override
  Future<void> revealLocalFile(String path) async => _unavailable();

  @override
  Future<TerminalSession> openTerminal(CliCommand command) async =>
      _unavailable();

  @override
  Stream<String> watchTerminal(TerminalSession session) =>
      Stream.error(UnsupportedError('此功能尚未在 Android 上开放'));

  @override
  Future<void> writeTerminal(TerminalSession session, String text) async =>
      _unavailable();

  @override
  Future<void> resizeTerminal(
    TerminalSession session,
    int columns,
    int rows,
  ) async => _unavailable();

  @override
  Future<void> interruptTerminal(TerminalSession session) async =>
      _unavailable();

  @override
  Future<void> closeTerminal(TerminalSession session) async => _unavailable();
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
  bool get terminal => {
    RunState.succeeded,
    RunState.failed,
    RunState.cancelled,
    RunState.timedOut,
    RunState.outcomeUnknown,
  }.contains(state);
}
