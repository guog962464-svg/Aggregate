import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show ValueListenable;
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
  static const _textContrastHaloStartDaylight = 0.46;
  static const _textContrastHaloEndDaylight = 0.55;

  double _seconds = 0;
  double? _switchDaylight;
  GlassSceneEmitter? _themeSwitchEmitter;
  bool _disposed = false;
  bool _textContrastUpdateScheduled = false;
  bool? _pendingTextContrastUsesDarkForeground;
  bool _textContrastHaloUpdateScheduled = false;
  bool _pendingTextContrastNeedsHalo = false;
  final ValueNotifier<bool?> _textContrastUsesDarkForeground =
      ValueNotifier<bool?>(null);
  final ValueNotifier<bool> _textContrastNeedsHalo = ValueNotifier(false);

  double get seconds => _seconds;
  double? get switchDaylight => _switchDaylight;
  GlassSceneEmitter? get themeSwitchEmitter => _themeSwitchEmitter;
  ValueListenable<bool?> get textContrastUsesDarkForeground =>
      _textContrastUsesDarkForeground;
  ValueListenable<bool> get textContrastNeedsHalo => _textContrastNeedsHalo;

  void publishThemeSwitch(
    double seconds,
    double daylight, {
    GlassSceneEmitter? emitter,
  }) {
    if (_disposed) return;
    final nextEmitter = emitter ?? _themeSwitchEmitter;
    final usesDarkForeground = daylight >= 0.5;
    _updateTextContrastForeground(usesDarkForeground);
    // A pixel sweep of the production settings text found the low-contrast
    // window around the foreground crossover. The halo never feeds back into
    // the switch simulation or the shader's live daylight value.
    _updateTextContrastHalo(
      daylight >= _textContrastHaloStartDaylight &&
          daylight <= _textContrastHaloEndDaylight,
    );
    final changed =
        (_seconds - seconds).abs() > 0.000001 ||
        _switchDaylight == null ||
        (_switchDaylight! - daylight).abs() > 0.000001 ||
        nextEmitter != _themeSwitchEmitter;
    _seconds = seconds;
    _switchDaylight = daylight;
    _themeSwitchEmitter = nextEmitter;
    if (changed) notifyListeners();
  }

  void clearThemeSwitch() {
    if (_disposed) return;
    if (_switchDaylight == null && _themeSwitchEmitter == null) return;
    _switchDaylight = null;
    _themeSwitchEmitter = null;
    _updateTextContrastForeground(null);
    _updateTextContrastHalo(false);
    notifyListeners();
  }

  void _updateTextContrastForeground(bool? usesDarkForeground) {
    if (_textContrastUsesDarkForeground.value == usesDarkForeground &&
        !_textContrastUpdateScheduled) {
      return;
    }
    _pendingTextContrastUsesDarkForeground = usesDarkForeground;
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks) {
      if (_textContrastUpdateScheduled) return;
      _textContrastUpdateScheduled = true;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _textContrastUpdateScheduled = false;
        if (!_disposed) {
          _textContrastUsesDarkForeground.value =
              _pendingTextContrastUsesDarkForeground;
        }
      });
      return;
    }
    _textContrastUsesDarkForeground.value = usesDarkForeground;
  }

  void _updateTextContrastHalo(bool needsHalo) {
    if (_textContrastNeedsHalo.value == needsHalo &&
        !_textContrastHaloUpdateScheduled) {
      return;
    }
    _pendingTextContrastNeedsHalo = needsHalo;
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks) {
      if (_textContrastHaloUpdateScheduled) return;
      _textContrastHaloUpdateScheduled = true;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _textContrastHaloUpdateScheduled = false;
        if (!_disposed) {
          _textContrastNeedsHalo.value = _pendingTextContrastNeedsHalo;
        }
      });
      return;
    }
    _textContrastNeedsHalo.value = needsHalo;
  }

  @override
  void dispose() {
    _disposed = true;
    _textContrastUsesDarkForeground.dispose();
    _textContrastNeedsHalo.dispose();
    super.dispose();
  }
}

/// A rendering-only light source whose spill is drawn across the whole scene.
/// Keeping it in window coordinates avoids clipping the theme switch's glow at
/// the bounds of its interactive widget.
@immutable
class GlassSceneEmitter {
  const GlassSceneEmitter({
    required this.center,
    required this.scale,
    required this.handle,
    required this.extent,
    required this.rounding,
    required this.orbitAngle,
    required this.energy,
    required this.lampRed,
    required this.lampGreen,
    required this.lampBlue,
    required this.stripHalfAngle,
  });

  final Offset center;
  final double scale;
  final Offset handle;
  final Size extent;
  final double rounding;
  final double orbitAngle;
  final double energy;
  final double lampRed;
  final double lampGreen;
  final double lampBlue;
  final double stripHalfAngle;

  @override
  bool operator ==(Object other) =>
      other is GlassSceneEmitter &&
      center == other.center &&
      scale == other.scale &&
      handle == other.handle &&
      extent == other.extent &&
      rounding == other.rounding &&
      orbitAngle == other.orbitAngle &&
      energy == other.energy &&
      lampRed == other.lampRed &&
      lampGreen == other.lampGreen &&
      lampBlue == other.lampBlue &&
      stripHalfAngle == other.stripHalfAngle;

  @override
  int get hashCode => Object.hash(
    center,
    scale,
    handle,
    extent,
    rounding,
    orbitAngle,
    energy,
    lampRed,
    lampGreen,
    lampBlue,
    stripHalfAngle,
  );
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
          frame.switchDaylight ?? tokens.daylight,
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
    final emitter = frame.themeSwitchEmitter;
    effect.setFloat(5, emitter == null ? 0 : 1);
    effect.setFloat(6, emitter?.center.dx ?? 0);
    effect.setFloat(7, emitter?.center.dy ?? 0);
    effect.setFloat(8, emitter?.scale ?? 1);
    effect.setFloat(9, emitter?.handle.dx ?? 0);
    effect.setFloat(10, emitter?.handle.dy ?? 0);
    effect.setFloat(11, emitter?.extent.width ?? 99);
    effect.setFloat(12, emitter?.extent.height ?? 99);
    effect.setFloat(13, emitter?.rounding ?? 58);
    effect.setFloat(14, emitter?.orbitAngle ?? 0);
    effect.setFloat(15, emitter?.energy ?? 0);
    effect.setFloat(16, emitter?.lampRed ?? 0);
    effect.setFloat(17, emitter?.lampGreen ?? 0);
    effect.setFloat(18, emitter?.lampBlue ?? 0);
    effect.setFloat(19, emitter?.stripHalfAngle ?? 0.92);
    canvas.drawRect(Offset.zero & size, Paint()..shader = effect);
  }

  @override
  bool shouldRepaint(covariant _GlassScenePainter oldDelegate) =>
      shader != oldDelegate.shader ||
      tokens != oldDelegate.tokens ||
      pixelRatio != oldDelegate.pixelRatio;
}
