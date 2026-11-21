import 'dart:async';

import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:aggregate_runtime/aggregate_runtime.dart';

import '../features/connections/connection_setup_dialog.dart';

enum Ui6InspectionCapabilityScope { all, git, mcp }

/// A disposable, in-memory runtime for native UI acceptance.
///
/// It exposes production confirmation/setup/account/terminal controls while
/// keeping every operation local to this process. Do not use it as the release
/// runtime or connect it to user data.
final class Ui6InspectionRuntime
    implements
        RuntimePort,
        RuntimePresentationPort,
        ConnectionSetupPort,
        ConnectionSetupTargetPort,
        ConnectionAccountPort,
        ConnectionSetupExecutableSelectionPort,
        ConnectionSetupInspectionSamplesPort {
  Ui6InspectionRuntime({
    bool emptyWorkspace = false,
    bool resultUnknownFixture = false,
    bool includeMusicPlaybackState = true,
    bool includeInspectionCapabilities = true,
    Ui6InspectionCapabilityScope capabilityScope =
        Ui6InspectionCapabilityScope.all,
    RuntimeFeatures features = RuntimeFeatures.localDesktop,
  }) : _resultUnknownFixture = resultUnknownFixture,
       _features = features,
       _preview = PreviewRuntime(
         connections: emptyWorkspace
             ? const <Connection>[]
             : _connectionsForScope(capabilityScope),
         capabilities: resultUnknownFixture
             ? const <Capability>[_resultUnknownCapability]
             : _seedCapabilities
                   .where((item) {
                     final isMusic = item.id.connection == _musicId;
                     final inScope = switch (capabilityScope) {
                       Ui6InspectionCapabilityScope.all => true,
                       Ui6InspectionCapabilityScope.git =>
                         isMusic || item.id.connection == _gitId,
                       Ui6InspectionCapabilityScope.mcp =>
                         isMusic || item.id.connection == _mcpId,
                     };
                     return inScope &&
                         (includeMusicPlaybackState ||
                             item.presentation != 'music.state') &&
                         (includeInspectionCapabilities ||
                             !_inspectionCapabilityNames.contains(
                               item.id.name,
                             ));
                   })
                   .toList(growable: false),
         latency: const Duration(milliseconds: 240),
         features: features,
       ),
       _connections = emptyWorkspace
           ? <Connection>[]
           : _connectionsForScope(capabilityScope);

  final PreviewRuntime _preview;
  final bool _resultUnknownFixture;
  final RuntimeFeatures _features;
  final List<Connection> _connections;
  final Map<String, ConnectionSetupDraft> _drafts = {};
  final Map<String, StreamController<String>> _terminalStreams = {};
  final Map<String, List<String>> _terminalInitialOutput = {};
  final Map<String, Completer<int>> _terminalExitWaiters = {};
  final Map<String, JsonMap> _actionManifests = {};
  final List<RunSummary> _filterStateInspectionActivities = [];
  final Map<String, RunSummary> _outcomeUnknownRuns = {};
  StreamController<RunEvent>? _inspectionRunEvents;
  var _target = ExecutionTarget.device;
  var _draftCounter = 0;
  var _connectionCounter = 0;
  var _terminalCounter = 0;
  var _outcomeUnknownRunCounter = 0;
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
  static final _inspectionActivityTime = DateTime(2026, 11, 21, 12);
  static const _resultUnknownCapability = Capability(
    id: CapabilityId(
      _gitId,
      CapabilityKind.cliAction,
      'inspection-outcome-unknown',
    ),
    title: '查看 Git 状态',
    description: '仅内存预览结果待确认状态',
    permission: PermissionLevel.read,
  );
  static const _inspectionCapabilityNames = {
    'write-sample',
    'inspect-terminal',
    'json-sample',
    'inspection-error',
    'queueAdd',
  };

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
        occurredAt: _inspectionActivityTime,
        failure: failure,
      ),
    );
  }

  static const List<Connection> _seedConnections = [
    Connection(
      id: _gitId,
      kind: ConnectionKind.cli,
      label: '示例 Git CLI',
      location: '仅内存预览',
    ),
    Connection(
      id: _mcpId,
      kind: ConnectionKind.mcpHttp,
      label: '示例 MCP',
      location: 'preview.invalid',
      protocolVersion: '2026-07-28',
    ),
    Connection(
      id: _musicId,
      kind: ConnectionKind.cli,
      label: '示例网易云音乐',
      location: '仅内存预览',
    ),
  ];

  static List<Connection> _connectionsForScope(
    Ui6InspectionCapabilityScope scope,
  ) {
    if (scope == Ui6InspectionCapabilityScope.all) {
      return List.of(_seedConnections);
    }
    return [_seedConnections[2], _seedConnections[0], _seedConnections[1]];
  }

  static final List<Capability> _seedCapabilities = [
    Capability(
      id: CapabilityId(_gitId, CapabilityKind.cliAction, 'status'),
      title: '查看 Git 状态',
      description: '显示当前分支与工作区状态',
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
      description: '读取两个数字并返回结果',
      permission: PermissionLevel.read,
      inputSchema: {
        'type': 'object',
        'properties': {
          'a': {'type': 'integer', 'title': '第一个整数', 'example': 12},
          'b': {'type': 'integer', 'title': '第二个整数', 'example': 30},
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
      title: '读取项目说明',
      description: '项目中的 README 文本',
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
  Map<String, Map<String, String>> get connectionSetupInitialValues => const {
    'ui6-inspection-cli': {
      'label': 'Git CLI',
      'executable': '/usr/bin/git',
      'arguments': '[]',
    },
    'ui6-inspection-mcp-stdio': {
      'label': '项目 MCP',
      'executable': '/usr/local/bin/mcp-server',
      'arguments': '[]',
    },
    'ui6-inspection-mcp-http': {
      'label': '项目 MCP',
      'url': 'https://mcp.example.com',
      'token': 'preview-token',
    },
    'ui6-inspection-music': {
      'label': '网易云音乐',
      'executable': '/usr/local/bin/ncm-cli',
    },
  };

  @override
  RuntimeFeatures get features => _features;

  @override
  List<String> get startupNotices => const [];

  @override
  List<ConnectionAdapter> get connectionAdapters => [
    ConnectionAdapter(
      id: 'ui6-inspection-cli',
      label: '自定义 CLI',
      kind: ConnectionKind.cli,
      executionTarget: _target,
      defaultLabel: 'Git CLI',
      description: '仅保存到当前进程内存，不会探测或运行本机命令。',
    ),
    ConnectionAdapter(
      id: 'ui6-inspection-mcp-stdio',
      label: 'stdio MCP',
      kind: ConnectionKind.mcpStdio,
      executionTarget: _target,
      defaultLabel: '项目 MCP',
      description: '仅显示配置，不会启动本机命令。',
    ),
    ConnectionAdapter(
      id: 'ui6-inspection-mcp-http',
      label: 'HTTP MCP',
      kind: ConnectionKind.mcpHttp,
      executionTarget: _target,
      defaultLabel: '项目 MCP',
      description: '仅保存到当前进程内存，不会发起网络请求。',
      showGenericCliFields: false,
    ),
    ConnectionAdapter(
      id: 'ui6-inspection-music',
      label: '网易云音乐',
      kind: ConnectionKind.cli,
      executionTarget: _target,
      defaultLabel: '网易云音乐',
      description: '仅验证配置布局，不会登录或访问网络。',
      showGenericCliFields: false,
      autoDetectExecutable: true,
      fields: const [
        SetupField(key: 'appId', label: '开放平台 App ID'),
        SetupField(
          key: 'privateKey',
          label: 'Private Key（PEM）',
          kind: SetupFieldKind.secret,
          hint: 'Private Key 只用于连接配置，不写入连接清单。',
          readFileContent: true,
        ),
      ],
    ),
  ].where((adapter) => _features.canAdd(adapter.kind)).toList();

  @override
  Future<List<ConnectionSetupTargetOption>> listSetupTargets() async => [
    const ConnectionSetupTargetOption(
      target: ExecutionTarget.device,
      label: '本机 Mac',
      detail: '默认目标 · 在此设备运行',
    ),
    ConnectionSetupTargetOption(
      target: ExecutionTarget.host('ui6-preview-host'),
      label: '示例 Mac Host',
      detail: '已配对 · 连接管理',
    ),
  ];

  @override
  Future<ConnectionSetupPort> setupForTarget(ExecutionTarget target) async {
    _target = target;
    return this;
  }

  @override
  Future<String?> detectExecutable(String adapterId) async =>
      adapterId == 'ui6-inspection-music' ? '/usr/local/bin/ncm-cli' : null;

  @override
  Future<DetectedExecutableSelection?> detectExecutableSelection(
    String adapterId, {
    String? executableName,
  }) async {
    if (_target.kind == ExecutionTargetKind.host &&
        executableName?.isNotEmpty == true) {
      return const DetectedExecutableSelection(
        displayLocation: '示例 Mac Host · 已确认',
        reference: 'ui6-inspection-executable-ref',
      );
    }
    final path = await detectExecutable(adapterId);
    return path == null
        ? null
        : DetectedExecutableSelection(displayLocation: path, path: path);
  }

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
  Future<int> waitAccountLogin(TerminalSession session) =>
      _terminalExitWaiters[session.id]?.future ?? Future<int>.value(0);

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
    _outcomeUnknownRuns.clear();
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
  String? connectionDisplayName(ConnectionId connection) {
    for (final item in _connections) {
      if (item.id.value == connection.value) return item.label;
    }
    return null;
  }

  @override
  String? capabilityDisplayName(CapabilityId capability) {
    for (final item in _seedCapabilities) {
      if (item.id.key == capability.key) return item.title;
    }
    if (capability.key == _resultUnknownCapability.id.key) {
      return _resultUnknownCapability.title;
    }
    return null;
  }

  @override
  Future<RunHandle> invoke(
    CapabilityId id,
    JsonMap arguments, {
    bool permissionGranted = false,
  }) async {
    if (_resultUnknownFixture && id.name == 'inspection-outcome-unknown') {
      final runId = RunId(
        'ui6-inspection-outcome-unknown-${++_outcomeUnknownRunCounter}',
      );
      final event = RunEvent(
        runId: runId,
        sequence: 1,
        state: RunState.outcomeUnknown,
        occurredAt: DateTime.now(),
        failure: const RuntimeFailure(
          RuntimeErrorCode.outcomeUnknown,
          '仅内存预览结果待确认',
        ),
      );
      _outcomeUnknownRuns[runId.value] = RunSummary(
        runId,
        _resultUnknownCapability.id,
        event,
      );
      return RunHandle(runId);
    }
    if (id.name == 'inspection-error') {
      throw StateError('预览错误态：未联系任何执行端');
    }
    return _preview.invoke(id, arguments, permissionGranted: permissionGranted);
  }

  @override
  Stream<RunEvent> watchRun(RunId id) {
    final unknownRun = _outcomeUnknownRuns[id.value];
    if (unknownRun != null) return Stream.value(unknownRun.latest);
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
    final stableRuns = _filterStateActivitiesSeeded
        ? runs.map((run) => _withInspectionTime(run)).toList()
        : runs;
    return [
      ?activity,
      ..._filterStateInspectionActivities,
      ..._outcomeUnknownRuns.values,
      ...stableRuns,
    ];
  }

  RunSummary _withInspectionTime(RunSummary run) {
    final latest = run.latest;
    return RunSummary(
      run.id,
      run.capability,
      RunEvent(
        runId: latest.runId,
        sequence: latest.sequence,
        state: latest.state,
        occurredAt: _inspectionActivityTime,
        blocks: latest.blocks,
        failure: latest.failure,
      ),
    );
  }

  @override
  Future<void> cancel(RunId id) async {
    if (_outcomeUnknownRuns.containsKey(id.value)) return;
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
    _terminalExitWaiters[session.id] = Completer<int>();
    _terminalInitialOutput[session.id] = [
      '\x1B[38;2;216;189;140m'
          'UI 检查终端：全内存模拟，不会运行外部命令。'
          '\x1B[0m\r\n',
      '\$ ${command.arguments.join(' ')}\r\n',
      if (command.arguments.join(' ') == 'git status --short') ...[
        ' M README.md\r\n',
        '?? draft.md\r\n\r\n',
      ],
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
    final exitWaiter = _terminalExitWaiters.remove(session.id);
    if (exitWaiter != null && !exitWaiter.isCompleted) {
      exitWaiter.complete(130);
    }
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
