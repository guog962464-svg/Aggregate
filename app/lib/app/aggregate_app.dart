import 'dart:async';

import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../features/invocation/capability_run_page.dart';
import '../features/music/music_session.dart';
import '../widgets/glass/glass_motion.dart';
import '../widgets/glass/glass_scene.dart';
import 'app_shell.dart';
import 'shortcut_scheme.dart';
import 'theme.dart';

class AggregateApp extends StatefulWidget {
  const AggregateApp({
    super.key,
    required this.runtime,
    this.platformSettingsSections = const [],
    this.glassMotionClock,
  });

  final RuntimePort runtime;
  final List<Widget> platformSettingsSections;
  final GlassMotionClock? glassMotionClock;

  @override
  State<AggregateApp> createState() => _AggregateAppState();
}

class _AggregateAppState extends State<AggregateApp> {
  UserPreferences preferences = const UserPreferences();
  final navigatorKey = GlobalKey<NavigatorState>();
  final shellKey = GlobalKey<AppShellState>();
  final messengerKey = GlobalKey<ScaffoldMessengerState>();
  late final MusicSession musicSession;

  @override
  void initState() {
    super.initState();
    musicSession = MusicSession(widget.runtime);
    unawaited(_loadPreferences());
  }

  @override
  void dispose() {
    musicSession.dispose();
    super.dispose();
  }

  Future<void> _loadPreferences() async {
    try {
      final loaded = await widget.runtime.loadPreferences();
      if (mounted) setState(() => preferences = loaded);
    } catch (cause) {
      messengerKey.currentState?.showSnackBar(
        SnackBar(content: Text('加载偏好设置失败：$cause')),
      );
    }
  }

  Future<void> _savePreferences(UserPreferences next) async {
    final previous = preferences;
    setState(() => preferences = next);
    try {
      await widget.runtime.savePreferences(next);
    } catch (cause) {
      if (!mounted) return;
      setState(() => preferences = previous);
      messengerKey.currentState?.showSnackBar(
        SnackBar(content: Text('保存偏好设置失败：$cause')),
      );
    }
  }

  Future<void> _clearActivity() async {
    await widget.runtime.clearActivity();
    shellKey.currentState?.refreshActivity();
  }

  ThemeMode get themeMode => switch (preferences.appearance) {
    AppearancePreference.system => ThemeMode.system,
    AppearancePreference.light => ThemeMode.light,
    AppearancePreference.dark => ThemeMode.dark,
  };

  Duration _themeAnimationDuration(BuildContext context) =>
      // The switch has its own continuous animation. Interpolating ThemeData
      // for the whole Android page on each vsync exceeds the high-refresh frame
      // budget; apply the selected page theme once while the switch keeps moving.
      MediaQuery.disableAnimationsOf(context) ||
          defaultTargetPlatform == TargetPlatform.android
      ? Duration.zero
      : const Duration(milliseconds: 560);

  void searchAll() {
    navigatorKey.currentState?.popUntil((route) => route.isFirst);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      shellKey.currentState?.searchAll();
    });
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Aggregate',
    debugShowCheckedModeBanner: false,
    theme: AggregateTheme.forPlatform(
      AggregateTheme.light,
      defaultTargetPlatform,
    ),
    darkTheme: AggregateTheme.forPlatform(
      AggregateTheme.dark,
      defaultTargetPlatform,
    ),
    themeMode: themeMode,
    themeAnimationDuration: _themeAnimationDuration(context),
    themeAnimationCurve: Curves.easeInOutCubic,
    navigatorKey: navigatorKey,
    scaffoldMessengerKey: messengerKey,
    builder: (context, child) {
      final content = CallbackShortcuts(
        bindings: {ShortcutScheme(defaultTargetPlatform).search: searchAll},
        child: Focus(autofocus: true, child: child ?? const SizedBox.shrink()),
      );
      return defaultTargetPlatform == TargetPlatform.macOS
          ? GlassScene(
              child: GlassMotionScope(
                clock: widget.glassMotionClock,
                child: content,
              ),
            )
          : content;
    },
    onGenerateRoute: (settings) {
      if (settings.name == '/' || settings.name == null) {
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => AppShell(
            key: shellKey,
            runtime: widget.runtime,
            preferences: preferences,
            onPreferencesChanged: (value) => unawaited(_savePreferences(value)),
            onClearActivity: _clearActivity,
            musicSession: musicSession,
            glassMotionClock: widget.glassMotionClock,
            platformSettingsSections: widget.platformSettingsSections,
          ),
        );
      }
      if (settings.name == '/run' && settings.arguments is Capability) {
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) {
            final page = CapabilityRunPage(
              runtime: widget.runtime,
              capability: settings.arguments! as Capability,
              musicSession: musicSession,
              onSearchAll: searchAll,
              onOpenMusic: shellKey.currentState?.openMusicPlayer,
            );
            return defaultTargetPlatform == TargetPlatform.macOS
                ? GlassMotionScope(clock: widget.glassMotionClock, child: page)
                : page;
          },
        );
      }
      return null;
    },
  );
}
