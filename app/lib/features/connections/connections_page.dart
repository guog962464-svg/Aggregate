import 'dart:convert';

import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

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
  late Future<List<Connection>> pending;
  List<Capability> catalog = [];
  String? selectedId;
  String? error;
  bool addingConnection = false;

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
        await showDialog<void>(
          context: context,
          builder: (_) => const AlertDialog(
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
        connection = await showDialog<Connection>(
          context: context,
          builder: (_) => ConnectionSetupDialog(
            setup: selectedSetup,
            initialKind: initialKind,
            allowedKinds: allowedKinds,
            selectedTargetLabel: selectedTargetLabel,
          ),
        );
      } else {
        final allowedKinds = widget.runtime.features.connectionKinds;
        if (allowedKinds.isEmpty) return;
        if (!allowedKinds.contains(initialKind)) {
          initialKind = ConnectionKind.values.firstWhere(allowedKinds.contains);
        }
        final spec = await showDialog<ConnectionSpec>(
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('删除 ${connection.label}？'),
        content: Text(
          connection.executionTarget.kind == ExecutionTargetKind.host
              ? '此连接将从配对的 Mac Host 删除。'
              : '此连接的配置将从本机移除。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
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
    final saved = await showDialog<bool>(
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
  Widget build(BuildContext context) => PageFrame(
    title: '连接',
    subtitle: widget.runtime is ConnectionSetupTargetPort
        ? '管理本机 HTTP MCP 与配对 Mac Host 连接。'
        : widget.runtime.isPreview
        ? '预览连接。'
        : widget.runtime.features.connectionKinds.isEmpty
        ? '此运行端的连接功能尚未开放。'
        : widget.runtime.features.connectionKinds.length == 1 &&
              widget.runtime.features.canAdd(ConnectionKind.mcpHttp)
        ? '管理 HTTP MCP 连接。'
        : '管理 CLI 与 MCP 连接。',
    children: [
      if (widget.runtime.features.connectionKinds.isNotEmpty)
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: addingConnection ? null : () => add(),
            icon: addingConnection
                ? const Icon(Icons.hourglass_top_outlined)
                : const Icon(Icons.add),
            label: Text(addingConnection ? '正在准备连接向导…' : '添加连接'),
          ),
        ),
      if (error != null) ...[
        const SizedBox(height: 12),
        Text(
          error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ],
      const SizedBox(height: 24),
      FutureBuilder<List<Connection>>(
        future: pending,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return PageState.error('加载连接失败：${snapshot.error}', onRetry: reload);
          }
          if (!snapshot.hasData) return const PageState.loading();
          final connections = snapshot.data!;
          if (connections.isEmpty) {
            return PageState.empty(
              widget.runtime.features.connectionKinds.isEmpty
                  ? '当前运行端尚无可添加的连接。'
                  : '还没有连接。添加一个连接开始使用。',
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
              if (!wide && selected != null) {
                return _detail(
                  selected,
                  compact: true,
                  canMoveUp: selectedIndex > 0,
                  canMoveDown: selectedIndex < connections.length - 1,
                );
              }
              final list = Column(
                children: [
                  for (final connection in connections) ...[
                    ListTile(
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
                        widget.runtime.isPreview
                            ? '预览'
                            : _status(connection.status),
                        style: TextStyle(
                          color:
                              connection.status == ConnectionStatus.unavailable
                              ? Theme.of(context).colorScheme.error
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      onTap: () =>
                          setState(() => selectedId = connection.id.value),
                    ),
                    const Divider(height: 1),
                  ],
                ],
              );
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
            TextButton.icon(
              onPressed: () => setState(() => selectedId = null),
              icon: const Icon(Icons.arrow_back, size: 18),
              label: const Text('返回连接'),
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
            FilledButton.tonalIcon(
              onPressed: () => widget.onOpenConnection!(connection),
              icon: Icon(
                experienceFor(connection, catalog) == ConnectionExperience.music
                    ? Icons.music_note_outlined
                    : Icons.open_in_new,
              ),
              label: Text(
                experienceFor(connection, catalog) == ConnectionExperience.music
                    ? '打开播放器'
                    : '打开连接工作区',
              ),
            ),
          ],
          const SizedBox(height: 20),
          Text(
            '已发现 ${capabilities.length} 项功能',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (capabilities.isEmpty) const Text('当前没有可用功能。刷新连接后重试。'),
          for (final capability in capabilities) ...[
            CapabilityRow(
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
                IconButton(
                  tooltip: '连接上移',
                  onPressed: canMoveUp ? () => move(connection, -1) : null,
                  icon: const Icon(Icons.arrow_upward, size: 18),
                ),
                IconButton(
                  tooltip: '连接下移',
                  onPressed: canMoveDown ? () => move(connection, 1) : null,
                  icon: const Icon(Icons.arrow_downward, size: 18),
                ),
                if (connection.kind == ConnectionKind.cli &&
                    connection.executionTarget.kind ==
                        ExecutionTargetKind.device)
                  OutlinedButton.icon(
                    onPressed: () => editActions(connection),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('编辑动作'),
                  ),
                OutlinedButton.icon(
                  onPressed: () => refresh(connection),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('测试连接'),
                ),
                TextButton.icon(
                  onPressed: () => remove(connection),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('删除连接'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

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
  Widget build(BuildContext context) => AlertDialog(
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
                  suffixIcon: IconButton(
                    tooltip: '选择程序',
                    onPressed: () => choose(executable),
                    icon: const Icon(Icons.folder_open_outlined),
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
                    suffixIcon: IconButton(
                      tooltip: '选择动作清单',
                      onPressed: () => choose(manifest),
                      icon: const Icon(Icons.folder_open_outlined),
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
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(onPressed: submit, child: const Text('添加')),
    ],
  );
}
