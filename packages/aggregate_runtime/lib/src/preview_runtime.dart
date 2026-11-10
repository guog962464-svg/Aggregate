import 'dart:async';

import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:aggregate_domain/aggregate_domain.dart';

/// Stage 1 contract implementation. It never starts a process or network call.
final class PreviewRuntime implements RuntimePort {
  @override
  bool get isPreview => true;
  @override
  final RuntimeFeatures features;
  @override
  List<String> get startupNotices => const [];
  PreviewRuntime({
    required List<Connection> connections,
    required List<Capability> capabilities,
    this.latency = const Duration(milliseconds: 120),
    this.features = RuntimeFeatures.localDesktop,
  }) : _connections = List.unmodifiable(connections),
       _catalog = CapabilityCatalog(
         connections: connections,
         capabilities: capabilities,
       );

  final List<Connection> _connections;
  final CapabilityCatalog _catalog;
  final Duration latency;
  final _events = StreamController<RunEvent>.broadcast(sync: true);
  final _histories = <String, List<RunEvent>>{};
  final _lifecycles = <String, RunLifecycle>{};
  final _runCapabilities = <String, CapabilityId>{};
  var _counter = 0;
  UserPreferences _preferences = const UserPreferences();

  @override
  Future<UserPreferences> loadPreferences() async => _preferences;

  @override
  Future<void> savePreferences(UserPreferences preferences) async {
    _preferences = preferences;
  }

  @override
  Future<void> clearActivity() async {
    _histories.clear();
    _runCapabilities.clear();
  }

  @override
  Future<List<Connection>> listConnections() async => List.of(_connections);

  @override
  Future<Connection> addConnection(ConnectionSpec spec) =>
      throw UnsupportedError('预览模式不能添加连接');

  @override
  Future<void> removeConnection(ConnectionId id) =>
      throw UnsupportedError('预览模式不能删除连接');

  @override
  Future<void> moveConnection(ConnectionId id, int offset) =>
      throw UnsupportedError('预览模式不能调整连接顺序');

  @override
  Future<Connection> refreshConnection(ConnectionId id) =>
      throw UnsupportedError('预览模式不能刷新连接');

  @override
  Future<JsonMap?> loadActionManifest(ConnectionId id) =>
      throw UnsupportedError('预览模式不能编辑动作');

  @override
  Future<JsonMap> readActionManifestFile(String path) =>
      throw UnsupportedError('预览模式不能导入动作');

  @override
  Future<void> saveActionManifest(ConnectionId id, JsonMap manifest) =>
      throw UnsupportedError('预览模式不能保存动作');

  @override
  Future<void> exportActionManifest(
    ConnectionId id,
    JsonMap manifest,
    String path,
  ) => throw UnsupportedError('预览模式不能导出动作');

  @override
  Future<List<Capability>> searchCapabilities(SearchQuery query) async =>
      _catalog.search(query);

  @override
  Future<RunHandle> invoke(
    CapabilityId id,
    JsonMap arguments, {
    bool permissionGranted = false,
  }) async {
    final capability = _catalog.byId(id);
    if (capability == null) {
      throw ArgumentError('unknown capability: ${id.key}');
    }
    final runId = RunId(
      'preview-${DateTime.now().microsecondsSinceEpoch}-${++_counter}',
    );
    _histories[runId.value] = [];
    _runCapabilities[runId.value] = id;
    _lifecycles[runId.value] = RunLifecycle(RunState.created);
    _emit(runId, RunState.created);
    _emit(runId, RunState.validating);
    final validationError = _validate(capability.inputSchema, arguments);
    if (validationError != null) {
      _emit(
        runId,
        RunState.failed,
        failure: RuntimeFailure(
          RuntimeErrorCode.invalidArguments,
          validationError,
          phase: 'validation',
        ),
      );
    } else {
      _catalog.markUsed(id);
      _emit(runId, RunState.running);
      unawaited(_complete(runId, capability, arguments));
    }
    return RunHandle(runId);
  }

  Future<void> _complete(
    RunId id,
    Capability capability,
    JsonMap arguments,
  ) async {
    await Future<void>.delayed(latency);
    if (_lifecycles[id.value]?.state != RunState.running) return;
    final blocks = switch (capability.id.name) {
      'add' => [
        ResultBlock(ResultKind.json, {
          'sum': (arguments['a'] as int) + (arguments['b'] as int),
        }),
      ],
      'status' => [const ResultBlock(ResultKind.text, '预览结果：工作区干净')],
      'search' => [
        const ResultBlock(ResultKind.json, {
          'code': 200,
          'data': {
            'records': [
              {
                'id': 'PREVIEW00000000000000000000000001',
                'originalId': 123,
                'name': '示例歌曲',
                'artists': [
                  {'name': '示例歌手'},
                ],
                'playFlag': true,
              },
              {
                'id': 'PREVIEW00000000000000000000000002',
                'originalId': 124,
                'name': '暂不可播放的歌曲',
                'artists': [
                  {'name': '示例歌手'},
                ],
                'playFlag': false,
              },
            ],
          },
        }),
      ],
      'state' => [
        const ResultBlock(ResultKind.json, {
          'success': true,
          'state': {
            'title': '示例歌曲',
            'status': 'playing',
            'progress': '0:12 / 3:20',
            'queueLength': 1,
          },
        }),
      ],
      _ => [ResultBlock(ResultKind.text, '预览结果：${capability.title}')],
    };
    _emit(id, RunState.succeeded, blocks: blocks);
  }

  void _emit(
    RunId id,
    RunState state, {
    List<ResultBlock> blocks = const [],
    RuntimeFailure? failure,
  }) {
    final history = _histories[id.value]!;
    if (history.isNotEmpty) _lifecycles[id.value]!.transition(state);
    final event = RunEvent(
      runId: id,
      sequence: history.length,
      state: state,
      occurredAt: DateTime.now().toUtc(),
      blocks: blocks,
      failure: failure,
    );
    history.add(event);
    _events.add(event);
  }

  @override
  Stream<RunEvent> watchRun(RunId id) {
    if (!_histories.containsKey(id.value)) throw ArgumentError('unknown run');
    return Stream.multi((controller) {
      final subscription = _events.stream
          .where((event) => event.runId.value == id.value)
          .listen(controller.add);
      for (final event in _histories[id.value]!) {
        controller.add(event);
      }
      controller.onCancel = subscription.cancel;
    });
  }

  @override
  Future<List<RunSummary>> listRecentRuns() async {
    final summaries = <RunSummary>[];
    for (final entry in _histories.entries) {
      if (entry.value.isEmpty) continue;
      summaries.add(
        RunSummary(
          RunId(entry.key),
          _runCapabilities[entry.key]!,
          entry.value.last,
        ),
      );
    }
    return summaries.reversed.toList();
  }

  @override
  Future<void> cancel(RunId id) async {
    if (_lifecycles[id.value]?.state == RunState.running) {
      _emit(
        id,
        RunState.cancelled,
        failure: const RuntimeFailure(RuntimeErrorCode.cancelled, '已取消'),
      );
    }
  }

  @override
  Future<List<ResultBlock>> readResource(ResourceRef ref) async {
    if (_catalog.byId(ref.capability)?.id.kind != CapabilityKind.mcpResource) {
      throw ArgumentError('unknown resource');
    }
    return [ResultBlock(ResultKind.text, '预览资源：${ref.uri}')];
  }

  @override
  Future<List<ResultBlock>> getPrompt(PromptRef ref, JsonMap arguments) async {
    if (_catalog.byId(ref.capability)?.id.kind != CapabilityKind.mcpPrompt) {
      throw ArgumentError('unknown prompt');
    }
    return [ResultBlock(ResultKind.text, '预览提示：${arguments['topic'] ?? ''}')];
  }

  @override
  Future<List<ResultBlock>> previewLocalFile(String path) async => [
    ResultBlock(ResultKind.text, '预览文件：$path'),
  ];

  @override
  Future<void> revealLocalFile(String path) async =>
      throw UnsupportedError('预览模式不能打开访达');

  @override
  Future<TerminalSession> openTerminal(CliCommand command) async {
    throw UnsupportedError('终端会话将在阶段 2 接入');
  }

  @override
  Stream<String> watchTerminal(TerminalSession session) =>
      throw UnsupportedError('预览模式没有终端');

  @override
  Future<void> writeTerminal(TerminalSession session, String text) =>
      throw UnsupportedError('预览模式没有终端');

  @override
  Future<void> resizeTerminal(TerminalSession session, int columns, int rows) =>
      throw UnsupportedError('预览模式没有终端');

  @override
  Future<void> interruptTerminal(TerminalSession session) =>
      throw UnsupportedError('预览模式没有终端');

  @override
  Future<void> closeTerminal(TerminalSession session) =>
      throw UnsupportedError('预览模式没有终端');

  Future<void> dispose() async => _events.close();
}

String? _validate(JsonMap schema, JsonMap arguments) {
  if (schema.isEmpty) return null;
  final properties = schema['properties'];
  if (properties is! Map) return '输入规则无效';
  final required = schema['required'];
  if (required is List) {
    for (final field in required) {
      if (!arguments.containsKey(field)) return '缺少必填参数：$field';
    }
  }
  for (final entry in arguments.entries) {
    final specification = properties[entry.key];
    if (specification is! Map) return '未知参数：${entry.key}';
    final matches = switch (specification['type']) {
      'string' => entry.value is String,
      'integer' => entry.value is int,
      'number' => entry.value is num,
      'boolean' => entry.value is bool,
      _ => false,
    };
    if (!matches) return '参数类型不正确：${entry.key}';
  }
  return null;
}
