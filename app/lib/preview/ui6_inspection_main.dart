import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:flutter/material.dart';

import '../app/aggregate_app.dart';
import '../platform/macos/mac_host_settings_panel.dart';
import 'ui6_inspection_host.dart';
import 'ui6_inspection_runtime.dart';

const _seedActivity = bool.fromEnvironment('UI6_SEED_ACTIVITY');
const _seedRunningActivity = bool.fromEnvironment('UI6_SEED_ACTIVITY_RUNNING');
const _previewAppearance = String.fromEnvironment(
  'PREVIEW_APPEARANCE',
  defaultValue: 'system',
);
const _seedActivityFilterStates = bool.fromEnvironment(
  'UI6_SEED_ACTIVITY_FILTER_STATES',
);
const _emptyWorkspace = bool.fromEnvironment('UI6_EMPTY_WORKSPACE');
const _httpOnlyWorkspace = bool.fromEnvironment('UI6_HTTP_ONLY_WORKSPACE');
const _resultUnknownFixture = bool.fromEnvironment(
  'UI6_RESULT_UNKNOWN_FIXTURE',
);

/// Dedicated macOS Profile entrypoint for reviewing production button contexts.
/// All runtime, setup, account, terminal, and Host services are in-memory stubs.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final runtime = Ui6InspectionRuntime(
    emptyWorkspace: _emptyWorkspace,
    resultUnknownFixture: _resultUnknownFixture,
    features: _httpOnlyWorkspace
        ? RuntimeFeatures.httpOnly
        : RuntimeFeatures.localDesktop,
  );
  if (_previewAppearance == 'light' || _previewAppearance == 'dark') {
    await runtime.savePreferences(
      UserPreferences(
        appearance: _previewAppearance == 'dark'
            ? AppearancePreference.dark
            : AppearancePreference.light,
      ),
    );
  }
  if (_seedActivity || _seedRunningActivity || _seedActivityFilterStates) {
    await runtime.seedActivityForInspection(
      includeRunning: _seedRunningActivity,
      includeFilterStates: _seedActivityFilterStates,
    );
  }
  final host = Ui6InspectionHost();
  runApp(
    AggregateApp(
      runtime: runtime,
      showMusicDesignPreview: true,
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
