import 'dart:math' as math;

import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../widgets/capability_row.dart';
import '../../widgets/glass/aggregate_buttons.dart';
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
    this.showMusicDesignPreview = false,
    this.onAccountChanged,
    this.onRefresh,
  });

  final Connection connection;
  final List<Capability> capabilities;
  final RuntimePort runtime;
  final MusicSession musicSession;
  final ValueChanged<Capability> onOpen;
  final bool showMusicDesignPreview;
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
        showPreviewSample: showMusicDesignPreview,
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

  @override
  void initState() {
    super.initState();
    selectedCapabilityKey = widget.capabilities.isEmpty
        ? null
        : widget.capabilities.first.id.key;
  }

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
      selectedCapabilityKey = widget.capabilities.isEmpty
          ? null
          : widget.capabilities.first.id.key;
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
    final selected = selectedCapability;
    final contentWidth = width - 88;
    final directoryWidth = math.min(
      306.0,
      math.max(240.0, contentWidth * .297),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 32, 48, 24),
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
                      key: const Key('connection-home-header-title'),
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '查看当前连接提供的能力与最近结果',
                      key: const Key('connection-home-header-subtitle'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (widget.onRefresh != null)
                SizedBox(
                  key: const Key('connection-home-refresh'),
                  width: 46,
                  height: 46,
                  child: AggregateIconButton(
                    tooltip: '刷新能力',
                    icon: Icons.refresh,
                    onPressed: _refreshConnection,
                    enabled: !refreshing,
                    busy: refreshing,
                  ),
                ),
            ],
          ),
          if (widget.connection.diagnostic case final diagnostic?) ...[
            const SizedBox(height: 8),
            Text(diagnostic, style: TextStyle(color: scheme.error)),
          ],
          const SizedBox(height: 32),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  key: const Key('connection-home-directory'),
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
                            '能力目录',
                            widget.capabilities,
                            detail: '选择一项查看详情或填写参数',
                            embedded: true,
                          )
                        : [
                            SliverToBoxAdapter(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '能力目录',
                                    key: const Key(
                                      'connection-home-directory-title',
                                    ),
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(
                                          fontWeight: FontWeight.w600,
                                          height: 1.2,
                                        ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    '选择一项查看详情或填写参数',
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(fontSize: 11, height: 1.2),
                                  ),
                                ],
                              ),
                            ),
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
                const SizedBox(width: 24),
                const VerticalDivider(
                  key: Key('connection-home-directory-divider'),
                  width: 1,
                ),
                const SizedBox(width: 30),
                Expanded(
                  child: KeyedSubtree(
                    key: const Key('connection-home-run-pane'),
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
                            embeddedTopInset: 37,
                            connectionHome: true,
                          ),
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
    String? detail,
    required bool embedded,
  }) {
    if (items.isEmpty) return const [];
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                key: title == '能力目录'
                    ? const Key('connection-home-directory-title')
                    : null,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (detail case final value?) ...[
                const SizedBox(height: 3),
                Text(value, style: Theme.of(context).textTheme.bodySmall),
              ],
            ],
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
                directorySubtitle: capability.description,
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
