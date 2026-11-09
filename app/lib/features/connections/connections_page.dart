import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:flutter/material.dart';

import '../../widgets/page_frame.dart';
import '../../widgets/page_state.dart';

class ConnectionsPage extends StatefulWidget {
  const ConnectionsPage({super.key, required this.runtime});
  final RuntimePort runtime;
  @override
  State<ConnectionsPage> createState() => _ConnectionsPageState();
}

class _ConnectionsPageState extends State<ConnectionsPage> {
  late Future<List<Connection>> pending;

  @override
  void initState() {
    super.initState();
    pending = widget.runtime.listConnections();
  }

  void reload() => setState(() => pending = widget.runtime.listConnections());

  @override
  Widget build(BuildContext context) => PageFrame(
    title: '连接',
    subtitle: '管理 CLI、本地 MCP 和 HTTP MCP。真实连接编辑将在阶段 2 开放。',
    children: [
      OutlinedButton.icon(
        onPressed: () => showDialog<void>(
          context: context,
          builder: (_) => const AlertDialog(
            title: Text('添加连接'),
            content: Text('当前为页面预览。阶段 2 将接入本机 CLI 与 MCP。'),
          ),
        ),
        icon: const Icon(Icons.add),
        label: const Text('添加连接'),
      ),
      const SizedBox(height: 24),
      FutureBuilder<List<Connection>>(
        future: pending,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return PageState.error('加载连接失败：${snapshot.error}', onRetry: reload);
          }
          if (!snapshot.hasData) return const PageState.loading();
          final connections = snapshot.data!;
          if (connections.isEmpty) return const PageState.empty('还没有连接。');
          return Column(
            children: [
              for (final connection in connections) ...[
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(connection.label),
                  subtitle: Tooltip(
                    message: connection.location,
                    child: Text(
                      '${connection.kind.name} · ${connection.location}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  trailing: Text(
                    connection.status == ConnectionStatus.ready ? '预览' : '不可用',
                  ),
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
