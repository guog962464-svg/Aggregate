import 'dart:async';

import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app/shortcut_scheme.dart';
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
  });
  final RuntimePort runtime;
  final Capability capability;
  final MusicSession? musicSession;
  final VoidCallback? onSearchAll;
  @override
  State<CapabilityRunPage> createState() => _CapabilityRunPageState();
}

String _permissionLabel(PermissionLevel permission) => switch (permission) {
  PermissionLevel.read => '读取',
  PermissionLevel.localControl => '本机控制',
  PermissionLevel.externalWrite => '外部写入',
  PermissionLevel.unknown => '未分类',
};

class _CapabilityRunPageState extends State<CapabilityRunPage> {
  final form = GlobalKey<SchemaFormState>();
  StreamSubscription<RunEvent>? subscription;
  RunHandle? handle;
  RunState? state;
  List<ResultBlock> blocks = [];
  RuntimeFailure? failure;
  String? sourceLabel;
  String? sourceLocation;

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
    widget.runtime.listConnections().then((connections) {
      if (!mounted) return;
      for (final connection in connections) {
        if (connection.id.value == widget.capability.id.connection.value) {
          setState(() {
            sourceLabel = connection.label;
            sourceLocation = connection.location;
          });
          return;
        }
      }
    });
  }

  @override
  void dispose() {
    subscription?.cancel();
    super.dispose();
  }

  Future<void> run() async {
    if (!(form.currentState?.validate() ?? true)) return;
    await subscription?.cancel();
    final arguments = form.currentState?.arguments() ?? <String, Object?>{};
    var permissionGranted = false;
    if (!widget.runtime.isPreview &&
        widget.capability.permission != PermissionLevel.read &&
        widget.capability.id.kind != CapabilityKind.mcpResource &&
        widget.capability.id.kind != CapabilityKind.mcpPrompt) {
      permissionGranted = await _confirmExecution(arguments);
      if (!permissionGranted || !mounted) return;
    }
    setState(() {
      state = RunState.running;
      blocks = [];
      failure = null;
      handle = null;
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
      subscription = widget.runtime.watchRun(handle!.id).listen((event) {
        if (!mounted) return;
        setState(() {
          state = event.state;
          if (event.blocks.isNotEmpty) blocks = event.blocks;
          failure = event.failure;
        });
        widget.musicSession?.observe(widget.capability, event);
      });
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
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('确认执行'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: SingleChildScrollView(
              child: Text(
                '功能：${(capability ?? widget.capability).title}\n'
                '来源：${sourceLabel ?? widget.capability.id.connection.value}\n'
                '目标：${sourceLocation ?? '当前连接'}\n'
                '权限：${_permissionLabel((capability ?? widget.capability).permission)}\n'
                '参数：$arguments\n\n'
                '此操作可能读取本机数据或产生外部写入。',
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('执行'),
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
    if (!await _confirmExecution(arguments) || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TerminalPage(
          runtime: widget.runtime,
          source: sourceLabel ?? widget.capability.title,
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
    if (current != null) await widget.runtime.cancel(current.id);
  }

  @override
  Widget build(BuildContext context) {
    final kind = widget.capability.id.kind;
    final action = kind == CapabilityKind.mcpResource
        ? '读取'
        : kind == CapabilityKind.mcpPrompt
        ? '预览提示'
        : '运行';
    return Scaffold(
      appBar: AppBar(title: Text(widget.capability.title)),
      bottomNavigationBar: widget.musicSession == null
          ? null
          : MusicMiniPlayer(session: widget.musicSession!),
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
                      SchemaForm(
                        key: form,
                        schema: widget.capability.inputSchema,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.icon(
                            onPressed: state == RunState.running ? null : run,
                            icon: const Icon(Icons.play_arrow, size: 18),
                            label: Text(
                              state == RunState.running ? '运行中…' : action,
                            ),
                          ),
                          if (kind == CapabilityKind.cliCommand &&
                              !widget.runtime.isPreview &&
                              widget.runtime.features.terminal)
                            OutlinedButton.icon(
                              onPressed: openTerminal,
                              icon: const Icon(Icons.terminal, size: 18),
                              label: const Text('在终端运行'),
                            ),
                          if (state == RunState.running && handle != null)
                            OutlinedButton(
                              onPressed: cancel,
                              child: const Text('取消'),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '运行快捷键  ${ShortcutScheme(defaultTargetPlatform).runLabel}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  );
                  final musicItems =
                      widget.capability.presentation == 'music.search'
                      ? parseMusicSearchResults(blocks)
                      : const <MusicSearchItem>[];
                  final resultPane = Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Theme.of(context).dividerColor),
                    ),
                    child: musicItems.isEmpty
                        ? ResultPanel(
                            state: state,
                            blocks: blocks,
                            failure: failure,
                            runtime: widget.runtime,
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
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                  );
                  if (constraints.maxWidth < 760) {
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
