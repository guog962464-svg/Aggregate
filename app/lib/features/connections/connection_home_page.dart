import 'dart:math' as math;

import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../widgets/capability_row.dart';
import '../../widgets/glass/aggregate_buttons.dart';
import '../../widgets/glass/glass_action_button.dart';
import '../../widgets/glass/glass_design_tokens.dart';
import '../../widgets/page_frame.dart';
import '../invocation/capability_run_page.dart';
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
    this.onAccountChanged,
    this.onRefresh,
  });

  final Connection connection;
  final List<Capability> capabilities;
  final RuntimePort runtime;
  final MusicSession musicSession;
  final ValueChanged<Capability> onOpen;
  final VoidCallback? onAccountChanged;
  final Future<void> Function()? onRefresh;

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
        onAccountChanged: onAccountChanged,
      );
    }
    return _GenericConnectionHome(
      connection: connection,
      capabilities: own,
      experience: experience,
      runtime: runtime,
      musicSession: musicSession,
      onOpen: onOpen,
      onRefresh: onRefresh,
    );
  }
}

class _GenericConnectionHome extends StatefulWidget {
  const _GenericConnectionHome({
    required this.connection,
    required this.capabilities,
    required this.experience,
    required this.runtime,
    required this.musicSession,
    required this.onOpen,
    required this.onRefresh,
  });

  final Connection connection;
  final List<Capability> capabilities;
  final ConnectionExperience experience;
  final RuntimePort runtime;
  final MusicSession musicSession;
  final ValueChanged<Capability> onOpen;
  final Future<void> Function()? onRefresh;

  @override
  State<_GenericConnectionHome> createState() => _GenericConnectionHomeState();
}

class _GenericConnectionHomeState extends State<_GenericConnectionHome> {
  String? selectedCapabilityKey;
  bool refreshing = false;

  Future<void> _refreshConnection() async {
    final refresh = widget.onRefresh;
    if (refresh == null || refreshing) return;
    setState(() => refreshing = true);
    try {
      await refresh();
    } finally {
      if (mounted) setState(() => refreshing = false);
    }
  }

  bool _wideLayout(double width) =>
      defaultTargetPlatform == TargetPlatform.macOS && width >= 760;

  Capability? get selectedCapability {
    for (final item in widget.capabilities) {
      if (item.id.key == selectedCapabilityKey) return item;
    }
    return null;
  }

  void _openCapability(Capability capability, {required bool embedded}) {
    if (embedded) {
      setState(() => selectedCapabilityKey = capability.id.key);
    } else {
      widget.onOpen(capability);
    }
  }

  @override
  void didUpdateWidget(covariant _GenericConnectionHome oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.connection.id != widget.connection.id ||
        !widget.capabilities.any(
          (item) => item.id.key == selectedCapabilityKey,
        )) {
      selectedCapabilityKey = null;
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final isCli = widget.experience == ConnectionExperience.cli;
      if (_wideLayout(constraints.maxWidth)) {
        return _buildDesktop(context, isCli, constraints.maxWidth);
      }
      return _buildCompact(context, isCli);
    },
  );

  Widget _buildDesktop(BuildContext context, bool isCli, double width) {
    final scheme = Theme.of(context).colorScheme;
    final tokens =
        Theme.of(context).extension<GlassDesignTokens>() ??
        GlassDesignTokens.forBrightness(Theme.of(context).brightness);
    final selected = selectedCapability;
    final directoryWidth = math.min(190.0, math.max(152.0, width * .185));
    return Padding(
      padding: const EdgeInsets.fromLTRB(30, 6, 30, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.connection.label,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _connectionTypeLabel(widget.connection.kind, isCli),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ExcludeSemantics(
                      child: Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          color: tokens.status,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    const SizedBox(width: 7),
                    Text(
                      _connectionStatusLabel(widget.connection.status),
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: tokens.status),
                    ),
                    const SizedBox(width: 12),
                    AggregateActionButton(
                      label: refreshing ? '刷新中…' : '刷新',
                      icon: Icons.refresh,
                      style: AggregateActionStyle.secondary,
                      busy: refreshing,
                      enabled: !refreshing && widget.onRefresh != null,
                      size: GlassButtonSize.compactAction,
                      onPressed: _refreshConnection,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (widget.connection.diagnostic case final diagnostic?) ...[
            const SizedBox(height: 8),
            Text(diagnostic, style: TextStyle(color: scheme.error)),
          ],
          const SizedBox(height: 26),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: directoryWidth,
                  child: CustomScrollView(
                    slivers: widget.capabilities.isEmpty
                        ? [
                            const SliverToBoxAdapter(
                              child: Padding(
                                padding: EdgeInsets.only(top: 12),
                                child: Text('这个连接暂时没有可用功能。请在连接页检查状态。'),
                              ),
                            ),
                          ]
                        : isCli
                        ? _sectionSlivers(
                            context,
                            '命令与动作',
                            widget.capabilities,
                            embedded: true,
                          )
                        : [
                            ..._sectionSlivers(
                              context,
                              '工具',
                              _ofKind(CapabilityKind.mcpTool),
                              embedded: true,
                            ),
                            ..._sectionSlivers(
                              context,
                              '资源',
                              _ofKind(CapabilityKind.mcpResource),
                              embedded: true,
                            ),
                            ..._sectionSlivers(
                              context,
                              '提示',
                              _ofKind(CapabilityKind.mcpPrompt),
                              embedded: true,
                            ),
                          ],
                  ),
                ),
                const SizedBox(width: 19),
                const VerticalDivider(width: 1),
                const SizedBox(width: 28),
                Expanded(
                  child: selected == null
                      ? Center(
                          child: Text(
                            '从左侧目录选择一个功能',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        )
                      : CapabilityRunPage(
                          key: ValueKey('embedded-run-${selected.id.key}'),
                          runtime: widget.runtime,
                          capability: selected,
                          musicSession: widget.musicSession,
                          embedded: true,
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompact(BuildContext context, bool isCli) {
    final scheme = Theme.of(context).colorScheme;
    return PageFrame(
      title: widget.connection.label,
      subtitle: isCli ? '命令与动作' : '工具、资源与提示',
      lazyChildren: widget.capabilities.length >= 40,
      children: [
        Row(
          children: [
            Icon(
              isCli ? Icons.terminal_outlined : Icons.hub_outlined,
              color: scheme.primary,
            ),
            const SizedBox(width: 10),
            Text(switch (widget.connection.status) {
              ConnectionStatus.ready => '已连接',
              ConnectionStatus.connecting => '连接中',
              ConnectionStatus.unavailable => '暂不可用',
            }, style: Theme.of(context).textTheme.bodyMedium),
            const Spacer(),
            Text(
              '${widget.capabilities.length} 项功能',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        const SizedBox(height: 24),
        if (widget.connection.diagnostic case final diagnostic?) ...[
          Text(diagnostic, style: TextStyle(color: scheme.error)),
          const SizedBox(height: 16),
        ],
        if (widget.capabilities.isEmpty)
          const Text('这个连接暂时没有可用功能。请在连接页检查状态。')
        else if (isCli)
          ..._sectionChildren(context, '命令与动作', widget.capabilities)
        else ...[
          ..._sectionChildren(context, '工具', _ofKind(CapabilityKind.mcpTool)),
          ..._sectionChildren(
            context,
            '资源',
            _ofKind(CapabilityKind.mcpResource),
          ),
          ..._sectionChildren(context, '提示', _ofKind(CapabilityKind.mcpPrompt)),
        ],
      ],
    );
  }

  List<Capability> _ofKind(CapabilityKind kind) =>
      widget.capabilities.where((item) => item.id.kind == kind).toList();

  List<Widget> _sectionChildren(
    BuildContext context,
    String title,
    List<Capability> items,
  ) {
    if (items.isEmpty) return const [];
    return [
      Text(title, style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 10),
      for (final capability in items) ...[
        CapabilityRow(
          key: ValueKey('connection-capability-${capability.id.key}'),
          capability: capability,
          source: widget.connection.label,
          onOpen: () => _openCapability(capability, embedded: false),
        ),
        const Divider(height: 1),
      ],
      const SizedBox(height: 22),
    ];
  }

  List<Widget> _sectionSlivers(
    BuildContext context,
    String title,
    List<Capability> items, {
    required bool embedded,
  }) {
    if (items.isEmpty) return const [];
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            title,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
      SliverList(
        delegate: SliverChildBuilderDelegate((context, index) {
          final capability = items[index];
          return Column(
            key: ValueKey('connection-capability-${capability.id.key}'),
            mainAxisSize: MainAxisSize.min,
            children: [
              CapabilityRow(
                capability: capability,
                source: widget.connection.label,
                compactDirectory: true,
                selected:
                    embedded && selectedCapabilityKey == capability.id.key,
                onOpen: () => _openCapability(capability, embedded: embedded),
              ),
              const SizedBox(height: 5),
            ],
          );
        }, childCount: items.length),
      ),
      const SliverToBoxAdapter(child: SizedBox(height: 22)),
    ];
  }
}

String _connectionTypeLabel(ConnectionKind kind, bool isCli) => switch (kind) {
  ConnectionKind.cli => isCli ? 'CLI 程序' : 'CLI 连接',
  ConnectionKind.mcpStdio => '本机 MCP',
  ConnectionKind.mcpHttp => 'HTTP MCP',
};

String _connectionStatusLabel(ConnectionStatus status) => switch (status) {
  ConnectionStatus.ready => '已连接',
  ConnectionStatus.connecting => '连接中',
  ConnectionStatus.unavailable => '暂不可用',
};
