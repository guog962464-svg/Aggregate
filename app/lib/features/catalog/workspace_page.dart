import 'dart:async';
import 'dart:math' as math;

import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/shortcut_scheme.dart';
import '../../widgets/capability_row.dart';
import '../../widgets/glass/aggregate_buttons.dart';
import '../../widgets/glass/glass_action_button.dart';
import '../../widgets/glass/glass_design_tokens.dart';
import '../../widgets/glass/glass_glyph.dart';
import '../../widgets/glass/glass_motion.dart';
import '../../widgets/page_frame.dart';
import '../../widgets/page_state.dart';
import '../invocation/capability_run_page.dart';
import '../music/music_session.dart';

enum _WorkspaceDirectoryScope { recent, favorites, all }

class WorkspacePage extends StatefulWidget {
  const WorkspacePage({
    super.key,
    required this.runtime,
    required this.onOpen,
    required this.onAddConnection,
    required this.favoriteKeys,
    required this.onFavoriteChanged,
    this.musicSession,
    this.onRunSettled,
    this.autofocusSearch = true,
  });

  final RuntimePort runtime;
  final ValueChanged<Capability> onOpen;
  final ValueChanged<ConnectionKind> onAddConnection;
  final List<String> favoriteKeys;
  final void Function(Capability, bool) onFavoriteChanged;
  final MusicSession? musicSession;
  final VoidCallback? onRunSettled;
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
  String? selectedCapabilityKey;
  Capability? _selectedCapability;
  _WorkspaceDirectoryScope _directoryScope = _WorkspaceDirectoryScope.all;

  bool _usesGlassButtons(BuildContext context) =>
      defaultTargetPlatform == TargetPlatform.macOS &&
      GlassMotionScope.maybeOf(context) != null;

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
        final selected = _selectedCapability;
        if (selected != null &&
            !loadedConnections.any(
              (connection) =>
                  connection.id.value == selected.id.connection.value,
            )) {
          selectedCapabilityKey = null;
          _selectedCapability = null;
        } else if (selected != null) {
          for (final capability in loadedCapabilities) {
            if (capability.id.key == selected.id.key) {
              _selectedCapability = capability;
              break;
            }
          }
        }
      });
    } catch (cause) {
      if (!mounted || current != generation) return;
      setState(() => error = cause);
    }
  }

  Future<void> refreshRecent() async {
    try {
      final loadedRecent = await widget.runtime.listRecentRuns();
      if (!mounted) return;
      setState(() => recent = loadedRecent);
    } catch (_) {
      // The catalog remains usable when the activity source is unavailable.
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

  Capability? get selectedCapability => _selectedCapability;

  void _openCapability(Capability capability, {required bool embedded}) {
    if (embedded) {
      setState(() {
        selectedCapabilityKey = capability.id.key;
        _selectedCapability = capability;
      });
    } else {
      widget.onOpen(capability);
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (_usesGlassButtons(context) && constraints.maxWidth >= 760) {
        return _buildMacDesktop(context, constraints);
      }
      return _buildCompact(context);
    },
  );

  Widget _buildCompact(BuildContext context) {
    final mobileInput = switch (defaultTargetPlatform) {
      TargetPlatform.android || TargetPlatform.iOS => true,
      _ => false,
    };
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
      title: defaultTargetPlatform == TargetPlatform.macOS ? '所有功能' : '工作台',
      subtitle: widget.runtime.isPreview
          ? '搜索所有连接中的功能。当前使用预览数据。'
          : '从一个地方找到并运行 CLI 与 MCP 功能。',
      lazyChildren: visible.length >= 40,
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
                  ? mobileInput
                        ? null
                        : Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: Center(
                              widthFactor: 1,
                              child: Text(
                                ShortcutScheme(defaultTargetPlatform)
                                    .searchLabel,
                              ),
                            ),
                          )
                  : _usesGlassButtons(context)
                  ? AggregateIconButton(
                      tooltip: '清除搜索',
                      icon: Icons.close,
                      onPressed: () {
                        search.clear();
                        reloadCatalog();
                        focusSearch();
                      },
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
            if (widget.runtime.features.canAdd(ConnectionKind.cli) ||
                visible.any(
                  (item) =>
                      item.id.kind == CapabilityKind.cliCommand ||
                      item.id.kind == CapabilityKind.cliAction,
                ))
              _filterChip('CLI', CapabilityKind.cliCommand),
            _filterChip('MCP 工具', CapabilityKind.mcpTool),
            _filterChip('资源', CapabilityKind.mcpResource),
            _filterChip('提示', CapabilityKind.mcpPrompt),
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
                AggregateActionButton(
                  label: '添加 CLI',
                  icon: Icons.terminal,
                  style: AggregateActionStyle.primary,
                  onPressed: () => widget.onAddConnection(ConnectionKind.cli),
                ),
              if (widget.runtime.features.canAdd(ConnectionKind.mcpStdio))
                AggregateActionButton(
                  label: '添加 MCP',
                  icon: Icons.hub_outlined,
                  onPressed: () =>
                      widget.onAddConnection(ConnectionKind.mcpStdio),
                )
              else if (widget.runtime.features.canAdd(ConnectionKind.mcpHttp))
                AggregateActionButton(
                  label: '添加 HTTP MCP',
                  icon: Icons.hub_outlined,
                  onPressed: () =>
                      widget.onAddConnection(ConnectionKind.mcpHttp),
                ),
            ],
          )
        else if (visible.isEmpty)
          PageState.empty(
            search.text.isEmpty ? '当前筛选下没有可用功能。' : '没有找到“${search.text}”对应的功能。',
            actions: [
              AggregateActionButton(
                label: '清除筛选',
                icon: Icons.close,
                style: AggregateActionStyle.quiet,
                onPressed: () {
                  search.clear();
                  setState(() => filter = null);
                  reloadCatalog();
                },
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

  Widget _buildMacDesktop(BuildContext context, BoxConstraints constraints) {
    final width = math.min(1080.0, constraints.maxWidth - 88);
    final sourceLabels = {
      for (final connection in connections)
        connection.id.value: connection.label,
    };
    final visible = visibleCapabilities;
    final favorites = visible
        .where((item) => widget.favoriteKeys.contains(item.id.key))
        .toList();
    final recentCapabilities = <Capability>[];
    if (capabilities != null) {
      final seen = <String>{};
      for (final run in recent) {
        if (!seen.add(run.capability.key)) continue;
        for (final capability in visible) {
          if (capability.id.key == run.capability.key) {
            recentCapabilities.add(capability);
          }
        }
        if (recentCapabilities.length >= 20) break;
      }
    }
    final directoryCapabilities = switch (_directoryScope) {
      _WorkspaceDirectoryScope.recent => recentCapabilities,
      _WorkspaceDirectoryScope.favorites => favorites,
      _WorkspaceDirectoryScope.all => visible,
    };
    final directoryWidth = math.min(296.0, math.max(240.0, width * .287));
    final selected = selectedCapability;

    return Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: constraints.maxWidth,
        height: constraints.maxHeight,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(40, 32, 52, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '所有功能',
                key: const Key('workspace-page-title'),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 6),
              Text(
                widget.runtime.isPreview
                    ? '搜索所有连接中的功能。当前使用预览数据。'
                    : '从一个地方找到并运行 CLI 与 MCP 功能。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: math.min(570.0, width - 60),
                height: 42,
                child: _desktopSearch(context),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  _filterChip('全部', null),
                  if (widget.runtime.features.canAdd(ConnectionKind.cli) ||
                      visible.any(
                        (item) =>
                            item.id.kind == CapabilityKind.cliCommand ||
                            item.id.kind == CapabilityKind.cliAction,
                      ))
                    _filterChip('CLI', CapabilityKind.cliCommand),
                  _filterChip('MCP 工具', CapabilityKind.mcpTool),
                  _filterChip('资源', CapabilityKind.mcpResource),
                  _filterChip('提示', CapabilityKind.mcpPrompt),
                ],
              ),
              const SizedBox(height: 19),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      key: const Key('workspace-capability-directory-panel'),
                      width: directoryWidth,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Text(
                                '功能目录',
                                style: Theme.of(context).textTheme.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                              const Spacer(),
                              Text(
                                capabilities == null
                                    ? '…'
                                    : '${directoryCapabilities.length} 项',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 4,
                            runSpacing: 4,
                            children: [
                              _directoryScopeButton(
                                '最近使用',
                                _WorkspaceDirectoryScope.recent,
                                Icons.history,
                              ),
                              _directoryScopeButton(
                                '收藏',
                                _WorkspaceDirectoryScope.favorites,
                                Icons.star_border_rounded,
                              ),
                              _directoryScopeButton(
                                '全部',
                                _WorkspaceDirectoryScope.all,
                                Icons.grid_view_outlined,
                              ),
                            ],
                          ),
                          const SizedBox(height: 13),
                          Expanded(
                            child: _desktopCatalog(
                              context,
                              visible: directoryCapabilities,
                              sourceLabels: sourceLabels,
                              emptyScope: _directoryScope,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 20),
                    const VerticalDivider(
                      key: Key('workspace-capability-directory-divider'),
                      width: 1,
                    ),
                    const SizedBox(width: 26),
                    Expanded(
                      child: KeyedSubtree(
                        key: const Key('workspace-capability-details'),
                        child: selected == null
                            ? Center(
                                child: Text(
                                  '从目录选择功能，查看参数、权限和运行结果。',
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              )
                            : CapabilityRunPage(
                                key: ValueKey(
                                  'workspace-run-${selected.id.key}',
                                ),
                                runtime: widget.runtime,
                                capability: selected,
                                musicSession: widget.musicSession,
                                onSearchAll: focusSearch,
                                onRunSettled: () {
                                  unawaited(refreshRecent());
                                  widget.onRunSettled?.call();
                                },
                                embedded: true,
                                embeddedTopInset: width >= 900 ? 56 : 0,
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _desktopSearch(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.enter): () {
        if (visibleCapabilities.isNotEmpty) {
          _openCapability(visibleCapabilities.first, embedded: true);
        }
      },
    },
    child: TextField(
      key: const Key('global-search'),
      controller: search,
      focusNode: searchFocus,
      autofocus: widget.autofocusSearch,
      style: Theme.of(context).textTheme.bodyMedium
          ?.copyWith(fontSize: 13, fontWeight: FontWeight.w400),
      decoration: InputDecoration(
        hintText: '搜索名称、说明或来源',
        hintStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
          fontSize: 13,
          fontWeight: FontWeight.w400,
          color:
              Theme.of(context).extension<GlassDesignTokens>()?.muted ??
              Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        prefixIconConstraints: const BoxConstraints.tightFor(
          width: 38,
          height: 42,
        ),
        prefixIcon: SizedBox(
          width: 38,
          child: Center(
            child: Transform.translate(
              offset: const Offset(2, 0),
              child: GlassGlyphMark(glyph: GlassGlyph.search, size: 16),
            ),
          ),
        ),
        suffixIcon: search.text.isEmpty
            ? null
            : AggregateIconButton(
                tooltip: '清除搜索',
                icon: Icons.close,
                onPressed: () {
                  search.clear();
                  reloadCatalog();
                  focusSearch();
                },
              ),
      ),
      onChanged: (_) => reloadCatalog(),
      onSubmitted: (_) {
        if (visibleCapabilities.isNotEmpty) {
          _openCapability(visibleCapabilities.first, embedded: true);
        }
      },
    ),
  );

  Widget _desktopCatalog(
    BuildContext context, {
    required List<Capability> visible,
    required Map<String, String> sourceLabels,
    required _WorkspaceDirectoryScope emptyScope,
  }) {
    if (error != null) {
      return PageState.error('加载功能失败：$error', onRetry: reloadCatalog);
    }
    if (capabilities == null) return const PageState.loading();
    if (connections.isEmpty && !widget.runtime.isPreview) {
      final message = widget.runtime.features.connectionKinds.isEmpty
          ? '当前运行端尚无可添加的连接。'
          : widget.runtime.features.canAdd(ConnectionKind.cli) ||
                widget.runtime.features.canAdd(ConnectionKind.mcpStdio)
          ? '还没有连接。添加第一个 CLI 或 MCP，功能会出现在这里。'
          : '还没有连接。添加第一个 HTTP MCP，功能会出现在这里。';
      return PageState.empty(
        message,
        actions: [
          if (widget.runtime.features.canAdd(ConnectionKind.cli))
            AggregateActionButton(
              label: '添加 CLI',
              icon: Icons.terminal,
              style: AggregateActionStyle.primary,
              onPressed: () => widget.onAddConnection(ConnectionKind.cli),
            ),
          if (widget.runtime.features.canAdd(ConnectionKind.mcpStdio))
            AggregateActionButton(
              label: '添加 MCP',
              icon: Icons.hub_outlined,
              onPressed: () => widget.onAddConnection(ConnectionKind.mcpStdio),
            )
          else if (widget.runtime.features.canAdd(ConnectionKind.mcpHttp))
            AggregateActionButton(
              label: '添加 HTTP MCP',
              icon: Icons.hub_outlined,
              onPressed: () => widget.onAddConnection(ConnectionKind.mcpHttp),
            ),
        ],
      );
    }
    if (visible.isEmpty) {
      final emptyMessage = switch (emptyScope) {
        _WorkspaceDirectoryScope.recent => '还没有最近使用的功能。',
        _WorkspaceDirectoryScope.favorites => '还没有收藏的功能。',
        _WorkspaceDirectoryScope.all =>
          search.text.isEmpty ? '当前筛选下没有可用功能。' : '没有找到“${search.text}”对应的功能。',
      };
      final isScopedEmpty = emptyScope != _WorkspaceDirectoryScope.all;
      return PageState.empty(
        emptyMessage,
        actions: [
          AggregateActionButton(
            label: isScopedEmpty ? '查看全部' : '清除筛选',
            icon: isScopedEmpty ? Icons.grid_view_outlined : Icons.close,
            style: AggregateActionStyle.quiet,
            onPressed: () {
              if (isScopedEmpty) {
                setState(() => _directoryScope = _WorkspaceDirectoryScope.all);
              } else {
                search.clear();
                setState(() => filter = null);
                reloadCatalog();
              }
            },
          ),
        ],
      );
    }

    return CustomScrollView(
      key: const Key('workspace-capability-directory'),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.only(bottom: 18),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate((context, index) {
              final capability = visible[index];
              return Padding(
                key: ValueKey('workspace-capability-${capability.id.key}'),
                padding: const EdgeInsets.only(bottom: 4),
                child: CapabilityRow(
                  capability: capability,
                  source:
                      sourceLabels[capability.id.connection.value] ?? '未知来源',
                  compactDirectory: true,
                  directorySubtitle: _workspaceDirectorySubtitle(
                    capability,
                    sourceLabels,
                  ),
                  selected: selectedCapabilityKey == capability.id.key,
                  onOpen: () => _openCapability(capability, embedded: true),
                  isFavorite: widget.favoriteKeys.contains(capability.id.key),
                  onFavoriteChanged: (value) =>
                      widget.onFavoriteChanged(capability, value),
                ),
              );
            }, childCount: visible.length),
          ),
        ),
      ],
    );
  }

  Widget _directoryScopeButton(
    String label,
    _WorkspaceDirectoryScope scope,
    IconData icon,
  ) => GlassActionButton(
    glyph: GlassGlyphCatalog.fromMaterialIcon(icon),
    label: label,
    semanticsLabel: '按目录视图：$label',
    onPressed: () => setState(() => _directoryScope = scope),
    selected: _directoryScope == scope,
    kind: GlassButtonKind.segmented,
    size: GlassButtonSize.segmented,
  );

  Widget _filterChip(String label, CapabilityKind? kind) {
    final selected = filter == kind;
    final icon = switch (kind) {
      null => Icons.grid_view_outlined,
      CapabilityKind.mcpTool => Icons.build_outlined,
      CapabilityKind.mcpResource => Icons.description_outlined,
      CapabilityKind.mcpPrompt => Icons.chat_bubble_outline,
      CapabilityKind.cliCommand ||
      CapabilityKind.cliAction => Icons.terminal_outlined,
    };
    if (_usesGlassButtons(context)) {
      return GlassActionButton(
        glyph: GlassGlyphCatalog.fromMaterialIcon(icon),
        label: label,
        semanticsLabel: '按类型筛选：$label',
        onPressed: () => setState(() => filter = kind),
        selected: selected,
        kind: GlassButtonKind.segmented,
        size: GlassButtonSize.segmented,
      );
    }
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => filter = kind),
    );
  }
}

String _workspaceDirectorySubtitle(
  Capability capability,
  Map<String, String> sourceLabels,
) {
  final kind = switch (capability.id.kind) {
    CapabilityKind.cliCommand || CapabilityKind.cliAction => 'CLI',
    CapabilityKind.mcpTool => 'MCP 工具',
    CapabilityKind.mcpResource => '资源',
    CapabilityKind.mcpPrompt => '提示',
  };
  final source = sourceLabels[capability.id.connection.value] ?? '未知来源';
  return '$kind · $source';
}
