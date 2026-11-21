import 'dart:convert';
import 'dart:math' as math;

import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../widgets/glass/aggregate_buttons.dart';
import '../../widgets/glass/glass_alert_dialog.dart';
import '../../widgets/glass/glass_action_button.dart';
import '../../widgets/glass/glass_glyph.dart';
import '../../widgets/glass/glass_motion.dart';
import '../../widgets/page_frame.dart';
import '../../widgets/page_state.dart';
import '../../widgets/capability_row.dart';
import 'action_editor_dialog.dart';
import 'connection_setup_dialog.dart';
import 'connection_setup_target_dialog.dart';
import 'connection_experience.dart';

class ConnectionsPage extends StatefulWidget {
  const ConnectionsPage({
    super.key,
    required this.runtime,
    required this.onOpen,
    this.onOpenConnection,
    this.onChanged,
    this.onAdded,
  });
  final RuntimePort runtime;
  final ValueChanged<Capability> onOpen;
  final ValueChanged<Connection>? onOpenConnection;
  final VoidCallback? onChanged;
  final ValueChanged<Connection>? onAdded;

  @override
  State<ConnectionsPage> createState() => ConnectionsPageState();
}

class ConnectionsPageState extends State<ConnectionsPage> {
  static const _lazyListThreshold = 40;

  late Future<List<Connection>> pending;
  List<Capability> catalog = [];
  String? selectedId;
  String? error;
  bool addingConnection = false;

  bool _usesGlassButtons(BuildContext context) =>
      defaultTargetPlatform == TargetPlatform.macOS &&
      GlassMotionScope.maybeOf(context) != null;

  @override
  void initState() {
    super.initState();
    pending = widget.runtime.listConnections();
    widget.runtime.searchCapabilities(const SearchQuery('')).then((items) {
      if (mounted) setState(() => catalog = items);
    });
  }

  void reload() {
    setState(() {
      pending = widget.runtime.listConnections();
    });
    widget.runtime.searchCapabilities(const SearchQuery('')).then((items) {
      if (mounted) setState(() => catalog = items);
    });
  }

  Future<void> add({ConnectionKind initialKind = ConnectionKind.cli}) async {
    if (addingConnection) return;
    setState(() => addingConnection = true);
    try {
      if (widget.runtime.isPreview) {
        await showGlassDialog<void>(
          context: context,
          builder: (_) => const GlassAlertDialog(
            title: Text('添加连接'),
            content: Text('预览模式不能添加真实连接。'),
          ),
        );
        return;
      }
      final Connection? connection;
      if (widget.runtime case final ConnectionSetupPort setup) {
        final ConnectionSetupPort selectedSetup;
        String? selectedTargetLabel;
        if (widget.runtime case final ConnectionSetupTargetPort targetPort) {
          final targets = await targetPort.listSetupTargets();
          if (!mounted) return;
          final target = await showConnectionSetupTargetDialog(
            context,
            targets,
          );
          if (target == null) return;
          selectedTargetLabel = targets
              .where((option) => option.target == target)
              .firstOrNull
              ?.label;
          selectedSetup = await targetPort.setupForTarget(target);
          if (!mounted) return;
        } else {
          selectedSetup = setup;
          if (Theme.of(context).platform == TargetPlatform.macOS) {
            selectedTargetLabel = '本机 Mac';
          }
        }
        final allowedKinds = selectedSetup.connectionAdapters
            .map((adapter) => adapter.kind)
            .toSet();
        if (allowedKinds.isEmpty) {
          setState(() => error = '此运行端没有可用的连接适配器。');
          return;
        }
        if (!allowedKinds.contains(initialKind)) {
          initialKind = ConnectionKind.values.firstWhere(allowedKinds.contains);
        }
        final inspectionValues =
            widget.runtime is ConnectionSetupInspectionSamplesPort
            ? (widget.runtime as ConnectionSetupInspectionSamplesPort)
                  .connectionSetupInitialValues
            : const <String, Map<String, String>>{};
        connection = await showGlassDialog<Connection>(
          context: context,
          builder: (_) => ConnectionSetupDialog(
            setup: selectedSetup,
            initialKind: initialKind,
            allowedKinds: allowedKinds,
            selectedTargetLabel: selectedTargetLabel,
            initialValuesByAdapter: inspectionValues,
          ),
        );
      } else {
        final allowedKinds = widget.runtime.features.connectionKinds;
        if (allowedKinds.isEmpty) return;
        if (!allowedKinds.contains(initialKind)) {
          initialKind = ConnectionKind.values.firstWhere(allowedKinds.contains);
        }
        final spec = await showGlassDialog<ConnectionSpec>(
          context: context,
          builder: (_) => AddConnectionDialog(
            initialKind: initialKind,
            allowedKinds: allowedKinds,
          ),
        );
        connection = spec == null
            ? null
            : await widget.runtime.addConnection(spec);
      }
      if (connection == null) return;
      if (!mounted) return;
      setState(() => error = connection!.diagnostic);
      selectedId = connection.id.value;
      reload();
      widget.onChanged?.call();
      widget.onAdded?.call(connection);
    } catch (cause) {
      if (mounted) setState(() => error = '$cause');
    } finally {
      if (mounted) setState(() => addingConnection = false);
    }
  }

  Future<void> refresh(Connection connection) async {
    final updated = await widget.runtime.refreshConnection(connection.id);
    if (!mounted) return;
    setState(() => error = updated.diagnostic);
    reload();
    widget.onChanged?.call();
  }

  Future<void> remove(Connection connection) async {
    final confirmed = await showGlassDialog<bool>(
      context: context,
      builder: (_) => GlassAlertDialog(
        title: Text('删除 ${connection.label}？'),
        content: Text(
          connection.executionTarget.kind == ExecutionTargetKind.host
              ? '此连接将从配对的 Mac Host 删除。'
              : '此连接的配置将从本机移除。',
        ),
        actions: [
          AggregateActionButton(
            label: '取消',
            icon: Icons.close,
            style: AggregateActionStyle.quiet,
            onPressed: () => Navigator.pop(context, false),
          ),
          AggregateActionButton(
            label: '删除',
            icon: Icons.delete_outline,
            style: AggregateActionStyle.danger,
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.runtime.removeConnection(connection.id);
    if (!mounted) return;
    if (selectedId == connection.id.value) selectedId = null;
    reload();
    widget.onChanged?.call();
  }

  Future<void> editActions(Connection connection) async {
    final saved = await showGlassDialog<bool>(
      context: context,
      builder: (_) =>
          ActionEditorDialog(runtime: widget.runtime, connection: connection),
    );
    if (saved == true && mounted) {
      reload();
      widget.onChanged?.call();
    }
  }

  Future<void> move(Connection connection, int offset) async {
    try {
      await widget.runtime.moveConnection(connection.id, offset);
      if (!mounted) return;
      reload();
      widget.onChanged?.call();
    } catch (cause) {
      if (mounted) setState(() => error = '$cause');
    }
  }

  @override
  Widget build(BuildContext context) {
    final macDesign = _usesGlassButtons(context);
    final canAddConnection = widget.runtime.features.connectionKinds.isNotEmpty;
    return PageFrame(
      title: macDesign ? '管理连接' : '连接',
      subtitle: macDesign
          ? '查看连接状态、诊断与可执行的管理操作'
          : widget.runtime is ConnectionSetupTargetPort
          ? '管理本机 HTTP MCP 与配对 Mac Host 连接。'
          : widget.runtime.isPreview
          ? '预览连接。'
          : widget.runtime.features.connectionKinds.isEmpty
          ? '此运行端的连接功能尚未开放。'
          : widget.runtime.features.connectionKinds.length == 1 &&
                widget.runtime.features.canAdd(ConnectionKind.mcpHttp)
          ? '管理 HTTP MCP 连接。'
          : '管理 CLI 与 MCP 连接。',
      trailing: macDesign && canAddConnection
          ? SizedBox(
              width: 148,
              child: Padding(
                padding: const EdgeInsets.only(top: 7),
                child: SizedBox(
                  height: 46,
                  child: AggregateActionButton(
                    key: const Key('managed-add-connection'),
                    label: addingConnection ? '正在准备连接向导…' : '添加连接',
                    icon: addingConnection
                        ? Icons.hourglass_top_outlined
                        : Icons.add,
                    style: AggregateActionStyle.primary,
                    onPressed: addingConnection ? null : () => add(),
                    enabled: !addingConnection,
                  ),
                ),
              ),
            )
          : null,
      headerSpacing: macDesign ? 17 : 24,
      children: [
        if (!macDesign && canAddConnection)
          Align(
            alignment: Alignment.centerLeft,
            child: AggregateActionButton(
              label: addingConnection ? '正在准备连接向导…' : '添加连接',
              icon: addingConnection ? Icons.hourglass_top_outlined : Icons.add,
              style: AggregateActionStyle.primary,
              onPressed: addingConnection ? null : () => add(),
              enabled: !addingConnection,
            ),
          ),
        if (error != null) ...[
          const SizedBox(height: 12),
          Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        if (!macDesign) const SizedBox(height: 24),
        FutureBuilder<List<Connection>>(
          future: pending,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return PageState.error(
                '加载连接失败：${snapshot.error}',
                onRetry: reload,
              );
            }
            if (!snapshot.hasData) return const PageState.loading();
            final connections = snapshot.data!;
            if (connections.isEmpty) {
              return PageState.empty(
                widget.runtime.features.connectionKinds.isEmpty
                    ? '当前运行端尚无可添加的连接。'
                    : '还没有连接。添加一个连接开始使用。',
                glyph: GlassGlyph.network,
              );
            }
            return LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 720;
                final selected =
                    connections
                        .where((item) => item.id.value == selectedId)
                        .firstOrNull ??
                    (wide ? connections.first : null);
                final selectedIndex = selected == null
                    ? -1
                    : connections.indexWhere(
                        (item) => item.id.value == selected.id.value,
                      );
                if (macDesign && constraints.maxWidth >= 760) {
                  return _macManagementLayout(
                    connections,
                    selected!,
                    selectedIndex,
                  );
                }
                if (!wide && selected != null) {
                  return _detail(
                    selected,
                    compact: true,
                    canMoveUp: selectedIndex > 0,
                    canMoveDown: selectedIndex < connections.length - 1,
                  );
                }
                final list = _connectionList(context, connections, selected);
                if (!wide) return list;
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 4, child: list),
                    const SizedBox(width: 24),
                    Expanded(
                      flex: 6,
                      child: _detail(
                        selected!,
                        canMoveUp: selectedIndex > 0,
                        canMoveDown: selectedIndex < connections.length - 1,
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ],
    );
  }

  Widget _macManagementLayout(
    List<Connection> connections,
    Connection selected,
    int selectedIndex,
  ) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: 285,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('连接列表', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              '选择连接查看详情 · 使用操作调整顺序',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 0),
            _connectionList(context, connections, selected),
          ],
        ),
      ),
      const SizedBox(width: 59),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.only(top: 39),
          child: _macDetail(
            selected,
            canMoveUp: selectedIndex > 0,
            canMoveDown: selectedIndex < connections.length - 1,
          ),
        ),
      ),
    ],
  );

  Widget _macDetail(
    Connection connection, {
    required bool canMoveUp,
    required bool canMoveDown,
  }) {
    final capabilities = catalog
        .where((item) => item.id.connection.value == connection.id.value)
        .toList();
    final theme = Theme.of(context);
    final body = theme.textTheme.bodySmall;

    Widget sectionHeading(
      String title, {
      String? detail,
      double detailSpacing = 0,
    }) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.titleMedium),
        if (detail != null) ...[
          SizedBox(height: detailSpacing),
          Text(detail, style: body),
        ],
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(connection.label, style: theme.textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    runSpacing: 6,
                    children: [
                      Text(
                        _targetPresentationName(connection.executionTarget),
                        style: body,
                      ),
                      _macStatus(
                        _status(connection.status),
                        status: connection.status,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (!widget.runtime.isPreview)
              Padding(
                padding: const EdgeInsets.only(right: 61),
                child: SizedBox(
                  width: 142,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: SizedBox(
                      height: 46,
                      child: AggregateActionButton(
                        key: const Key('managed-test-connection'),
                        label: '测试连接',
                        icon: Icons.refresh,
                        onPressed: () => refresh(connection),
                        size: GlassButtonSize.compactAction,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 27),
        sectionHeading('连接信息'),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 129, child: Text('执行程序', style: body)),
            Expanded(
              child: SelectableText(
                connection.location,
                style: const TextStyle(fontFamily: 'monospace'),
              ),
            ),
          ],
        ),
        if (connection.protocolVersion != null) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              SizedBox(width: 129, child: Text('服务版本', style: body)),
              Expanded(child: Text(connection.protocolVersion!)),
            ],
          ),
        ],
        const SizedBox(height: 4),
        Divider(color: theme.dividerColor.withValues(alpha: .72)),
        const SizedBox(height: 16),
        sectionHeading('可用功能', detail: '${capabilities.length} 项 · 选择后打开参数与结果'),
        const SizedBox(height: 0),
        if (capabilities.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text('当前没有可用功能。刷新连接后重试。', style: body),
          )
        else if (capabilities.length >= _lazyListThreshold)
          SizedBox(
            key: const Key('managed-capability-list'),
            height: _capabilityListHeight(context),
            child: ListView.separated(
              primary: false,
              padding: EdgeInsets.zero,
              itemCount: capabilities.length,
              itemBuilder: (context, index) =>
                  _macCapabilityRow(capabilities[index], connection),
              separatorBuilder: (_, _) => Divider(
                height: 7,
                thickness: 1,
                color: theme.dividerColor.withValues(alpha: .72),
              ),
            ),
          )
        else
          for (final capability in capabilities) ...[
            _macCapabilityRow(capability, connection),
            Divider(
              height: 7,
              thickness: 1,
              color: theme.dividerColor.withValues(alpha: .72),
            ),
          ],
        const SizedBox(height: 30),
        sectionHeading(
          '诊断',
          detail: widget.runtime is ConnectionSetupInspectionSamplesPort
              ? '当前数据来自只读预览'
              : null,
          detailSpacing: 6,
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _macStatus(_status(connection.status), status: connection.status),
            const SizedBox(width: 22),
            Expanded(
              child: Text(
                connection.diagnostic ?? '已发现 ${capabilities.length} 项功能',
                style: connection.diagnostic == null
                    ? body
                    : TextStyle(color: theme.colorScheme.error),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 26),
        if (!widget.runtime.isPreview) ...[
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Row(
              children: [
                if (connection.kind == ConnectionKind.cli &&
                    connection.executionTarget.kind ==
                        ExecutionTargetKind.device)
                  SizedBox(
                    width: 124,
                    height: 40,
                    child: AggregateActionButton(
                      label: '编辑动作',
                      icon: Icons.edit_outlined,
                      onPressed: () => editActions(connection),
                      size: GlassButtonSize.compactAction,
                    ),
                  ),
                if (connection.kind == ConnectionKind.cli &&
                    connection.executionTarget.kind ==
                        ExecutionTargetKind.device)
                  const SizedBox(width: 11),
                SizedBox(
                  width: 91,
                  height: 40,
                  child: AggregateActionButton(
                    semanticsLabel: '连接上移',
                    label: '上移',
                    icon: Icons.arrow_upward,
                    onPressed: canMoveUp ? () => move(connection, -1) : null,
                    enabled: canMoveUp,
                    size: GlassButtonSize.compactAction,
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 91,
                  height: 40,
                  child: AggregateActionButton(
                    semanticsLabel: '连接下移',
                    label: '下移',
                    icon: Icons.arrow_downward,
                    onPressed: canMoveDown ? () => move(connection, 1) : null,
                    enabled: canMoveDown,
                    size: GlassButtonSize.compactAction,
                  ),
                ),
                const Spacer(),
                SizedBox(
                  width: 136,
                  height: 40,
                  child: AggregateActionButton(
                    label: '删除连接',
                    icon: Icons.delete_outline,
                    style: AggregateActionStyle.danger,
                    onPressed: () => remove(connection),
                    size: GlassButtonSize.compactAction,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _macCapabilityRow(
    Capability capability,
    Connection connection,
  ) => AggregateActionButton(
    key: ValueKey('managed-capability-${capability.id.key}'),
    label: capability.title,
    semanticsLabel:
        '${capability.title}；${capability.description}；来源：${connection.label}',
    icon: switch (capability.id.kind) {
      CapabilityKind.cliCommand => Icons.terminal_outlined,
      CapabilityKind.cliAction => Icons.play_circle_outline,
      CapabilityKind.mcpTool => Icons.build_outlined,
      CapabilityKind.mcpResource => Icons.description_outlined,
      CapabilityKind.mcpPrompt => Icons.chat_bubble_outline,
    },
    style: AggregateActionStyle.quiet,
    onPressed: () => widget.onOpen(capability),
    size: GlassButtonSize.capabilityRow,
    expand: true,
  );

  Widget _macStatus(String label, {required ConnectionStatus status}) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _statusColor(status),
        ),
      ),
      const SizedBox(width: 8),
      Text(
        label,
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: _statusColor(status)),
      ),
    ],
  );

  Widget _detail(
    Connection connection, {
    bool compact = false,
    bool canMoveUp = false,
    bool canMoveDown = false,
  }) {
    final capabilities = catalog
        .where((item) => item.id.connection.value == connection.id.value)
        .toList();
    return Container(
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
              label: '返回连接',
              icon: Icons.arrow_back,
              style: AggregateActionStyle.quiet,
              onPressed: () => setState(() => selectedId = null),
            ),
          Text(
            connection.label,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            '${_kind(connection.kind)} · ${widget.runtime.isPreview ? '预览' : _status(connection.status)}',
          ),
          const SizedBox(height: 20),
          Text('程序或地址', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          SelectableText(
            connection.location,
            style: const TextStyle(fontFamily: 'monospace'),
          ),
          if (connection.protocolVersion != null) ...[
            const SizedBox(height: 16),
            Text('服务版本 ${connection.protocolVersion}'),
          ],
          if (connection.diagnostic != null) ...[
            const SizedBox(height: 16),
            Text(
              '连接诊断：${connection.diagnostic}',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          if (widget.onOpenConnection != null) ...[
            const SizedBox(height: 16),
            AggregateActionButton(
              label:
                  experienceFor(connection, catalog) ==
                      ConnectionExperience.music
                  ? '打开播放器'
                  : '打开连接工作区',
              icon:
                  experienceFor(connection, catalog) ==
                      ConnectionExperience.music
                  ? Icons.music_note_outlined
                  : Icons.open_in_new,
              style: AggregateActionStyle.secondary,
              onPressed: () => widget.onOpenConnection!(connection),
            ),
          ],
          const SizedBox(height: 20),
          Text(
            '已发现 ${capabilities.length} 项功能',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (capabilities.isEmpty) const Text('当前没有可用功能。刷新连接后重试。'),
          if (capabilities.length >= _lazyListThreshold)
            SizedBox(
              key: const Key('managed-capability-list'),
              height: _capabilityListHeight(context),
              child: ListView.separated(
                primary: false,
                padding: EdgeInsets.zero,
                itemCount: capabilities.length,
                itemBuilder: (context, index) {
                  final capability = capabilities[index];
                  return CapabilityRow(
                    key: ValueKey('managed-capability-${capability.id.key}'),
                    capability: capability,
                    source: connection.label,
                    onOpen: () => widget.onOpen(capability),
                  );
                },
                separatorBuilder: (context, index) => const Divider(height: 1),
              ),
            ),
          if (capabilities.isNotEmpty &&
              capabilities.length < _lazyListThreshold)
            for (final capability in capabilities) ...[
              CapabilityRow(
                key: ValueKey('managed-capability-${capability.id.key}'),
                capability: capability,
                source: connection.label,
                onOpen: () => widget.onOpen(capability),
              ),
              const Divider(height: 1),
            ],
          if (!widget.runtime.isPreview) ...[
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                AggregateIconButton(
                  tooltip: '连接上移',
                  icon: Icons.arrow_upward,
                  onPressed: canMoveUp ? () => move(connection, -1) : null,
                  enabled: canMoveUp,
                ),
                AggregateIconButton(
                  tooltip: '连接下移',
                  icon: Icons.arrow_downward,
                  onPressed: canMoveDown ? () => move(connection, 1) : null,
                  enabled: canMoveDown,
                ),
                if (connection.kind == ConnectionKind.cli &&
                    connection.executionTarget.kind ==
                        ExecutionTargetKind.device)
                  AggregateActionButton(
                    label: '编辑动作',
                    icon: Icons.edit_outlined,
                    onPressed: () => editActions(connection),
                  ),
                AggregateActionButton(
                  label: '测试连接',
                  icon: Icons.refresh,
                  onPressed: () => refresh(connection),
                ),
                AggregateActionButton(
                  label: '删除连接',
                  icon: Icons.delete_outline,
                  style: AggregateActionStyle.danger,
                  onPressed: () => remove(connection),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _connectionList(
    BuildContext context,
    List<Connection> connections,
    Connection? selected,
  ) {
    if (_usesGlassButtons(context) && connections.length < _lazyListThreshold) {
      return Column(
        children: [
          for (var index = 0; index < connections.length; index++) ...[
            _connectionRow(context, connections[index], selected),
            if (index > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Divider(
                  height: 1,
                  thickness: 1,
                  color: Theme.of(context).dividerColor.withValues(alpha: .58),
                ),
              ),
            if (index != connections.length - 1) const SizedBox(height: 9),
          ],
        ],
      );
    }
    if (_usesGlassButtons(context)) {
      return SizedBox(
        key: const Key('managed-connection-list'),
        height: _connectionListHeight(context),
        child: ListView.separated(
          primary: false,
          padding: EdgeInsets.zero,
          itemCount: connections.length,
          itemBuilder: (context, index) =>
              _connectionRow(context, connections[index], selected),
          separatorBuilder: (_, index) => index == 0
              ? const SizedBox(height: 9)
              : Divider(
                  height: 9,
                  thickness: 1,
                  color: Theme.of(context).dividerColor.withValues(alpha: .58),
                ),
        ),
      );
    }
    if (connections.length < _lazyListThreshold) {
      return Column(
        children: [
          for (final connection in connections) ...[
            _connectionRow(context, connection, selected),
            const Divider(height: 1),
          ],
        ],
      );
    }

    return SizedBox(
      key: const Key('managed-connection-list'),
      height: _connectionListHeight(context),
      child: ListView.separated(
        primary: false,
        padding: EdgeInsets.zero,
        itemCount: connections.length,
        itemBuilder: (context, index) =>
            _connectionRow(context, connections[index], selected),
        separatorBuilder: (context, index) => const Divider(height: 1),
      ),
    );
  }

  Widget _connectionRow(
    BuildContext context,
    Connection connection,
    Connection? selected,
  ) {
    final row = _usesGlassButtons(context)
        ? AggregateActionButton(
            label: connection.label,
            description:
                '${_kind(connection.kind)} · '
                '${_targetName(connection.executionTarget)} · '
                '${widget.runtime.isPreview ? '预览' : _status(connection.status)}',
            semanticsLabel:
                '${connection.label}，${_kind(connection.kind)}，'
                '${_targetName(connection.executionTarget)}，'
                '${widget.runtime.isPreview ? '预览' : _status(connection.status)}',
            leading: SizedBox(
              width: 10,
              height: 10,
              child: Center(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: _statusColor(connection.status),
                    shape: BoxShape.circle,
                  ),
                  child: const SizedBox.square(dimension: 7),
                ),
              ),
            ),
            icon: switch (connection.kind) {
              ConnectionKind.cli => Icons.terminal_outlined,
              ConnectionKind.mcpStdio ||
              ConnectionKind.mcpHttp => Icons.hub_outlined,
            },
            style: AggregateActionStyle.quiet,
            size: GlassButtonSize.targetOption,
            onPressed: () => setState(() => selectedId = connection.id.value),
            selected: selected?.id.value == connection.id.value,
            expand: true,
          )
        : ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            selected: selected?.id.value == connection.id.value,
            title: Tooltip(
              message: connection.label,
              child: Text(
                connection.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            subtitle: Text(_kind(connection.kind)),
            trailing: Text(
              widget.runtime.isPreview ? '预览' : _status(connection.status),
              style: TextStyle(
                color: connection.status == ConnectionStatus.unavailable
                    ? Theme.of(context).colorScheme.error
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            onTap: () => setState(() => selectedId = connection.id.value),
          );
    return KeyedSubtree(
      key: ValueKey('managed-connection-${connection.id.value}'),
      child: row,
    );
  }

  double _connectionListHeight(BuildContext context) =>
      math.min(520.0, math.max(240.0, MediaQuery.sizeOf(context).height - 300));

  double _capabilityListHeight(BuildContext context) =>
      math.min(360.0, math.max(200.0, MediaQuery.sizeOf(context).height * .42));
}

String _targetName(ExecutionTarget target) => switch (target.kind) {
  ExecutionTargetKind.device => '本机',
  ExecutionTargetKind.host => 'Mac Host',
};

String _targetPresentationName(ExecutionTarget target) => switch (target.kind) {
  ExecutionTargetKind.device => '本机执行',
  ExecutionTargetKind.host => 'Mac Host',
};

Color _statusColor(ConnectionStatus status) => switch (status) {
  ConnectionStatus.ready => const Color(0xFF39765D),
  ConnectionStatus.connecting => const Color(0xFFB56F16),
  ConnectionStatus.unavailable => const Color(0xFFB54C43),
};

String _kind(ConnectionKind kind) => switch (kind) {
  ConnectionKind.cli => 'CLI 程序',
  ConnectionKind.mcpStdio => '本机 MCP',
  ConnectionKind.mcpHttp => '远程 MCP',
};

String _status(ConnectionStatus status) => switch (status) {
  ConnectionStatus.ready => '就绪',
  ConnectionStatus.connecting => '连接中',
  ConnectionStatus.unavailable => '不可用',
};

class AddConnectionDialog extends StatefulWidget {
  const AddConnectionDialog({
    super.key,
    this.initialKind = ConnectionKind.cli,
    this.allowedKinds = const {
      ConnectionKind.cli,
      ConnectionKind.mcpStdio,
      ConnectionKind.mcpHttp,
    },
  });
  final ConnectionKind initialKind;
  final Set<ConnectionKind> allowedKinds;
  @override
  State<AddConnectionDialog> createState() => _AddConnectionDialogState();
}

class _AddConnectionDialogState extends State<AddConnectionDialog> {
  final label = TextEditingController();
  final executable = TextEditingController();
  final arguments = TextEditingController(text: '[]');
  final directory = TextEditingController();
  final url = TextEditingController();
  final manifest = TextEditingController();
  final token = TextEditingController();
  late ConnectionKind kind;
  String? error;

  @override
  void initState() {
    super.initState();
    assert(widget.allowedKinds.isNotEmpty);
    kind = widget.allowedKinds.contains(widget.initialKind)
        ? widget.initialKind
        : ConnectionKind.values.firstWhere(widget.allowedKinds.contains);
  }

  @override
  void dispose() {
    for (final controller in [
      label,
      executable,
      arguments,
      directory,
      url,
      manifest,
      token,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> choose(TextEditingController controller) async {
    final file = await openFile();
    if (file != null) controller.text = file.path;
  }

  void submit() {
    try {
      final parsed = jsonDecode(arguments.text);
      if (parsed is! List || parsed.any((item) => item is! String)) {
        throw const FormatException('启动参数必须是 JSON 字符串数组');
      }
      if (label.text.trim().isEmpty) {
        throw const FormatException('请输入连接名称');
      }
      if (kind == ConnectionKind.mcpHttp) {
        final endpoint = Uri.tryParse(url.text.trim());
        if (endpoint == null ||
            !endpoint.hasAuthority ||
            !['http', 'https'].contains(endpoint.scheme)) {
          throw const FormatException('请输入有效的 HTTP MCP 地址');
        }
      } else if (executable.text.trim().isEmpty) {
        throw const FormatException('请选择程序绝对路径');
      }
      Navigator.pop(
        context,
        ConnectionSpec(
          kind: kind,
          label: label.text.trim(),
          executable: kind == ConnectionKind.mcpHttp
              ? null
              : executable.text.trim(),
          arguments: parsed.cast<String>(),
          workingDirectory: directory.text.trim().isEmpty
              ? null
              : directory.text.trim(),
          url: kind == ConnectionKind.mcpHttp ? url.text.trim() : null,
          authToken:
              kind == ConnectionKind.mcpHttp && token.text.trim().isNotEmpty
              ? token.text.trim()
              : null,
          manifestPath:
              kind == ConnectionKind.cli && manifest.text.trim().isNotEmpty
              ? manifest.text.trim()
              : null,
        ),
      );
    } catch (cause) {
      setState(() => error = '$cause');
    }
  }

  @override
  Widget build(BuildContext context) => GlassAlertDialog(
    title: const Text('添加连接'),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<ConnectionKind>(
              initialValue: kind,
              decoration: const InputDecoration(labelText: '类型'),
              items: [
                for (final item in ConnectionKind.values)
                  if (widget.allowedKinds.contains(item))
                    DropdownMenuItem(
                      value: item,
                      child: Text(switch (item) {
                        ConnectionKind.cli => 'CLI 程序',
                        ConnectionKind.mcpStdio => 'stdio MCP',
                        ConnectionKind.mcpHttp => 'HTTP MCP',
                      }),
                    ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => kind = value);
              },
            ),
            const SizedBox(height: 16),
            TextField(
              controller: label,
              decoration: const InputDecoration(labelText: '名称'),
            ),
            const SizedBox(height: 16),
            if (kind == ConnectionKind.mcpHttp) ...[
              TextField(
                controller: url,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(labelText: 'HTTP URL'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: token,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Bearer Token（可选）',
                  helperText: '保存在当前运行端的安全存储中',
                ),
              ),
            ] else ...[
              TextField(
                controller: executable,
                decoration: InputDecoration(
                  labelText: '程序绝对路径',
                  suffixIcon: AggregateIconButton(
                    tooltip: '选择程序',
                    icon: Icons.folder_open_outlined,
                    onPressed: () => choose(executable),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: arguments,
                decoration: const InputDecoration(labelText: '启动参数 JSON 数组'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: directory,
                decoration: const InputDecoration(labelText: '工作目录（可选）'),
              ),
              if (kind == ConnectionKind.cli) ...[
                const SizedBox(height: 16),
                TextField(
                  controller: manifest,
                  decoration: InputDecoration(
                    labelText: '动作清单 JSON（可选）',
                    suffixIcon: AggregateIconButton(
                      tooltip: '选择动作清单',
                      icon: Icons.folder_open_outlined,
                      onPressed: () => choose(manifest),
                    ),
                  ),
                ),
              ],
            ],
            if (error != null) ...[
              const SizedBox(height: 12),
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    ),
    actions: [
      AggregateActionButton(
        label: '取消',
        icon: Icons.close,
        style: AggregateActionStyle.quiet,
        onPressed: () => Navigator.pop(context),
      ),
      AggregateActionButton(
        label: '添加',
        icon: Icons.add,
        style: AggregateActionStyle.primary,
        onPressed: submit,
      ),
    ],
  );
}
