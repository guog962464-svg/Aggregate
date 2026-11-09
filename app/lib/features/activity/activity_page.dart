import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:flutter/material.dart';

import '../../widgets/page_frame.dart';
import '../../widgets/page_state.dart';

class ActivityPage extends StatefulWidget {
  const ActivityPage({super.key, required this.runtime, required this.onOpen});
  final RuntimePort runtime;
  final ValueChanged<Capability> onOpen;
  @override
  State<ActivityPage> createState() => _ActivityPageState();
}

class _ActivityPageState extends State<ActivityPage> {
  late Future<List<RunSummary>> pending;

  @override
  void initState() {
    super.initState();
    pending = widget.runtime.listRecentRuns();
  }

  void reload() => setState(() => pending = widget.runtime.listRecentRuns());

  Future<void> reopen(RunSummary run) async {
    final matches = await widget.runtime.searchCapabilities(
      const SearchQuery(''),
    );
    for (final capability in matches) {
      if (capability.id.key == run.capability.key) {
        widget.onOpen(capability);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) => PageFrame(
    title: '活动',
    subtitle: '本次启动中的预览调用记录。',
    children: [
      TextButton.icon(
        onPressed: reload,
        icon: const Icon(Icons.refresh),
        label: const Text('刷新'),
      ),
      FutureBuilder<List<RunSummary>>(
        future: pending,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return PageState.error('加载活动失败：${snapshot.error}', onRetry: reload);
          }
          if (!snapshot.hasData) return const PageState.loading();
          if (snapshot.data!.isEmpty) return const PageState.empty('还没有运行记录。');
          return Column(
            children: [
              for (final run in snapshot.data!) ...[
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(run.capability.name),
                  subtitle: Text(
                    '${run.latest.state.name} · ${run.latest.occurredAt.toLocal()}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => reopen(run),
                ),
                const Divider(height: 1),
              ],
            ],
          );
        },
      ),
    ],
  );
}
