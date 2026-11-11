import 'package:flutter/material.dart';

import 'app/aggregate_app.dart';
import 'platform/runtime_factory.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final runtime = await createRuntimePort();
  runApp(AggregateApp(runtime: runtime));
}
