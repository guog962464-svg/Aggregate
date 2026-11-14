import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../widgets/glass/aggregate_buttons.dart';
import '../../widgets/glass/glass_motion.dart';
import 'glass_theme_switch.dart';
import 'theme_switch_fitted_calibration.dart';

class AppearanceSelector extends StatelessWidget {
  const AppearanceSelector({
    super.key,
    required this.appearance,
    required this.onChanged,
    required this.systemLabel,
  });

  final AppearancePreference appearance;
  final ValueChanged<AppearancePreference> onChanged;
  final String systemLabel;

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
          constraints: const BoxConstraints(maxWidth: 360),
          child: GlassThemeSwitch(
            calibration: videoFittedThemeSwitch,
            light: light,
            onChanged: (value) => onChanged(
              value ? AppearancePreference.light : AppearancePreference.dark,
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (defaultTargetPlatform == TargetPlatform.macOS &&
            GlassMotionScope.maybeOf(context) != null)
          AggregateActionButton(
            label: systemLabel,
            icon: Icons.brightness_auto_outlined,
            semanticsLabel: systemLabel,
            selected: followsSystem,
            onPressed: () => onChanged(AppearancePreference.system),
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
