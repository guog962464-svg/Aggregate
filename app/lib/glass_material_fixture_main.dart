import 'package:flutter/material.dart';

import 'app/theme.dart';
import 'widgets/glass/glass_material_fixture.dart';
import 'widgets/glass/glass_scene.dart';

void main() => runApp(const GlassMaterialFixtureApp());

class GlassMaterialFixtureApp extends StatefulWidget {
  const GlassMaterialFixtureApp({super.key});

  @override
  State<GlassMaterialFixtureApp> createState() =>
      _GlassMaterialFixtureAppState();
}

class _GlassMaterialFixtureAppState extends State<GlassMaterialFixtureApp> {
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
      home: GlassMaterialFixturePage(
        light: _light,
        onLightChanged: (value) => setState(() => _light = value),
      ),
    );
  }
}
