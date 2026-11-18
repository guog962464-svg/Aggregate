import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'glass_design_tokens.dart';
import 'glass_glyph.dart';

const _glyphMorphDuration = Duration(milliseconds: 360);

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
  next,
  previous,
  add,
  stop,
  copy,
  paste,
  save,
  logout,
  terminal,
  check,
  close,
  search,
  refresh,
  music,
  grid,
  more,
  connect,
  activity,
  settings,
  link,
  remove,
  export,
  allowAccess,
  list,
  folder,
  star,
  arrow,
  arrowBack,
  arrowUp,
  arrowDown,
  filter,
  brightness,
  build,
  chat,
  device,
  phone,
  lock,
  document,
  account,
  desktop,
  open,
  hourglass,
  inbox,
  history,
  info,
  error,
  key,
  qr,
  code,
  tune,
  visibility,
  flash,
  chevron,
  playlist,
  data,
  expand,
  collapse,
  appearance,
  neutral,
}

enum _GlassIdlePattern {
  forwardSweep,
  reverseSweep,
  verticalSweep,
  reverseVerticalSweep,
  diagonal,
  reverseDiagonal,
  radial,
  ring,
  rows,
  columns,
  sourcePhase,
  checker,
  centerPulse,
  orbit,
}

enum _GlassLightPattern {
  none,
  scanX,
  reverseScanX,
  scanY,
  reverseScanY,
  scanDiagonal,
  radialSweep,
  rows,
  columns,
  pointPhase,
  centerPulse,
  rimSweep,
}

@immutable
class _GlassMotionProfile {
  const _GlassMotionProfile({
    required this.duration,
    required this.idle,
    required this.light,
    this.translation = Offset.zero,
    this.scaleX = 0,
    this.scaleY = 0,
    this.rotationRadians = 0,
    this.rotationFollowsProgress = false,
    this.separation = 0,
    this.idleDrift = const Offset(.05, .04),
    this.idleOpacity = .014,
    this.lightAmplitude = .08,
  });

  final Duration duration;
  final _GlassIdlePattern idle;
  final _GlassLightPattern light;
  final Offset translation;
  final double scaleX;
  final double scaleY;
  final double rotationRadians;
  final bool rotationFollowsProgress;
  final double separation;
  final Offset idleDrift;
  final double idleOpacity;
  final double lightAmplitude;

  _GlassIdleMotion get idleMotion {
    final (spatial, radial, angular, point, phaseOffset) = switch (idle) {
      _GlassIdlePattern.forwardSweep => (
        const Offset(.14, 0),
        0.0,
        0.0,
        0.0,
        0.0,
      ),
      _GlassIdlePattern.reverseSweep => (
        const Offset(-.14, 0),
        0.0,
        0.0,
        0.0,
        0.0,
      ),
      _GlassIdlePattern.verticalSweep => (
        const Offset(0, .14),
        0.0,
        0.0,
        0.0,
        0.0,
      ),
      _GlassIdlePattern.reverseVerticalSweep => (
        const Offset(0, -.14),
        0.0,
        0.0,
        0.0,
        0.0,
      ),
      _GlassIdlePattern.diagonal => (
        const Offset(.10, .10),
        0.0,
        0.0,
        0.0,
        0.0,
      ),
      _GlassIdlePattern.reverseDiagonal => (
        const Offset(.10, -.10),
        0.0,
        0.0,
        0.0,
        0.0,
      ),
      _GlassIdlePattern.radial => (Offset.zero, .16, 0.0, 0.0, 0.0),
      _GlassIdlePattern.ring => (Offset.zero, -.22, 0.0, 0.0, 1.98),
      _GlassIdlePattern.rows => (const Offset(0, .24), 0.0, 0.0, 0.0, 0.0),
      _GlassIdlePattern.columns => (const Offset(.24, 0), 0.0, 0.0, 0.0, 0.0),
      _GlassIdlePattern.sourcePhase => (Offset.zero, 0.0, 0.0, 1.0, 0.0),
      _GlassIdlePattern.checker => (const Offset(.20, .20), 0.0, 0.0, 0.5, 0.0),
      _GlassIdlePattern.centerPulse => (Offset.zero, -.18, 0.0, 0.0, 0.0),
      _GlassIdlePattern.orbit => (Offset.zero, 0.0, 1.3, 0.0, 0.0),
    };
    return _GlassIdleMotion(
      spatial: spatial,
      radial: radial,
      angular: angular,
      point: point,
      phaseOffset: phaseOffset,
      drift: idleDrift,
      opacityAmplitude: idleOpacity,
    );
  }
}

@immutable
class _GlassIdleMotion {
  const _GlassIdleMotion({
    this.spatial = Offset.zero,
    this.radial = 0,
    this.angular = 0,
    this.point = 0,
    this.phaseOffset = 0,
    this.drift = Offset.zero,
    this.opacityAmplitude = 0,
  });

  final Offset spatial;
  final double radial;
  final double angular;
  final double point;
  final double phaseOffset;
  final Offset drift;
  final double opacityAmplitude;

  static _GlassIdleMotion lerp(
    _GlassIdleMotion from,
    _GlassIdleMotion to,
    double t,
  ) => _GlassIdleMotion(
    spatial: Offset.lerp(from.spatial, to.spatial, t)!,
    radial: from.radial + (to.radial - from.radial) * t,
    angular: from.angular + (to.angular - from.angular) * t,
    point: from.point + (to.point - from.point) * t,
    phaseOffset: from.phaseOffset + (to.phaseOffset - from.phaseOffset) * t,
    drift: Offset.lerp(from.drift, to.drift, t)!,
    opacityAmplitude:
        from.opacityAmplitude +
        (to.opacityAmplitude - from.opacityAmplitude) * t,
  );

  double signal(Offset position, double wave, double pointPhase) {
    final relative = position - const Offset(16, 16);
    var phase =
        wave +
        phaseOffset +
        relative.dx * spatial.dx +
        relative.dy * spatial.dy;
    if (radial != 0) phase += relative.distance * radial;
    if (angular != 0) {
      phase += math.atan2(relative.dy, relative.dx) * angular;
    }
    if (point != 0) phase += pointPhase * point;
    return math.sin(phase);
  }
}

const _glassMotionProfiles = <GlassMotionAction, _GlassMotionProfile>{
  GlassMotionAction.play: _GlassMotionProfile(
    duration: Duration(milliseconds: 520),
    idle: _GlassIdlePattern.forwardSweep,
    light: _GlassLightPattern.scanX,
    translation: Offset(1.3, 0),
    scaleX: .08,
    lightAmplitude: .16,
    idleDrift: Offset(.09, 0),
  ),
  GlassMotionAction.pause: _GlassMotionProfile(
    duration: Duration(milliseconds: 560),
    idle: _GlassIdlePattern.columns,
    light: _GlassLightPattern.columns,
    scaleX: -.035,
    idleDrift: Offset(.04, .07),
  ),
  GlassMotionAction.next: _GlassMotionProfile(
    duration: Duration(milliseconds: 480),
    idle: _GlassIdlePattern.forwardSweep,
    light: _GlassLightPattern.scanX,
    translation: Offset(.32, 0),
    scaleX: .015,
    idleDrift: Offset(.08, .02),
  ),
  GlassMotionAction.previous: _GlassMotionProfile(
    duration: Duration(milliseconds: 500),
    idle: _GlassIdlePattern.reverseSweep,
    light: _GlassLightPattern.reverseScanX,
    translation: Offset(-.32, 0),
    scaleX: .012,
    idleDrift: Offset(-.08, .02),
  ),
  GlassMotionAction.add: _GlassMotionProfile(
    duration: Duration(milliseconds: 540),
    idle: _GlassIdlePattern.centerPulse,
    light: _GlassLightPattern.centerPulse,
    scaleX: -.15,
    scaleY: -.15,
    idleDrift: Offset(.03, .03),
  ),
  GlassMotionAction.stop: _GlassMotionProfile(
    duration: Duration(milliseconds: 480),
    idle: _GlassIdlePattern.sourcePhase,
    light: _GlassLightPattern.pointPhase,
    scaleX: -.14,
    scaleY: -.02,
    idleDrift: Offset(.02, .07),
  ),
  GlassMotionAction.copy: _GlassMotionProfile(
    duration: Duration(milliseconds: 520),
    idle: _GlassIdlePattern.diagonal,
    light: _GlassLightPattern.scanDiagonal,
    separation: .23,
    idleDrift: Offset(.07, .06),
  ),
  GlassMotionAction.paste: _GlassMotionProfile(
    duration: Duration(milliseconds: 540),
    idle: _GlassIdlePattern.reverseVerticalSweep,
    light: _GlassLightPattern.reverseScanY,
    translation: Offset(.04, .16),
    scaleX: -.025,
    scaleY: -.055,
    idleDrift: Offset(.03, -.07),
  ),
  GlassMotionAction.save: _GlassMotionProfile(
    duration: Duration(milliseconds: 580),
    idle: _GlassIdlePattern.verticalSweep,
    light: _GlassLightPattern.scanY,
    translation: Offset(0, .39),
    idleDrift: Offset(.02, .08),
  ),
  GlassMotionAction.logout: _GlassMotionProfile(
    duration: Duration(milliseconds: 560),
    idle: _GlassIdlePattern.forwardSweep,
    light: _GlassLightPattern.scanX,
    translation: Offset(.58, 0),
    scaleX: .02,
    idleDrift: Offset(.10, -.02),
  ),
  GlassMotionAction.terminal: _GlassMotionProfile(
    duration: Duration(milliseconds: 500),
    idle: _GlassIdlePattern.columns,
    light: _GlassLightPattern.scanX,
    translation: Offset(.08, 0),
    scaleX: .025,
    idleDrift: Offset(.03, .05),
  ),
  GlassMotionAction.check: _GlassMotionProfile(
    duration: Duration(milliseconds: 420),
    idle: _GlassIdlePattern.diagonal,
    light: _GlassLightPattern.scanDiagonal,
    translation: Offset(.10, -.04),
    scaleX: .035,
    scaleY: .035,
    idleDrift: Offset(.04, -.04),
  ),
  GlassMotionAction.close: _GlassMotionProfile(
    duration: Duration(milliseconds: 460),
    idle: _GlassIdlePattern.checker,
    light: _GlassLightPattern.centerPulse,
    scaleX: -.11,
    scaleY: -.06,
    rotationRadians: .08,
    idleDrift: Offset(-.05, .04),
  ),
  GlassMotionAction.search: _GlassMotionProfile(
    duration: Duration(milliseconds: 560),
    idle: _GlassIdlePattern.radial,
    light: _GlassLightPattern.scanX,
    scaleX: .11,
    scaleY: .11,
    lightAmplitude: .18,
    idleDrift: Offset(.04, .02),
  ),
  GlassMotionAction.refresh: _GlassMotionProfile(
    duration: Duration(milliseconds: 680),
    idle: _GlassIdlePattern.orbit,
    light: _GlassLightPattern.radialSweep,
    rotationRadians: math.pi * 2,
    rotationFollowsProgress: true,
    lightAmplitude: .14,
    idleDrift: Offset(.04, -.04),
  ),
  GlassMotionAction.music: _GlassMotionProfile(
    duration: Duration(milliseconds: 540),
    idle: _GlassIdlePattern.verticalSweep,
    light: _GlassLightPattern.rows,
    scaleY: .065,
    rotationRadians: .035,
    idleDrift: Offset(.06, .08),
  ),
  GlassMotionAction.grid: _GlassMotionProfile(
    duration: Duration(milliseconds: 540),
    idle: _GlassIdlePattern.checker,
    light: _GlassLightPattern.rows,
    scaleX: .035,
    scaleY: .025,
    idleDrift: Offset(.06, -.03),
  ),
  GlassMotionAction.more: _GlassMotionProfile(
    duration: Duration(milliseconds: 520),
    idle: _GlassIdlePattern.columns,
    light: _GlassLightPattern.pointPhase,
    scaleX: .12,
    scaleY: .12,
    idleDrift: Offset(.04, .06),
  ),
  GlassMotionAction.connect: _GlassMotionProfile(
    duration: Duration(milliseconds: 560),
    idle: _GlassIdlePattern.sourcePhase,
    light: _GlassLightPattern.pointPhase,
    scaleX: -.055,
    scaleY: -.055,
    lightAmplitude: .09,
    idleDrift: Offset(.08, -.04),
  ),
  GlassMotionAction.activity: _GlassMotionProfile(
    duration: Duration(milliseconds: 520),
    idle: _GlassIdlePattern.rows,
    light: _GlassLightPattern.rows,
    scaleY: .075,
    translation: Offset(.03, 0),
    idleDrift: Offset(.08, .04),
  ),
  GlassMotionAction.settings: _GlassMotionProfile(
    duration: Duration(milliseconds: 640),
    idle: _GlassIdlePattern.orbit,
    light: _GlassLightPattern.rimSweep,
    rotationRadians: .18,
    idleDrift: Offset(.05, -.05),
  ),
  GlassMotionAction.link: _GlassMotionProfile(
    duration: Duration(milliseconds: 520),
    idle: _GlassIdlePattern.diagonal,
    light: _GlassLightPattern.scanDiagonal,
    scaleX: -.045,
    scaleY: -.02,
    translation: Offset(.05, 0),
    idleDrift: Offset(.06, -.06),
  ),
  GlassMotionAction.remove: _GlassMotionProfile(
    duration: Duration(milliseconds: 640),
    idle: _GlassIdlePattern.ring,
    light: _GlassLightPattern.rimSweep,
    scaleX: -.12,
    scaleY: -.12,
    translation: Offset(0, .28),
    idleDrift: Offset(.03, .07),
  ),
  GlassMotionAction.export: _GlassMotionProfile(
    duration: Duration(milliseconds: 560),
    idle: _GlassIdlePattern.verticalSweep,
    light: _GlassLightPattern.reverseScanY,
    translation: Offset(.02, -.36),
    scaleY: .025,
    idleDrift: Offset(.02, -.08),
  ),
  GlassMotionAction.allowAccess: _GlassMotionProfile(
    duration: Duration(milliseconds: 560),
    idle: _GlassIdlePattern.ring,
    light: _GlassLightPattern.rimSweep,
    scaleX: .035,
    scaleY: .035,
    idleDrift: Offset(.04, .05),
  ),
  GlassMotionAction.list: _GlassMotionProfile(
    duration: Duration(milliseconds: 500),
    idle: _GlassIdlePattern.rows,
    light: _GlassLightPattern.rows,
    translation: Offset(.06, .01),
    scaleY: .02,
    idleDrift: Offset(.08, .03),
  ),
  GlassMotionAction.folder: _GlassMotionProfile(
    duration: Duration(milliseconds: 560),
    idle: _GlassIdlePattern.reverseVerticalSweep,
    light: _GlassLightPattern.scanY,
    translation: Offset(.02, -.42),
    scaleY: .035,
    idleDrift: Offset(.02, .07),
  ),
  GlassMotionAction.star: _GlassMotionProfile(
    duration: Duration(milliseconds: 560),
    idle: _GlassIdlePattern.orbit,
    light: _GlassLightPattern.centerPulse,
    scaleX: .09,
    scaleY: .09,
    rotationRadians: .12,
    idleDrift: Offset(.07, .05),
  ),
  GlassMotionAction.arrow: _GlassMotionProfile(
    duration: Duration(milliseconds: 460),
    idle: _GlassIdlePattern.forwardSweep,
    light: _GlassLightPattern.scanX,
    translation: Offset(.28, 0),
    idleDrift: Offset(.06, .02),
  ),
  GlassMotionAction.arrowBack: _GlassMotionProfile(
    duration: Duration(milliseconds: 460),
    idle: _GlassIdlePattern.reverseSweep,
    light: _GlassLightPattern.reverseScanX,
    translation: Offset(-.28, 0),
    idleDrift: Offset(-.06, .02),
  ),
  GlassMotionAction.arrowUp: _GlassMotionProfile(
    duration: Duration(milliseconds: 460),
    idle: _GlassIdlePattern.reverseVerticalSweep,
    light: _GlassLightPattern.reverseScanY,
    translation: Offset(0, -.28),
    idleDrift: Offset(.02, -.06),
  ),
  GlassMotionAction.arrowDown: _GlassMotionProfile(
    duration: Duration(milliseconds: 460),
    idle: _GlassIdlePattern.verticalSweep,
    light: _GlassLightPattern.scanY,
    translation: Offset(0, .28),
    idleDrift: Offset(.02, .06),
  ),
  GlassMotionAction.filter: _GlassMotionProfile(
    duration: Duration(milliseconds: 540),
    idle: _GlassIdlePattern.verticalSweep,
    light: _GlassLightPattern.scanY,
    scaleY: -.035,
    rotationRadians: .03,
    idleDrift: Offset(-.04, .07),
  ),
  GlassMotionAction.brightness: _GlassMotionProfile(
    duration: Duration(milliseconds: 520),
    idle: _GlassIdlePattern.centerPulse,
    light: _GlassLightPattern.centerPulse,
    scaleX: .055,
    scaleY: .055,
    idleOpacity: .018,
    idleDrift: Offset(.04, .02),
  ),
  GlassMotionAction.build: _GlassMotionProfile(
    duration: Duration(milliseconds: 600),
    idle: _GlassIdlePattern.orbit,
    light: _GlassLightPattern.radialSweep,
    rotationRadians: .22,
    scaleX: .018,
    idleDrift: Offset(-.04, -.04),
  ),
  GlassMotionAction.chat: _GlassMotionProfile(
    duration: Duration(milliseconds: 540),
    idle: _GlassIdlePattern.diagonal,
    light: _GlassLightPattern.centerPulse,
    scaleX: .045,
    scaleY: .06,
    translation: Offset(0, -.035),
    idleDrift: Offset(.03, -.06),
  ),
  GlassMotionAction.device: _GlassMotionProfile(
    duration: Duration(milliseconds: 560),
    idle: _GlassIdlePattern.ring,
    light: _GlassLightPattern.rimSweep,
    scaleX: .035,
    scaleY: .02,
    rotationRadians: .035,
    idleDrift: Offset(.07, -.03),
  ),
  GlassMotionAction.phone: _GlassMotionProfile(
    duration: Duration(milliseconds: 520),
    idle: _GlassIdlePattern.verticalSweep,
    light: _GlassLightPattern.columns,
    scaleX: -.02,
    scaleY: .045,
    rotationRadians: .045,
    idleDrift: Offset(.03, .08),
  ),
  GlassMotionAction.lock: _GlassMotionProfile(
    duration: Duration(milliseconds: 520),
    idle: _GlassIdlePattern.ring,
    light: _GlassLightPattern.rimSweep,
    rotationRadians: .14,
    scaleX: .025,
    idleDrift: Offset(-.04, .05),
  ),
  GlassMotionAction.document: _GlassMotionProfile(
    duration: Duration(milliseconds: 560),
    idle: _GlassIdlePattern.verticalSweep,
    light: _GlassLightPattern.scanY,
    translation: Offset(.01, -.26),
    scaleY: .025,
    idleDrift: Offset(.04, .08),
  ),
  GlassMotionAction.account: _GlassMotionProfile(
    duration: Duration(milliseconds: 580),
    idle: _GlassIdlePattern.orbit,
    light: _GlassLightPattern.radialSweep,
    rotationRadians: .11,
    scaleX: .035,
    scaleY: .035,
    idleDrift: Offset(.08, .01),
  ),
  GlassMotionAction.desktop: _GlassMotionProfile(
    duration: Duration(milliseconds: 560),
    idle: _GlassIdlePattern.rows,
    light: _GlassLightPattern.rows,
    scaleX: .035,
    scaleY: .018,
    translation: Offset(0, -.025),
    idleDrift: Offset(.07, .03),
  ),
  GlassMotionAction.open: _GlassMotionProfile(
    duration: Duration(milliseconds: 560),
    idle: _GlassIdlePattern.forwardSweep,
    light: _GlassLightPattern.reverseScanY,
    translation: Offset(0, -.42),
    scaleX: .025,
    idleDrift: Offset(.03, -.07),
  ),
  GlassMotionAction.hourglass: _GlassMotionProfile(
    duration: Duration(milliseconds: 640),
    idle: _GlassIdlePattern.rows,
    light: _GlassLightPattern.rows,
    scaleX: -.025,
    scaleY: .04,
    translation: Offset(0, .035),
    idleDrift: Offset(.02, .06),
  ),
  GlassMotionAction.inbox: _GlassMotionProfile(
    duration: Duration(milliseconds: 540),
    idle: _GlassIdlePattern.verticalSweep,
    light: _GlassLightPattern.reverseScanY,
    translation: Offset(0, .22),
    scaleY: -.025,
    idleDrift: Offset(.02, .07),
  ),
  GlassMotionAction.history: _GlassMotionProfile(
    duration: Duration(milliseconds: 620),
    idle: _GlassIdlePattern.reverseSweep,
    light: _GlassLightPattern.reverseScanX,
    rotationRadians: -.18,
    translation: Offset(-.08, 0),
    idleDrift: Offset(-.07, .02),
  ),
  GlassMotionAction.info: _GlassMotionProfile(
    duration: Duration(milliseconds: 480),
    idle: _GlassIdlePattern.centerPulse,
    light: _GlassLightPattern.centerPulse,
    scaleX: .065,
    scaleY: .065,
    idleDrift: Offset(.03, .03),
  ),
  GlassMotionAction.error: _GlassMotionProfile(
    duration: Duration(milliseconds: 600),
    idle: _GlassIdlePattern.checker,
    light: _GlassLightPattern.pointPhase,
    scaleX: -.03,
    rotationRadians: .10,
    translation: Offset(-.035, 0),
    idleOpacity: .018,
    idleDrift: Offset(-.05, .02),
  ),
  GlassMotionAction.key: _GlassMotionProfile(
    duration: Duration(milliseconds: 560),
    idle: _GlassIdlePattern.diagonal,
    light: _GlassLightPattern.scanDiagonal,
    rotationRadians: .16,
    translation: Offset(.06, 0),
    idleDrift: Offset(.06, -.04),
  ),
  GlassMotionAction.qr: _GlassMotionProfile(
    duration: Duration(milliseconds: 520),
    idle: _GlassIdlePattern.rows,
    light: _GlassLightPattern.scanX,
    scaleX: .025,
    scaleY: .025,
    idleDrift: Offset(.08, .03),
  ),
  GlassMotionAction.code: _GlassMotionProfile(
    duration: Duration(milliseconds: 540),
    idle: _GlassIdlePattern.diagonal,
    light: _GlassLightPattern.scanDiagonal,
    scaleX: .075,
    scaleY: .015,
    idleDrift: Offset(.06, -.05),
  ),
  GlassMotionAction.tune: _GlassMotionProfile(
    duration: Duration(milliseconds: 560),
    idle: _GlassIdlePattern.columns,
    light: _GlassLightPattern.columns,
    scaleY: .025,
    translation: Offset(.03, 0),
    idleDrift: Offset(-.03, .06),
  ),
  GlassMotionAction.visibility: _GlassMotionProfile(
    duration: Duration(milliseconds: 520),
    idle: _GlassIdlePattern.forwardSweep,
    light: _GlassLightPattern.scanX,
    scaleY: -.10,
    idleDrift: Offset(.05, .01),
  ),
  GlassMotionAction.flash: _GlassMotionProfile(
    duration: Duration(milliseconds: 480),
    idle: _GlassIdlePattern.diagonal,
    light: _GlassLightPattern.scanDiagonal,
    translation: Offset(.16, -.05),
    rotationRadians: .05,
    idleDrift: Offset(.06, -.06),
  ),
  GlassMotionAction.chevron: _GlassMotionProfile(
    duration: Duration(milliseconds: 460),
    idle: _GlassIdlePattern.forwardSweep,
    light: _GlassLightPattern.scanX,
    translation: Offset(.24, 0),
    scaleX: .02,
    idleDrift: Offset(.07, .01),
  ),
  GlassMotionAction.playlist: _GlassMotionProfile(
    duration: Duration(milliseconds: 560),
    idle: _GlassIdlePattern.rows,
    light: _GlassLightPattern.rows,
    scaleX: .045,
    translation: Offset(.04, 0),
    idleDrift: Offset(.09, .03),
  ),
  GlassMotionAction.data: _GlassMotionProfile(
    duration: Duration(milliseconds: 540),
    idle: _GlassIdlePattern.columns,
    light: _GlassLightPattern.columns,
    scaleY: .055,
    rotationRadians: .025,
    idleDrift: Offset(.06, .06),
  ),
  GlassMotionAction.expand: _GlassMotionProfile(
    duration: Duration(milliseconds: 520),
    idle: _GlassIdlePattern.diagonal,
    light: _GlassLightPattern.rimSweep,
    scaleX: .08,
    scaleY: .08,
    idleDrift: Offset(.05, .05),
  ),
  GlassMotionAction.collapse: _GlassMotionProfile(
    duration: Duration(milliseconds: 520),
    idle: _GlassIdlePattern.reverseDiagonal,
    light: _GlassLightPattern.centerPulse,
    scaleX: -.08,
    scaleY: -.08,
    idleDrift: Offset(-.05, -.05),
  ),
  GlassMotionAction.appearance: _GlassMotionProfile(
    duration: Duration(milliseconds: 560),
    idle: _GlassIdlePattern.diagonal,
    light: _GlassLightPattern.scanDiagonal,
    rotationRadians: .06,
    scaleX: .025,
    scaleY: -.015,
    idleDrift: Offset(.06, -.02),
  ),
  GlassMotionAction.neutral: _GlassMotionProfile(
    duration: Duration(milliseconds: 520),
    idle: _GlassIdlePattern.sourcePhase,
    light: _GlassLightPattern.pointPhase,
    idleOpacity: .01,
  ),
};

extension GlassMotionActionDetails on GlassMotionAction {
  Duration get duration => _glassMotionProfiles[this]!.duration;

  _GlassMotionProfile get _profile => _glassMotionProfiles[this]!;

  static GlassMotionAction forGlyph(GlassGlyph glyph) => switch (glyph) {
    GlassGlyph.play => GlassMotionAction.play,
    GlassGlyph.pause => GlassMotionAction.pause,
    GlassGlyph.next => GlassMotionAction.next,
    GlassGlyph.previous => GlassMotionAction.previous,
    GlassGlyph.plus => GlassMotionAction.add,
    GlassGlyph.stop => GlassMotionAction.stop,
    GlassGlyph.copy => GlassMotionAction.copy,
    GlassGlyph.paste => GlassMotionAction.paste,
    GlassGlyph.save => GlassMotionAction.save,
    GlassGlyph.logout => GlassMotionAction.logout,
    GlassGlyph.terminal => GlassMotionAction.terminal,
    GlassGlyph.check => GlassMotionAction.check,
    GlassGlyph.close => GlassMotionAction.close,
    GlassGlyph.search => GlassMotionAction.search,
    GlassGlyph.refresh => GlassMotionAction.refresh,
    GlassGlyph.music => GlassMotionAction.music,
    GlassGlyph.grid => GlassMotionAction.grid,
    GlassGlyph.more => GlassMotionAction.more,
    GlassGlyph.network => GlassMotionAction.connect,
    GlassGlyph.activity => GlassMotionAction.activity,
    GlassGlyph.settings => GlassMotionAction.settings,
    GlassGlyph.link => GlassMotionAction.link,
    GlassGlyph.trash => GlassMotionAction.remove,
    GlassGlyph.export => GlassMotionAction.export,
    GlassGlyph.shield => GlassMotionAction.allowAccess,
    GlassGlyph.list => GlassMotionAction.list,
    GlassGlyph.folder => GlassMotionAction.folder,
    GlassGlyph.star => GlassMotionAction.star,
    GlassGlyph.arrow => GlassMotionAction.arrow,
    GlassGlyph.arrowBack => GlassMotionAction.arrowBack,
    GlassGlyph.arrowUp => GlassMotionAction.arrowUp,
    GlassGlyph.arrowDown => GlassMotionAction.arrowDown,
    GlassGlyph.filter => GlassMotionAction.filter,
    GlassGlyph.brightness => GlassMotionAction.brightness,
    GlassGlyph.build => GlassMotionAction.build,
    GlassGlyph.chat => GlassMotionAction.chat,
    GlassGlyph.device => GlassMotionAction.device,
    GlassGlyph.phone => GlassMotionAction.phone,
    GlassGlyph.lock => GlassMotionAction.lock,
    GlassGlyph.document => GlassMotionAction.document,
    GlassGlyph.account => GlassMotionAction.account,
    GlassGlyph.desktop => GlassMotionAction.desktop,
    GlassGlyph.externalLink => GlassMotionAction.open,
    GlassGlyph.hourglass => GlassMotionAction.hourglass,
    GlassGlyph.inbox => GlassMotionAction.inbox,
    GlassGlyph.history => GlassMotionAction.history,
    GlassGlyph.info => GlassMotionAction.info,
    GlassGlyph.error => GlassMotionAction.error,
    GlassGlyph.key => GlassMotionAction.key,
    GlassGlyph.qr => GlassMotionAction.qr,
    GlassGlyph.code => GlassMotionAction.code,
    GlassGlyph.tune => GlassMotionAction.tune,
    GlassGlyph.visibility => GlassMotionAction.visibility,
    GlassGlyph.flash => GlassMotionAction.flash,
    GlassGlyph.chevron => GlassMotionAction.chevron,
    GlassGlyph.playlist => GlassMotionAction.playlist,
    GlassGlyph.data => GlassMotionAction.data,
    GlassGlyph.expand => GlassMotionAction.expand,
    GlassGlyph.collapse => GlassMotionAction.collapse,
    GlassGlyph.appearance => GlassMotionAction.appearance,
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
      phaseSeed = phaseSeed ?? _allocatePhaseSeed() {
    final idleMotion = GlassMotionActionDetails.forGlyph(initialGlyph)
        ._profile
        .idleMotion;
    _idleMotionFrom = idleMotion;
    _idleMotionTo = idleMotion;
  }

  static int _nextPhaseSeed = 0;

  static int _allocatePhaseSeed() {
    _nextPhaseSeed += 37;
    return _nextPhaseSeed;
  }

  final int phaseSeed;
  final ChangeNotifier surfaceMotion = ChangeNotifier();
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
  late _GlassIdleMotion _idleMotionFrom;
  late _GlassIdleMotion _idleMotionTo;
  Duration _idleMotionStart = Duration.zero;
  Duration _lastSurfaceDelivery = Duration.zero;

  GlassGlyph get glyph => _glyph;
  Duration get now => _scope?.now ?? Duration.zero;
  bool get animationsEnabled => _motionAllowed && _isRegistered;

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
    surfaceMotion.notifyListeners();
  }

  void setVisible(bool visible) {
    if (_visible == visible) return;
    _visible = visible;
    _syncRegistration();
    if (_isRegistered) _scope!._deliverCurrentTime();
    surfaceMotion.notifyListeners();
  }

  void setMotionAllowed(bool allowed) {
    if (_motionAllowed == allowed) return;
    _motionAllowed = allowed;
    if (!allowed) _clearDecorations();
    _syncRegistration();
    if (_isRegistered) _scope!._deliverCurrentTime();
    surfaceMotion.notifyListeners();
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
    surfaceMotion.notifyListeners();
    notifyListeners();
  }

  void setGlyph(GlassGlyph glyph) {
    if (_glyph == glyph) return;
    final time = now;
    _idleMotionFrom = _idleMotionAt(time);
    _idleMotionTo = GlassMotionActionDetails.forGlyph(glyph)
        ._profile
        .idleMotion;
    _idleMotionStart = time;
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
    surfaceMotion.notifyListeners();
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
    surfaceMotion.notifyListeners();
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
    final interactionAnimating =
        _energyPulses.any(
          (pulse) => _linearProgress(time, pulse.start, pulse.duration) < 1,
        ) ||
        (_interactionAt(time) - _interactionTo).abs() > .001;
    final surfaceInterval = interactionAnimating
        ? const Duration(milliseconds: 33)
        : const Duration(milliseconds: 100);
    if (time - _lastSurfaceDelivery >= surfaceInterval) {
      _lastSurfaceDelivery = time;
      surfaceMotion.notifyListeners();
    }
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

  _GlassIdleMotion _idleMotionAt(Duration time) {
    final t = _linearProgress(time, _idleMotionStart, _glyphMorphDuration);
    if (t >= 1) return _idleMotionTo;
    return _GlassIdleMotion.lerp(
      _idleMotionFrom,
      _idleMotionTo,
      _smootherstep(t),
    );
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
    final idleMotion = _idleMotionAt(time);
    return [
      for (var index = 0; index < morphed.length; index++)
        _poseDot(
          morphed[index],
          phase: idlePhase,
          energy: energy,
          actionEnergy: actionEnergy,
          action: action,
          progress: progress,
          idleMotion: idleMotion,
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
    required _GlassIdleMotion idleMotion,
  }) {
    final profile = action._profile;
    final wave = phase * (math.pi * 2 / 5.8) + phaseSeed * .37 + source.phase;
    final idleSignal = _motionAllowed
        ? idleMotion.signal(source.position, wave, source.phase)
        : 0.0;
    final idleAlpha = _motionAllowed
        ? .90 + .06 * math.sin(wave) + idleMotion.opacityAmplitude * idleSignal
        : 1.0;
    final idleOffset = _motionAllowed
        ? Offset(math.sin(wave) * .16, math.cos(wave * .83) * .13)
        : Offset.zero;
    final position =
        _transformAction(source.position, action, progress, actionEnergy) +
        idleOffset +
        idleMotion.drift * idleSignal;

    final detailEnergy = _detailEnergy(
      profile,
      source.position,
      source.phase,
      progress,
      actionEnergy,
    );
    final brightness = 1 + energy * .06 + detailEnergy;
    return GlassDotPose(
      position: position,
      opacity: (source.opacity * idleAlpha * brightness).clamp(0.0, 1.0),
      phase: source.phase,
    );
  }

  double _detailEnergy(
    _GlassMotionProfile profile,
    Offset position,
    double pointPhase,
    double progress,
    double energy,
  ) {
    final amplitude = profile.lightAmplitude * energy;
    if (amplitude == 0) return 0;
    final relative = position - const Offset(16, 16);
    final row = (position.dy / 3).roundToDouble();
    final column = (position.dx / 3).roundToDouble();
    return switch (profile.light) {
      _GlassLightPattern.none => 0,
      _GlassLightPattern.scanX => _scanEnergy(
        position.dx,
        progress,
        energy,
        profile.lightAmplitude,
      ),
      _GlassLightPattern.reverseScanX => _scanEnergy(
        position.dx,
        1 - progress,
        energy,
        profile.lightAmplitude,
      ),
      _GlassLightPattern.scanY => _scanEnergy(
        position.dy,
        progress,
        energy,
        profile.lightAmplitude,
      ),
      _GlassLightPattern.reverseScanY => _scanEnergy(
        position.dy,
        1 - progress,
        energy,
        profile.lightAmplitude,
      ),
      _GlassLightPattern.scanDiagonal => _scanEnergy(
        (position.dx + position.dy) * .5,
        progress,
        energy,
        profile.lightAmplitude,
      ),
      _GlassLightPattern.radialSweep =>
        amplitude *
            math.max(
              0,
              math.cos(
                math.atan2(relative.dy, relative.dx) -
                    2 * math.pi * _smootherstep(progress),
              ),
            ),
      _GlassLightPattern.rows =>
        amplitude * math.cos(progress * math.pi * 2 + row * math.pi),
      _GlassLightPattern.columns =>
        amplitude * math.cos(progress * math.pi * 2 + column * math.pi),
      _GlassLightPattern.pointPhase =>
        amplitude * math.cos(progress * math.pi * 2 + pointPhase),
      _GlassLightPattern.centerPulse =>
        amplitude * math.exp(-relative.distanceSquared / 32),
      _GlassLightPattern.rimSweep =>
        amplitude *
            math.exp(-math.pow((relative.distance - 10) / 3.2, 2)) *
            math.max(
              0,
              math.cos(
                math.atan2(relative.dy, relative.dx) -
                    2 * math.pi * _smootherstep(progress),
              ),
            ),
    };
  }

  Offset _transformAction(
    Offset source,
    GlassMotionAction action,
    double progress,
    double energy,
  ) {
    final profile = action._profile;
    if (energy <= 0 && !profile.rotationFollowsProgress) return source;
    final relative = source - const Offset(16, 16);
    final scale = Offset(
      relative.dx * (1 + profile.scaleX * energy),
      relative.dy * (1 + profile.scaleY * energy),
    );
    final angle = profile.rotationFollowsProgress
        ? profile.rotationRadians * _smootherstep(progress)
        : profile.rotationRadians * energy;
    final cosine = math.cos(angle);
    final sine = math.sin(angle);
    final rotated = Offset(
      scale.dx * cosine - scale.dy * sine,
      scale.dx * sine + scale.dy * cosine,
    );
    final separation = Offset(
      relative.dx.sign * profile.separation,
      relative.dy.sign * profile.separation,
    );
    return const Offset(16, 16) +
        rotated +
        (profile.translation + separation) *
            (GlassDesignTokens.glyphPitch * energy);
  }

  double _scanEnergy(
    double coordinate,
    double progress,
    double energy,
    double amplitude,
  ) {
    final center = 4 + 24 * _smootherstep(progress);
    final distance = (coordinate - center) / 3.2;
    return amplitude * energy * math.exp(-distance * distance);
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
    surfaceMotion.notifyListeners();
    notifyListeners();
  }

  @override
  void dispose() {
    _scope?._unregister(this);
    surfaceMotion.dispose();
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
      duration: _glyphMorphDuration,
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
