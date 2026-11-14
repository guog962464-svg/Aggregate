import 'dart:math' as math;

import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../widgets/capability_row.dart';
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
  });

  final Connection connection;
  final List<Capability> capabilities;
  final RuntimePort runtime;
  final MusicSession musicSession;
  final ValueChanged<Capability> onOpen;
  final VoidCallback? onAccountChanged;

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
  });

  final Connection connection;
  final List<Capability> capabilities;
  final ConnectionExperience experience;
  final RuntimePort runtime;
  final MusicSession musicSession;
  final ValueChanged<Capability> onOpen;

  @override
  State<_GenericConnectionHome> createState() => _GenericConnectionHomeState();
}

class _GenericConnectionHomeState extends State<_GenericConnectionHome> {
  String? selectedCapabilityKey;

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
    final selected = selectedCapability;
    final directoryWidth = math.min(300.0, math.max(232.0, width * .32));
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 28, 32, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.connection.label,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          Text(
            isCli ? '命令与动作 · 选择一个功能后填写参数并运行。' : '工具、资源与提示 · 选择一项查看参数和结果。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(
                isCli ? Icons.terminal_outlined : Icons.hub_outlined,
                color: scheme.primary,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(switch (widget.connection.status) {
                ConnectionStatus.ready => '已连接',
                ConnectionStatus.connecting => '连接中',
                ConnectionStatus.unavailable => '暂不可用',
              }),
              const SizedBox(width: 12),
              Text(
                '${widget.capabilities.length} 项功能',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          if (widget.connection.diagnostic case final diagnostic?) ...[
            const SizedBox(height: 10),
            Text(diagnostic, style: TextStyle(color: scheme.error)),
          ],
          const SizedBox(height: 18),
          const Divider(height: 1),
          const SizedBox(height: 14),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: directoryWidth,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: widget.capabilities.isEmpty
                          ? [
                              const Padding(
                                padding: EdgeInsets.only(top: 12),
                                child: Text('这个连接暂时没有可用功能。请在连接页检查状态。'),
                              ),
                            ]
                          : isCli
                          ? [
                              _section(
                                context,
                                '命令与动作',
                                widget.capabilities,
                                embedded: true,
                              ),
                            ]
                          : [
                              _section(
                                context,
                                '工具',
                                _ofKind(CapabilityKind.mcpTool),
                                embedded: true,
                              ),
                              _section(
                                context,
                                '资源',
                                _ofKind(CapabilityKind.mcpResource),
                                embedded: true,
                              ),
                              _section(
                                context,
                                '提示',
                                _ofKind(CapabilityKind.mcpPrompt),
                                embedded: true,
                              ),
                            ],
                    ),
                  ),
                ),
                const SizedBox(width: 18),
                const VerticalDivider(width: 1),
                const SizedBox(width: 20),
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
          _section(context, '命令与动作', widget.capabilities)
        else ...[
          _section(context, '工具', _ofKind(CapabilityKind.mcpTool)),
          _section(context, '资源', _ofKind(CapabilityKind.mcpResource)),
          _section(context, '提示', _ofKind(CapabilityKind.mcpPrompt)),
        ],
      ],
    );
  }

  List<Capability> _ofKind(CapabilityKind kind) =>
      widget.capabilities.where((item) => item.id.kind == kind).toList();

  Widget _section(
    BuildContext context,
    String title,
    List<Capability> items, {
    bool embedded = false,
  }) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          for (final capability in items) ...[
            CapabilityRow(
              capability: capability,
              source: widget.connection.label,
              selected: embedded && selectedCapabilityKey == capability.id.key,
              onOpen: () => _openCapability(capability, embedded: embedded),
            ),
            const Divider(height: 1),
          ],
        ],
      ),
    );
  }
}
