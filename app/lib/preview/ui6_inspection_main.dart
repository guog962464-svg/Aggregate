import 'package:flutter/material.dart';

import '../app/aggregate_app.dart';
import '../platform/macos/mac_host_settings_panel.dart';
import 'ui6_inspection_host.dart';
import 'ui6_inspection_runtime.dart';

const _seedActivity = bool.fromEnvironment('UI6_SEED_ACTIVITY');

/// Dedicated macOS Profile entrypoint for reviewing production button contexts.
/// All runtime, setup, account, terminal, and Host services are in-memory stubs.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final runtime = Ui6InspectionRuntime();
  if (_seedActivity) await runtime.seedActivityForInspection();
  final host = Ui6InspectionHost();
  runApp(
    AggregateApp(
      runtime: runtime,
      platformSettingsSections: [
        MacHostSettingsPanel(
          hostControl: host,
          pairingControl: host,
          identityRotation: host,
          loadConnections: runtime.listConnections,
        ),
      ],
    ),
  );
}
