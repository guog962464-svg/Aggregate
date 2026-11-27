import 'package:flutter/material.dart';
import 'package:aggregate_contracts/aggregate_contracts.dart';

import 'app/aggregate_app.dart';
import 'platform/macos/mac_host_settings_panel.dart';
import 'preview/ui6_inspection_host.dart';
import 'preview/preview_runtime_factory.dart';

/// Visual review entrypoint. The release entrypoint remains main.dart.
const _previewAppearance = String.fromEnvironment(
  'PREVIEW_APPEARANCE',
  defaultValue: 'system',
);
const _previewMusic = bool.fromEnvironment('PREVIEW_MUSIC');
const _previewHostBoard06 = bool.fromEnvironment('PREVIEW_HOST_BOARD06');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final runtime = createPreviewRuntime();
  if (_previewAppearance == 'light' || _previewAppearance == 'dark') {
    await runtime.savePreferences(
      UserPreferences(
        appearance: _previewAppearance == 'dark'
            ? AppearancePreference.dark
            : AppearancePreference.light,
      ),
    );
  }
  final host = Ui6InspectionHost(matchBoard06: _previewHostBoard06);
  runApp(
    AggregateApp(
      runtime: runtime,
      showMusicDesignPreview: _previewMusic,
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
