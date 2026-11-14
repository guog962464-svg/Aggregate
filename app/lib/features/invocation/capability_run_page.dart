import 'dart:async';
import 'dart:convert';

import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app/shortcut_scheme.dart';
import '../../widgets/glass/aggregate_buttons.dart';
import '../../widgets/page_frame.dart';
import '../../widgets/result_panel.dart';
import '../music/music_mini_player.dart';
import '../music/music_search_results.dart';
import '../music/music_session.dart';
import 'schema_form.dart';
import 'terminal_page.dart';

class CapabilityRunPage extends StatefulWidget {
  const CapabilityRunPage({
    super.key,
    required this.runtime,
    required this.capability,
    this.musicSession,
    this.onSearchAll,
    this.onOpenMusic,
    this.embedded = false,
  });
  final RuntimePort runtime;
  final Capability capability;
  final MusicSession? musicSession;
  final VoidCallback? onSearchAll;
  final VoidCallback? onOpenMusic;
  final bool embedded;
  @override
  State<CapabilityRunPage> createState() => _CapabilityRunPageState();
}

String _permissionLabel(PermissionLevel permission) => switch (permission) {
  PermissionLevel.read => '只读',
  PermissionLevel.localControl => '运行端控制',
  PermissionLevel.externalWrite => '外部写入',
  PermissionLevel.unknown => '权限待确认',
};

String _permissionExplanation(PermissionLevel permission) =>
    switch (permission) {
      PermissionLevel.read => '此功能声明为只读；仍请确认参数和数据来源。',
      PermissionLevel.localControl => '此功能可能控制执行设备上的程序或状态。',
      PermissionLevel.externalWrite => '此功能可能向外部服务写入或提交数据。',
      PermissionLevel.unknown => '此功能的权限级别尚未分类，请先核对来源和参数。',
    };

bool _sensitiveKey(String key) => RegExp(
  r'(password|passwd|secret|token|api.?key|authorization|credential)',
  caseSensitive: false,
).hasMatch(key);

bool _isRestorableRunState(RunState state) => switch (state) {
  RunState.created ||
  RunState.validating ||
  RunState.awaitingPermission ||
  RunState.running ||
  RunState.outcomeUnknown => true,
  RunState.succeeded ||
  RunState.failed ||
  RunState.cancelled ||
  RunState.timedOut => false,
};

bool _isActiveRunState(RunState? state) => switch (state) {
  RunState.created ||
  RunState.validating ||
  RunState.awaitingPermission ||
  RunState.running => true,
  null ||
  RunState.succeeded ||
  RunState.failed ||
  RunState.cancelled ||
  RunState.timedOut ||
  RunState.outcomeUnknown => false,
};

Object? _redactNestedValue(Object? value) {
  if (value is Map) {
    return {
      for (final entry in value.entries)
        if (entry.key is String)
          entry.key as String: _sensitiveKey(entry.key as String)
              ? '••••••'
              : _redactNestedValue(entry.value),
    };
  }
  if (value is List) return value.map(_redactNestedValue).toList();
  return value;
}

List<String> _redactCliArguments(List<String> arguments) {
  final result = <String>[];
  var hideNext = false;
  for (final argument in arguments) {
    if (hideNext) {
      result.add('••••••');
      hideNext = false;
      continue;
    }
    final equals = argument.indexOf('=');
    final flag = equals < 0 ? argument : argument.substring(0, equals);
    if (_sensitiveKey(flag)) {
      if (equals < 0) {
        result.add(argument);
        hideNext = true;
      } else {
        result.add('${argument.substring(0, equals + 1)}••••••');
      }
    } else {
      result.add(argument);
    }
  }
  return result;
}

JsonMap _redactArguments(JsonMap arguments, JsonMap schema) {
  final rawProperties = schema['properties'];
  final properties = rawProperties is Map
      ? Map<String, Object?>.from(rawProperties)
      : const <String, Object?>{};
  return {
    for (final entry in arguments.entries)
      entry.key: () {
        final rawSpec = properties[entry.key];
        final spec = rawSpec is Map ? rawSpec : const {};
        final explicitlySensitive =
            spec['writeOnly'] == true || spec['format'] == 'password';
        if (explicitlySensitive || _sensitiveKey(entry.key)) {
          return '••••••';
        }
        if (entry.key == 'argv' && entry.value is List) {
          final argv = entry.value as List;
          if (argv.every((value) => value is String)) {
            return _redactCliArguments(argv.cast<String>());
          }
        }
        return _redactNestedValue(entry.value);
      }(),
  };
}

String _prettyArguments(JsonMap arguments, JsonMap schema) =>
    const JsonEncoder.withIndent('  ')
        .convert(_redactArguments(arguments, schema));

class _CapabilityRunPageState extends State<CapabilityRunPage> {
  final form = GlobalKey<SchemaFormState>();
  StreamSubscription<RunEvent>? subscription;
  RunHandle? handle;
  RunState? state;
  List<ResultBlock> blocks = [];
  RuntimeFailure? failure;
  String? sourceLabel;
  String executionLabel = '执行端待确认';
  JsonMap? submittedArguments;
  bool checkingActivity = false;

  Future<void> playSong(MusicSearchItem song) async {
    final session = widget.musicSession;
    if (session == null) return;
    await session.attach(widget.capability);
    final play = session.actions['music.play'];
    if (play == null || !mounted) return;
    final arguments = <String, Object?>{
      'encryptedId': song.id,
      'originalId': song.originalId,
    };
    if (!widget.runtime.isPreview &&
        !await _confirmExecution(arguments, capability: play)) {
      return;
    }
    session.prepareTrack(song.name, song.artist);
    await session.execute('play', arguments);
  }

  Future<void> queueSong(MusicSearchItem song) async {
    final session = widget.musicSession;
    if (session == null) return;
    await session.attach(widget.capability);
    final queue = session.actions['music.queueAdd'];
    if (queue == null || !mounted) return;
    final arguments = <String, Object?>{
      'encryptedId': song.id,
      'originalId': song.originalId,
    };
    if (!widget.runtime.isPreview &&
        !await _confirmExecution(arguments, capability: queue)) {
      return;
    }
    await session.execute('queueAdd', arguments);
  }

  @override
  void initState() {
    super.initState();
    if (widget.capability.presentation?.startsWith('music.') == true) {
      unawaited(widget.musicSession?.attach(widget.capability));
    }
    widget.runtime
        .listConnections()
        .then((connections) {
          if (!mounted) return;
          for (final connection in connections) {
            if (connection.id.value == widget.capability.id.connection.value) {
              setState(() {
                sourceLabel = connection.label;
                executionLabel = widget.runtime.isPreview
                    ? '预览运行时'
                    : connection.executionTarget.kind ==
                          ExecutionTargetKind.host
                    ? '配对 Mac'
                    : '此设备';
              });
              return;
            }
          }
          setState(() {
            executionLabel = widget.runtime.isPreview ? '预览运行时' : '执行端未知';
          });
        })
        .catchError((Object _) {
          if (!mounted) return;
          setState(() {
            executionLabel = widget.runtime.isPreview ? '预览运行时' : '执行端未知';
          });
        });
    unawaited(_restoreRecentRun());
  }

  Future<void> _restoreRecentRun() async {
    try {
      final summaries = await widget.runtime.listRecentRuns();
      if (!mounted || state != null || handle != null) return;
      for (final summary in summaries) {
        if (summary.capability.key != widget.capability.id.key ||
            !_isRestorableRunState(summary.latest.state)) {
          continue;
        }
        setState(() {
          handle = RunHandle(summary.id);
          state = summary.latest.state;
          blocks = summary.latest.blocks;
          failure = summary.latest.failure;
        });
        _watchRun(summary.id);
        return;
      }
    } catch (_) {
      // Activity is a recovery aid; the form remains usable if it is offline.
    }
  }

  @override
  void dispose() {
    subscription?.cancel();
    super.dispose();
  }

  Future<void> run() async {
    if (_isActiveRunState(state)) return;
    if (!(form.currentState?.validate() ?? true)) return;
    await subscription?.cancel();
    final arguments = form.currentState?.arguments() ?? <String, Object?>{};
    var permissionGranted = false;
    final needsPermission =
        widget.capability.permission != PermissionLevel.read &&
        widget.capability.id.kind != CapabilityKind.mcpResource &&
        widget.capability.id.kind != CapabilityKind.mcpPrompt;
    final retryingUnknownOutcome = state == RunState.outcomeUnknown;
    if (!widget.runtime.isPreview &&
        (needsPermission || retryingUnknownOutcome)) {
      final accepted = await _confirmExecution(
        arguments,
        retryingUnknownOutcome: retryingUnknownOutcome,
      );
      if (!accepted || !mounted) return;
      permissionGranted = needsPermission;
    }
    setState(() {
      state = RunState.running;
      blocks = [];
      failure = null;
      handle = null;
      submittedArguments = _redactArguments(
        arguments,
        widget.capability.inputSchema,
      );
    });
    final started = Stopwatch()..start();
    try {
      if (widget.capability.id.kind == CapabilityKind.mcpResource) {
        final result = await widget.runtime.readResource(
          ResourceRef(
            widget.capability.id,
            Uri.parse(
              widget.runtime.isPreview
                  ? 'memo://preview/readme'
                  : widget.capability.id.name,
            ),
          ),
        );
        if (mounted) {
          setState(() {
            blocks = [
              ...result,
              ResultBlock(ResultKind.json, {
                'durationMs': started.elapsedMilliseconds,
              }),
            ];
            state = RunState.succeeded;
          });
        }
        return;
      }
      if (widget.capability.id.kind == CapabilityKind.mcpPrompt) {
        final result = await widget.runtime.getPrompt(
          PromptRef(widget.capability.id),
          arguments,
        );
        if (mounted) {
          setState(() {
            blocks = [
              ...result,
              ResultBlock(ResultKind.json, {
                'durationMs': started.elapsedMilliseconds,
              }),
            ];
            state = RunState.succeeded;
          });
        }
        return;
      }
      handle = await widget.runtime.invoke(
        widget.capability.id,
        arguments,
        permissionGranted: permissionGranted,
      );
      _watchRun(handle!.id);
    } catch (cause) {
      if (mounted) {
        setState(() {
          state = RunState.failed;
          failure = RuntimeFailure(RuntimeErrorCode.internal, '$cause');
        });
      }
    }
  }

  Future<bool> _confirmExecution(
    JsonMap arguments, {
    Capability? capability,
    bool retryingUnknownOutcome = false,
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(retryingUnknownOutcome ? '确认重新执行' : '确认执行'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440, maxHeight: 480),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '功能：${(capability ?? widget.capability).title}\n'
                    '来源：${sourceLabel ?? widget.capability.id.connection.value}\n'
                    '执行端：$executionLabel\n'
                    '权限：${_permissionLabel((capability ?? widget.capability).permission)}',
                  ),
                  if (retryingUnknownOutcome) ...[
                    const SizedBox(height: 12),
                    const Text('上一次调用结果仍未知。重新执行可能重复外部写入；请先确认执行端状态。'),
                  ],
                  const SizedBox(height: 16),
                  const Text('提交参数（密钥字段已隐藏）'),
                  const SizedBox(height: 6),
                  SelectableText(
                    _prettyArguments(
                      arguments,
                      (capability ?? widget.capability).inputSchema,
                    ),
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _permissionExplanation(
                      (capability ?? widget.capability).permission,
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            AggregateActionButton(
              label: '取消',
              icon: Icons.close,
              style: AggregateActionStyle.quiet,
              onPressed: () => Navigator.pop(context, false),
            ),
            AggregateActionButton(
              label: retryingUnknownOutcome ? '仍然执行' : '执行',
              icon: Icons.play_arrow_rounded,
              style: AggregateActionStyle.primary,
              onPressed: () => Navigator.pop(context, true),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> openTerminal() async {
    if (!(form.currentState?.validate() ?? true)) return;
    final arguments = form.currentState?.arguments() ?? <String, Object?>{};
    final argv = arguments['argv'];
    if (argv is! List || argv.any((item) => item is! String)) return;
    if (!await _confirmExecution(
          arguments,
          retryingUnknownOutcome: state == RunState.outcomeUnknown,
        ) ||
        !mounted) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TerminalPage(
          runtime: widget.runtime,
          source: sourceLabel ?? widget.capability.title,
          executionTarget: executionLabel,
          permission: widget.capability.permission,
          command: CliCommand(
            widget.capability.id.connection,
            argv.cast<String>(),
          ),
        ),
      ),
    );
  }

  Future<void> cancel() async {
    final current = handle;
    if (current == null) return;
    try {
      await widget.runtime.cancel(current.id);
    } catch (cause) {
      _markOutcomeUnknown(cause);
    }
  }

  void _markOutcomeUnknown(Object cause) {
    if (!mounted) return;
    setState(() {
      state = RunState.outcomeUnknown;
      failure = RuntimeFailure(
        RuntimeErrorCode.outcomeUnknown,
        '未能收到运行终态：$cause',
      );
    });
  }

  void _watchRun(RunId runId) {
    unawaited(subscription?.cancel());
    try {
      subscription = widget.runtime
          .watchRun(runId)
          .listen(
            (event) {
              if (!mounted || event.runId.value != runId.value) return;
              setState(() {
                state = event.state;
                if (event.blocks.isNotEmpty) blocks = event.blocks;
                failure = event.failure;
              });
              widget.musicSession?.observe(widget.capability, event);
            },
            onError: (Object cause) => _markOutcomeUnknown(cause),
            onDone: () {
              if (mounted && state != null && _isRestorableRunState(state!)) {
                _markOutcomeUnknown('执行状态流提前结束');
              }
            },
            cancelOnError: true,
          );
    } catch (cause) {
      _markOutcomeUnknown(cause);
    }
  }

  Future<void> _checkActivityStatus() async {
    final current = handle;
    if (current == null || checkingActivity) return;
    setState(() => checkingActivity = true);
    try {
      final summaries = await widget.runtime.listRecentRuns();
      if (!mounted) return;
      RunSummary? matching;
      for (final summary in summaries) {
        if (summary.id.value == current.id.value) {
          matching = summary;
          break;
        }
      }
      if (matching == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('活动记录尚未提供终态；未重新执行，请稍后再检查执行端。')),
        );
        return;
      }
      final summary = matching;
      setState(() {
        state = summary.latest.state;
        if (summary.latest.blocks.isNotEmpty) {
          blocks = summary.latest.blocks;
        }
        failure = summary.latest.failure;
      });
      if (summary.latest.state == RunState.outcomeUnknown) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('结果仍未知；请先在执行端确认，不要直接重跑。')));
      }
    } catch (cause) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('检查活动状态失败：$cause')));
      }
    } finally {
      if (mounted) setState(() => checkingActivity = false);
    }
  }

  Widget _executionContext() => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Theme.of(context).dividerColor),
    ),
    child: Wrap(
      spacing: 20,
      runSpacing: 12,
      children: [
        _contextValue(
          '来源',
          sourceLabel ?? widget.capability.id.connection.value,
        ),
        _contextValue('执行端', executionLabel),
        _contextValue('权限', _permissionLabel(widget.capability.permission)),
      ],
    ),
  );

  Widget _contextValue(String label, String value) => SizedBox(
    width: 150,
    child: Semantics(
      label: '$label：$value',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 2),
          Text(value, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    ),
  );

  Widget _actionControls(String action, {required bool compact}) {
    final kind = widget.capability.id.kind;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        AggregateActionButton(
          style: AggregateActionStyle.primary,
          onPressed: _isActiveRunState(state) ? null : run,
          icon: Icons.play_arrow,
          label: _isActiveRunState(state) ? '运行中…' : action,
        ),
        if (kind == CapabilityKind.cliCommand &&
            !widget.runtime.isPreview &&
            widget.runtime.features.terminal)
          AggregateActionButton(
            style: AggregateActionStyle.secondary,
            onPressed: _isActiveRunState(state) ? null : openTerminal,
            icon: Icons.terminal,
            label: compact ? '终端' : '在终端运行',
          ),
        if (_isActiveRunState(state) && handle != null)
          AggregateActionButton(
            style: AggregateActionStyle.secondary,
            onPressed: cancel,
            icon: Icons.stop_circle_outlined,
            label: '取消',
          ),
      ],
    );
  }

  Widget _submittedArguments() => ExpansionTile(
    tilePadding: EdgeInsets.zero,
    title: const Text('本次提交参数（密钥字段已隐藏）'),
    children: [
      ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 240),
        child: SingleChildScrollView(
          child: SelectableText(
            const JsonEncoder.withIndent('  ').convert(submittedArguments),
            style: const TextStyle(fontFamily: 'monospace'),
          ),
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final compactPhone = MediaQuery.sizeOf(context).width < 600;
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final kind = widget.capability.id.kind;
    final action = kind == CapabilityKind.mcpResource
        ? '读取'
        : kind == CapabilityKind.mcpPrompt
        ? '预览提示'
        : '运行';
    return Scaffold(
      appBar: widget.embedded
          ? null
          : AppBar(title: Text(widget.capability.title)),
      bottomNavigationBar: widget.embedded
          ? null
          : compactPhone
          ? AnimatedPadding(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              padding: EdgeInsets.only(bottom: keyboardInset),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Material(
                      color: Theme.of(context).colorScheme.surface,
                      elevation: 6,
                      child: SizedBox(
                        width: double.infinity,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                          child: _actionControls(action, compact: true),
                        ),
                      ),
                    ),
                    if (widget.musicSession != null)
                      MusicMiniPlayer(
                        session: widget.musicSession!,
                        onOpen: widget.onOpenMusic,
                      ),
                  ],
                ),
              ),
            )
          : widget.musicSession == null
          ? null
          : MusicMiniPlayer(
              session: widget.musicSession!,
              onOpen: widget.onOpenMusic,
            ),
      body: CallbackShortcuts(
        bindings: {
          ShortcutScheme(defaultTargetPlatform).run: run,
          if (widget.onSearchAll != null)
            ShortcutScheme(defaultTargetPlatform).search: widget.onSearchAll!,
        },
        child: Focus(
          autofocus: true,
          child: PageFrame(
            title: widget.capability.title,
            subtitle:
                '${widget.capability.description} · ${sourceLabel ?? widget.capability.id.connection.value}'
                '${widget.runtime.isPreview ? ' · 预览数据' : ''}',
            children: [
              _executionContext(),
              const SizedBox(height: 20),
              if (widget.capability.presentation?.startsWith('music.') ==
                      true &&
                  widget.capability.presentation != 'music.search' &&
                  widget.musicSession != null) ...[
                MusicRunPanel(session: widget.musicSession!),
              ],
              LayoutBuilder(
                builder: (context, constraints) {
                  final formPane = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '参数',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 16),
                      AbsorbPointer(
                        absorbing: _isActiveRunState(state),
                        child: SchemaForm(
                          key: form,
                          schema: widget.capability.inputSchema,
                        ),
                      ),
                      if (!compactPhone) ...[
                        const SizedBox(height: 8),
                        _actionControls(action, compact: false),
                        const SizedBox(height: 12),
                        Text(
                          '运行快捷键  ${ShortcutScheme(defaultTargetPlatform).runLabel}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ],
                  );
                  final musicItems =
                      widget.capability.presentation == 'music.search'
                      ? parseMusicSearchResults(blocks)
                      : const <MusicSearchItem>[];
                  final resultPane = Material(
                    color: Theme.of(context).colorScheme.surface,
                    shape: RoundedRectangleBorder(
                      side: BorderSide(color: Theme.of(context).dividerColor),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: musicItems.isEmpty
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (submittedArguments != null)
                                  _submittedArguments(),
                                if (handle != null &&
                                    submittedArguments == null)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: Text(
                                      '已从活动记录恢复运行状态；原始参数不会保存在活动记录中。',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall,
                                    ),
                                  ),
                                ResultPanel(
                                  state: state,
                                  blocks: blocks,
                                  failure: failure,
                                  runtime: widget.runtime,
                                  onCheckActivity: _checkActivityStatus,
                                  activityCheckInProgress: checkingActivity,
                                ),
                              ],
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (widget.musicSession case final session?)
                                  AnimatedBuilder(
                                    animation: session,
                                    builder: (context, _) => MusicSearchResults(
                                      items: musicItems,
                                      onPlay: playSong,
                                      onQueue:
                                          session.queueLength > 0 &&
                                              session.actions.containsKey(
                                                'music.queueAdd',
                                              )
                                          ? queueSong
                                          : null,
                                      busy: session.busy,
                                    ),
                                  )
                                else
                                  MusicSearchResults(
                                    items: musicItems,
                                    onPlay: playSong,
                                    busy: false,
                                  ),
                                Material(
                                  type: MaterialType.transparency,
                                  child: ExpansionTile(
                                    title: const Text('原始结果'),
                                    tilePadding: EdgeInsets.zero,
                                    children: [
                                      ResultPanel(
                                        state: state,
                                        blocks: blocks,
                                        failure: failure,
                                        runtime: widget.runtime,
                                        onCheckActivity: _checkActivityStatus,
                                        activityCheckInProgress:
                                            checkingActivity,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                    ),
                  );
                  if (widget.embedded || constraints.maxWidth < 760) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        formPane,
                        const SizedBox(height: 28),
                        resultPane,
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 5, child: formPane),
                      const SizedBox(width: 28),
                      Expanded(flex: 5, child: resultPane),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
