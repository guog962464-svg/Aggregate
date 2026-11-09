import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../widgets/capability_row.dart';
import '../../widgets/page_frame.dart';
import '../../widgets/page_state.dart';

class WorkspacePage extends StatefulWidget {
  const WorkspacePage({super.key, required this.runtime, required this.onOpen});
  final RuntimePort runtime;
  final ValueChanged<Capability> onOpen;
  @override
  State<WorkspacePage> createState() => _WorkspacePageState();
}

class _WorkspacePageState extends State<WorkspacePage> {
  final search = TextEditingController();
  List<Capability>? capabilities;
  Map<String, String> sources = {};
  Object? error;
  int generation = 0;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final current = ++generation;
    setState(() {
      capabilities = null;
      error = null;
    });
    try {
      final connections = await widget.runtime.listConnections();
      final results = await widget.runtime.searchCapabilities(
        SearchQuery(search.text),
      );
      if (!mounted || current != generation) return;
      setState(() {
        sources = {for (final item in connections) item.id.value: item.label};
        capabilities = results;
      });
    } catch (cause) {
      if (!mounted || current != generation) return;
      setState(() => error = cause);
    }
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  void openFirst() {
    if (capabilities?.isNotEmpty ?? false) {
      widget.onOpen(capabilities!.first);
    }
  }

  @override
  Widget build(BuildContext context) => PageFrame(
    title: '工作台',
    subtitle: '搜索所有连接中的功能。当前结果为阶段 1 预览数据。',
    children: [
      CallbackShortcuts(
        bindings: {const SingleActivator(LogicalKeyboardKey.enter): openFirst},
        child: TextField(
          key: const Key('global-search'),
          controller: search,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '搜索功能',
            hintText: '名称、说明或来源',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (_) => load(),
          onSubmitted: (_) => openFirst(),
        ),
      ),
      const SizedBox(height: 24),
      if (error != null)
        PageState.error('加载功能失败：$error', onRetry: load)
      else if (capabilities == null)
        const PageState.loading()
      else if (capabilities!.isEmpty)
        PageState.empty(search.text.isEmpty ? '还没有可用功能。请先添加连接。' : '没有匹配的功能。')
      else ...[
        Text('全部功能', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final capability in capabilities!) ...[
          CapabilityRow(
            capability: capability,
            source: sources[capability.id.connection.value] ?? '未知来源',
            onOpen: () => widget.onOpen(capability),
          ),
          const Divider(height: 1),
        ],
      ],
    ],
  );
}
