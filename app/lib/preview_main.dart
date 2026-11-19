import 'package:flutter/material.dart';
import 'package:aggregate_contracts/aggregate_contracts.dart';

import 'app/aggregate_app.dart';
import 'preview/preview_runtime_factory.dart';

/// Visual review entrypoint. The release entrypoint remains main.dart.
const _previewAppearance = String.fromEnvironment(
  'PREVIEW_APPEARANCE',
  defaultValue: 'system',
);

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
  runApp(AggregateApp(runtime: runtime));
}
