import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../widgets/glass/aggregate_buttons.dart';
import '../../widgets/glass/glass_action_button.dart';
import '../../widgets/glass/glass_glyph.dart';
import '../../widgets/glass/glass_motion.dart';
import '../../widgets/page_frame.dart';
import '../../widgets/page_state.dart';

class ActivityPage extends StatefulWidget {
  const ActivityPage({super.key, required this.runtime, required this.onOpen});
  final RuntimePort runtime;
  final ValueChanged<Capability> onOpen;

  @override
  State<ActivityPage> createState() => ActivityPageState();
}

class ActivityPageState extends State<ActivityPage> {
  late Future<List<RunSummary>> pending;
  RunSummary? selected;
  RunState? stateFilter;
  final Set<String> cancellingRunIds = {};

  bool _usesGlassButtons(BuildContext context) =>
      defaultTargetPlatform == TargetPlatform.macOS &&
      GlassMotionScope.maybeOf(context) != null;

  @override
  void initState() {
    super.initState();
    pending = widget.runtime.listRecentRuns();
  }

  void reload() => setState(() {
    pending = widget.runtime.listRecentRuns();
  });

  Future<void> reopen(RunSummary run) async {
    final matches = await widget.runtime.searchCapabilities(
      const SearchQuery(''),
    );
    if (!mounted) return;
    for (final capability in matches) {
      if (capability.id.key == run.capability.key) {
        widget.onOpen(capability);
        return;
      }
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('此功能当前不可用。请在连接页刷新来源。')));
  }

  bool _canCancel(RunState state) => switch (state) {
    RunState.created ||
    RunState.validating ||
    RunState.awaitingPermission ||
    RunState.running => true,
    RunState.succeeded ||
    RunState.failed ||
    RunState.cancelled ||
    RunState.timedOut ||
    RunState.outcomeUnknown => false,
  };

  Future<void> _cancel(RunSummary run) async {
    final runId = run.id.value;
    if (cancellingRunIds.contains(runId)) return;
    setState(() => cancellingRunIds.add(runId));
    try {
      await widget.runtime.cancel(run.id);
      if (!mounted) return;
      reload();
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已请求取消；请刷新确认最终状态。')));
    } catch (cause) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('取消请求失败：$cause')));
      }
    } finally {
      if (mounted) setState(() => cancellingRunIds.remove(runId));
    }
  }

  String _capabilityName(RunSummary run) =>
      (widget.runtime is RuntimePresentationPort
          ? (widget.runtime as RuntimePresentationPort).capabilityDisplayName(
              run.capability,
            )
          : null) ??
      run.capability.name;

  String _connectionName(RunSummary run) =>
      (widget.runtime is RuntimePresentationPort
          ? (widget.runtime as RuntimePresentationPort).connectionDisplayName(
              run.capability.connection,
            )
          : null) ??
      run.capability.connection.value;

  @override
  Widget build(BuildContext context) => PageFrame(
    title: '活动',
    subtitle: widget.runtime.isPreview
        ? '本次启动中的预览调用记录。'
        : '最近 100 条运行状态。记录只保留状态和时间，不包含参数和结果正文。',
    children: [
      Row(
        children: [
          Text('运行记录', style: Theme.of(context).textTheme.titleMedium),
          const Spacer(),
          AggregateIconButton(
            tooltip: '刷新活动',
            icon: Icons.refresh,
            onPressed: reload,
          ),
        ],
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        children: [
          _filter('全部', null),
          _filter('成功', RunState.succeeded),
          _filter('失败', RunState.failed),
          _filter('取消', RunState.cancelled),
          _filter('超时', RunState.timedOut),
          _filter('运行中', RunState.running),
          _filter('结果待确认', RunState.outcomeUnknown),
        ],
      ),
      const SizedBox(height: 20),
      FutureBuilder<List<RunSummary>>(
        future: pending,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return PageState.error('加载活动失败：${snapshot.error}', onRetry: reload);
          }
          if (!snapshot.hasData) return const PageState.loading();
          final runs = snapshot.data!
              .where(
                (run) => stateFilter == null || run.latest.state == stateFilter,
              )
              .toList();
          if (snapshot.data!.isEmpty) return const PageState.empty('还没有运行记录。');
          if (runs.isEmpty) return const PageState.empty('当前筛选下没有运行记录。');
          return LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 680;
              final current = selected == null
                  ? (wide ? runs.first : null)
                  : runs
                        .where((run) => run.id.value == selected!.id.value)
                        .firstOrNull;
              if (!wide && current != null) {
                return _detail(current, compact: true);
              }
              final list = SizedBox(
                height: _runListViewportHeight(context),
                child: ListView.builder(
                  primary: false,
                  padding: EdgeInsets.zero,
                  itemCount: runs.length * 2,
                  itemBuilder: (context, index) {
                    if (index.isOdd) return const Divider(height: 1);
                    final run = runs[index ~/ 2];
                    if (_usesGlassButtons(context)) {
                      return AggregateActionButton(
                        label: _capabilityName(run),
                        description: _time(run.latest.occurredAt),
                        source: _state(run.latest.state),
                        semanticsLabel:
                            '${_capabilityName(run)}，${_state(run.latest.state)}，'
                            '${_time(run.latest.occurredAt)}',
                        icon: _stateIcon(run.latest.state),
                        style: AggregateActionStyle.quiet,
                        onPressed: () => setState(() => selected = run),
                        selected: current?.id.value == run.id.value,
                        expand: true,
                      );
                    }
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                      selected: current?.id.value == run.id.value,
                      title: Text(
                        _capabilityName(run),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(_time(run.latest.occurredAt)),
                      trailing: Text(_state(run.latest.state)),
                      onTap: () => setState(() => selected = run),
                    );
                  },
                ),
              );
              if (!wide) return list;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 4, child: list),
                  const SizedBox(width: 24),
                  Expanded(
                    flex: 5,
                    child: current == null
                        ? const SizedBox.shrink()
                        : _detail(current),
                  ),
                ],
              );
            },
          );
        },
      ),
    ],
  );

  double _runListViewportHeight(BuildContext context) =>
      (MediaQuery.sizeOf(context).height - 336).clamp(220.0, 560.0).toDouble();

  Widget _filter(String label, RunState? state) {
    final isSelected = stateFilter == state;
    final icon = state == null ? Icons.grid_view_outlined : _stateIcon(state);
    if (_usesGlassButtons(context)) {
      return GlassActionButton(
        glyph: GlassGlyphCatalog.fromMaterialIcon(icon),
        label: label,
        semanticsLabel: '按状态筛选：$label',
        onPressed: () => setState(() {
          stateFilter = state;
          selected = null;
        }),
        selected: isSelected,
        kind: GlassButtonKind.segmented,
        size: GlassButtonSize.secondary,
      );
    }
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => setState(() {
        stateFilter = state;
        selected = null;
      }),
    );
  }

  Widget _detail(RunSummary run, {bool compact = false}) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Theme.of(context).dividerColor),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (compact)
          AggregateActionButton(
            label: '返回记录',
            icon: Icons.arrow_back,
            style: AggregateActionStyle.quiet,
            onPressed: () => setState(() => selected = null),
          ),
        Text('运行详情', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 18),
        _line('功能', _capabilityName(run)),
        _line('来源', _connectionName(run)),
        _line('状态', _state(run.latest.state)),
        _line('时间', _time(run.latest.occurredAt)),
        _line('运行 ID', run.id.value),
        const SizedBox(height: 12),
        Text('参数与结果未写入活动记录。', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          children: [
            AggregateActionButton(
              label:
                  _canCancel(run.latest.state) ||
                      run.latest.state == RunState.outcomeUnknown
                  ? '查看运行'
                  : '重新打开功能',
              icon: Icons.open_in_new,
              onPressed: () => reopen(run),
            ),
            if (_canCancel(run.latest.state))
              AggregateActionButton(
                label: cancellingRunIds.contains(run.id.value)
                    ? '取消中…'
                    : '取消运行',
                icon: Icons.stop_circle_outlined,
                style: AggregateActionStyle.danger,
                onPressed: cancellingRunIds.contains(run.id.value)
                    ? null
                    : () => _cancel(run),
                enabled: !cancellingRunIds.contains(run.id.value),
              ),
            AggregateActionButton(
              label: '复制诊断',
              icon: Icons.copy_outlined,
              style: AggregateActionStyle.quiet,
              onPressed: () async {
                await Clipboard.setData(
                  ClipboardData(
                    text:
                        'Run ${run.id.value} · ${_state(run.latest.state)} · ${_time(run.latest.occurredAt)}',
                  ),
                );
                if (mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(const SnackBar(content: Text('已复制脱敏诊断')));
                }
              },
            ),
          ],
        ),
      ],
    ),
  );

  Widget _line(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 64,
          child: Text(label, style: Theme.of(context).textTheme.bodySmall),
        ),
        Expanded(child: SelectableText(value)),
      ],
    ),
  );
}

String _time(DateTime value) {
  final local = value.toLocal();
  String pad(int number) => number.toString().padLeft(2, '0');
  return '${local.year}-${pad(local.month)}-${pad(local.day)} ${pad(local.hour)}:${pad(local.minute)}:${pad(local.second)}';
}

String _state(RunState value) => switch (value) {
  RunState.succeeded => '成功',
  RunState.failed => '失败',
  RunState.cancelled => '已取消',
  RunState.timedOut => '超时',
  RunState.outcomeUnknown => '结果待确认',
  RunState.running => '运行中',
  RunState.awaitingPermission => '等待确认',
  RunState.validating => '验证中',
  RunState.created => '已创建',
};

IconData _stateIcon(RunState value) => switch (value) {
  RunState.succeeded => Icons.check_circle_outline,
  RunState.failed || RunState.timedOut => Icons.error_outline,
  RunState.cancelled => Icons.close,
  RunState.outcomeUnknown => Icons.info_outline,
  RunState.running ||
  RunState.validating ||
  RunState.created => Icons.hourglass_top_outlined,
  RunState.awaitingPermission => Icons.lock_outline,
};
