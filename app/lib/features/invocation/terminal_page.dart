import 'dart:async';
import 'dart:convert';

import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:terminal_view/terminal_view.dart';

import '../../widgets/glass/aggregate_buttons.dart';
import '../../widgets/glass/glass_action_button.dart';
import '../../widgets/glass/glass_design_tokens.dart';
import '../../widgets/glass/glass_motion.dart';

const _maxClipboardBytes = 256 * 1024;

class TerminalPage extends StatefulWidget {
  const TerminalPage({
    super.key,
    required this.runtime,
    required this.command,
    required this.source,
    this.executionTarget = '此设备',
    this.permission = PermissionLevel.localControl,
  });

  final RuntimePort runtime;
  final CliCommand command;
  final String source;
  final String executionTarget;
  final PermissionLevel permission;

  String get _displayCommand => _redactCommandArguments(command.arguments);

  @override
  State<TerminalPage> createState() => _TerminalPageState();
}

class _TerminalPageState extends State<TerminalPage> {
  late final Terminal _terminal;
  late final TerminalController _terminalController;
  late final FocusNode _focusNode;

  TerminalSession? _session;
  StreamSubscription<String>? _subscription;
  Future<void> _writeQueue = Future<void>.value();
  Future<void> _resizeQueue = Future<void>.value();
  String? _startupError;
  String? _connectionMessage;
  bool _connected = false;
  bool _ctrlPending = false;
  bool _closeRequested = false;

  bool get _hasSelection {
    final selection = _terminalController.selection;
    return selection != null && !selection.isCollapsed;
  }

  bool _usesGlassButtons(BuildContext context) =>
      defaultTargetPlatform == TargetPlatform.macOS &&
      GlassMotionScope.maybeOf(context) != null;

  @override
  void initState() {
    super.initState();
    _terminal = Terminal(maxLines: 2000);
    _terminalController = TerminalController();
    _terminalController.addListener(_selectionChanged);
    _focusNode = FocusNode();
    _terminal.onOutput = _sendInput;
    _terminal.onResize = (columns, rows, _, _) {
      if (columns > 0 && rows > 0) _resize(columns, rows);
    };
    unawaited(_start());
  }

  Future<void> _start() async {
    try {
      final opened = await widget.runtime.openTerminal(widget.command);
      if (!mounted) {
        await widget.runtime.closeTerminal(opened);
        return;
      }

      _session = opened;
      final output = widget.runtime.watchTerminal(opened);
      _subscription = output.listen(
        _receiveOutput,
        onError: (Object cause) {
          _markDisconnected('终端连接中断：$cause');
        },
        onDone: () => _markDisconnected('终端会话已结束，输出仍可查看。'),
        cancelOnError: true,
      );
      setState(() => _connected = true);
      _resize(_terminal.viewWidth, _terminal.viewHeight);
    } catch (cause) {
      if (!mounted) return;
      if (_session == null) {
        setState(() => _startupError = '$cause');
      } else {
        _markDisconnected('终端连接中断：$cause');
      }
    }
  }

  void _receiveOutput(String text) {
    if (!mounted) return;
    _terminal.write(text);
  }

  void _selectionChanged() {
    if (mounted) setState(() {});
  }

  void _sendInput(String text) {
    final current = _session;
    if (!_connected || current == null || text.isEmpty) return;

    var output = text;
    final controlCode = _ctrlPending ? _controlCode(text) : null;
    if (controlCode != null) {
      output = String.fromCharCode(controlCode);
      setState(() => _ctrlPending = false);
    }

    _writeQueue = _writeQueue
        .then((_) async {
          if (!_connected || _session != current) return;
          await widget.runtime.writeTerminal(current, output);
        })
        .catchError((Object cause) {
          _markDisconnected('终端输入失败：$cause');
        });
  }

  int? _controlCode(String text) {
    if (text.length != 1) return null;
    final code = text.codeUnitAt(0);
    if ((code >= 0x41 && code <= 0x5a) || (code >= 0x61 && code <= 0x7a)) {
      return code & 0x1f;
    }
    if (code >= 0x40 && code <= 0x5f) return code & 0x1f;
    if (code == 0x3f) return 0x7f;
    return null;
  }

  void _resize(int columns, int rows) {
    final current = _session;
    if (!_connected || current == null) return;
    _resizeQueue = _resizeQueue
        .then((_) async {
          if (!_connected || _session != current) return;
          await widget.runtime.resizeTerminal(current, columns, rows);
        })
        .catchError((Object cause) {
          _markDisconnected('终端尺寸同步失败：$cause');
        });
  }

  void _sendKey(TerminalKey key) {
    if (!_connected) return;
    final useControl = _ctrlPending;
    if (useControl) setState(() => _ctrlPending = false);
    _terminal.keyInput(key, ctrl: useControl);
    _focusNode.requestFocus();
  }

  Future<void> _interrupt() async {
    final current = _session;
    if (!_connected || current == null) return;
    try {
      await widget.runtime.interruptTerminal(current);
    } catch (cause) {
      _markDisconnected('中断终端失败：$cause');
    }
  }

  Future<void> _copySelection() async {
    final selection = _terminalController.selection;
    if (selection == null || selection.isCollapsed) return;
    final text = _terminal.buffer.getText(selection);
    if (text.isEmpty) {
      _showMessage('所选区域没有可复制的文本');
      return;
    }
    if (utf8.encode(text).length > _maxClipboardBytes) {
      _showMessage('选中内容超过 256 KiB，请缩小选择范围');
      return;
    }
    try {
      await Clipboard.setData(ClipboardData(text: text));
      _showMessage('已复制终端文本');
    } catch (cause) {
      _showMessage('复制失败：$cause');
    }
  }

  Future<void> _pasteClipboard() async {
    if (!_connected) return;
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (!mounted || !_connected) return;
      final text = data?.text;
      if (text == null || text.isEmpty) {
        _showMessage('剪贴板没有文本');
        return;
      }
      if (utf8.encode(text).length > _maxClipboardBytes) {
        _showMessage('粘贴内容超过 256 KiB，未发送');
        return;
      }
      _terminal.paste(text);
      _focusNode.requestFocus();
    } catch (cause) {
      _showMessage('读取剪贴板失败：$cause');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _markDisconnected(String message) {
    if (!_connected && _connectionMessage != null) return;
    if (mounted) {
      setState(() {
        _connected = false;
        _ctrlPending = false;
        _connectionMessage = message;
      });
    } else {
      _connected = false;
      _ctrlPending = false;
      _connectionMessage = message;
    }
    final subscription = _subscription;
    _subscription = null;
    if (subscription != null) unawaited(subscription.cancel());
    final current = _session;
    if (current != null) unawaited(_close(current));
  }

  Future<void> _close(TerminalSession current) async {
    if (_closeRequested) return;
    _closeRequested = true;
    try {
      await widget.runtime.closeTerminal(current);
    } catch (_) {
      // A disconnected Host may already have closed the remote PTY.
    }
  }

  @override
  void dispose() {
    _connected = false;
    final current = _session;
    if (current != null) unawaited(_close(current));
    unawaited(_subscription?.cancel());
    _terminalController
      ..removeListener(_selectionChanged)
      ..dispose();
    _focusNode.dispose();
    _terminal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _usesGlassButtons(context)
      ? _buildMacOS(context)
      : _buildStandard(context);

  Widget _buildStandard(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('终端'),
      actions: [
        if (_usesGlassButtons(context))
          AggregateIconButton(
            tooltip: '中断程序',
            icon: Icons.stop_circle_outlined,
            onPressed: _connected ? _interrupt : null,
            enabled: _connected,
          )
        else
          IconButton(
            tooltip: '中断程序',
            onPressed: _connected ? _interrupt : null,
            icon: const Icon(Icons.stop_circle_outlined),
          ),
      ],
    ),
    body: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.terminal, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${widget.source}  ${widget._displayCommand}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontFamily: 'monospace'),
                        ),
                        const SizedBox(height: 2),
                        Semantics(
                          label:
                              '执行端：${widget.executionTarget}；权限：${_permissionLabel(widget.permission)}',
                          child: Text(
                            '执行端：${widget.executionTarget} · 权限：${_permissionLabel(widget.permission)}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _connected
                        ? '交互会话'
                        : _session == null
                        ? '正在启动'
                        : '已断开',
                  ),
                ],
              ),
              if (_ctrlPending) ...[
                const SizedBox(height: 4),
                Text(
                  'Ctrl 已按下，点按一个按键以发送控制字符',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
              if (_connectionMessage case final message?) ...[
                const SizedBox(height: 4),
                Text(
                  message,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: _startupError != null && _session == null
                ? Center(child: Text(_startupError!))
                : _session == null
                ? const Center(child: CircularProgressIndicator())
                : _terminalView(padding: const EdgeInsets.all(4)),
          ),
        ),
        _buildToolbar(context),
      ],
    ),
  );

  Widget _buildMacOS(BuildContext context) => Scaffold(
    backgroundColor: Colors.transparent,
    body: LayoutBuilder(
      builder: (context, constraints) {
        final terminalHeight = (constraints.maxHeight - 340)
            .clamp(320.0, 508.0)
            .toDouble();
        final tokens = Theme.of(context).extension<GlassDesignTokens>();
        return Padding(
          padding: const EdgeInsets.only(top: 43, bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(48, 0, 48, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '终端',
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(fontSize: 19),
                          ),
                          const SizedBox(height: 19),
                          Text(
                            '${widget.source}  '
                            '${widget._displayCommand.isEmpty ? '' : '\$ ${widget._displayCommand}'}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(fontSize: 12),
                          ),
                          const SizedBox(height: 4),
                          Semantics(
                            label:
                                '执行端：$_displayExecutionTarget；权限：$_displayPermission；$_terminalSessionLabel',
                            child: Text(
                              '执行端：$_displayExecutionTarget · '
                              '权限：$_displayPermission · '
                              '$_terminalSessionLabel',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: const Color(0xFF686761),
                                    fontSize: 10,
                                  ),
                            ),
                          ),
                          if (_ctrlPending || _connectionMessage != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              _connectionMessage ?? 'Ctrl 已按下，点按一个按键以发送控制字符',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: _connectionMessage == null
                                        ? tokens?.warm
                                        : tokens?.danger,
                                  ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 20),
                    Transform.translate(
                      offset: const Offset(0, -8),
                      child: AggregateIconButton(
                        tooltip: '中断程序',
                        icon: Icons.stop_circle_outlined,
                        kind: GlassButtonKind.danger,
                        size: GlassButtonSize.terminalIcon,
                        onPressed: _connected ? _interrupt : null,
                        enabled: _connected,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 19),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: SizedBox(
                  height: terminalHeight,
                  child: Container(
                    key: const Key('terminal-surface'),
                    decoration: BoxDecoration(
                      color: const Color(0xFF17181C),
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(
                        color: const Color(0xFF555660),
                        width: 1,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(13),
                      child: _startupError != null && _session == null
                          ? Center(
                              child: Text(
                                _startupError!,
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(color: Colors.white70),
                              ),
                            )
                          : _session == null
                          ? const Center(child: CircularProgressIndicator())
                          : _terminalView(padding: const EdgeInsets.all(24)),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: _buildToolbar(context),
              ),
              const Spacer(),
            ],
          ),
        );
      },
    ),
  );

  Widget _terminalView({required EdgeInsets padding}) => TerminalView(
    _terminal,
    controller: _terminalController,
    textStyle: defaultTargetPlatform == TargetPlatform.macOS
        ? const TerminalStyle(height: 27 / 13)
        : const TerminalStyle(),
    backgroundOpacity: defaultTargetPlatform == TargetPlatform.macOS ? 0 : 1,
    focusNode: _focusNode,
    autofocus: true,
    keyboardType: TextInputType.text,
    readOnly: !_connected,
    deleteDetection: true,
    padding: padding,
  );

  String get _terminalSessionLabel => _connected
      ? '交互会话'
      : _session == null
      ? '正在启动'
      : '已断开';

  String get _displayExecutionTarget =>
      defaultTargetPlatform == TargetPlatform.macOS &&
          widget.executionTarget == '此设备'
      ? '本机 Mac'
      : widget.executionTarget;

  String get _displayPermission => widget.permission == PermissionLevel.read
      ? '读取连接'
      : _permissionLabel(widget.permission);

  Widget _buildToolbar(BuildContext context) {
    final glass = _usesGlassButtons(context);
    final controls = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: glass ? 0 : 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (glass)
              _terminalToolbarAction(
                key: const Key('terminal-control-ctrl'),
                width: 64,
                label: 'Ctrl',
                icon: Icons.terminal_outlined,
                onPressed: _connected
                    ? () => setState(() => _ctrlPending = !_ctrlPending)
                    : null,
                enabled: _connected,
                selected: _ctrlPending,
              )
            else
              IconButton(
                key: const Key('terminal-control-ctrl'),
                tooltip: _ctrlPending ? '取消 Ctrl' : '启用 Ctrl',
                onPressed: _connected
                    ? () => setState(() => _ctrlPending = !_ctrlPending)
                    : null,
                style: IconButton.styleFrom(
                  backgroundColor: _ctrlPending
                      ? Theme.of(context).colorScheme.secondaryContainer
                      : null,
                ),
                icon: const Text('Ctrl'),
              ),
            if (glass) const SizedBox(width: 10),
            _keyButton(TerminalKey.escape, 'Esc', '发送 Esc 键'),
            if (glass) const SizedBox(width: 10),
            _keyButton(TerminalKey.tab, 'Tab', '发送 Tab 键'),
            if (glass) const SizedBox(width: 10),
            _keyButton(TerminalKey.arrowUp, '↑', '方向键上'),
            if (glass) const SizedBox(width: 10),
            _keyButton(TerminalKey.arrowDown, '↓', '方向键下'),
            if (glass) const SizedBox(width: 10),
            _keyButton(TerminalKey.arrowLeft, '←', '方向键左'),
            if (glass) const SizedBox(width: 10),
            _keyButton(TerminalKey.arrowRight, '→', '方向键右'),
            if (glass) const SizedBox(width: 10),
            if (glass) ...[
              _terminalToolbarAction(
                key: const Key('terminal-copy'),
                width: 90,
                label: '复制',
                icon: Icons.copy_outlined,
                onPressed: _hasSelection ? _copySelection : null,
                enabled: _hasSelection,
                style: AggregateActionStyle.quiet,
                textOnly: true,
              ),
              const SizedBox(width: 10),
              _terminalToolbarAction(
                key: const Key('terminal-paste'),
                width: 90,
                label: '粘贴',
                icon: Icons.content_paste_outlined,
                onPressed: _connected ? _pasteClipboard : null,
                enabled: _connected,
                style: AggregateActionStyle.quiet,
                textOnly: true,
              ),
            ] else ...[
              TextButton.icon(
                key: const Key('terminal-copy'),
                onPressed: _hasSelection ? _copySelection : null,
                style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                icon: const Icon(Icons.copy_outlined),
                label: const Text('复制'),
              ),
              TextButton.icon(
                key: const Key('terminal-paste'),
                onPressed: _connected ? _pasteClipboard : null,
                style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                icon: const Icon(Icons.content_paste_outlined),
                label: const Text('粘贴'),
              ),
            ],
          ],
        ),
      ),
    );
    if (glass) {
      return Align(alignment: Alignment.centerLeft, child: controls);
    }
    return SafeArea(
      top: false,
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainer,
        child: controls,
      ),
    );
  }

  Widget _keyButton(TerminalKey key, String label, String tooltip) {
    final icon = switch (key) {
      TerminalKey.escape => Icons.close,
      TerminalKey.tab => Icons.arrow_forward_rounded,
      TerminalKey.arrowUp => Icons.arrow_upward,
      TerminalKey.arrowDown => Icons.arrow_downward,
      TerminalKey.arrowLeft => Icons.arrow_back,
      TerminalKey.arrowRight => Icons.arrow_forward_rounded,
      _ => Icons.more_horiz,
    };
    if (_usesGlassButtons(context)) {
      return _terminalToolbarAction(
        key: Key('terminal-key-${key.name}'),
        width: switch (key) {
          TerminalKey.arrowUp ||
          TerminalKey.arrowDown ||
          TerminalKey.arrowLeft ||
          TerminalKey.arrowRight => 52,
          _ => 64,
        },
        label: label,
        icon: icon,
        onPressed: _connected ? () => _sendKey(key) : null,
        enabled: _connected,
        textOnly: true,
      );
    }
    return IconButton(
      key: Key('terminal-key-${key.name}'),
      tooltip: tooltip,
      onPressed: _connected ? () => _sendKey(key) : null,
      icon: Text(label),
    );
  }

  Widget _terminalToolbarAction({
    Key? key,
    required double width,
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
    required bool enabled,
    AggregateActionStyle style = AggregateActionStyle.secondary,
    bool selected = false,
    bool textOnly = false,
  }) => SizedBox(
    width: width,
    height: 40,
    child: AggregateActionButton(
      key: key,
      label: label,
      icon: icon,
      leading: textOnly ? const SizedBox(width: 2) : null,
      onPressed: onPressed,
      enabled: enabled,
      selected: selected,
      style: style,
      size: GlassButtonSize.terminalToolbar,
      expand: true,
    ),
  );
}

String _permissionLabel(PermissionLevel permission) => switch (permission) {
  PermissionLevel.read => '只读',
  PermissionLevel.localControl => '运行端控制',
  PermissionLevel.externalWrite => '外部写入',
  PermissionLevel.unknown => '权限待确认',
};

String _redactCommandArguments(List<String> arguments) {
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
    if (RegExp(
      r'(password|passwd|secret|token|api.?key|authorization|credential)',
      caseSensitive: false,
    ).hasMatch(flag)) {
      if (equals >= 0) {
        result.add('${argument.substring(0, equals + 1)}••••••');
      } else {
        result.add(argument);
        hideNext = true;
      }
    } else {
      result.add(argument);
    }
  }
  return result.join(' ');
}
