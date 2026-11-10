import 'dart:async';

import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:flutter/material.dart';
import 'package:terminal_view/terminal_view.dart';

class TerminalPage extends StatefulWidget {
  const TerminalPage({
    super.key,
    required this.runtime,
    required this.command,
    required this.source,
  });
  final RuntimePort runtime;
  final CliCommand command;
  final String source;

  @override
  State<TerminalPage> createState() => _TerminalPageState();
}

class _TerminalPageState extends State<TerminalPage> {
  late final Terminal terminal;
  TerminalSession? session;
  StreamSubscription<String>? subscription;
  String? error;

  @override
  void initState() {
    super.initState();
    terminal = Terminal(maxLines: 2000);
    terminal.onOutput = (text) {
      final current = session;
      if (current != null) {
        unawaited(widget.runtime.writeTerminal(current, text));
      }
    };
    terminal.onResize = (columns, rows, _, _) {
      final current = session;
      if (current != null) {
        unawaited(widget.runtime.resizeTerminal(current, columns, rows));
      }
    };
    unawaited(start());
  }

  Future<void> start() async {
    try {
      final opened = await widget.runtime.openTerminal(widget.command);
      if (!mounted) {
        await widget.runtime.closeTerminal(opened);
        return;
      }
      setState(() => session = opened);
      subscription = widget.runtime
          .watchTerminal(opened)
          .listen(terminal.write);
      await widget.runtime.resizeTerminal(
        opened,
        terminal.viewWidth,
        terminal.viewHeight,
      );
    } catch (cause) {
      if (mounted) setState(() => error = '$cause');
    }
  }

  Future<void> interrupt() async {
    final current = session;
    if (current != null) await widget.runtime.interruptTerminal(current);
  }

  @override
  void dispose() {
    final current = session;
    if (current != null) unawaited(widget.runtime.closeTerminal(current));
    unawaited(subscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('终端'),
      actions: [
        IconButton(
          tooltip: '中断程序',
          onPressed: session == null ? null : interrupt,
          icon: const Icon(Icons.stop_circle_outlined),
        ),
      ],
    ),
    body: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: Row(
            children: [
              const Icon(Icons.terminal, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${widget.source}  ${widget.command.arguments.join(' ')}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
              ),
              Text(session == null ? '正在启动' : '交互会话'),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: error != null
                ? Center(child: Text(error!))
                : session == null
                ? const Center(child: CircularProgressIndicator())
                : TerminalView(terminal, autofocus: true),
          ),
        ),
      ],
    ),
  );
}
