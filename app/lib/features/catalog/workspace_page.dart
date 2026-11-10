import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/shortcut_scheme.dart';
import '../../widgets/capability_row.dart';
import '../../widgets/page_frame.dart';
import '../../widgets/page_state.dart';

class WorkspacePage extends StatefulWidget {
  const WorkspacePage({
    super.key,
    required this.runtime,
    required this.onOpen,
    required this.onAddConnection,
    required this.favoriteKeys,
    required this.onFavoriteChanged,
    this.autofocusSearch = true,
  });

  final RuntimePort runtime;
  final ValueChanged<Capability> onOpen;
  final ValueChanged<ConnectionKind> onAddConnection;
  final List<String> favoriteKeys;
  final void Function(Capability, bool) onFavoriteChanged;
  final bool autofocusSearch;

  @override
  State<WorkspacePage> createState() => WorkspacePageState();
}

class WorkspacePageState extends State<WorkspacePage> {
  final search = TextEditingController();
  final searchFocus = FocusNode();
  List<Capability>? capabilities;
  List<Connection> connections = [];
  List<RunSummary> recent = [];
  CapabilityKind? filter;
  Object? error;
  int generation = 0;

  @override
  void initState() {
    super.initState();
    reloadCatalog();
  }

  void focusSearch() {
    searchFocus.requestFocus();
    search.selection = TextSelection(
      baseOffset: 0,
      extentOffset: search.text.length,
    );
  }

  Future<void> reloadCatalog() async {
    final current = ++generation;
    setState(() {
      capabilities = null;
      error = null;
    });
    try {
      final loadedConnections = await widget.runtime.listConnections();
      final loadedCapabilities = await widget.runtime.searchCapabilities(
        SearchQuery(search.text),
      );
      final loadedRecent = await widget.runtime.listRecentRuns();
      if (!mounted || current != generation) return;
      setState(() {
        connections = loadedConnections;
        capabilities = loadedCapabilities;
        recent = loadedRecent;
      });
    } catch (cause) {
      if (!mounted || current != generation) return;
      setState(() => error = cause);
    }
  }

  @override
  void dispose() {
    search.dispose();
    searchFocus.dispose();
    super.dispose();
  }

  List<Capability> get visibleCapabilities {
    final items = capabilities ?? const <Capability>[];
    if (filter == null) return items;
    if (filter == CapabilityKind.cliCommand) {
      return items
          .where(
            (item) =>
                item.id.kind == CapabilityKind.cliCommand ||
                item.id.kind == CapabilityKind.cliAction,
          )
          .toList();
    }
    return items.where((item) => item.id.kind == filter).toList();
  }

  void openFirst() {
    if (visibleCapabilities.isNotEmpty) {
      widget.onOpen(visibleCapabilities.first);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sources = {for (final item in connections) item.id.value: item.label};
    final visible = visibleCapabilities;
    final recentCapabilities = <Capability>[];
    final favorites = visible
        .where((item) => widget.favoriteKeys.contains(item.id.key))
        .toList();
    if (search.text.isEmpty && filter == null && capabilities != null) {
      final seen = <String>{};
      for (final run in recent) {
        if (!seen.add(run.capability.key)) continue;
        for (final item in capabilities!) {
          if (item.id.key == run.capability.key) recentCapabilities.add(item);
        }
        if (recentCapabilities.length >= 3) break;
      }
    }
    return PageFrame(
      title: '工作台',
      subtitle: widget.runtime.isPreview
          ? '搜索所有连接中的功能。当前使用预览数据。'
          : '从一个地方找到并运行 CLI 与 MCP 功能。',
      children: [
        for (final notice in widget.runtime.startupNotices) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SelectableText(notice),
            ),
          ),
          const SizedBox(height: 12),
        ],
        CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.enter): openFirst,
          },
          child: TextField(
            key: const Key('global-search'),
            controller: search,
            focusNode: searchFocus,
            autofocus: widget.autofocusSearch,
            style: Theme.of(context).textTheme.titleMedium,
            decoration: InputDecoration(
              labelText: '搜索功能',
              hintText: '名称、说明或来源',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: search.text.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Center(
                        widthFactor: 1,
                        child: Text(
                          ShortcutScheme(defaultTargetPlatform).searchLabel,
                        ),
                      ),
                    )
                  : IconButton(
                      tooltip: '清除搜索',
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        search.clear();
                        reloadCatalog();
                        focusSearch();
                      },
                    ),
            ),
            onChanged: (_) => reloadCatalog(),
            onSubmitted: (_) => openFirst(),
          ),
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _filterChip('全部', null),
            _filterChip('工具', CapabilityKind.mcpTool),
            _filterChip('资源', CapabilityKind.mcpResource),
            _filterChip('提示', CapabilityKind.mcpPrompt),
            _filterChip('CLI', CapabilityKind.cliCommand),
          ],
        ),
        const SizedBox(height: 28),
        if (error != null)
          PageState.error('加载功能失败：$error', onRetry: reloadCatalog)
        else if (capabilities == null)
          const PageState.loading()
        else if (connections.isEmpty && !widget.runtime.isPreview)
          PageState.empty(
            widget.runtime.features.connectionKinds.isEmpty
                ? '当前运行端尚无可添加的连接。'
                : widget.runtime.features.canAdd(ConnectionKind.cli) ||
                      widget.runtime.features.canAdd(ConnectionKind.mcpStdio)
                ? '还没有连接。添加第一个 CLI 或 MCP，功能会出现在这里。'
                : '还没有连接。添加第一个 HTTP MCP，功能会出现在这里。',
            actions: [
              if (widget.runtime.features.canAdd(ConnectionKind.cli))
                FilledButton.icon(
                  onPressed: () => widget.onAddConnection(ConnectionKind.cli),
                  icon: const Icon(Icons.terminal),
                  label: const Text('添加 CLI'),
                ),
              if (widget.runtime.features.canAdd(ConnectionKind.mcpStdio))
                OutlinedButton.icon(
                  onPressed: () =>
                      widget.onAddConnection(ConnectionKind.mcpStdio),
                  icon: const Icon(Icons.hub_outlined),
                  label: const Text('添加 MCP'),
                )
              else if (widget.runtime.features.canAdd(ConnectionKind.mcpHttp))
                OutlinedButton.icon(
                  onPressed: () =>
                      widget.onAddConnection(ConnectionKind.mcpHttp),
                  icon: const Icon(Icons.hub_outlined),
                  label: const Text('添加 HTTP MCP'),
                ),
            ],
          )
        else if (visible.isEmpty)
          PageState.empty(
            search.text.isEmpty ? '当前筛选下没有可用功能。' : '没有找到“${search.text}”对应的功能。',
            actions: [
              TextButton(
                onPressed: () {
                  search.clear();
                  setState(() => filter = null);
                  reloadCatalog();
                },
                child: const Text('清除筛选'),
              ),
            ],
          )
        else ...[
          if (favorites.isNotEmpty &&
              search.text.isEmpty &&
              filter == null) ...[
            Text('收藏的功能', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final capability in favorites) ...[
              CapabilityRow(
                capability: capability,
                source: sources[capability.id.connection.value] ?? '未知来源',
                onOpen: () => widget.onOpen(capability),
                isFavorite: true,
                onFavoriteChanged: (value) =>
                    widget.onFavoriteChanged(capability, value),
              ),
              const Divider(height: 1),
            ],
            const SizedBox(height: 28),
          ],
          if (recentCapabilities.isNotEmpty) ...[
            Text('最近使用', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final capability in recentCapabilities) ...[
              CapabilityRow(
                capability: capability,
                source: sources[capability.id.connection.value] ?? '未知来源',
                onOpen: () => widget.onOpen(capability),
                isFavorite: widget.favoriteKeys.contains(capability.id.key),
                onFavoriteChanged: (value) =>
                    widget.onFavoriteChanged(capability, value),
              ),
              const Divider(height: 1),
            ],
            const SizedBox(height: 28),
          ],
          Text(
            '全部功能 · ${visible.length}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          for (final capability in visible) ...[
            CapabilityRow(
              capability: capability,
              source: sources[capability.id.connection.value] ?? '未知来源',
              onOpen: () => widget.onOpen(capability),
              isFavorite: widget.favoriteKeys.contains(capability.id.key),
              onFavoriteChanged: (value) =>
                  widget.onFavoriteChanged(capability, value),
            ),
            const Divider(height: 1),
          ],
        ],
      ],
    );
  }

  Widget _filterChip(String label, CapabilityKind? kind) => ChoiceChip(
    label: Text(label),
    selected: filter == kind,
    onSelected: (_) => setState(() => filter = kind),
  );
}
