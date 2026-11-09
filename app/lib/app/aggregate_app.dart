import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:flutter/material.dart';

import '../features/invocation/capability_run_page.dart';
import 'app_shell.dart';
import 'theme.dart';

class AggregateApp extends StatelessWidget {
  const AggregateApp({super.key, required this.runtime});

  final RuntimePort runtime;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Aggregate',
    debugShowCheckedModeBanner: false,
    theme: AggregateTheme.light,
    darkTheme: AggregateTheme.dark,
    themeMode: ThemeMode.system,
    onGenerateRoute: (settings) {
      if (settings.name == '/' || settings.name == null) {
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => AppShell(runtime: runtime),
        );
      }
      if (settings.name == '/run' && settings.arguments is Capability) {
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => CapabilityRunPage(
            runtime: runtime,
            capability: settings.arguments! as Capability,
          ),
        );
      }
      return null;
    },
  );
}
