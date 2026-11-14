import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'glass_design_tokens.dart';
import 'glass_glyph.dart';

/// A monotonic time source used by [GlassMotionScope].
///
/// Tests can inject [ManualGlassMotionClock] and sample the exact same motion
/// model at arbitrary refresh rates without relying on wall-clock timing.
abstract interface class GlassMotionClock implements Listenable {
  Duration get now;
}

/// A controllable clock for deterministic tests and frozen visual reviews.
class ManualGlassMotionClock extends ChangeNotifier
    implements GlassMotionClock {
  Duration _now = Duration.zero;

  @override
  Duration get now => _now;

  void advanceTo(Duration time) {
    if (time < _now) {
      throw ArgumentError.value(time, 'time', 'Clock time must be monotonic');
    }
    if (time == _now) return;
    _now = time;
    notifyListeners();
  }

  void advanceBy(Duration amount) {
    if (amount.isNegative) {
      throw ArgumentError.value(amount, 'amount', 'Cannot reverse time');
    }
    advanceTo(_now + amount);
  }
}

/// One shared clock for the decorative motion on a page or route.
///
/// Visible buttons share one ticker. Idle samples are coalesced to 30 Hz;
/// actions, morphs and hover/focus transitions use every available display
/// frame. The stopwatch continues while the ticker is muted, so a hidden page
/// resumes at its current phase instead of replaying missed frames.
class GlassMotionScope extends StatefulWidget {
  const GlassMotionScope({super.key, required this.child, this.clock});

  final Widget child;

  /// Optional external clock for deterministic tests. Production pages should
  /// leave this unset and use the shared monotonic Stopwatch.
  final GlassMotionClock? clock;

  static GlassMotionScopeState? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_GlassMotionScopeData>()
      ?.scope;

  @override
  State<GlassMotionScope> createState() => GlassMotionScopeState();
}

class GlassMotionScopeState extends State<GlassMotionScope>
    with SingleTickerProviderStateMixin {
  final Stopwatch _stopwatch = Stopwatch()..start();
  final Set<GlassMotionController> _clients = {};
  final Set<void Function(Size previous, Size current)>
  _visibilityViewportListeners = {};
  final Set<void Function()> _pendingSizeVisibilityChecks = {};
  Timer? _visibilityViewportTimer;
  Timer? _sizeVisibilityTimer;
  final Map<AxisDirection, double> _viewportDimensions = {};
  late final Ticker _ticker;
  AppLifecycleListener? _lifecycleListener;
  Duration _lastDelivery = Duration.zero;
  Duration? _frameTime;
  Size? _pendingViewportStart;
  Size? _pendingViewportEnd;
  bool _lastFrameNeededDisplayRate = false;
  bool _routeEnabled = true;
  bool _lifecycleEnabled = true;

  Duration get now => _frameTime ?? _readClock();

  Duration _readClock() => widget.clock?.now ?? _stopwatch.elapsed;

  @visibleForTesting
  int get registeredClientCountForTesting => _clients.length;

  void addVisibilityViewportListener(
    void Function(Size previous, Size current) listener,
  ) {
    _visibilityViewportListeners.add(listener);
  }

  void removeVisibilityViewportListener(
    void Function(Size previous, Size current) listener,
  ) {
    _visibilityViewportListeners.remove(listener);
  }

  void scheduleSizeVisibilityCheck(void Function() listener) {
    _pendingSizeVisibilityChecks.add(listener);
    _sizeVisibilityTimer ??= Timer(
      const Duration(milliseconds: 200),
      _dispatchSizeVisibilityChecks,
    );
  }

  void removeSizeVisibilityCheck(void Function() listener) {
    _pendingSizeVisibilityChecks.remove(listener);
  }

  bool get _canDeliver => _routeEnabled && _lifecycleEnabled;

  @override
  void initState() {
    super.initState();
    _frameTime = _readClock();
    _ticker = createTicker(_onTicker);
    if (widget.clock != null) widget.clock!.addListener(_onExternalTick);
    _lifecycleListener = AppLifecycleListener(
      onStateChange: _onLifecycleChanged,
    );
  }

  @override
  void didUpdateWidget(covariant GlassMotionScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.clock == widget.clock) return;
    oldWidget.clock?.removeListener(_onExternalTick);
    widget.clock?.addListener(_onExternalTick);
    _lastDelivery = Duration.zero;
    _deliverCurrentTime();
    _syncTicker();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final wasEnabled = _routeEnabled;
    _routeEnabled = TickerMode.valuesOf(context).enabled;
    if (!wasEnabled && _routeEnabled) _deliverCurrentTime();
  }

  bool _handleScrollMetricsChanged(ScrollMetricsNotification notification) {
    final direction = notification.metrics.axisDirection;
    final previous = _viewportDimensions[direction];
    final current = notification.metrics.viewportDimension;
    _viewportDimensions[direction] = current;
    if (previous != null && previous != current) {
      final vertical =
          direction == AxisDirection.up || direction == AxisDirection.down;
      _scheduleVisibilityViewportDispatch(
        vertical ? Size(0, previous) : Size(previous, 0),
        vertical ? Size(0, current) : Size(current, 0),
      );
    }
    return false;
  }

  void _scheduleVisibilityViewportDispatch(Size previous, Size current) {
    _pendingViewportStart ??= previous;
    _pendingViewportEnd = current;
    _visibilityViewportTimer ??= Timer(
      const Duration(milliseconds: 200),
      _dispatchVisibilityViewportChange,
    );
  }

  void _dispatchVisibilityViewportChange() {
    _visibilityViewportTimer = null;
    final previous = _pendingViewportStart;
    final current = _pendingViewportEnd;
    _pendingViewportStart = null;
    _pendingViewportEnd = null;
    if (!mounted ||
        previous == null ||
        current == null ||
        previous == current) {
      return;
    }
    for (final listener in List<void Function(Size, Size)>.of(
      _visibilityViewportListeners,
    )) {
      listener(previous, current);
    }
  }

  void _dispatchSizeVisibilityChecks() {
    _sizeVisibilityTimer = null;
    final checks = List<void Function()>.of(_pendingSizeVisibilityChecks);
    _pendingSizeVisibilityChecks.clear();
    for (final check in checks) {
      check();
    }
  }

  void _onLifecycleChanged(AppLifecycleState state) {
    final enabled = state == AppLifecycleState.resumed;
    if (_lifecycleEnabled == enabled) return;
    _lifecycleEnabled = enabled;
    if (enabled) _deliverCurrentTime();
    _syncTicker();
  }

  void _onTicker(Duration _) {
    final time = _readClock();
    final needsDisplayRate = _clients.any(
      (client) => client._needsDisplayRate(time),
    );
    if (!needsDisplayRate &&
        !_lastFrameNeededDisplayRate &&
        time - _lastDelivery < const Duration(milliseconds: 33)) {
      return;
    }
    _lastDelivery = time;
    _notifyClients(time);
  }

  void _onExternalTick() {
    if (!_canDeliver || _clients.isEmpty) return;
    final time = _readClock();
    _lastDelivery = time;
    _notifyClients(time);
  }

  void _deliverCurrentTime() {
    if (!_canDeliver || _clients.isEmpty) return;
    final time = _readClock();
    _lastDelivery = time;
    _notifyClients(time);
  }

  void _notifyClients(Duration time) {
    _frameTime = time;
    for (final client in List<GlassMotionController>.of(_clients)) {
      client._onClockTick(time);
    }
    _lastFrameNeededDisplayRate = _clients.any(
      (client) => client._needsDisplayRate(time),
    );
  }

  void _register(GlassMotionController client) {
    if (!_clients.add(client)) return;
    if (_canDeliver) client._onClockTick(_readClock());
    _lastFrameNeededDisplayRate = _clients.any(
      (registered) => registered._needsDisplayRate(now),
    );
    _syncTicker();
  }

  void _unregister(GlassMotionController client) {
    if (!_clients.remove(client)) return;
    _lastFrameNeededDisplayRate = _clients.any(
      (registered) => registered._needsDisplayRate(now),
    );
    _syncTicker();
  }

  void _syncTicker() {
    if (widget.clock != null) return;
    final shouldRun = _clients.isNotEmpty && _lifecycleEnabled;
    if (shouldRun && !_ticker.isActive) {
      _lastDelivery = _readClock();
      _ticker.start();
    } else if (!shouldRun && _ticker.isActive) {
      _ticker.stop(canceled: false);
    }
  }

  @override
  Widget build(BuildContext context) => _GlassMotionScopeData(
    scope: this,
    child: NotificationListener<ScrollMetricsNotification>(
      onNotification: _handleScrollMetricsChanged,
      child: widget.child,
    ),
  );

  @override
  void dispose() {
    _visibilityViewportTimer?.cancel();
    _sizeVisibilityTimer?.cancel();
    widget.clock?.removeListener(_onExternalTick);
    _lifecycleListener?.dispose();
    _ticker.dispose();
    for (final client in List<GlassMotionController>.of(_clients)) {
      client._detachScope(this);
    }
    _clients.clear();
    _visibilityViewportListeners.clear();
    _pendingSizeVisibilityChecks.clear();
    super.dispose();
  }
}

class _GlassMotionScopeData extends InheritedWidget {
  const _GlassMotionScopeData({required this.scope, required super.child});

  final GlassMotionScopeState scope;

  @override
  bool updateShouldNotify(_GlassMotionScopeData oldWidget) =>
      scope != oldWidget.scope;
}

enum GlassMotionAction {
  play,
  pause,
  add,
  refresh,
  copy,
  save,
  search,
  open,
  stop,
  remove,
  connect,
  allowAccess,
  neutral,
}

extension GlassMotionActionDetails on GlassMotionAction {
  Duration get duration => switch (this) {
    GlassMotionAction.play => const Duration(milliseconds: 520),
    GlassMotionAction.pause => const Duration(milliseconds: 560),
    GlassMotionAction.add => const Duration(milliseconds: 540),
    GlassMotionAction.refresh => const Duration(milliseconds: 680),
    GlassMotionAction.copy => const Duration(milliseconds: 520),
    GlassMotionAction.save => const Duration(milliseconds: 580),
    GlassMotionAction.search => const Duration(milliseconds: 560),
    GlassMotionAction.open => const Duration(milliseconds: 560),
    GlassMotionAction.stop => const Duration(milliseconds: 480),
    GlassMotionAction.remove => const Duration(milliseconds: 640),
    GlassMotionAction.connect => const Duration(milliseconds: 560),
    GlassMotionAction.allowAccess => const Duration(milliseconds: 560),
    GlassMotionAction.neutral => const Duration(milliseconds: 520),
  };

  static GlassMotionAction forGlyph(GlassGlyph glyph) => switch (glyph) {
    GlassGlyph.play => GlassMotionAction.play,
    GlassGlyph.pause => GlassMotionAction.pause,
    GlassGlyph.plus || GlassGlyph.playlist => GlassMotionAction.add,
    GlassGlyph.refresh => GlassMotionAction.refresh,
    GlassGlyph.copy => GlassMotionAction.copy,
    GlassGlyph.save => GlassMotionAction.save,
    GlassGlyph.search => GlassMotionAction.search,
    GlassGlyph.externalLink || GlassGlyph.folder => GlassMotionAction.open,
    GlassGlyph.stop => GlassMotionAction.stop,
    GlassGlyph.trash || GlassGlyph.close => GlassMotionAction.remove,
    GlassGlyph.network || GlassGlyph.link => GlassMotionAction.connect,
    GlassGlyph.shield ||
    GlassGlyph.lock ||
    GlassGlyph.key => GlassMotionAction.allowAccess,
    _ => GlassMotionAction.neutral,
  };
}

@immutable
class GlassDotPose {
  const GlassDotPose({
    required this.position,
    required this.opacity,
    this.phase = 0,
  });

  final Offset position;
  final double opacity;
  final double phase;
}

@immutable
class GlassMotionSample {
  const GlassMotionSample({
    required this.dots,
    required this.action,
    required this.actionProgress,
    required this.energy,
    required this.isMorphing,
  });

  final List<GlassDotPose> dots;
  final GlassMotionAction action;
  final double actionProgress;
  final double energy;
  final bool isMorphing;
}

/// Per-button state sampled from the scope's single clock.
class GlassMotionController extends ChangeNotifier {
  GlassMotionController({required GlassGlyph initialGlyph, int? phaseSeed})
    : _glyph = initialGlyph,
      phaseSeed = phaseSeed ?? _allocatePhaseSeed();

  static int _nextPhaseSeed = 0;

  static int _allocatePhaseSeed() {
    _nextPhaseSeed += 37;
    return _nextPhaseSeed;
  }

  final int phaseSeed;
  GlassGlyph _glyph;
  GlassMotionScopeState? _scope;
  bool _visible = true;
  bool _motionAllowed = false;
  _ActionPulse? _posePulse;
  final List<_ActionPulse> _energyPulses = [];
  _GlyphMorph? _morph;
  Duration _interactionStart = Duration.zero;
  double _interactionFrom = 0;
  double _interactionTo = 0;

  GlassGlyph get glyph => _glyph;
  Duration get now => _scope?.now ?? Duration.zero;

  GlassMotionSample get sample => sampleAt(now);

  double get energy => math.max(_energyAt(now), _interactionAt(now));

  /// Pure, rate-independent sample used by tests and visual review tooling.
  GlassMotionSample sampleAt(Duration time) {
    final pulses = _energyAt(time);
    final action =
        _posePulse?.action ?? GlassMotionActionDetails.forGlyph(_glyph);
    final progress = _posePulse == null
        ? 0.0
        : _linearProgress(time, _posePulse!.start, _posePulse!.duration);
    final dots = _dotsAt(
      time,
      action: action,
      progress: progress,
      energy: pulses,
    );
    return GlassMotionSample(
      dots: List.unmodifiable(dots),
      action: action,
      actionProgress: _smootherstep(progress),
      energy: math.max(pulses, _interactionAt(time)),
      isMorphing:
          _morph != null &&
          _linearProgress(time, _morph!.start, _morph!.duration) < 1,
    );
  }

  void configure({
    required GlassMotionScopeState? scope,
    required bool visible,
    required bool motionAllowed,
  }) {
    final previousScope = _scope;
    final wasActive = _isRegistered;
    _scope = scope;
    _visible = visible;
    _motionAllowed = motionAllowed;
    if (!_motionAllowed) _clearDecorations();
    if (previousScope != null && previousScope != scope && wasActive) {
      previousScope._unregister(this);
    }
    _syncRegistration();
    if (_isRegistered) _scope!._deliverCurrentTime();
  }

  void setVisible(bool visible) {
    if (_visible == visible) return;
    _visible = visible;
    _syncRegistration();
    if (_isRegistered) _scope!._deliverCurrentTime();
  }

  void setMotionAllowed(bool allowed) {
    if (_motionAllowed == allowed) return;
    _motionAllowed = allowed;
    if (!allowed) _clearDecorations();
    _syncRegistration();
    if (_isRegistered) _scope!._deliverCurrentTime();
    notifyListeners();
  }

  void setInteraction({required bool hovered, required bool focused}) {
    if (!_motionAllowed) return;
    final target = focused ? .13 : (hovered ? .08 : 0.0);
    final time = now;
    final current = _interactionAt(time);
    if ((target - _interactionTo).abs() < .0001) return;
    _interactionStart = time;
    _interactionFrom = current;
    _interactionTo = target;
    _syncActivity(time);
    notifyListeners();
  }

  void setGlyph(GlassGlyph glyph) {
    if (_glyph == glyph) return;
    final time = now;
    final pulse = _posePulse;
    final progress = pulse == null
        ? 0.0
        : _linearProgress(time, pulse.start, pulse.duration);
    final energy = pulse == null ? 0.0 : _energyAt(time);
    final from = [
      for (final pose in _morphAt(time))
        GlassDotPose(
          position: pulse == null
              ? pose.position
              : _transformAction(pose.position, pulse.action, progress, energy),
          opacity: pose.opacity,
          phase: pose.phase,
        ),
    ];
    _glyph = glyph;
    _posePulse = null;
    _morph = _motionAllowed
        ? _GlyphMorph.create(
            from: from,
            to: _canonicalPoses(glyph),
            start: time,
          )
        : null;
    _syncActivity(time);
    notifyListeners();
  }

  /// Starts a decorative pulse. Callers must invoke the real operation
  /// independently; animation state never gates business work.
  void trigger() {
    if (!_isRegistered) return;
    final time = now;
    _expire(time);
    final action = GlassMotionActionDetails.forGlyph(_glyph);
    final duration = action.duration;
    _posePulse ??= _ActionPulse(
      action: action,
      start: time,
      duration: duration,
    );
    _energyPulses.add(
      _ActionPulse(action: action, start: time, duration: duration),
    );
    _syncActivity(time);
    notifyListeners();
  }

  void _syncRegistration() {
    final shouldRegister = _isRegistered;
    if (shouldRegister) {
      _scope!._register(this);
    } else {
      _scope?._unregister(this);
    }
  }

  bool get _isRegistered => _scope != null && _visible && _motionAllowed;

  void _onClockTick(Duration time) {
    if (!_isRegistered) return;
    _expire(time);
    _syncActivity(time);
    notifyListeners();
  }

  bool _needsDisplayRate(Duration time) =>
      _isRegistered && _hasActiveAnimation(time);

  bool _hasActiveAnimation(Duration time) {
    if (!_motionAllowed) return false;
    if (_energyPulses.any(
      (pulse) => _linearProgress(time, pulse.start, pulse.duration) < 1,
    )) {
      return true;
    }
    if (_posePulse != null &&
        _linearProgress(time, _posePulse!.start, _posePulse!.duration) < 1) {
      return true;
    }
    if (_morph != null &&
        _linearProgress(time, _morph!.start, _morph!.duration) < 1) {
      return true;
    }
    return (_interactionAt(time) - _interactionTo).abs() > .001;
  }

  void _syncActivity(Duration time) {
    // Activity is sampled by the shared scope. No per-button ticker is created.
    _expire(time);
  }

  void _expire(Duration time) {
    _energyPulses.removeWhere(
      (pulse) => _linearProgress(time, pulse.start, pulse.duration) >= 1,
    );
    if (_posePulse != null &&
        _energyPulses.isEmpty &&
        _linearProgress(time, _posePulse!.start, _posePulse!.duration) >= 1) {
      _posePulse = null;
    }
    if (_morph != null &&
        _linearProgress(time, _morph!.start, _morph!.duration) >= 1) {
      _morph = null;
    }
  }

  double _energyAt(Duration time) {
    var energy = 0.0;
    for (final pulse in _energyPulses) {
      final t = _linearProgress(time, pulse.start, pulse.duration);
      if (t >= 1) continue;
      final sine = math.sin(math.pi * t);
      energy = math.max(energy, sine * sine);
    }
    return energy;
  }

  double _interactionAt(Duration time) {
    if (!_motionAllowed) return 0;
    final t = _linearProgress(
      time,
      _interactionStart,
      const Duration(milliseconds: 320),
    );
    if (t >= 1) return _interactionTo;
    return _interactionFrom +
        (_interactionTo - _interactionFrom) * _smootherstep(t);
  }

  List<GlassDotPose> _dotsAt(
    Duration time, {
    required GlassMotionAction action,
    required double progress,
    required double energy,
    bool applyAction = true,
  }) {
    final morphed = _morphAt(time);
    final idlePhase = time.inMicroseconds / 1000000;
    final actionEnergy = applyAction && _posePulse != null ? energy : 0.0;
    return [
      for (var index = 0; index < morphed.length; index++)
        _poseDot(
          morphed[index],
          phase: idlePhase,
          energy: energy,
          actionEnergy: actionEnergy,
          action: action,
          progress: progress,
          rotationActive:
              action == GlassMotionAction.refresh &&
              _posePulse != null &&
              applyAction,
        ),
    ];
  }

  List<GlassDotPose> _morphAt(Duration time) {
    final morph = _morph;
    if (morph == null) return _canonicalOrIdleBase();
    final t = _smootherstep(_linearProgress(time, morph.start, morph.duration));
    return [
      for (final tween in morph.tweens)
        GlassDotPose(
          position: Offset.lerp(tween.from.position, tween.to.position, t)!,
          opacity:
              tween.from.opacity + (tween.to.opacity - tween.from.opacity) * t,
          phase: tween.from.phase + (tween.to.phase - tween.from.phase) * t,
        ),
    ];
  }

  List<GlassDotPose> _canonicalOrIdleBase() => _canonicalPoses(_glyph);

  GlassDotPose _poseDot(
    GlassDotPose source, {
    required double phase,
    required double energy,
    required double actionEnergy,
    required GlassMotionAction action,
    required double progress,
    required bool rotationActive,
  }) {
    final wave = phase * (math.pi * 2 / 5.8) + phaseSeed * .37 + source.phase;
    final idleAlpha = _motionAllowed ? .90 + .06 * math.sin(wave) : 1.0;
    final idleOffset = _motionAllowed
        ? Offset(math.sin(wave) * .16, math.cos(wave * .83) * .13)
        : Offset.zero;
    final position =
        _transformAction(
          source.position,
          action,
          rotationActive ? progress : 0,
          actionEnergy,
        ) +
        idleOffset;

    final detailEnergy = switch (action) {
      GlassMotionAction.pause =>
        .08 *
            actionEnergy *
            math.cos(
              progress * math.pi * 2 + (source.position.dx < 16 ? math.pi : 0),
            ),
      GlassMotionAction.refresh =>
        .08 *
            actionEnergy *
            math.max(
              0,
              math.cos(
                math.atan2(source.position.dy - 16, source.position.dx - 16) -
                    2 * math.pi * _smootherstep(progress),
              ),
            ),
      GlassMotionAction.search => _scanEnergy(
        source.position.dx,
        progress,
        actionEnergy,
      ),
      GlassMotionAction.save => _scanEnergy(
        source.position.dy,
        progress,
        actionEnergy,
      ),
      GlassMotionAction.connect =>
        .09 *
            actionEnergy *
            math.max(0, math.cos(source.phase - progress * math.pi * 2)),
      _ => 0.0,
    };
    final brightness = 1 + energy * .06 + detailEnergy;
    return GlassDotPose(
      position: position,
      opacity: (source.opacity * idleAlpha * brightness).clamp(0.0, 1.0),
      phase: source.phase,
    );
  }

  Offset _transformAction(
    Offset source,
    GlassMotionAction action,
    double progress,
    double energy,
  ) {
    if (action == GlassMotionAction.refresh && progress > 0) {
      final angle = 2 * math.pi * _smootherstep(progress);
      final cosine = math.cos(angle);
      final sine = math.sin(angle);
      final relative = source - const Offset(16, 16);
      return const Offset(16, 16) +
          Offset(
            relative.dx * cosine - relative.dy * sine,
            relative.dx * sine + relative.dy * cosine,
          );
    }
    if (energy <= 0) return source;
    final relative = source - const Offset(16, 16);
    return switch (action) {
      GlassMotionAction.play =>
        source + Offset(.40 * GlassDesignTokens.glyphPitch * energy, 0),
      GlassMotionAction.pause =>
        const Offset(16, 16) +
            Offset(relative.dx * (1 - .035 * energy), relative.dy),
      GlassMotionAction.add =>
        const Offset(16, 16) + relative * (1 - .15 * energy),
      GlassMotionAction.refresh => source,
      GlassMotionAction.copy =>
        source +
            Offset(
              relative.dx.sign * .23 * GlassDesignTokens.glyphPitch * energy,
              relative.dy.sign * .23 * GlassDesignTokens.glyphPitch * energy,
            ),
      GlassMotionAction.save =>
        source + Offset(0, .55 * GlassDesignTokens.glyphCellSize * energy),
      GlassMotionAction.search =>
        const Offset(16, 16) + relative * (1 + .045 * energy),
      GlassMotionAction.open =>
        source + Offset(0, -.42 * GlassDesignTokens.glyphPitch * energy),
      GlassMotionAction.stop =>
        const Offset(16, 16) + Offset(relative.dx * .86, relative.dy),
      GlassMotionAction.remove =>
        const Offset(16, 16) +
            relative * (1 - .12 * energy) +
            Offset(0, .28 * GlassDesignTokens.glyphPitch * energy),
      GlassMotionAction.connect =>
        const Offset(16, 16) + relative * (1 - .055 * energy),
      GlassMotionAction.allowAccess =>
        const Offset(16, 16) + relative * (1 + .035 * energy),
      GlassMotionAction.neutral => source,
    };
  }

  double _scanEnergy(double coordinate, double progress, double energy) {
    final center = 4 + 24 * _smootherstep(progress);
    final distance = (coordinate - center) / 3.2;
    return .12 * energy * math.exp(-distance * distance);
  }

  void _clearDecorations() {
    _posePulse = null;
    _energyPulses.clear();
    _morph = null;
    _interactionFrom = 0;
    _interactionTo = 0;
    _interactionStart = now;
  }

  void _detachScope(GlassMotionScopeState scope) {
    if (_scope != scope) return;
    _scope = null;
    _clearDecorations();
    notifyListeners();
  }

  @override
  void dispose() {
    _scope?._unregister(this);
    super.dispose();
  }
}

class _ActionPulse {
  const _ActionPulse({
    required this.action,
    required this.start,
    required this.duration,
  });

  final GlassMotionAction action;
  final Duration start;
  final Duration duration;
}

class _PoseTween {
  const _PoseTween(this.from, this.to);

  final GlassDotPose from;
  final GlassDotPose to;
}

class _GlyphMorph {
  const _GlyphMorph({
    required this.tweens,
    required this.start,
    required this.duration,
  });

  final List<_PoseTween> tweens;
  final Duration start;
  final Duration duration;

  static _GlyphMorph create({
    required List<GlassDotPose> from,
    required List<GlassDotPose> to,
    required Duration start,
  }) {
    final unmatchedFrom = <int>{for (var i = 0; i < from.length; i++) i};
    final unmatchedTo = <int>{for (var i = 0; i < to.length; i++) i};
    final candidates = <(double, int, int)>[];
    for (var i = 0; i < from.length; i++) {
      for (var j = 0; j < to.length; j++) {
        candidates.add((
          (from[i].position - to[j].position).distanceSquared,
          i,
          j,
        ));
      }
    }
    candidates.sort((left, right) => left.$1.compareTo(right.$1));
    final tweens = <_PoseTween>[];
    for (final (_, fromIndex, toIndex) in candidates) {
      if (!unmatchedFrom.contains(fromIndex) ||
          !unmatchedTo.contains(toIndex)) {
        continue;
      }
      unmatchedFrom.remove(fromIndex);
      unmatchedTo.remove(toIndex);
      tweens.add(
        _PoseTween(
          from[fromIndex],
          GlassDotPose(
            position: to[toIndex].position,
            opacity: 1,
            phase: to[toIndex].phase,
          ),
        ),
      );
    }
    for (final index in unmatchedFrom) {
      tweens.add(_PoseTween(from[index], from[index].copyWith(opacity: 0)));
    }
    for (final index in unmatchedTo) {
      tweens.add(
        _PoseTween(
          GlassDotPose(
            position: to[index].position,
            opacity: 0,
            phase: to[index].phase,
          ),
          GlassDotPose(
            position: to[index].position,
            opacity: 1,
            phase: to[index].phase,
          ),
        ),
      );
    }
    return _GlyphMorph(
      tweens: List.unmodifiable(tweens),
      start: start,
      duration: const Duration(milliseconds: 360),
    );
  }
}

extension on GlassDotPose {
  GlassDotPose copyWith({Offset? position, double? opacity}) => GlassDotPose(
    position: position ?? this.position,
    opacity: opacity ?? this.opacity,
    phase: phase,
  );
}

List<GlassDotPose> _canonicalPoses(GlassGlyph glyph) {
  final points = GlassGlyphFactory.pointsFor(glyph);
  return [
    for (var index = 0; index < points.length; index++)
      GlassDotPose(position: points[index], opacity: 1, phase: index * .71),
  ];
}

double _linearProgress(Duration time, Duration start, Duration duration) {
  if (duration.inMicroseconds <= 0) return 1;
  return ((time.inMicroseconds - start.inMicroseconds) /
          duration.inMicroseconds)
      .clamp(0.0, 1.0);
}

double _smootherstep(double value) {
  final t = value.clamp(0.0, 1.0);
  return t * t * t * (t * (t * 6 - 15) + 10);
}
