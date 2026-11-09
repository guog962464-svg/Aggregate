import 'dart:convert';

import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:flutter/material.dart';

class ResultPanel extends StatelessWidget {
  const ResultPanel({
    super.key,
    required this.state,
    required this.blocks,
    this.failure,
  });
  final RunState? state;
  final List<ResultBlock> blocks;
  final RuntimeFailure? failure;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('本次运行', style: Theme.of(context).textTheme.titleMedium),
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
        SelectableText(
          block.kind == ResultKind.json
              ? const JsonEncoder.withIndent('  ').convert(block.value)
              : '${block.value}',
          style: block.kind == ResultKind.json
              ? const TextStyle(fontFamily: 'monospace')
              : null,
        ),
      ],
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
