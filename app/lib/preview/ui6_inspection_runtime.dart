import 'dart:async';

import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:aggregate_runtime/aggregate_runtime.dart';

/// A disposable, in-memory runtime for native UI acceptance.
///
/// It exposes production confirmation/setup/account/terminal controls while
/// keeping every operation local to this process. Do not use it as the release
/// runtime or connect it to user data.
final class Ui6InspectionRuntime
    implements
        RuntimePort,
        ConnectionSetupPort,
        ConnectionSetupTargetPort,
        ConnectionAccountPort {
  Ui6InspectionRuntime()
    : _preview = PreviewRuntime(
        connections: _seedConnections,
        capabilities: _seedCapabilities,
        latency: const Duration(milliseconds: 240),
        features: RuntimeFeatures.localDesktop,
      ),
      _connections = List.of(_seedConnections);

  final PreviewRuntime _preview;
  final List<Connection> _connections;
  final Map<String, ConnectionSetupDraft> _drafts = {};
  final Map<String, StreamController<String>> _terminalStreams = {};
  final Map<String, List<String>> _terminalInitialOutput = {};
  final Map<String, JsonMap> _actionManifests = {};
  final List<RunSummary> _filterStateInspectionActivities = [];
  StreamController<RunEvent>? _inspectionRunEvents;
  var _target = ExecutionTarget.device;
  var _draftCounter = 0;
  var _connectionCounter = 0;
  var _terminalCounter = 0;
  var _activitySeeded = false;
  var _filterStateActivitiesSeeded = false;
  RunSummary? _runningInspectionActivity;
  AccountSnapshot _musicAccount = const AccountSnapshot(
    AccountState.signedIn,
    nickname: '预览账号',
  );

  static const _gitId = ConnectionId('ui6-review-git');
  static const _mcpId = ConnectionId('ui6-review-mcp');
  static const _musicId = ConnectionId('ui6-review-music');
  static const _activityStatusCapability = CapabilityId(
    _gitId,
    CapabilityKind.cliAction,
    'status',
  );

  /// Seeds local, disposable ActivityPage states for visual inspection.
  /// This method never invokes a host process, network service, or user data.
  Future<void> seedActivityForInspection({
    bool includeRunning = false,
    bool includeFilterStates = false,
  }) async {
    if (!_activitySeeded) {
      _activitySeeded = true;
      await _preview.invoke(_activityStatusCapability, const {});
      await Future<void>.delayed(const Duration(milliseconds: 260));
      await _preview.invoke(
        const CapabilityId(_mcpId, CapabilityKind.mcpTool, 'add'),
        const {'a': 'invalid', 'b': 1},
      );
      final pending = await _preview.invoke(
        _activityStatusCapability,
        const {},
      );
      await _preview.cancel(pending.id);
    }
    if (includeFilterStates && !_filterStateActivitiesSeeded) {
      _filterStateActivitiesSeeded = true;
      _filterStateInspectionActivities.addAll([
        _inspectionTerminalActivity(
          id: 'ui6-inspection-timed-out',
          state: RunState.timedOut,
          failure: const RuntimeFailure(RuntimeErrorCode.timedOut, '仅内存预览超时'),
        ),
        _inspectionTerminalActivity(
          id: 'ui6-inspection-outcome-unknown',
          state: RunState.outcomeUnknown,
          failure: const RuntimeFailure(
            RuntimeErrorCode.outcomeUnknown,
            '仅内存预览结果待确认',
          ),
        ),
      ]);
    }
    if (!includeRunning || _runningInspectionActivity != null) return;

    const runId = RunId('ui6-inspection-running');
    final running = RunEvent(
      runId: runId,
      sequence: 1,
      state: RunState.running,
      occurredAt: DateTime.now(),
    );
    _inspectionRunEvents ??= StreamController<RunEvent>.broadcast(sync: true);
    _runningInspectionActivity = RunSummary(
      runId,
      _activityStatusCapability,
      running,
    );
  }

  RunSummary _inspectionTerminalActivity({
    required String id,
    required RunState state,
    required RuntimeFailure failure,
  }) {
    final runId = RunId(id);
    return RunSummary(
      runId,
      _activityStatusCapability,
      RunEvent(
        runId: runId,
        sequence: 1,
        state: state,
        occurredAt: DateTime.now(),
        failure: failure,
      ),
    );
  }

  static const List<Connection> _seedConnections = [
    Connection(
      id: _gitId,
      kind: ConnectionKind.cli,
      label: 'UI 检查 · Git CLI',
      location: '仅内存预览',
    ),
    Connection(
      id: _mcpId,
      kind: ConnectionKind.mcpHttp,
      label: 'UI 检查 · MCP',
      location: 'preview.invalid',
      protocolVersion: '2026-07-28',
    ),
    Connection(
      id: _musicId,
      kind: ConnectionKind.cli,
      label: 'UI 检查 · 音乐',
      location: '仅内存预览',
    ),
  ];

  static final List<Capability> _seedCapabilities = [
    Capability(
      id: CapabilityId(_gitId, CapabilityKind.cliAction, 'status'),
      title: '查看 Git 状态',
      description: '在隔离预览中返回本地样例结果',
      permission: PermissionLevel.read,
    ),
    Capability(
      id: CapabilityId(_gitId, CapabilityKind.cliAction, 'write-sample'),
      title: '演示写入权限确认',
      description: '仅用于检查确认弹窗，不会执行外部命令',
      permission: PermissionLevel.externalWrite,
      inputSchema: {
        'type': 'object',
        'properties': {
          'note': {'type': 'string', 'title': '备注'},
        },
        'required': ['note'],
      },
    ),
    Capability(
      id: CapabilityId(_gitId, CapabilityKind.cliCommand, 'inspect-terminal'),
      title: '打开预览终端',
      description: '终端输出和输入均为本地模拟',
      permission: PermissionLevel.read,
      inputSchema: {
        'type': 'object',
        'properties': {
          'argv': {
            'type': 'array',
            'title': '参数',
            'items': {'type': 'string'},
          },
        },
        'required': ['argv'],
      },
    ),
    Capability(
      id: CapabilityId(_mcpId, CapabilityKind.mcpTool, 'add'),
      title: '两个整数相加',
      description: '在隔离预览中返回结构化结果',
      permission: PermissionLevel.read,
      inputSchema: {
        'type': 'object',
        'properties': {
          'a': {'type': 'integer', 'title': '第一个整数'},
          'b': {'type': 'integer', 'title': '第二个整数'},
        },
        'required': ['a', 'b'],
      },
    ),
    Capability(
      id: CapabilityId(_mcpId, CapabilityKind.mcpTool, 'json-sample'),
      title: '编辑 JSON 参数',
      description: '用于检查对象字段与展开控件',
      permission: PermissionLevel.read,
      inputSchema: {
        'type': 'object',
        'properties': {
          'payload': {'type': 'object', 'title': 'JSON 参数'},
        },
        'required': ['payload'],
      },
    ),
    Capability(
      id: CapabilityId(_mcpId, CapabilityKind.mcpTool, 'inspection-error'),
      title: '演示恢复状态',
      description: '仅让验收页显示本地模拟错误状态',
      permission: PermissionLevel.read,
    ),
    Capability(
      id: CapabilityId(_mcpId, CapabilityKind.mcpResource, 'readme'),
      title: '读取预览说明',
      description: '资源阅读器的本地样例',
      permission: PermissionLevel.read,
    ),
    Capability(
      id: CapabilityId(_mcpId, CapabilityKind.mcpPrompt, 'summary'),
      title: '生成摘要提示',
      description: '提示预览的本地样例',
      permission: PermissionLevel.read,
      inputSchema: {
        'type': 'object',
        'properties': {
          'topic': {'type': 'string', 'title': '主题'},
        },
        'required': ['topic'],
      },
    ),
    Capability(
      id: CapabilityId(_musicId, CapabilityKind.cliAction, 'search'),
      title: '搜索歌曲',
      description: '触发搜索授权与非空结果预览',
      permission: PermissionLevel.externalWrite,
      presentation: 'music.search',
      inputSchema: {
        'type': 'object',
        'properties': {
          'keyword': {'type': 'string', 'title': '关键词'},
        },
        'required': ['keyword'],
      },
    ),
    Capability(
      id: CapabilityId(_musicId, CapabilityKind.cliAction, 'play'),
      title: '播放歌曲',
      description: '播放控制只更新预览状态',
      permission: PermissionLevel.externalWrite,
      presentation: 'music.play',
      inputSchema: {
        'type': 'object',
        'properties': {
          'encryptedId': {'type': 'string', 'title': '加密 ID'},
          'originalId': {'type': 'string', 'title': '原始 ID'},
        },
        'required': ['encryptedId', 'originalId'],
      },
    ),
    Capability(
      id: CapabilityId(_musicId, CapabilityKind.cliAction, 'queueAdd'),
      title: '加入播放队列',
      description: '队列控制只更新预览状态',
      permission: PermissionLevel.externalWrite,
      presentation: 'music.queueAdd',
    ),
    for (final role in const [
      'pause',
      'resume',
      'stop',
      'next',
      'prev',
      'state',
    ])
      Capability(
        id: CapabilityId(_musicId, CapabilityKind.cliAction, role),
        title: switch (role) {
          'pause' => '暂停播放',
          'resume' => '继续播放',
          'stop' => '停止播放',
          'next' => '下一首',
          'prev' => '上一首',
          _ => '刷新播放状态',
        },
        description: '仅更新本地预览状态',
        permission: PermissionLevel.externalWrite,
        presentation: 'music.$role',
      ),
  ];

  @override
  bool get isPreview => false;

  @override
  RuntimeFeatures get features => RuntimeFeatures.localDesktop;

  @override
  List<String> get startupNotices => const [];

  @override
  List<ConnectionAdapter> get connectionAdapters => [
    ConnectionAdapter(
      id: 'ui6-inspection-cli',
      label: '预览 CLI',
      kind: ConnectionKind.cli,
      executionTarget: _target,
      defaultLabel: '新建预览 CLI',
      description: '仅保存到当前进程内存，不会探测或运行本机命令。',
      showGenericCliFields: true,
    ),
    ConnectionAdapter(
      id: 'ui6-inspection-mcp-http',
      label: '预览 MCP HTTP',
      kind: ConnectionKind.mcpHttp,
      executionTarget: _target,
      defaultLabel: '新建预览 MCP',
      description: '仅保存到当前进程内存，不会发起网络请求。',
      fields: const [
        SetupField(key: 'url', label: '服务地址', hint: 'https://preview.invalid'),
        SetupField(
          key: 'authToken',
          label: '访问令牌',
          kind: SetupFieldKind.secret,
          required: false,
        ),
      ],
      showGenericCliFields: false,
    ),
  ];

  @override
  Future<List<ConnectionSetupTargetOption>> listSetupTargets() async => [
    const ConnectionSetupTargetOption(
      target: ExecutionTarget.device,
      label: '本机 Mac（预览）',
      detail: '仅在内存中展示设置流程',
    ),
    ConnectionSetupTargetOption(
      target: ExecutionTarget.host('ui6-preview-host'),
      label: '配对 Mac（样例）',
      detail: '虚构的执行目标，不会连接设备',
    ),
  ];

  @override
  Future<ConnectionSetupPort> setupForTarget(ExecutionTarget target) async {
    _target = target;
    return this;
  }

  @override
  Future<String?> detectExecutable(String adapterId) async => null;

  @override
  Future<ConnectionSetupReport> testConnectionSetup(
    ConnectionSetupDraft draft,
  ) async {
    final id = 'ui6-inspection-draft-${++_draftCounter}';
    _drafts[id] = draft;
    return ConnectionSetupReport(
      draftId: id,
      checks: const [
        SetupCheck('预览安全检查', SetupCheckStatus.passed, '未访问本机命令、网络或凭据存储。'),
      ],
      canSave: true,
    );
  }

  @override
  Future<Connection> saveConnectionSetup(String draftId) async {
    final draft = _drafts.remove(draftId);
    if (draft == null) throw StateError('未知的预览设置草稿');
    final connection = _connectionFromSpec(draft.spec);
    _connections.add(connection);
    return connection;
  }

  @override
  Future<void> discardConnectionSetup(String draftId) async {
    _drafts.remove(draftId);
  }

  @override
  Future<AccountSnapshot?> readAccount(ConnectionId connection) async =>
      connection == _musicId ? _musicAccount : null;

  @override
  Future<TerminalSession> beginAccountLogin(ConnectionId connection) async {
    final session = await openTerminal(
      CliCommand(connection, const ['preview-login']),
    );
    return session;
  }

  @override
  Future<int> waitAccountLogin(TerminalSession session) async => 0;

  @override
  Future<AccountSnapshot> logoutAccount(
    ConnectionId connection, {
    required bool confirmed,
  }) async {
    if (!confirmed) throw StateError('预览账号退出需要确认');
    _musicAccount = const AccountSnapshot(AccountState.signedOut);
    return _musicAccount;
  }

  @override
  Future<UserPreferences> loadPreferences() => _preview.loadPreferences();

  @override
  Future<void> savePreferences(UserPreferences preferences) =>
      _preview.savePreferences(preferences);

  @override
  Future<void> clearActivity() async {
    await _preview.clearActivity();
    _runningInspectionActivity = null;
    _filterStateInspectionActivities.clear();
    _filterStateActivitiesSeeded = false;
    _activitySeeded = false;
    await _inspectionRunEvents?.close();
    _inspectionRunEvents = null;
  }

  @override
  Future<List<Connection>> listConnections() async => List.of(_connections);

  @override
  Future<Connection> addConnection(ConnectionSpec spec) async {
    final connection = _connectionFromSpec(spec);
    _connections.add(connection);
    return connection;
  }

  @override
  Future<void> removeConnection(ConnectionId id) async {
    _connections.removeWhere((connection) => connection.id.value == id.value);
  }

  @override
  Future<void> moveConnection(ConnectionId id, int offset) async {
    final index = _connections.indexWhere((item) => item.id.value == id.value);
    if (index < 0) throw StateError('预览连接不存在');
    final target = (index + offset).clamp(0, _connections.length - 1);
    final connection = _connections.removeAt(index);
    _connections.insert(target, connection);
  }

  @override
  Future<Connection> refreshConnection(ConnectionId id) async =>
      _findConnection(id);

  @override
  Future<JsonMap?> loadActionManifest(ConnectionId id) async =>
      _actionManifests[id.value] ?? _manifestFor(_findConnection(id));

  @override
  Future<JsonMap> readActionManifestFile(String path) async =>
      _manifestFor(_findConnection(_gitId));

  @override
  Future<void> saveActionManifest(ConnectionId id, JsonMap manifest) async {
    _actionManifests[id.value] = Map<String, Object?>.from(manifest);
  }

  @override
  Future<void> exportActionManifest(
    ConnectionId id,
    JsonMap manifest,
    String path,
  ) async {}

  @override
  Future<List<Capability>> searchCapabilities(SearchQuery query) =>
      _preview.searchCapabilities(query);

  @override
  Future<RunHandle> invoke(
    CapabilityId id,
    JsonMap arguments, {
    bool permissionGranted = false,
  }) {
    if (id.name == 'inspection-error') {
      throw StateError('预览错误态：未联系任何执行端');
    }
    return _preview.invoke(id, arguments, permissionGranted: permissionGranted);
  }

  @override
  Stream<RunEvent> watchRun(RunId id) {
    final heldRun = _runningInspectionActivity;
    if (heldRun == null || heldRun.id.value != id.value) {
      return _preview.watchRun(id);
    }
    return Stream<RunEvent>.multi((controller) {
      final subscription = _inspectionRunEvents?.stream
          .where((event) => event.runId.value == id.value)
          .listen(controller.add);
      controller.add(_runningInspectionActivity?.latest ?? heldRun.latest);
      if (subscription != null) controller.onCancel = subscription.cancel;
    });
  }

  @override
  Future<List<RunSummary>> listRecentRuns() async {
    final runs = await _preview.listRecentRuns();
    final activity = _runningInspectionActivity;
    return [?activity, ..._filterStateInspectionActivities, ...runs];
  }

  @override
  Future<void> cancel(RunId id) async {
    final activity = _runningInspectionActivity;
    if (activity?.id.value != id.value) {
      await _preview.cancel(id);
      return;
    }
    if (activity!.latest.state != RunState.running) return;
    final cancelled = RunEvent(
      runId: id,
      sequence: activity.latest.sequence + 1,
      state: RunState.cancelled,
      occurredAt: DateTime.now(),
      failure: const RuntimeFailure(RuntimeErrorCode.cancelled, '仅内存预览取消'),
    );
    _runningInspectionActivity = RunSummary(id, activity.capability, cancelled);
    _inspectionRunEvents?.add(cancelled);
  }

  @override
  Future<List<ResultBlock>> readResource(ResourceRef ref) =>
      _preview.readResource(ref);

  @override
  Future<List<ResultBlock>> getPrompt(PromptRef ref, JsonMap arguments) =>
      _preview.getPrompt(ref, arguments);

  @override
  Future<List<ResultBlock>> previewLocalFile(String path) =>
      _preview.previewLocalFile(path);

  @override
  Future<void> revealLocalFile(String path) async {}

  @override
  Future<TerminalSession> openTerminal(CliCommand command) async {
    final session = TerminalSession('ui6-inspection-${++_terminalCounter}');
    _terminalStreams[session.id] = StreamController<String>.broadcast(
      sync: true,
    );
    _terminalInitialOutput[session.id] = [
      'UI 检查终端：全内存模拟，不会运行外部命令。\n',
      '\$ ${command.arguments.join(' ')}\n',
    ];
    return session;
  }

  @override
  Stream<String> watchTerminal(TerminalSession session) async* {
    for (final line in _terminalInitialOutput[session.id] ?? const []) {
      yield line;
    }
    final stream = _terminalStreams[session.id];
    if (stream != null) yield* stream.stream;
  }

  @override
  Future<void> writeTerminal(TerminalSession session, String text) async {
    _terminalStreams[session.id]?.add('> $text\n');
  }

  @override
  Future<void> resizeTerminal(
    TerminalSession session,
    int columns,
    int rows,
  ) async {}

  @override
  Future<void> interruptTerminal(TerminalSession session) async {
    _terminalStreams[session.id]?.add('^C\n');
  }

  @override
  Future<void> closeTerminal(TerminalSession session) async {
    await _terminalStreams.remove(session.id)?.close();
    _terminalInitialOutput.remove(session.id);
  }

  Connection _findConnection(ConnectionId id) => _connections.firstWhere(
    (connection) => connection.id.value == id.value,
    orElse: () => throw StateError('预览连接不存在：${id.value}'),
  );

  Connection _connectionFromSpec(ConnectionSpec spec) {
    final sequence = ++_connectionCounter;
    final location = switch (spec.kind) {
      ConnectionKind.cli => '仅内存预览',
      ConnectionKind.mcpStdio => '仅内存预览',
      ConnectionKind.mcpHttp => 'preview.invalid',
    };
    return Connection(
      id: ConnectionId('ui6-added-$sequence'),
      kind: spec.kind,
      label: spec.label,
      location: location,
      executionTarget: spec.executionTarget,
    );
  }

  JsonMap _manifestFor(Connection connection) => {
    'schemaVersion': 1,
    'id': 'ui6-${connection.id.value}',
    'displayName': connection.label,
    'platforms': ['macos'],
    'executable': connection.location,
    'actions': [
      {
        'id': 'version',
        'title': '查看版本',
        'argv': ['--version'],
        'inputSchema': {
          'type': 'object',
          'properties': <String, Object?>{},
          'required': <String>[],
          'additionalProperties': false,
        },
        'output': 'text',
        'permission': 'read',
        'timeoutMs': 30000,
      },
    ],
  };
}
