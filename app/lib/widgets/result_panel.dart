import 'dart:convert';

import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ResultPanel extends StatelessWidget {
  const ResultPanel({
    super.key,
    required this.state,
    required this.blocks,
    this.failure,
    this.runtime,
  });
  final RunState? state;
  final List<ResultBlock> blocks;
  final RuntimeFailure? failure;
  final RuntimePort? runtime;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(
            child: Text('本次运行', style: Theme.of(context).textTheme.titleMedium),
          ),
          if (blocks.isNotEmpty)
            IconButton(
              tooltip: '复制结果',
              onPressed: () async {
                final content = blocks
                    .map(
                      (block) => block.kind == ResultKind.json
                          ? const JsonEncoder.withIndent('  ')
                                .convert(block.value)
                          : '${block.value}',
                    )
                    .join('\n\n');
                await Clipboard.setData(ClipboardData(text: content));
                if (context.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(const SnackBar(content: Text('已复制结果')));
                }
              },
              icon: const Icon(Icons.copy_outlined, size: 18),
            ),
        ],
      ),
      const SizedBox(height: 8),
      Text(_stateLabel(state)),
      if (failure != null) ...[
        const SizedBox(height: 12),
        Text(
          failure!.message,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ],
      if (blocks.isEmpty && state == RunState.succeeded)
        const Text('运行成功，未返回内容。'),
      for (final block in blocks) ...[
        const SizedBox(height: 12),
        _ResultContent(block: block, runtime: runtime),
      ],
    ],
  );
}

class _ResultContent extends StatelessWidget {
  const _ResultContent({required this.block, this.runtime});
  final ResultBlock block;
  final RuntimePort? runtime;

  @override
  Widget build(BuildContext context) {
    final value = block.value;
    if (block.kind == ResultKind.file && value is String) {
      return _FileResultView(path: value.trim(), runtime: runtime);
    }
    if (block.kind == ResultKind.image && value is Map) {
      final data = value['data'];
      if (data is String) {
        try {
          final bytes = base64Decode(data);
          return ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 420),
            child: Image.memory(bytes, fit: BoxFit.contain),
          );
        } on FormatException {
          // Show the raw block when a provider returns malformed image data.
        }
      }
    }
    if (value is Map && value['exitCode'] is int) {
      return Text(
        '退出码 ${value['exitCode']} · 耗时 ${value['durationMs'] ?? '?'} ms',
      );
    }
    if (value is Map && value.length == 1 && value['durationMs'] is int) {
      return Text('耗时 ${value['durationMs']} ms');
    }
    return SelectableText(
      block.kind == ResultKind.json
          ? const JsonEncoder.withIndent('  ').convert(value)
          : '$value',
      style: block.kind == ResultKind.json
          ? const TextStyle(fontFamily: 'monospace')
          : null,
    );
  }
}

class _FileResultView extends StatefulWidget {
  const _FileResultView({required this.path, required this.runtime});

  final String path;
  final RuntimePort? runtime;

  @override
  State<_FileResultView> createState() => _FileResultViewState();
}

class _FileResultViewState extends State<_FileResultView> {
  bool busy = false;
  String? error;
  List<ResultBlock>? preview;

  Future<void> _loadPreview() async {
    final runtime = widget.runtime;
    if (runtime == null) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await runtime.previewLocalFile(widget.path);
      if (mounted) setState(() => preview = result);
    } catch (cause) {
      if (mounted) setState(() => error = '$cause');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _reveal() async {
    final runtime = widget.runtime;
    if (runtime == null) return;
    try {
      await runtime.revealLocalFile(widget.path);
    } catch (cause) {
      if (mounted) setState(() => error = '$cause');
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SelectableText(widget.path),
      if (widget.runtime?.features.localFilePreview == true ||
          widget.runtime?.features.localFileReveal == true) ...[
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            if (widget.runtime?.features.localFilePreview == true)
              OutlinedButton(
                onPressed: busy ? null : _loadPreview,
                child: const Text('预览文件'),
              ),
            if (widget.runtime?.features.localFileReveal == true)
              TextButton(
                onPressed: busy ? null : _reveal,
                child: Text(
                  Theme.of(context).platform == TargetPlatform.macOS
                      ? '在访达中显示'
                      : '在文件管理器中显示',
                ),
              ),
          ],
        ),
      ],
      if (busy) const LinearProgressIndicator(),
      if (error != null)
        Text(
          error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      if (preview != null)
        for (final block in preview!) _ResultContent(block: block),
    ],
  );
}

String _stateLabel(RunState? state) => switch (state) {
  null => '尚未运行',
  RunState.created => '已创建',
  RunState.validating => '正在验证',
  RunState.awaitingPermission => '等待授权',
  RunState.running => '正在运行…',
  RunState.succeeded => '运行成功',
  RunState.failed => '运行失败',
  RunState.cancelled => '已取消',
  RunState.timedOut => '已超时',
  RunState.outcomeUnknown => '结果待确认',
};
