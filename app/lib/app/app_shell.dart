import 'dart:async';

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
import '../widgets/glass/aggregate_buttons.dart';
import '../widgets/glass/glass_motion.dart';
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
    this.glassMotionClock,
    this.platformSettingsSections = const [],
  });
  final RuntimePort runtime;
  final UserPreferences preferences;
  final ValueChanged<UserPreferences> onPreferencesChanged;
  final Future<void> Function() onClearActivity;
  final MusicSession musicSession;
  final GlassMotionClock? glassMotionClock;
  final List<Widget> platformSettingsSections;
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
  StreamSubscription<void>? runtimeChanges;
  final workspaceKey = GlobalKey<WorkspacePageState>();
  final connectionsKey = GlobalKey<ConnectionsPageState>();
  final activityKey = GlobalKey<ActivityPageState>();

  static const _mobileSections = [
    Section.workspace,
    Section.connections,
    Section.activity,
    Section.settings,
  ];

  bool get _mobilePlatform => switch (defaultTargetPlatform) {
    TargetPlatform.android || TargetPlatform.iOS => true,
    _ => false,
  };

  int get _mobileSelectedIndex {
    final index = _mobileSections.indexOf(selected);
    return index < 0 ? 0 : index;
  }

  @override
  void initState() {
    super.initState();
    if (_mobilePlatform) selected = Section.workspace;
    reloadConnectionHomes(selectInitial: true);
    final runtime = widget.runtime;
    if (runtime is RuntimeChangeSource) {
      runtimeChanges = (runtime as RuntimeChangeSource).changes.listen((_) {
        if (!mounted) return;
        reloadConnectionHomes();
        connectionsKey.currentState?.reload();
        workspaceKey.currentState?.reloadCatalog();
        activityKey.currentState?.reload();
      });
    }
  }

  @override
  void dispose() {
    runtimeChanges?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant AppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    final preferred = widget.preferences.preferredConnectionId;
    if (preferred != null &&
        preferred != oldWidget.preferences.preferredConnectionId &&
        connectionHomes.any((item) => item.id.value == preferred)) {
      selectedConnectionId = preferred;
      selected = _mobilePlatform ? Section.workspace : Section.home;
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
          selected = selectedConnectionId == null || _mobilePlatform
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

  Future<void> refreshAfterAccountChange(ConnectionId id) async {
    try {
      await widget.runtime.refreshConnection(id);
    } catch (_) {
      // A removed connection will be reflected by the following reload.
    }
    if (mounted) await reloadConnectionHomes();
  }

  Connection? get activeConnection {
    for (final item in connectionHomes) {
      if (item.id.value == selectedConnectionId) return item;
    }
    return null;
  }

  void select(Section section) => setState(() => selected = section);

  void selectMobileDestination(int index) {
    if (index < 0 || index >= _mobileSections.length) return;
    select(_mobileSections[index]);
  }

  void selectConnection(Connection connection) {
    setState(() {
      selectedConnectionId = connection.id.value;
      selected = _mobilePlatform ? Section.workspace : Section.home;
    });
    widget.onPreferencesChanged(
      widget.preferences.copyWith(preferredConnectionId: connection.id.value),
    );
  }

  void openMusicPlayer() {
    final connectionId = widget.musicSession.connection?.value;
    if (connectionId == null) {
      select(Section.connections);
      return;
    }
    Connection? connection;
    for (final item in connectionHomes) {
      if (item.id.value == connectionId) {
        connection = item;
        break;
      }
    }
    if (connection == null ||
        experienceFor(connection, catalog) != ConnectionExperience.music) {
      select(Section.connections);
      return;
    }
    if (_mobilePlatform) {
      unawaited(openConnectionWorkspace(connection));
    } else {
      selectConnection(connection);
    }
  }

  void connectionAdded(Connection connection) {
    setState(() {
      selectedConnectionId = connection.id.value;
      selected = _mobilePlatform ? Section.connections : Section.home;
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

  Future<void> openConnectionWorkspace(Connection connection) async {
    final experience = experienceFor(connection, catalog);
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(connection.label)),
          bottomNavigationBar: experience == ConnectionExperience.music
              ? null
              : MusicMiniPlayer(
                  session: widget.musicSession,
                  onOpen: openMusicPlayer,
                ),
          body: ConnectionHomePage(
            key: ValueKey('mobile-connection-${connection.id.value}'),
            connection: connection,
            capabilities: catalog,
            runtime: widget.runtime,
            musicSession: widget.musicSession,
            onOpen: openCapability,
            onAccountChanged: () {
              unawaited(refreshAfterAccountChange(connection.id));
            },
          ),
        ),
      ),
    );
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
        padding: const EdgeInsets.only(left: 22, right: 12, top: 8, bottom: 4),
        child: Row(
          children: [
            Expanded(
              child: Text('我的连接', style: Theme.of(context).textTheme.bodySmall),
            ),
            if (defaultTargetPlatform == TargetPlatform.macOS &&
                widget.runtime.features.connectionKinds.isNotEmpty)
              AggregateIconButton(
                tooltip: '添加连接',
                icon: Icons.add,
                onPressed: () => addConnection(
                  ConnectionKind.values.firstWhere(
                    widget.runtime.features.canAdd,
                  ),
                ),
              ),
          ],
        ),
      ),
      for (final connection in connectionHomes)
        _connectionNavigationItem(connection, compact: compact),
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

  Widget _connectionNavigationItem(
    Connection connection, {
    required bool compact,
  }) {
    final icon = switch (experienceFor(connection, catalog)) {
      ConnectionExperience.music => Icons.music_note_outlined,
      ConnectionExperience.cli => Icons.terminal_outlined,
      ConnectionExperience.mcp => Icons.hub_outlined,
    };
    final isSelected =
        selected == Section.home && selectedConnectionId == connection.id.value;
    void activate() {
      if (compact) Navigator.of(context).pop();
      selectConnection(connection);
    }

    if (defaultTargetPlatform == TargetPlatform.macOS) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        child: AggregateActionButton(
          label: connection.label,
          icon: icon,
          onPressed: activate,
          style: AggregateActionStyle.quiet,
          selected: isSelected,
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: ListTile(
        leading: Icon(icon, size: 19),
        title: Text(
          connection.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        selected: isSelected,
        dense: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        onTap: activate,
      ),
    );
  }

  Widget _navigationItem(Section section, {required bool compact}) {
    void activate() {
      if (compact) Navigator.of(context).pop();
      select(section);
    }

    if (defaultTargetPlatform == TargetPlatform.macOS) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        child: AggregateActionButton(
          label: section.label,
          icon: section.icon,
          onPressed: activate,
          style: AggregateActionStyle.quiet,
          selected: selected == section,
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: ListTile(
        leading: Icon(section.icon, size: 19),
        title: Text(section.label),
        selected: selected == section,
        dense: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        onTap: activate,
      ),
    );
  }

  Widget _mobileNavigationRail({required bool extended}) => NavigationRail(
    selectedIndex: _mobileSelectedIndex,
    extended: extended,
    labelType: extended ? null : NavigationRailLabelType.all,
    onDestinationSelected: selectMobileDestination,
    destinations: const [
      NavigationRailDestination(
        icon: Icon(Icons.search_outlined),
        selectedIcon: Icon(Icons.search),
        label: Text('功能'),
      ),
      NavigationRailDestination(
        icon: Icon(Icons.hub_outlined),
        selectedIcon: Icon(Icons.hub),
        label: Text('连接'),
      ),
      NavigationRailDestination(
        icon: Icon(Icons.history_outlined),
        selectedIcon: Icon(Icons.history),
        label: Text('活动'),
      ),
      NavigationRailDestination(
        icon: Icon(Icons.tune_outlined),
        selectedIcon: Icon(Icons.tune),
        label: Text('设置'),
      ),
    ],
  );

  Widget _pageStack(Connection? connection) => IndexedStack(
    index: selected.index,
    children: [
      if (connection != null)
        _pageMotionScope(
          active: selected == Section.home,
          child: ConnectionHomePage(
            key: ValueKey('home-${connection.id.value}'),
            connection: connection,
            capabilities: catalog,
            runtime: widget.runtime,
            musicSession: widget.musicSession,
            onOpen: openCapability,
            onAccountChanged: () {
              unawaited(refreshAfterAccountChange(connection.id));
            },
          ),
        )
      else if (homesLoading)
        const Center(child: CircularProgressIndicator())
      else if (homesError != null)
        Center(child: Text('加载连接失败：$homesError'))
      else
        const Center(child: Text('添加连接后，在这里使用它。')),
      _pageMotionScope(
        active: selected == Section.workspace,
        child: WorkspacePage(
          key: workspaceKey,
          runtime: widget.runtime,
          onOpen: openCapability,
          onAddConnection: addConnection,
          favoriteKeys: widget.preferences.favoriteCapabilityKeys,
          onFavoriteChanged: setFavorite,
          autofocusSearch: selected == Section.workspace,
        ),
      ),
      _pageMotionScope(
        active: selected == Section.connections,
        child: ConnectionsPage(
          key: connectionsKey,
          runtime: widget.runtime,
          onOpen: openCapability,
          onOpenConnection: _mobilePlatform ? openConnectionWorkspace : null,
          onAdded: connectionAdded,
          onChanged: () {
            reloadConnectionHomes();
            workspaceKey.currentState?.reloadCatalog();
          },
        ),
      ),
      _pageMotionScope(
        active: selected == Section.activity,
        child: ActivityPage(
          key: activityKey,
          runtime: widget.runtime,
          onOpen: openCapability,
        ),
      ),
      _pageMotionScope(
        active: selected == Section.settings,
        child: TickerMode(
          enabled: selected == Section.settings,
          child: SettingsPage(
            preferences: widget.preferences,
            onPreferencesChanged: widget.onPreferencesChanged,
            onClearActivity: widget.onClearActivity,
            platformSections: widget.platformSettingsSections,
          ),
        ),
      ),
    ],
  );

  Widget _pageMotionScope({required bool active, required Widget child}) {
    if (defaultTargetPlatform != TargetPlatform.macOS) return child;
    return TickerMode(
      enabled: active,
      child: GlassMotionScope(clock: widget.glassMotionClock, child: child),
    );
  }

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
          final width = constraints.maxWidth;
          final compact = width < 760;
          final mobileInput = _mobilePlatform;
          final mobilePhone = _mobilePlatform && width < 600;
          final mobileRail = _mobilePlatform && width >= 600;
          final extendedRail = _mobilePlatform && width >= 840;
          final hideBottomChrome =
              _mobilePlatform && MediaQuery.of(context).viewInsets.bottom > 0;
          final Widget? bottomNavigationBar;
          if (mobilePhone) {
            bottomNavigationBar = hideBottomChrome
                ? const SizedBox.shrink()
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!onMusicHome)
                        MusicMiniPlayer(
                          session: widget.musicSession,
                          includeBottomSafeArea: false,
                          onOpen: openMusicPlayer,
                        ),
                      NavigationBar(
                        selectedIndex: _mobileSelectedIndex,
                        onDestinationSelected: selectMobileDestination,
                        labelBehavior:
                            NavigationDestinationLabelBehavior.alwaysShow,
                        destinations: const [
                          NavigationDestination(
                            icon: Icon(Icons.search_outlined),
                            selectedIcon: Icon(Icons.search),
                            label: '功能',
                          ),
                          NavigationDestination(
                            icon: Icon(Icons.hub_outlined),
                            selectedIcon: Icon(Icons.hub),
                            label: '连接',
                          ),
                          NavigationDestination(
                            icon: Icon(Icons.history_outlined),
                            selectedIcon: Icon(Icons.history),
                            label: '活动',
                          ),
                          NavigationDestination(
                            icon: Icon(Icons.tune_outlined),
                            selectedIcon: Icon(Icons.tune),
                            label: '设置',
                          ),
                        ],
                      ),
                    ],
                  );
          } else if (_mobilePlatform) {
            bottomNavigationBar = hideBottomChrome
                ? const SizedBox.shrink()
                : onMusicHome
                ? null
                : MusicMiniPlayer(
                    session: widget.musicSession,
                    onOpen: openMusicPlayer,
                  );
          } else {
            bottomNavigationBar = onMusicHome
                ? null
                : MusicMiniPlayer(
                    session: widget.musicSession,
                    onOpen: openMusicPlayer,
                  );
          }
          return Scaffold(
            bottomNavigationBar: bottomNavigationBar,
            appBar: AppBar(
              toolbarHeight: 64,
              title: const Text(
                'Aggregate',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              actions: [
                AggregateIconButton(
                  tooltip: mobileInput
                      ? '搜索所有功能'
                      : '搜索所有功能（${ShortcutScheme(defaultTargetPlatform).searchLabel}）',
                  onPressed: searchAll,
                  icon: Icons.search,
                ),
                const SizedBox(width: 4),
                if (defaultTargetPlatform != TargetPlatform.macOS &&
                    widget.runtime.features.connectionKinds.isNotEmpty)
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
            drawer: !_mobilePlatform && compact
                ? Drawer(child: SafeArea(child: navigation(compact: true)))
                : null,
            body: Row(
              children: [
                if (mobileRail)
                  _mobileNavigationRail(extended: extendedRail)
                else if (!_mobilePlatform && !compact)
                  SizedBox(
                    width: 200,
                    child: Material(
                      color: defaultTargetPlatform == TargetPlatform.macOS
                          ? Colors.transparent
                          : Theme.of(context).colorScheme.surface,
                      child: navigation(compact: false),
                    ),
                  ),
                Expanded(child: _pageStack(connection)),
              ],
            ),
          );
        },
      ),
    );
  }
}
