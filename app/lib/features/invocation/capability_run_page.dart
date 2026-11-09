import 'dart:async';

import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:flutter/material.dart';

import '../../widgets/page_frame.dart';
import '../../widgets/result_panel.dart';
import 'schema_form.dart';

class CapabilityRunPage extends StatefulWidget {
  const CapabilityRunPage({
    super.key,
    required this.runtime,
    required this.capability,
  });
  final RuntimePort runtime;
  final Capability capability;
  @override
  State<CapabilityRunPage> createState() => _CapabilityRunPageState();
}

class _CapabilityRunPageState extends State<CapabilityRunPage> {
  final form = GlobalKey<SchemaFormState>();
  StreamSubscription<RunEvent>? subscription;
  RunHandle? handle;
  RunState? state;
  List<ResultBlock> blocks = [];
  RuntimeFailure? failure;

  @override
  void dispose() {
    subscription?.cancel();
    super.dispose();
  }

  Future<void> run() async {
    if (!(form.currentState?.validate() ?? true)) return;
    await subscription?.cancel();
    final arguments = form.currentState?.arguments() ?? <String, Object?>{};
    setState(() {
      state = RunState.running;
      blocks = [];
      failure = null;
    });
    try {
      if (widget.capability.id.kind == CapabilityKind.mcpResource) {
        final result = await widget.runtime.readResource(
          ResourceRef(widget.capability.id, Uri.parse('memo://preview/readme')),
        );
        if (mounted) {
          setState(() {
            blocks = result;
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
            blocks = result;
            state = RunState.succeeded;
          });
        }
        return;
      }
      handle = await widget.runtime.invoke(widget.capability.id, arguments);
      subscription = widget.runtime.watchRun(handle!.id).listen((event) {
        if (!mounted) return;
        setState(() {
          state = event.state;
          if (event.blocks.isNotEmpty) blocks = event.blocks;
          failure = event.failure;
        });
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
      body: PageFrame(
        title: widget.capability.title,
        subtitle:
            '${widget.capability.description} · 来源：${widget.capability.id.connection.value} · 预览数据',
        children: [
          Text('参数', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          SchemaForm(key: form, schema: widget.capability.inputSchema),
          const SizedBox(height: 8),
          Row(
            children: [
              FilledButton(
                onPressed: state == RunState.running ? null : run,
                child: Text(action),
              ),
              if (state == RunState.running && handle != null) ...[
                const SizedBox(width: 12),
                OutlinedButton(onPressed: cancel, child: const Text('取消')),
              ],
            ],
          ),
          const SizedBox(height: 32),
          const Divider(),
          const SizedBox(height: 16),
          ResultPanel(state: state, blocks: blocks, failure: failure),
        ],
      ),
    );
  }
}
