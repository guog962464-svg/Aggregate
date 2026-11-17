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
    this.systemDisableAnimations,
  });

  final RuntimePort runtime;
  final List<Widget> platformSettingsSections;
  final GlassMotionClock? glassMotionClock;
  final ValueListenable<bool>? systemDisableAnimations;

  @override
  State<AggregateApp> createState() => _AggregateAppState();
}

class _AggregateAppState extends State<AggregateApp> {
  UserPreferences preferences = const UserPreferences();
  final navigatorKey = GlobalKey<NavigatorState>();
  final shellKey = GlobalKey<AppShellState>();
  final messengerKey = GlobalKey<ScaffoldMessengerState>();
  late final MusicSession musicSession;
  late bool _systemDisableAnimations;

  @override
  void initState() {
    super.initState();
    _systemDisableAnimations = widget.systemDisableAnimations?.value ?? false;
    widget.systemDisableAnimations?.addListener(_systemMotionChanged);
    musicSession = MusicSession(widget.runtime);
    unawaited(_loadPreferences());
  }

  @override
  void didUpdateWidget(covariant AggregateApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.systemDisableAnimations != widget.systemDisableAnimations) {
      oldWidget.systemDisableAnimations?.removeListener(_systemMotionChanged);
      _systemDisableAnimations = widget.systemDisableAnimations?.value ?? false;
      widget.systemDisableAnimations?.addListener(_systemMotionChanged);
    }
  }

  void _systemMotionChanged() {
    final next = widget.systemDisableAnimations?.value ?? false;
    if (next == _systemDisableAnimations || !mounted) return;
    setState(() => _systemDisableAnimations = next);
  }

  @override
  void dispose() {
    widget.systemDisableAnimations?.removeListener(_systemMotionChanged);
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
      _systemDisableAnimations ||
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
      final safeTheme = AggregateTheme.withMacOSSurfaceTextContrast(
        Theme.of(context),
      );
      final appContent = defaultTargetPlatform == TargetPlatform.macOS
          ? Theme(
              data: safeTheme,
              child: GlassScene(
                child: _GlassSceneTextContrast(
                  child: GlassMotionScope(
                    clock: widget.glassMotionClock,
                    child: content,
                  ),
                ),
              ),
            )
          : content;
      final mediaQuery = MediaQuery.of(context);
      final disableAnimations =
          mediaQuery.disableAnimations || _systemDisableAnimations;
      return disableAnimations == mediaQuery.disableAnimations
          ? appContent
          : MediaQuery(
              data: mediaQuery.copyWith(disableAnimations: disableAnimations),
              child: appContent,
            );
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

/// Updates semantic foregrounds only when the glass background crosses its
/// luminance midpoint; the continuously animated backdrop stays independent.
class _GlassSceneTextContrast extends StatelessWidget {
  const _GlassSceneTextContrast({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final frame = GlassSceneScope.maybeOf(context)?.frame;
    if (frame == null) return child;

    return ValueListenableBuilder<bool?>(
      valueListenable: frame.textContrastUsesDarkForeground,
      child: child,
      builder: (context, usesDarkForeground, child) {
        final safeTheme = AggregateTheme.withMacOSSurfaceTextContrast(
          Theme.of(context),
        );
        final data = usesDarkForeground == null
            ? safeTheme
            : AggregateTheme.withMacOSBackdropTextContrast(
                safeTheme,
                usesDarkForeground: usesDarkForeground,
              );
        return Theme(data: data, child: child!);
      },
    );
  }
}
