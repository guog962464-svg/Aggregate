import 'dart:async';

import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:flutter/material.dart';

import '../features/activity/activity_page.dart';
import '../features/catalog/workspace_page.dart';
import '../features/connections/connections_page.dart';
import '../features/settings/settings_page.dart';

enum Section {
  workspace('工作台', Icons.search_outlined),
  connections('连接', Icons.hub_outlined),
  activity('活动', Icons.history_outlined),
  settings('设置', Icons.tune_outlined);

  const Section(this.label, this.icon);
  final String label;
  final IconData icon;
}

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.runtime});
  final RuntimePort runtime;
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  Section selected = Section.workspace;
  int activityRevision = 0;
  UserPreferences preferences = const UserPreferences();

  @override
  void initState() {
    super.initState();
    unawaited(_loadPreferences());
  }

  Future<void> _loadPreferences() async {
    final loaded = await widget.runtime.loadPreferences();
    if (mounted) setState(() => preferences = loaded);
  }

  Future<void> _savePreferences(UserPreferences value) async {
    setState(() => preferences = value);
    await widget.runtime.savePreferences(value);
  }

  void select(Section section) => setState(() => selected = section);

  Future<void> openCapability(Capability capability) async {
    await Navigator.of(context).pushNamed('/run', arguments: capability);
    if (mounted) setState(() => activityRevision++);
  }

  Widget navigation({required bool compact}) => ListView(
    padding: const EdgeInsets.all(12),
    children: [
      for (final section in Section.values)
        ListTile(
          leading: Icon(section.icon, size: 20),
          title: Text(section.label),
          selected: selected == section,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          onTap: () {
            if (compact) {
              Navigator.of(context).pop();
            }
            select(section);
          },
        ),
    ],
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 760;
      return Scaffold(
        appBar: AppBar(
          title: const Text('Aggregate'),
          actions: [
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Center(child: Text('阶段 1 · 预览数据')),
            ),
            IconButton(
              tooltip: '添加连接',
              onPressed: () => select(Section.connections),
              icon: const Icon(Icons.add),
            ),
            const SizedBox(width: 8),
          ],
        ),
        drawer: compact
            ? Drawer(child: SafeArea(child: navigation(compact: true)))
            : null,
        body: Row(
          children: [
            if (!compact)
              SizedBox(
                width: 208,
                child: Material(
                  color: Theme.of(context).colorScheme.surface,
                  child: navigation(compact: false),
                ),
              ),
            Expanded(
              child: IndexedStack(
                index: selected.index,
                children: [
                  WorkspacePage(
                    runtime: widget.runtime,
                    onOpen: openCapability,
                    onAddConnection: (_) => select(Section.connections),
                    favoriteKeys: preferences.favoriteCapabilityKeys,
                    onFavoriteChanged: (capability, value) {
                      final keys = [...preferences.favoriteCapabilityKeys];
                      if (value) {
                        if (!keys.contains(capability.id.key)) {
                          keys.add(capability.id.key);
                        }
                      } else {
                        keys.remove(capability.id.key);
                      }
                      unawaited(
                        _savePreferences(
                          preferences.copyWith(favoriteCapabilityKeys: keys),
                        ),
                      );
                    },
                  ),
                  ConnectionsPage(
                    runtime: widget.runtime,
                    onOpen: openCapability,
                  ),
                  ActivityPage(
                    key: ValueKey(activityRevision),
                    runtime: widget.runtime,
                    onOpen: openCapability,
                  ),
                  SettingsPage(
                    preferences: preferences,
                    onPreferencesChanged: (value) =>
                        unawaited(_savePreferences(value)),
                    onClearActivity: widget.runtime.clearActivity,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}
