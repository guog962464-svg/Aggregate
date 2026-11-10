import 'package:flutter/material.dart';

import 'app/aggregate_app.dart';
import 'platform/macos/local_runtime_port.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final runtime = await LocalRuntimePort.createLive();
  runApp(AggregateApp(runtime: runtime));
}
