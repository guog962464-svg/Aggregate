import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'theme_switch_calibration.dart';
import 'theme_switch_simulation.dart';

/// A single draggable glass handle. All animation state belongs to one clock,
/// including the particles visible through the glass and its moving edge light.
class GlassThemeSwitch extends StatefulWidget {
  const GlassThemeSwitch({
    super.key,
    required this.light,
    required this.onChanged,
    this.calibration = ThemeSwitchCalibration.reference,
  });

  final bool light;
  final ValueChanged<bool> onChanged;
  final ThemeSwitchCalibration calibration;

  @override
  State<GlassThemeSwitch> createState() => _GlassThemeSwitchState();
}

class _GlassThemeSwitchState extends State<GlassThemeSwitch>
    with SingleTickerProviderStateMixin {
  late ThemeSwitchSimulation _simulation;
  final _focus = FocusNode(debugLabel: 'Theme switch');
  late final Ticker _ticker;
  Duration? _lastTick;
  bool _reduceMotion = false;
  bool _focused = false;
  bool _hoveredOnTrack = false;
  int? _pointer;
  bool _startedOnHandle = false;
  bool _dragAccepted = false;
  bool _tapRejected = false;
  bool _dragRejected = false;
  PointerMoveEvent? _pendingMove;
  double _startX = 0;
  double _startPosition = 0;
  double _moved = 0;
  double _lastPosition = 0;
  Duration _lastPointerTime = Duration.zero;
  double _time = 0;

  @override
  void initState() {
    super.initState();
    _simulation = ThemeSwitchSimulation(calibration: widget.calibration);
    _time = widget.calibration.timeOriginSeconds;
    _simulation.snapTo(widget.light);
    _simulation.advanceRealtime(0, _time);
    _ticker = createTicker(_tick);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion) {
      _ticker.stop();
      _simulation.snapTo(widget.light);
    } else if (!_ticker.isActive) {
      _lastTick = null;
      _ticker.start();
    }
  }

  @override
  void didUpdateWidget(covariant GlassThemeSwitch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.calibration != oldWidget.calibration) {
      _pointer = null;
      _simulation = ThemeSwitchSimulation(calibration: widget.calibration)
        ..snapTo(widget.light);
      _time = widget.calibration.timeOriginSeconds;
      _simulation.advanceRealtime(0, _time);
      _lastTick = null;
    }
    if (widget.light != oldWidget.light) {
      if (_reduceMotion) {
        _simulation.snapTo(widget.light);
      } else if (_pointer == null) {
        _simulation.setLight(widget.light);
      }
    }
  }

  void _tick(Duration elapsed) {
    final dt = _lastTick == null
        ? 0.0
        : (elapsed - _lastTick!).inMicroseconds / 1000000;
    _lastTick = elapsed;
    _time += dt;
    _simulation.advanceRealtime(dt, _time);
    setState(() {});
  }

  @override
  void dispose() {
    _ticker.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _select(bool light) {
    if (_reduceMotion) {
      _simulation.snapTo(light);
    } else {
      _simulation.setLight(light);
    }
    widget.onChanged(light);
    setState(() {});
  }

  Offset _designPoint(Offset local, Size size) =>
      (local - ThemeSwitchArtwork.sceneOrigin(size, widget.calibration.scene)) /
      ThemeSwitchArtwork.sceneScale(size, widget.calibration.scene);

  bool _insideTrack(Offset point) => RRect.fromRectAndRadius(
    const Rect.fromLTWH(-216, -112, 432, 224),
    const Radius.circular(72),
  ).contains(point);

  bool _insideHandle(Offset point) {
    final frame = _simulation.snapshot;
    return RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(frame.knobX, 0),
        width: frame.halfWidth * 2,
        height: frame.halfHeight * 2,
      ),
      Radius.circular(frame.radius),
    ).contains(point);
  }

  bool _allowsPointer(PointerDownEvent event, Size size, {bool drag = false}) {
    if (event.buttons != kPrimaryButton ||
        (_pointer != null && _pointer != event.pointer)) {
      return false;
    }
    final point = _designPoint(event.localPosition, size);
    return _insideTrack(point) &&
        (!drag || (!_reduceMotion && _insideHandle(point)));
  }

  void _down(PointerDownEvent event, Size size) {
    final point = _designPoint(event.localPosition, size);
    if (!_allowsPointer(event, size) || _pointer != null) return;
    _focus.requestFocus();
    _pointer = event.pointer;
    _startX = point.dx;
    _startPosition = _simulation.unresistedPosition;
    _lastPosition = _startPosition;
    _lastPointerTime = event.timeStamp;
    _moved = 0;
    _startedOnHandle = _insideHandle(point);
    _dragAccepted = false;
    _tapRejected = false;
    _dragRejected = !_startedOnHandle || _reduceMotion;
    _pendingMove = null;
    if (_startedOnHandle && !_reduceMotion) _simulation.beginDrag();
    _simulation.setPressed(true);
    setState(() {});
  }

  void _move(PointerMoveEvent event, Size size) {
    if (_pointer != event.pointer || !_startedOnHandle || _reduceMotion) return;
    _pendingMove = event;
    if (!_dragAccepted) return;
    _applyMove(event, size);
  }

  void _acceptDrag(Size size) {
    if (_pointer == null) return;
    _dragAccepted = true;
    if (_pendingMove case final event?) _applyMove(event, size);
  }

  void _applyMove(PointerMoveEvent event, Size size) {
    final point = _designPoint(event.localPosition, size);
    final distance = point.dx - _startX;
    _moved = math.max(
      _moved,
      distance.abs() *
          ThemeSwitchArtwork.sceneScale(size, widget.calibration.scene),
    );
    final position =
        _startPosition + distance / widget.calibration.motion.knobTravel;
    final dt = math.max(
      0.001,
      (event.timeStamp - _lastPointerTime).inMicroseconds / 1000000,
    );
    _simulation.dragTo(
      position,
      (position - _lastPosition) / dt,
      elapsedSeconds: dt,
    );
    _lastPosition = position;
    _lastPointerTime = event.timeStamp;
  }

  void _cancelRejectedGesture() {
    if (_tapRejected && _dragRejected) _finish(cancel: true);
  }

  void _rejectPointer(int pointer, {required bool tap}) {
    if (_pointer != pointer) return;
    if (tap) {
      _tapRejected = true;
    } else {
      _dragRejected = true;
    }
    _cancelRejectedGesture();
  }

  void _finish({bool cancel = false, bool tap = false}) {
    if (_pointer == null) return;
    _pointer = null;
    _pendingMove = null;
    _simulation.setPressed(false);
    if (cancel) {
      _simulation.releaseDrag(cancel: true);
      _simulation.setLight(widget.light);
    } else if (!tap && _startedOnHandle && _moved >= 4) {
      _simulation.releaseDrag();
      widget.onChanged(_simulation.light);
    } else {
      _simulation.releaseDrag(cancel: true);
      _select(!widget.light);
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    toggled: widget.light,
    label: '外观主题',
    value: widget.light ? '浅色' : '深色',
    hint: '点击切换，或左右拖动滑块',
    onTap: () => _select(!widget.light),
    child: FocusableActionDetector(
      focusNode: _focus,
      onShowFocusHighlight: (value) => setState(() => _focused = value),
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.arrowLeft): _DarkIntent(),
        SingleActivator(LogicalKeyboardKey.arrowRight): _LightIntent(),
      },
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) => _select(!widget.light),
        ),
        _DarkIntent: CallbackAction<_DarkIntent>(
          onInvoke: (_) => _select(false),
        ),
        _LightIntent: CallbackAction<_LightIntent>(
          onInvoke: (_) => _select(true),
        ),
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxWidth * 0.75);
          return MouseRegion(
            cursor: _pointer != null && _startedOnHandle
                ? SystemMouseCursors.grabbing
                : _hoveredOnTrack
                ? SystemMouseCursors.click
                : MouseCursor.defer,
            onHover: (event) {
              final hovered = _insideTrack(
                _designPoint(event.localPosition, size),
              );
              _simulation.setHovered(hovered);
              if (hovered != _hoveredOnTrack) {
                setState(() => _hoveredOnTrack = hovered);
              }
            },
            onExit: (_) {
              _simulation.setHovered(false);
              setState(() => _hoveredOnTrack = false);
            },
            child: RawGestureDetector(
              excludeFromSemantics: true,
              gestures: {
                _ThemeTapRecognizer:
                    GestureRecognizerFactoryWithHandlers<_ThemeTapRecognizer>(
                      _ThemeTapRecognizer.new,
                      (recognizer) {
                        recognizer.allowsPointer = (event) =>
                            _allowsPointer(event, size);
                        recognizer.onTapUp = (_) => _finish(tap: true);
                        recognizer.onRejected = (pointer) =>
                            _rejectPointer(pointer, tap: true);
                      },
                    ),
                _ThemeDragRecognizer:
                    GestureRecognizerFactoryWithHandlers<_ThemeDragRecognizer>(
                      _ThemeDragRecognizer.new,
                      (recognizer) {
                        recognizer.allowsPointer = (event) =>
                            _allowsPointer(event, size, drag: true);
                        recognizer.dragStartBehavior = DragStartBehavior.down;
                        recognizer.onStart = (_) => _acceptDrag(size);
                        recognizer.onEnd = (_) => _finish();
                        recognizer.onRejected = (pointer) =>
                            _rejectPointer(pointer, tap: false);
                      },
                    ),
              },
              child: Listener(
                onPointerDown: (event) => _down(event, size),
                onPointerMove: (event) => _move(event, size),
                onPointerCancel: (event) {
                  if (_pointer == event.pointer) _finish(cancel: true);
                },
                child: ExcludeSemantics(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: _focused
                          ? Border.all(
                              color: Theme.of(context).colorScheme.primary,
                              width: 2,
                            )
                          : null,
                    ),
                    child: SizedBox.fromSize(
                      size: size,
                      child: ThemeSwitchArtwork(
                        frame: _simulation.snapshot,
                        time: _time,
                        optics: widget.calibration.optics,
                        scene: widget.calibration.scene,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
}

/// Filter before joining the arena: canvas padding and secondary pointers must
/// not compete with the page's scrolling or start another thumb drag.
class _ThemeTapRecognizer extends TapGestureRecognizer {
  bool Function(PointerDownEvent)? allowsPointer;
  ValueChanged<int>? onRejected;

  @override
  bool isPointerAllowed(PointerDownEvent event) =>
      allowsPointer?.call(event) == true && super.isPointerAllowed(event);

  @override
  void rejectGesture(int pointer) {
    super.rejectGesture(pointer);
    // A fast scroll may reject a tap before its down deadline, in which case
    // onTapCancel is never called. Always release our captured raw pointer.
    onRejected?.call(pointer);
  }
}

class _ThemeDragRecognizer extends HorizontalDragGestureRecognizer {
  bool Function(PointerDownEvent)? allowsPointer;
  ValueChanged<int>? onRejected;

  @override
  bool isPointerAllowed(PointerEvent event) =>
      event is PointerDownEvent &&
      allowsPointer?.call(event) == true &&
      super.isPointerAllowed(event);

  @override
  void rejectGesture(int pointer) {
    super.rejectGesture(pointer);
    onRejected?.call(pointer);
  }
}

class _DarkIntent extends Intent {
  const _DarkIntent();
}

class _LightIntent extends Intent {
  const _LightIntent();
}

/// Explicit snapshots allow the same optical renderer to be sampled at exact
/// reference timestamps without advancing or settling an implicit animation.
class ThemeSwitchArtwork extends StatefulWidget {
  const ThemeSwitchArtwork({
    super.key,
    required this.frame,
    required this.time,
    this.program,
    this.scale,
    this.center,
    this.optics = const ThemeSwitchOptics(),
    this.scene = const ThemeSwitchScene(),
  });

  final ThemeSwitchSnapshot frame;
  final double time;
  final ui.FragmentProgram? program;
  final double? scale;
  final Offset? center;
  final ThemeSwitchOptics optics;
  final ThemeSwitchScene scene;

  static Future<ui.FragmentProgram>? _program;
  static Future<ui.FragmentProgram> loadProgram() => _program ??=
      ui.FragmentProgram.fromAsset('shaders/glass_theme_switch.frag');
  static double sceneScale(
    Size size, [
    ThemeSwitchScene scene = const ThemeSwitchScene(),
  ]) => size.width * scene.scale / 720;
  static Offset sceneOrigin(
    Size size, [
    ThemeSwitchScene scene = const ThemeSwitchScene(),
  ]) => Offset(
    size.width / 2 + size.width * scene.offsetX / 720,
    size.height / 2 + size.width * scene.offsetY / 720,
  );

  @override
  State<ThemeSwitchArtwork> createState() => _ThemeSwitchArtworkState();
}

class _ThemeSwitchArtworkState extends State<ThemeSwitchArtwork> {
  ui.FragmentShader? _shader;
  ui.Image? _matrix;
  ui.Image? _diffuse;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _makeTextures();
    if (widget.program case final program?) {
      _shader = program.fragmentShader();
    } else {
      ThemeSwitchArtwork.loadProgram().then(
        (program) {
          if (!mounted) return;
          setState(() => _shader = program.fragmentShader());
        },
        onError: (Object error) {
          if (mounted) setState(() => _error = error);
        },
      );
    }
  }

  @override
  void didUpdateWidget(covariant ThemeSwitchArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    _makeTextures();
  }

  void _makeTextures() {
    final previous = [_matrix, _diffuse];
    ui.Image render(double ratio, {bool blur = false}) {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder)..scale(ratio);
      if (blur) {
        canvas.saveLayer(
          const Rect.fromLTWH(0, 0, 552, 344),
          Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: 4, sigmaY: 4),
        );
      }
      if (blur) {
        final sharp = _matrix!;
        canvas.drawImageRect(
          sharp,
          Rect.fromLTWH(0, 0, sharp.width.toDouble(), sharp.height.toDouble()),
          const Rect.fromLTWH(0, 0, 552, 344),
          Paint()..filterQuality = FilterQuality.low,
        );
      } else {
        for (final particle in widget.frame.particles) {
          if (particle.alpha <= 0.002) continue;
          canvas.drawRect(
            Rect.fromCenter(
              center: Offset(276 + particle.x, 172 + particle.y),
              width: particle.size,
              height: particle.size,
            ),
            Paint()
              ..isAntiAlias = true
              ..color = Colors.white.withValues(
                alpha: particle.alpha.clamp(0, 1),
              ),
          );
        }
      }
      if (blur) canvas.restore();
      final picture = recorder.endRecording();
      final image = picture.toImageSync(
        (552 * ratio).round(),
        (344 * ratio).round(),
      );
      picture.dispose();
      return image;
    }

    _matrix = render(2);
    _diffuse = render(1, blur: true);
    SchedulerBinding.instance.addPostFrameCallback((_) {
      for (final image in previous) {
        image?.dispose();
      }
    });
  }

  @override
  void dispose() {
    _shader?.dispose();
    _matrix?.dispose();
    _diffuse?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Icon(
          widget.frame.theme > 0.5 ? Icons.light_mode : Icons.dark_mode,
        ),
      );
    }
    return CustomPaint(
      painter: _GlassPainter(
        shader: _shader,
        matrix: _matrix!,
        diffuse: _diffuse!,
        frame: widget.frame,
        time: widget.time,
        ratio: MediaQuery.devicePixelRatioOf(context),
        scale: widget.scale,
        center: widget.center,
        optics: widget.optics,
        scene: widget.scene,
      ),
    );
  }
}

class _GlassPainter extends CustomPainter {
  const _GlassPainter({
    required this.shader,
    required this.matrix,
    required this.diffuse,
    required this.frame,
    required this.time,
    required this.ratio,
    required this.scale,
    required this.center,
    required this.optics,
    required this.scene,
  });

  final ui.FragmentShader? shader;
  final ui.Image matrix;
  final ui.Image diffuse;
  final ThemeSwitchSnapshot frame;
  final double time;
  final double ratio;
  final double? scale;
  final Offset? center;
  final ThemeSwitchOptics optics;
  final ThemeSwitchScene scene;

  @override
  void paint(Canvas canvas, Size size) {
    final effect = shader;
    if (effect == null) return;
    final origin = center ?? ThemeSwitchArtwork.sceneOrigin(size, scene);
    final uniforms = [
      size.width,
      size.height,
      origin.dx,
      origin.dy,
      scale ?? ThemeSwitchArtwork.sceneScale(size, scene),
      ratio,
      frame.knobX,
      0.0,
      frame.halfWidth,
      frame.halfHeight,
      frame.radius,
      frame.theme,
      time,
      frame.led,
      frame.lift,
      frame.theta,
      _lampChannel(16),
      _lampChannel(8),
      _lampChannel(0),
      optics.refraction,
      optics.frost,
      optics.pixelGlow,
      optics.stripHalfAngle,
    ];
    for (var i = 0; i < uniforms.length; i++) {
      effect.setFloat(i, uniforms[i]);
    }
    effect.setImageSampler(0, matrix, filterQuality: FilterQuality.low);
    effect.setImageSampler(1, diffuse, filterQuality: FilterQuality.low);
    canvas.drawRect(Offset.zero & size, Paint()..shader = effect);
  }

  double _lampChannel(int shift) {
    final moon = (optics.moonRgb >> shift) & 0xff;
    final sun = (optics.sunRgb >> shift) & 0xff;
    return (moon + (sun - moon) * frame.theme) / 255;
  }

  @override
  bool shouldRepaint(covariant _GlassPainter oldDelegate) => true;
}
