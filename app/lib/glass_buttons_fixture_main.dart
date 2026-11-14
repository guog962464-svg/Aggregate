import 'package:flutter/material.dart';

import 'app/theme.dart';
import 'widgets/glass/glass_buttons_fixture.dart';
import 'widgets/glass/glass_scene.dart';

void main() => runApp(const GlassButtonsFixtureApp());

class GlassButtonsFixtureApp extends StatefulWidget {
  const GlassButtonsFixtureApp({super.key});

  @override
  State<GlassButtonsFixtureApp> createState() => _GlassButtonsFixtureAppState();
}

class _GlassButtonsFixtureAppState extends State<GlassButtonsFixtureApp> {
  bool _light = false;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AggregateTheme.forPlatform(
        AggregateTheme.light,
        TargetPlatform.macOS,
      ),
      darkTheme: AggregateTheme.forPlatform(
        AggregateTheme.dark,
        TargetPlatform.macOS,
      ),
      themeMode: _light ? ThemeMode.light : ThemeMode.dark,
      builder: (context, child) =>
          GlassScene(child: child ?? const SizedBox.shrink()),
      home: GlassButtonsFixturePage(
        light: _light,
        onLightChanged: (value) => setState(() => _light = value),
      ),
    );
  }
}
