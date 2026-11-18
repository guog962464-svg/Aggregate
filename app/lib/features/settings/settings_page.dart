import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:aggregate_contracts/aggregate_contracts.dart';

import '../../app/shortcut_scheme.dart';
import '../../widgets/glass/aggregate_buttons.dart';
import '../../widgets/glass/glass_design_tokens.dart';
import '../../widgets/page_frame.dart';
import 'appearance_selector.dart';
import 'theme_switch_calibration.dart';

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
          AggregateActionButton(
            label: '取消',
            icon: Icons.close,
            style: AggregateActionStyle.quiet,
            onPressed: () => Navigator.pop(context, false),
          ),
          AggregateActionButton(
            label: '清空记录',
            icon: Icons.delete_outline,
            style: AggregateActionStyle.danger,
            onPressed: () => Navigator.pop(context, true),
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
  Widget build(BuildContext context) =>
      defaultTargetPlatform == TargetPlatform.macOS
      ? _buildMacSettings(context)
      : _buildStandardSettings(context);

  Widget _buildMacSettings(BuildContext context) => DefaultTabController(
    length: 4,
    child: Builder(
      builder: (context) {
        final controller = DefaultTabController.of(context);
        final glassTokens =
            Theme.of(context).extension<GlassDesignTokens>() ??
            GlassDesignTokens.forBrightness(Theme.of(context).brightness);
        return AnimatedBuilder(
          animation: controller,
          builder: (context, _) => PageFrame(
            title: '设置',
            children: [
              TabBar(
                controller: controller,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                dividerColor: Colors.transparent,
                labelColor: Theme.of(context).colorScheme.onSurface,
                unselectedLabelColor: Theme.of(context)
                    .colorScheme
                    .onSurfaceVariant,
                labelStyle: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(fontWeight: FontWeight.w600),
                unselectedLabelStyle: Theme.of(context).textTheme.bodySmall,
                labelPadding: const EdgeInsets.symmetric(horizontal: 16),
                indicatorSize: TabBarIndicatorSize.label,
                indicatorPadding: const EdgeInsets.only(bottom: 3),
                indicator: BoxDecoration(
                  color: glassTokens.raised.withValues(alpha: .42),
                  borderRadius: BorderRadius.circular(10),
                  border: Border(
                    bottom: BorderSide(
                      color: glassTokens.glow.withValues(alpha: .60),
                      width: 1.2,
                    ),
                  ),
                ),
                tabs: const [
                  Tab(height: 38, text: '外观'),
                  Tab(height: 38, text: 'Mac Host'),
                  Tab(height: 38, text: '快捷键'),
                  Tab(height: 38, text: '本机数据'),
                ],
              ),
              const SizedBox(height: 20),
              const Divider(height: 1),
              const SizedBox(height: 24),
              switch (controller.index) {
                0 => _appearanceTab(context),
                1 => _macHostTab(),
                2 => _shortcutsTab(context),
                _ => _localDataTab(context),
              },
            ],
          ),
        );
      },
    ),
  );

  Widget _appearanceTab(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('外观', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      const Text('选择浅色、深色，或跟随 macOS。'),
      const SizedBox(height: 60),
      SizedBox(
        width: 440,
        child: Center(
          child: AppearanceSelector(
            switchWidth: 440,
            switchHeightFactor: .46,
            calibration: ThemeSwitchCalibration.reference,
            appearance: preferences.appearance,
            systemLabel: '跟随 macOS 系统',
            onChanged: (appearance) => onPreferencesChanged(
              preferences.copyWith(appearance: appearance),
            ),
          ),
        ),
      ),
    ],
  );

  Widget _macHostTab() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (var i = 0; i < platformSections.length; i++) ...[
        if (i > 0) const SizedBox(height: 20),
        platformSections[i],
      ],
    ],
  );

  Widget _shortcutsTab(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('快捷键', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      const Text('用键盘快速打开常用操作。'),
      const SizedBox(height: 18),
      _shortcutRow(
        context,
        '搜索所有功能',
        ShortcutScheme(defaultTargetPlatform).searchLabel,
      ),
      const Divider(height: 1),
      _shortcutRow(
        context,
        '运行当前功能',
        ShortcutScheme(defaultTargetPlatform).runLabel,
      ),
      const Divider(height: 1),
      _shortcutRow(context, '返回', 'Esc'),
    ],
  );

  Widget _shortcutRow(BuildContext context, String label, String shortcut) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Expanded(child: Text(label)),
            Text(
              shortcut,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );

  Widget _localDataTab(BuildContext context) {
    final dropdownDecoration = InputDecoration(
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('本机数据', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        const Text('连接配置和活动记录保存在本机或执行端；活动内容不会保存参数或结果。'),
        const SizedBox(height: 6),
        const Text('HTTP MCP 的 Bearer Token 保存在当前运行端的安全存储中。'),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('活动保留时长'),
                  const SizedBox(height: 3),
                  Text(
                    '只保留最近活动记录。',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 108,
              child: DropdownButtonFormField<int>(
                initialValue: preferences.activityRetentionDays,
                decoration: dropdownDecoration,
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
            ),
          ],
        ),
        const SizedBox(height: 16),
        const Divider(height: 1),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('清空活动记录'),
                  const SizedBox(height: 3),
                  Text(
                    '删除本机保存的调用历史。',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            AggregateActionButton(
              label: '清空记录',
              icon: Icons.delete_outline,
              style: AggregateActionStyle.danger,
              onPressed: () => clearActivity(context),
            ),
          ],
        ),
        const SizedBox(height: 24),
        const Divider(height: 1),
        const SizedBox(height: 20),
        Text('关于 Aggregate', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        const Text('Aggregate $_appVersion · CLI 与 MCP 功能聚合工作台'),
      ],
    );
  }

  Widget _buildStandardSettings(BuildContext context) => PageFrame(
    title: '设置',
    subtitle: '让工作台适应你的使用方式。',
    children: [
      Text('外观', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      const Text('主题选择保存在本机。'),
      const SizedBox(height: 16),
      Center(
        child: AppearanceSelector(
          appearance: preferences.appearance,
          systemLabel: defaultTargetPlatform == TargetPlatform.macOS
              ? '跟随 macOS 系统'
              : '跟随系统',
          onChanged: (appearance) => onPreferencesChanged(
            preferences.copyWith(appearance: appearance),
          ),
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
        child: AggregateActionButton(
          label: '清空活动记录',
          icon: Icons.delete_outline,
          style: AggregateActionStyle.danger,
          onPressed: () => clearActivity(context),
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
