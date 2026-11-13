import 'package:flutter/material.dart';

import 'app/aggregate_app.dart';
import 'features/settings/android_host_settings_panel.dart';
import 'features/settings/mac_host_settings_panel.dart';
import 'platform/android/android_runtime_port.dart';
import 'platform/macos/local_runtime_port.dart';
import 'platform/runtime_factory.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final runtime = await createRuntimePort();
  final settingsSections = switch (runtime) {
    LocalRuntimePort(:final hostControl) => [
      MacHostSettingsPanel(
        hostControl: hostControl,
        pairingControl: hostControl,
      ),
    ],
    AndroidRuntimePort(:final hostManager) => [
      AndroidHostSettingsPanel(hostManager: hostManager),
    ],
    _ => const <Widget>[],
  };
  runApp(
    AggregateApp(runtime: runtime, platformSettingsSections: settingsSections),
  );
}
