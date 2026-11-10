import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:flutter/material.dart';

import '../../widgets/capability_row.dart';
import '../../widgets/page_frame.dart';
import '../music/music_player_page.dart';
import '../music/music_session.dart';
import 'connection_experience.dart';

class ConnectionHomePage extends StatelessWidget {
  const ConnectionHomePage({
    super.key,
    required this.connection,
    required this.capabilities,
    required this.runtime,
    required this.musicSession,
    required this.onOpen,
  });

  final Connection connection;
  final List<Capability> capabilities;
  final RuntimePort runtime;
  final MusicSession musicSession;
  final ValueChanged<Capability> onOpen;

  @override
  Widget build(BuildContext context) {
    final experience = experienceFor(connection, capabilities);
    final own = capabilities
        .where((item) => item.id.connection.value == connection.id.value)
        .toList();
    if (experience == ConnectionExperience.music) {
      return MusicPlayerPage(
        key: ValueKey('music-${connection.id.value}'),
        connection: connection,
        capabilities: own,
        runtime: runtime,
        session: musicSession,
      );
    }
    return _GenericConnectionHome(
      connection: connection,
      capabilities: own,
      experience: experience,
      onOpen: onOpen,
    );
  }
}

class _GenericConnectionHome extends StatelessWidget {
  const _GenericConnectionHome({
    required this.connection,
    required this.capabilities,
    required this.experience,
    required this.onOpen,
  });

  final Connection connection;
  final List<Capability> capabilities;
  final ConnectionExperience experience;
  final ValueChanged<Capability> onOpen;

  @override
  Widget build(BuildContext context) {
    final isCli = experience == ConnectionExperience.cli;
    final scheme = Theme.of(context).colorScheme;
    return PageFrame(
      title: connection.label,
      subtitle: isCli ? '命令与动作' : '工具、资源与提示',
      children: [
        Row(
          children: [
            Icon(
              isCli ? Icons.terminal_outlined : Icons.hub_outlined,
              color: scheme.primary,
            ),
            const SizedBox(width: 10),
            Text(switch (connection.status) {
              ConnectionStatus.ready => '已连接',
              ConnectionStatus.connecting => '连接中',
              ConnectionStatus.unavailable => '暂不可用',
            }, style: Theme.of(context).textTheme.bodyMedium),
            const Spacer(),
            Text(
              '${capabilities.length} 项功能',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        const SizedBox(height: 24),
        if (connection.diagnostic case final diagnostic?) ...[
          Text(diagnostic, style: TextStyle(color: scheme.error)),
          const SizedBox(height: 16),
        ],
        if (capabilities.isEmpty)
          const Text('这个连接暂时没有可用功能。请在连接页检查状态。')
        else if (isCli) ...[
          _section(context, '命令与动作', capabilities),
        ] else ...[
          _section(context, '工具', _ofKind(CapabilityKind.mcpTool)),
          _section(context, '资源', _ofKind(CapabilityKind.mcpResource)),
          _section(context, '提示', _ofKind(CapabilityKind.mcpPrompt)),
        ],
      ],
    );
  }

  List<Capability> _ofKind(CapabilityKind kind) =>
      capabilities.where((item) => item.id.kind == kind).toList();

  Widget _section(BuildContext context, String title, List<Capability> items) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          for (final capability in items) ...[
            CapabilityRow(
              capability: capability,
              source: connection.label,
              onOpen: () => onOpen(capability),
            ),
            const Divider(height: 1),
          ],
        ],
      ),
    );
  }
}
