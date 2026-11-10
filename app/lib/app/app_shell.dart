import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../features/activity/activity_page.dart';
import '../features/catalog/workspace_page.dart';
import '../features/connections/connection_experience.dart';
import '../features/connections/connection_home_page.dart';
import '../features/connections/connections_page.dart';
import '../features/settings/settings_page.dart';
import '../features/music/music_mini_player.dart';
import '../features/music/music_session.dart';
import 'shortcut_scheme.dart';

enum Section {
  home('', Icons.grid_view_outlined),
  workspace('所有功能', Icons.search_outlined),
  connections('管理连接', Icons.hub_outlined),
  activity('活动', Icons.history_outlined),
  settings('设置', Icons.tune_outlined);

  const Section(this.label, this.icon);
  final String label;
  final IconData icon;
}

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.runtime,
    required this.preferences,
    required this.onPreferencesChanged,
    required this.onClearActivity,
    required this.musicSession,
  });
  final RuntimePort runtime;
  final UserPreferences preferences;
  final ValueChanged<UserPreferences> onPreferencesChanged;
  final Future<void> Function() onClearActivity;
  final MusicSession musicSession;
  @override
  State<AppShell> createState() => AppShellState();
}

class AppShellState extends State<AppShell> {
  Section selected = Section.home;
  List<Connection> connectionHomes = const [];
  List<Capability> catalog = const [];
  String? selectedConnectionId;
  bool homesLoading = true;
  Object? homesError;
  int homesGeneration = 0;
  final workspaceKey = GlobalKey<WorkspacePageState>();
  final connectionsKey = GlobalKey<ConnectionsPageState>();
  final activityKey = GlobalKey<ActivityPageState>();

  @override
  void initState() {
    super.initState();
    reloadConnectionHomes(selectInitial: true);
  }

  @override
  void didUpdateWidget(covariant AppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    final preferred = widget.preferences.preferredConnectionId;
    if (preferred != null &&
        preferred != oldWidget.preferences.preferredConnectionId &&
        connectionHomes.any((item) => item.id.value == preferred)) {
      selectedConnectionId = preferred;
      selected = Section.home;
    }
  }

  Future<void> reloadConnectionHomes({bool selectInitial = false}) async {
    final current = ++homesGeneration;
    try {
      final connections = await widget.runtime.listConnections();
      final capabilities = await widget.runtime.searchCapabilities(
        const SearchQuery(''),
      );
      if (!mounted || current != homesGeneration) return;
      final selectedStillExists = connections.any(
        (item) => item.id.value == selectedConnectionId,
      );
      final preferred = connections.where(
        (item) =>
            experienceFor(item, capabilities) == ConnectionExperience.music,
      );
      final savedId = widget.preferences.preferredConnectionId;
      setState(() {
        connectionHomes = connections;
        catalog = capabilities;
        homesLoading = false;
        homesError = null;
        if (!selectedStillExists) {
          selectedConnectionId =
              connections.any((item) => item.id.value == savedId)
              ? savedId
              : preferred.isNotEmpty
              ? preferred.first.id.value
              : connections.firstOrNull?.id.value;
        }
        if (selectInitial || selected == Section.home && !selectedStillExists) {
          selected = selectedConnectionId == null
              ? Section.workspace
              : Section.home;
        }
      });
    } catch (cause) {
      if (!mounted || current != homesGeneration) return;
      setState(() {
        homesLoading = false;
        homesError = cause;
        if (selectInitial) selected = Section.workspace;
      });
    }
  }

  Connection? get activeConnection {
    for (final item in connectionHomes) {
      if (item.id.value == selectedConnectionId) return item;
    }
    return null;
  }

  void select(Section section) => setState(() => selected = section);

  void selectConnection(Connection connection) {
    setState(() {
      selectedConnectionId = connection.id.value;
      selected = Section.home;
    });
    widget.onPreferencesChanged(
      widget.preferences.copyWith(preferredConnectionId: connection.id.value),
    );
  }

  void connectionAdded(Connection connection) {
    setState(() {
      selectedConnectionId = connection.id.value;
      selected = Section.home;
    });
    widget.onPreferencesChanged(
      widget.preferences.copyWith(preferredConnectionId: connection.id.value),
    );
    reloadConnectionHomes();
    workspaceKey.currentState?.reloadCatalog();
  }

  void searchAll() {
    select(Section.workspace);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) workspaceKey.currentState?.focusSearch();
    });
  }

  void addConnection(ConnectionKind kind) {
    if (!widget.runtime.features.canAdd(kind)) return;
    select(Section.connections);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      connectionsKey.currentState?.add(initialKind: kind);
    });
  }

  Future<void> openCapability(Capability capability) async {
    await Navigator.of(context).pushNamed('/run', arguments: capability);
    if (!mounted) return;
    activityKey.currentState?.reload();
    workspaceKey.currentState?.reloadCatalog();
    reloadConnectionHomes();
  }

  void refreshActivity() {
    activityKey.currentState?.reload();
    workspaceKey.currentState?.reloadCatalog();
  }

  void setFavorite(Capability capability, bool favorite) {
    final keys = {...widget.preferences.favoriteCapabilityKeys};
    if (favorite) {
      keys.add(capability.id.key);
    } else {
      keys.remove(capability.id.key);
    }
    widget.onPreferencesChanged(
      widget.preferences.copyWith(favoriteCapabilityKeys: keys.toList()),
    );
  }

  Widget navigation({required bool compact}) => Column(
    children: [
      const SizedBox(height: 20),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text('我的连接', style: Theme.of(context).textTheme.bodySmall),
        ),
      ),
      for (final connection in connectionHomes)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          child: ListTile(
            leading: Icon(switch (experienceFor(connection, catalog)) {
              ConnectionExperience.music => Icons.music_note_outlined,
              ConnectionExperience.cli => Icons.terminal_outlined,
              ConnectionExperience.mcp => Icons.hub_outlined,
            }, size: 19),
            title: Text(
              connection.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            selected:
                selected == Section.home &&
                selectedConnectionId == connection.id.value,
            dense: true,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            onTap: () {
              if (compact) Navigator.of(context).pop();
              selectConnection(connection);
            },
          ),
        ),
      const SizedBox(height: 20),
      const Divider(height: 1),
      const SizedBox(height: 8),
      for (final section in Section.values.where(
        (item) => item != Section.home && item != Section.settings,
      ))
        _navigationItem(section, compact: compact),
      const Spacer(),
      const Divider(height: 1),
      _navigationItem(Section.settings, compact: compact),
      const SizedBox(height: 12),
    ],
  );

  Widget _navigationItem(Section section, {required bool compact}) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
    child: ListTile(
      leading: Icon(section.icon, size: 19),
      title: Text(section.label),
      selected: selected == section,
      dense: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      onTap: () {
        if (compact) Navigator.of(context).pop();
        select(section);
      },
    ),
  );

  @override
  Widget build(BuildContext context) {
    final connection = activeConnection;
    final onMusicHome =
        selected == Section.home &&
        connection != null &&
        experienceFor(connection, catalog) == ConnectionExperience.music;
    return Focus(
      autofocus: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 760;
          return Scaffold(
            bottomNavigationBar: onMusicHome
                ? null
                : MusicMiniPlayer(session: widget.musicSession),
            appBar: AppBar(
              toolbarHeight: 64,
              title: const Text(
                'Aggregate',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              actions: [
                IconButton(
                  tooltip:
                      '搜索所有功能（${ShortcutScheme(defaultTargetPlatform).searchLabel}）',
                  onPressed: searchAll,
                  icon: const Icon(Icons.search),
                ),
                const SizedBox(width: 4),
                if (widget.runtime.features.connectionKinds.isNotEmpty)
                  IconButton(
                    tooltip: '添加连接',
                    onPressed: () => addConnection(
                      ConnectionKind.values.firstWhere(
                        widget.runtime.features.canAdd,
                      ),
                    ),
                    icon: const Icon(Icons.add),
                  ),
                const SizedBox(width: 20),
              ],
            ),
            drawer: compact
                ? Drawer(child: SafeArea(child: navigation(compact: true)))
                : null,
            body: Row(
              children: [
                if (!compact)
                  SizedBox(
                    width: 200,
                    child: Material(
                      color: Theme.of(context).colorScheme.surface,
                      child: navigation(compact: false),
                    ),
                  ),
                Expanded(
                  child: IndexedStack(
                    index: selected.index,
                    children: [
                      if (connection != null)
                        ConnectionHomePage(
                          key: ValueKey('home-${connection.id.value}'),
                          connection: connection,
                          capabilities: catalog,
                          runtime: widget.runtime,
                          musicSession: widget.musicSession,
                          onOpen: openCapability,
                        )
                      else if (homesLoading)
                        const Center(child: CircularProgressIndicator())
                      else if (homesError != null)
                        Center(child: Text('加载连接失败：$homesError'))
                      else
                        const Center(child: Text('添加连接后，在这里使用它。')),
                      WorkspacePage(
                        key: workspaceKey,
                        runtime: widget.runtime,
                        onOpen: openCapability,
                        onAddConnection: addConnection,
                        favoriteKeys: widget.preferences.favoriteCapabilityKeys,
                        onFavoriteChanged: setFavorite,
                        autofocusSearch: selected == Section.workspace,
                      ),
                      ConnectionsPage(
                        key: connectionsKey,
                        runtime: widget.runtime,
                        onOpen: openCapability,
                        onAdded: connectionAdded,
                        onChanged: () {
                          reloadConnectionHomes();
                          workspaceKey.currentState?.reloadCatalog();
                        },
                      ),
                      ActivityPage(
                        key: activityKey,
                        runtime: widget.runtime,
                        onOpen: openCapability,
                      ),
                      SettingsPage(
                        preferences: widget.preferences,
                        onPreferencesChanged: widget.onPreferencesChanged,
                        onClearActivity: widget.onClearActivity,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
