import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Keeps native macOS window chrome in step with the in-app appearance choice.
/// The shared Flutter theme and theme-switch gesture remain the source of truth.
abstract final class MacWindowAppearance {
  static const _channel = MethodChannel('aggregate/macos_window_appearance');

  static Future<void> apply(AppearancePreference appearance) async {
    if (defaultTargetPlatform != TargetPlatform.macOS) return;
    try {
      await _channel.invokeMethod<void>('setAppearance', switch (appearance) {
        AppearancePreference.system => 'system',
        AppearancePreference.light => 'light',
        AppearancePreference.dark => 'dark',
      });
    } on MissingPluginException {
      // Keep the Flutter theme usable in previews without the macOS runner.
    } on PlatformException {
      // Native chrome falls back to the system appearance if the bridge fails.
    }
  }
}
