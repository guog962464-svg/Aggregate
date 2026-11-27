import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:aggregate_contracts/aggregate_contracts.dart';

import '../../app/shortcut_scheme.dart';
import '../../widgets/glass/aggregate_buttons.dart';
import '../../widgets/glass/glass_alert_dialog.dart';
import '../../widgets/glass/glass_design_tokens.dart';
import '../../widgets/page_frame.dart';
import 'appearance_selector.dart';
import 'theme_switch_calibration.dart';

const _appVersion = String.fromEnvironment('APP_VERSION', defaultValue: '开发版');

// Keep the reference switch's simulation, particles, and optics unchanged.
// The macOS settings card has room for the full-size glass track, so only its
// scene presentation scale differs from the compact default instances.
const _macSettingsThemeSwitchCalibration = ThemeSwitchCalibration(
  scene: ThemeSwitchScene(scale: 1.5),
);

// At scene scale 1.5, this host resolves to the reference 432×224pt track.
const _macSettingsThemeSwitchWidth = 480.0;
const _macSettingsThemeSwitchHeightFactor = 224 / _macSettingsThemeSwitchWidth;

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
    final confirmed = await showGlassDialog<bool>(
      context: context,
      builder: (_) => GlassAlertDialog(
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

  Widget _buildMacSettings(BuildContext context) {
    final glassTokens =
        Theme.of(context).extension<GlassDesignTokens>() ??
        GlassDesignTokens.forBrightness(Theme.of(context).brightness);
    final divider = Divider(
      height: 1,
      color: glassTokens.line.withValues(alpha: .38),
    );
    return PageFrame(
      title: '设置',
      subtitle: '外观、设备和本机数据',
      contentPadding: const EdgeInsets.fromLTRB(40, 36, 52, 40),
      // The Profile window adds a native 32pt title bar above the Flutter
      // surface; keep the body aligned to the full-window v9 artboards.
      headerSpacing: 26,
      pinnedHeader: true,
      pinnedContentTopOcclusion: 60,
      children: [
        _appearanceTab(context),
        const SizedBox(height: 24),
        divider,
        const SizedBox(height: 24),
        _macHostTab(),
        const SizedBox(height: 24),
        divider,
        const SizedBox(height: 24),
        _shortcutsTab(context),
        const SizedBox(height: 24),
        divider,
        const SizedBox(height: 24),
        _localDataTab(context),
      ],
    );
  }

  Widget _appearanceTab(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 36, right: 10),
    child: AppearanceSelector(
      macSettingsLayout: true,
      switchWidth: _macSettingsThemeSwitchWidth,
      switchHeightFactor: _macSettingsThemeSwitchHeightFactor,
      calibration: _macSettingsThemeSwitchCalibration,
      appearance: preferences.appearance,
      systemLabel: '跟随 macOS 系统',
      helperText: '切换控件保持原始实时拖动、方向反转与太阳/月亮内部变化。',
      onChanged: (appearance) =>
          onPreferencesChanged(preferences.copyWith(appearance: appearance)),
    ),
  );

  Widget _macHostTab() => Padding(
    key: const Key('macos-settings-host-section'),
    padding: const EdgeInsets.only(left: 36, right: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < platformSections.length; i++) ...[
          if (i > 0) const SizedBox(height: 20),
          platformSections[i],
        ],
      ],
    ),
  );

  Widget _shortcutsTab(BuildContext context) => Padding(
    key: const Key('macos-settings-shortcuts-section'),
    padding: const EdgeInsets.only(left: 36, right: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '快捷键',
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(fontSize: 16, height: 19 / 16),
        ),
        const SizedBox(height: 5),
        Text(
          '名称与组合键沿用当前快捷键配置。',
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(fontSize: 11, height: 14 / 11),
        ),
        const SizedBox(height: 22),
        Text('导航', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        _shortcutRow(
          context,
          '所有功能',
          ShortcutScheme(defaultTargetPlatform).searchLabel,
        ),
        const Divider(height: 1),
        _shortcutRow(context, '返回', 'Esc'),
        const SizedBox(height: 18),
        Text('运行', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        _shortcutRow(
          context,
          '运行当前功能',
          ShortcutScheme(defaultTargetPlatform).runLabel,
        ),
      ],
    ),
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
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(11)),
    );
    return Padding(
      key: const Key('macos-settings-local-data-section'),
      padding: const EdgeInsets.only(left: 36, right: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('本机数据', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text('连接配置和活动记录保存在本机。'),
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('活动保留时长'),
                    const SizedBox(height: 5),
                    Text(
                      '仅保存脱敏后的运行状态信息',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    const Text('保留最近'),
                  ],
                ),
              ),
              SizedBox(
                width: 223,
                height: 44,
                child: DropdownButtonFormField<int>(
                  initialValue: preferences.activityRetentionDays,
                  isExpanded: true,
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
          const SizedBox(height: 24),
          const Divider(height: 1),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('清空活动记录'),
                    const SizedBox(height: 3),
                    Text(
                      '只删除本机保存的调用历史，不移除连接。',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '删除后无法恢复。',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 163,
                height: 40,
                child: AggregateActionButton(
                  label: '清空记录',
                  icon: Icons.delete_outline,
                  style: AggregateActionStyle.danger,
                  onPressed: () => clearActivity(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Divider(height: 1),
          const SizedBox(height: 20),
          Text('关于 Aggregate', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text('Aggregate $_appVersion · CLI 与 MCP 功能聚合工作台'),
          const SizedBox(height: 8),
          const Text('HTTP MCP 的 Bearer Token 保存在当前运行端的安全存储中。'),
        ],
      ),
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
