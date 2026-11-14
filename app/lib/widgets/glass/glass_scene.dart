import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'glass_design_tokens.dart';

/// Window-sized background and coordinate scope used by macOS glass widgets.
class GlassScene extends StatefulWidget {
  const GlassScene({super.key, required this.child});

  final Widget child;

  @override
  State<GlassScene> createState() => _GlassSceneState();
}

class _GlassSceneState extends State<GlassScene> {
  final _sceneKey = GlobalKey(debugLabel: 'Aggregate glass scene');
  final _frame = GlassSceneFrame();
  ui.FragmentShader? _shader;

  @override
  void initState() {
    super.initState();
    ui.FragmentProgram.fromAsset('shaders/glass_scene.frag')
        .then((program) {
          if (!mounted) return;
          setState(() => _shader = program.fragmentShader());
        })
        .catchError((Object _) {
          // The content remains usable if the optional backdrop shader fails.
        });
  }

  @override
  void dispose() {
    _frame.dispose();
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens =
        theme.extension<GlassDesignTokens>() ??
        GlassDesignTokens.forBrightness(theme.brightness);
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final sceneSize = constraints.biggest;
        return Stack(
          key: _sceneKey,
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: ExcludeSemantics(
                  child: CustomPaint(
                    painter: _GlassScenePainter(
                      shader: _shader,
                      tokens: tokens,
                      pixelRatio: pixelRatio,
                      frame: _frame,
                    ),
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: GlassSceneScope(
                size: sceneSize,
                sceneKey: _sceneKey,
                frame: _frame,
                child: widget.child,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Coordinates and the theme-switch clock shared by the full-window shader.
class GlassSceneScope extends InheritedWidget {
  const GlassSceneScope({
    super.key,
    required this.size,
    required this.sceneKey,
    required this.frame,
    required super.child,
  });

  final Size size;
  final GlobalKey sceneKey;
  final GlassSceneFrame frame;

  static GlassSceneScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GlassSceneScope>();

  Offset? originFor(BuildContext context, {VoidCallback? onLayoutDeferred}) {
    final child = context.findRenderObject();
    final scene = sceneKey.currentContext?.findRenderObject();
    if (child is! RenderBox ||
        scene is! RenderBox ||
        !child.attached ||
        !scene.attached) {
      return null;
    }

    RenderObject? current = child;
    while (current != null && current != scene) {
      if (current is RenderBox && (!current.attached || !current.hasSize)) {
        _deferUntilLayout(context, onLayoutDeferred);
        return null;
      }
      current = current.parent;
    }
    if (current != scene) return null;

    try {
      return MatrixUtils.transformPoint(
        child.getTransformTo(scene),
        Offset.zero,
      );
    } on FlutterError {
      _deferUntilLayout(context, onLayoutDeferred);
      return null;
    } on StateError {
      _deferUntilLayout(context, onLayoutDeferred);
      return null;
    } on AssertionError {
      _deferUntilLayout(context, onLayoutDeferred);
      return null;
    }
  }

  void _deferUntilLayout(BuildContext context, VoidCallback? callback) {
    if (callback == null) return;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) callback();
    });
  }

  @override
  bool updateShouldNotify(covariant GlassSceneScope oldWidget) =>
      size != oldWidget.size || sceneKey != oldWidget.sceneKey;
}

/// Rendering-only phase published by the original switch so its backdrop
/// samples the same grain time and theme-interpolation value.
class GlassSceneFrame extends ChangeNotifier {
  double _seconds = 0;
  double? _switchDaylight;
  bool _disposed = false;

  double get seconds => _seconds;
  double? get switchDaylight => _switchDaylight;

  void publishThemeSwitch(double seconds, double daylight) {
    if (_disposed) return;
    final changed =
        (_seconds - seconds).abs() > 0.000001 ||
        _switchDaylight == null ||
        (_switchDaylight! - daylight).abs() > 0.000001;
    _seconds = seconds;
    _switchDaylight = daylight;
    if (changed) notifyListeners();
  }

  void clearThemeSwitch() {
    if (_disposed) return;
    if (_switchDaylight == null) return;
    _switchDaylight = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class _GlassScenePainter extends CustomPainter {
  const _GlassScenePainter({
    required this.shader,
    required this.tokens,
    required this.pixelRatio,
    required this.frame,
  }) : super(repaint: frame);

  final ui.FragmentShader? shader;
  final GlassDesignTokens tokens;
  final double pixelRatio;
  final GlassSceneFrame frame;

  @override
  void paint(Canvas canvas, Size size) {
    final effect = shader;
    if (effect == null) {
      canvas.drawColor(
        Color.lerp(
          const Color(0xFF0A0A0A),
          const Color(0xFFCCCCCC),
          tokens.daylight,
        )!,
        BlendMode.src,
      );
      return;
    }
    effect.setFloat(0, size.width);
    effect.setFloat(1, size.height);
    effect.setFloat(2, frame.switchDaylight ?? tokens.daylight);
    effect.setFloat(3, frame.seconds);
    effect.setFloat(4, pixelRatio);
    canvas.drawRect(Offset.zero & size, Paint()..shader = effect);
  }

  @override
  bool shouldRepaint(covariant _GlassScenePainter oldDelegate) =>
      shader != oldDelegate.shader ||
      tokens != oldDelegate.tokens ||
      pixelRatio != oldDelegate.pixelRatio;
}
