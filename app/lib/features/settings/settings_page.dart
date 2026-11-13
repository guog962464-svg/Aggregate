import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:aggregate_contracts/aggregate_contracts.dart';

import '../../app/shortcut_scheme.dart';
import '../../widgets/page_frame.dart';

const _appVersion = String.fromEnvironment('APP_VERSION', defaultValue: '开发版');

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.preferences,
    required this.onPreferencesChanged,
    required this.onClearActivity,
    this.platformSections = const [],
  });

  final UserPreferences preferences;
  final ValueChanged<UserPreferences> onPreferencesChanged;
  final Future<void> Function() onClearActivity;
  final List<Widget> platformSections;

  Future<void> clearActivity(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('清空活动记录？'),
        content: Text(
          defaultTargetPlatform == TargetPlatform.android
              ? '只删除 Android 本机保存的活动记录；Mac Host 上的记录不会删除。此操作无法撤销。'
              : '本机保存的活动记录将被删除。此操作无法撤销。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清空记录'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await onClearActivity();
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('本机活动记录已清空')));
      }
    } catch (cause) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('清空失败：$cause')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => PageFrame(
    title: '设置',
    subtitle: '让工作台适应你的使用方式。',
    children: [
      Text('外观', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      const Text('主题选择保存在本机。'),
      const SizedBox(height: 16),
      SegmentedButton<AppearancePreference>(
        segments: [
          ButtonSegment(
            value: AppearancePreference.system,
            label: Text(
              defaultTargetPlatform == TargetPlatform.macOS
                  ? '跟随 macOS 系统'
                  : '跟随系统',
            ),
            icon: const Icon(Icons.brightness_auto_outlined),
          ),
          const ButtonSegment(
            value: AppearancePreference.light,
            label: Text('浅色'),
            icon: Icon(Icons.light_mode_outlined),
          ),
          const ButtonSegment(
            value: AppearancePreference.dark,
            label: Text('深色'),
            icon: Icon(Icons.dark_mode_outlined),
          ),
        ],
        selected: {preferences.appearance},
        onSelectionChanged: (selection) => onPreferencesChanged(
          preferences.copyWith(appearance: selection.first),
        ),
      ),
      const SizedBox(height: 32),
      const Divider(),
      const SizedBox(height: 24),
      Text('快捷操作', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('搜索所有功能'),
        trailing: Text(ShortcutScheme(defaultTargetPlatform).searchLabel),
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('运行当前功能'),
        trailing: Text(ShortcutScheme(defaultTargetPlatform).runLabel),
      ),
      const SizedBox(height: 24),
      const Divider(),
      const SizedBox(height: 24),
      Text('数据与隐私', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      const Text('连接配置和最近 100 条活动分别保存在本机或执行目标上。活动记录只保留状态和时间，不保存参数或结果内容。'),
      const SizedBox(height: 8),
      const Text('HTTP MCP 的 Bearer Token 保存在当前运行端的安全存储中，删除连接时同步删除。'),
      const SizedBox(height: 16),
      DropdownButtonFormField<int>(
        initialValue: preferences.activityRetentionDays,
        decoration: const InputDecoration(labelText: '活动保留时长'),
        items: const [
          DropdownMenuItem(value: 7, child: Text('7 天')),
          DropdownMenuItem(value: 30, child: Text('30 天')),
          DropdownMenuItem(value: 90, child: Text('90 天')),
        ],
        onChanged: (value) {
          if (value != null) {
            onPreferencesChanged(
              preferences.copyWith(activityRetentionDays: value),
            );
          }
        },
      ),
      const SizedBox(height: 16),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: () => clearActivity(context),
          icon: const Icon(Icons.delete_outline),
          label: const Text('清空活动记录'),
        ),
      ),
      for (final section in platformSections) ...[
        const SizedBox(height: 32),
        const Divider(),
        const SizedBox(height: 24),
        section,
      ],
      const SizedBox(height: 32),
      const Divider(),
      const SizedBox(height: 24),
      Text('关于 Aggregate', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      const Text('Aggregate $_appVersion · CLI 与 MCP 功能聚合工作台'),
    ],
  );
}
