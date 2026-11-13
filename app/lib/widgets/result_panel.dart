import 'dart:convert';

import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

class ResultPanel extends StatelessWidget {
  const ResultPanel({
    super.key,
    required this.state,
    required this.blocks,
    this.failure,
    this.runtime,
    this.onCheckActivity,
    this.activityCheckInProgress = false,
  });
  final RunState? state;
  final List<ResultBlock> blocks;
  final RuntimeFailure? failure;
  final RuntimePort? runtime;
  final VoidCallback? onCheckActivity;
  final bool activityCheckInProgress;

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
      Semantics(
        liveRegion: true,
        label: '运行状态：${_stateLabel(state)}',
        child: Text(_stateLabel(state)),
      ),
      if (_isActiveRunState(state)) ...[
        const SizedBox(height: 12),
        const LinearProgressIndicator(),
      ],
      if (failure != null) ...[
        const SizedBox(height: 12),
        _FailureRecovery(
          failure: failure!,
          onCheckActivity: onCheckActivity,
          activityCheckInProgress: activityCheckInProgress,
        ),
      ] else if (state == RunState.outcomeUnknown) ...[
        const SizedBox(height: 12),
        _UnknownOutcomeRecovery(
          onCheckActivity: onCheckActivity,
          activityCheckInProgress: activityCheckInProgress,
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
    final content = block.kind == ResultKind.json
        ? const JsonEncoder.withIndent('  ').convert(value)
        : '$value';
    final style = block.kind == ResultKind.json
        ? const TextStyle(fontFamily: 'monospace')
        : null;
    if (content.length <= _longResultThreshold) {
      return SelectableText(content, style: style);
    }
    final preview = content.substring(0, _longResultThreshold);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SelectableText('$preview\n… 其余内容已收起', style: style),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Text('展开完整内容（${content.length} 字符）'),
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: SingleChildScrollView(
                child: SelectableText(content, style: style),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

const _longResultThreshold = 1600;

class _FailureRecovery extends StatelessWidget {
  const _FailureRecovery({
    required this.failure,
    required this.onCheckActivity,
    required this.activityCheckInProgress,
  });

  final RuntimeFailure failure;
  final VoidCallback? onCheckActivity;
  final bool activityCheckInProgress;

  @override
  Widget build(BuildContext context) {
    final recovery = switch (failure.code) {
      RuntimeErrorCode.invalidArguments => '检查标出的参数格式和必填项，再由你决定是否重新运行。',
      RuntimeErrorCode.executableMissing =>
        '检查 Mac Host 上的 CLI 是否安装，并在连接页刷新能力列表。',
      RuntimeErrorCode.connectionFailed =>
        '检查网络和执行端在线状态；若调用可能已发出，先检查活动记录，再由你决定是否重跑。',
      RuntimeErrorCode.authenticationRequired => '到连接页完成登录或更新凭据，再手动运行。',
      RuntimeErrorCode.permissionDenied => '请在配对 Mac 的 Host 设置中检查此连接的授权范围。',
      RuntimeErrorCode.protocolError => '刷新连接或能力列表；若操作可能已发送，先检查执行端状态。',
      RuntimeErrorCode.timedOut => '先检查执行端的活动记录；确认操作状态后再决定是否重跑。',
      RuntimeErrorCode.cancelled => '本次操作已取消，可检查活动记录确认最终状态。',
      RuntimeErrorCode.outputLimitExceeded =>
        '输出超过安全上限；缩小查询范围，并先确认原操作是否完成，再决定是否执行新一轮。',
      RuntimeErrorCode.outcomeUnknown => '操作可能已经执行。先检查活动记录和执行端状态，不要直接重跑。',
      RuntimeErrorCode.unsupported => '此执行端不支持该操作；检查连接类型或改用支持的功能。',
      RuntimeErrorCode.internal => '检查执行端状态与活动记录；确认没有重复副作用后再决定是否重试。',
    };
    final canCheckActivity = {
      RuntimeErrorCode.connectionFailed,
      RuntimeErrorCode.protocolError,
      RuntimeErrorCode.timedOut,
      RuntimeErrorCode.outputLimitExceeded,
      RuntimeErrorCode.outcomeUnknown,
      RuntimeErrorCode.internal,
    }.contains(failure.code);
    return Material(
      color: Theme.of(context).colorScheme.errorContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('需要处理', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            Text(recovery),
            if (canCheckActivity && onCheckActivity != null) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: activityCheckInProgress ? null : onCheckActivity,
                icon: const Icon(Icons.manage_search),
                label: Text(activityCheckInProgress ? '检查中…' : '检查活动状态'),
              ),
            ],
            const SizedBox(height: 8),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('查看错误详情'),
              children: [SelectableText(failure.message)],
            ),
          ],
        ),
      ),
    );
  }
}

class _UnknownOutcomeRecovery extends StatelessWidget {
  const _UnknownOutcomeRecovery({
    required this.onCheckActivity,
    required this.activityCheckInProgress,
  });

  final VoidCallback? onCheckActivity;
  final bool activityCheckInProgress;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.errorContainer,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('操作可能已经发送，但没有收到最终确认。先检查活动状态和执行端，再决定是否重跑。'),
          if (onCheckActivity != null) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: activityCheckInProgress ? null : onCheckActivity,
              icon: const Icon(Icons.manage_search),
              label: Text(activityCheckInProgress ? '检查中…' : '检查活动状态'),
            ),
          ],
        ],
      ),
    ),
  );
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
