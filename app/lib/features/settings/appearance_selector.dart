import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../widgets/glass/aggregate_buttons.dart';
import '../../widgets/glass/glass_action_button.dart';
import '../../widgets/glass/glass_motion.dart';
import 'glass_theme_switch.dart';
import 'theme_switch_calibration.dart';
import 'theme_switch_fitted_calibration.dart';

class AppearanceSelector extends StatelessWidget {
  const AppearanceSelector({
    super.key,
    required this.appearance,
    required this.onChanged,
    required this.systemLabel,
    this.helperText,
    this.macSettingsLayout = false,
    this.calibration = videoFittedThemeSwitch,
    this.switchWidth = 360,
    this.switchHeightFactor = .75,
  });

  final AppearancePreference appearance;
  final ValueChanged<AppearancePreference> onChanged;
  final String systemLabel;
  final String? helperText;
  final bool macSettingsLayout;
  final ThemeSwitchCalibration calibration;
  final double switchWidth;
  final double switchHeightFactor;

  @override
  Widget build(BuildContext context) {
    final light = switch (appearance) {
      AppearancePreference.light => true,
      AppearancePreference.dark => false,
      AppearancePreference.system =>
        Theme.of(context).brightness == Brightness.light,
    };
    final followsSystem = appearance == AppearancePreference.system;
    final scheme = Theme.of(context).colorScheme;
    final macGlass =
        defaultTargetPlatform == TargetPlatform.macOS &&
        GlassMotionScope.maybeOf(context) != null;
    final switchWidget = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: switchWidth),
      child: GlassThemeSwitch(
        calibration: calibration,
        heightFactor: switchHeightFactor,
        light: light,
        onChanged: (value) => onChanged(
          value ? AppearancePreference.light : AppearancePreference.dark,
        ),
      ),
    );
    final systemButton = macGlass
        ? SizedBox(
            width: 178,
            child: AggregateActionButton(
              label: systemLabel,
              icon: Icons.brightness_auto_outlined,
              semanticsLabel: systemLabel,
              selected: followsSystem,
              size: GlassButtonSize.compactAction,
              expand: true,
              onPressed: () => onChanged(AppearancePreference.system),
            ),
          )
        : Semantics(
            button: true,
            selected: followsSystem,
            label: systemLabel,
            onTap: () => onChanged(AppearancePreference.system),
            child: ExcludeSemantics(
              child: TextButton.icon(
                onPressed: () => onChanged(AppearancePreference.system),
                style: TextButton.styleFrom(
                  minimumSize: const Size(48, 48),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  foregroundColor: followsSystem
                      ? scheme.primary
                      : scheme.onSurfaceVariant,
                  backgroundColor: followsSystem
                      ? scheme.primaryContainer.withValues(alpha: 0.48)
                      : Colors.transparent,
                  shape: const StadiumBorder(),
                ),
                icon: const Icon(Icons.brightness_auto_outlined, size: 18),
                label: Text(systemLabel),
              ),
            ),
          );
    if (macGlass && macSettingsLayout) {
      final modeLabel = switch (appearance) {
        AppearancePreference.system => '跟随 macOS',
        AppearancePreference.light => '浅色',
        AppearancePreference.dark => '深色',
      };
      final macBodyText = Theme.of(context).textTheme.bodySmall
          ?.copyWith(fontSize: 11, height: 14 / 11);
      return LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 720) {
            return Column(
              key: const Key('macos-settings-appearance-section'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '外观',
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontSize: 16, height: 19 / 16),
                ),
                const SizedBox(height: 5),
                Text('拖动控件切换浅色和深色；也可以跟随 macOS。', style: macBodyText),
                const SizedBox(height: 12),
                Align(alignment: Alignment.center, child: switchWidget),
                const SizedBox(height: 12),
                Text('当前模式', style: macBodyText),
                const SizedBox(height: 5),
                Text(
                  modeLabel,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontSize: 14,
                    height: 17 / 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (helperText case final text?) ...[
                  const SizedBox(height: 12),
                  Text(text, style: macBodyText),
                ],
                const SizedBox(height: 12),
                systemButton,
              ],
            );
          }
          return SizedBox(
            key: const Key('macos-settings-appearance-section'),
            height: 238,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '外观',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontSize: 16, height: 19 / 16),
                        ),
                        const SizedBox(height: 5),
                        Text('拖动控件切换浅色和深色；也可以跟随 macOS。', style: macBodyText),
                        const SizedBox(height: 22),
                        Text('当前模式', style: macBodyText),
                        const SizedBox(height: 5),
                        Text(
                          modeLabel,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                fontSize: 14,
                                height: 17 / 14,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                        const SizedBox(height: 23),
                        if (helperText case final text?)
                          Text(text, style: macBodyText),
                        const SizedBox(height: 18),
                        systemButton,
                      ],
                    ),
                  ),
                ),
                SizedBox(
                  width: switchWidth,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: switchWidget,
                  ),
                ),
              ],
            ),
          );
        },
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: macGlass
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      children: [
        Align(
          alignment: Alignment.center,
          child: macGlass
              ? Padding(
                  padding: const EdgeInsets.only(left: 10),
                  child: switchWidget,
                )
              : switchWidget,
        ),
        if (macGlass && helperText != null) ...[
          const SizedBox(height: 84),
          Text(
            helperText!,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(fontSize: 11, height: 14 / 11),
          ),
          const SizedBox(height: 30),
        ] else
          const SizedBox(height: 8),
        systemButton,
      ],
    );
  }
}
