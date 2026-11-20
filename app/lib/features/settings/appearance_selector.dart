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
    this.calibration = videoFittedThemeSwitch,
    this.switchWidth = 360,
    this.switchHeightFactor = .75,
  });

  final AppearancePreference appearance;
  final ValueChanged<AppearancePreference> onChanged;
  final String systemLabel;
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: switchWidth),
          child: GlassThemeSwitch(
            calibration: calibration,
            heightFactor: switchHeightFactor,
            light: light,
            onChanged: (value) => onChanged(
              value ? AppearancePreference.light : AppearancePreference.dark,
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (defaultTargetPlatform == TargetPlatform.macOS &&
            GlassMotionScope.maybeOf(context) != null)
          SizedBox(
            width: 166,
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
        else
          Semantics(
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
          ),
      ],
    );
  }
}
