import 'package:flutter/material.dart';

import 'app/aggregate_app.dart';
import 'preview/preview_runtime_factory.dart';

/// Visual review entrypoint. The release entrypoint remains main.dart.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(AggregateApp(runtime: createPreviewRuntime()));
}
