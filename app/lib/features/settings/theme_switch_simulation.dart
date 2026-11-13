import 'dart:math' as math;

/// Independent native reconstruction of the geometry and physical behaviour in
/// https://experiments.thisiswhitespace.com/glass-light-toggle .
///
/// This model owns a single moving particle icon. Moon and sun cells are paired
/// spatially; particles retain their velocity when the destination changes.
/// Seeded initialization makes comparisons repeatable, but the recording's
/// random seed is unknown, so identical individual particle paths are not
/// established merely by using the same physical parameters.
class ThemeSwitchSimulation {
  ThemeSwitchSimulation({int seed = 0x6d2b79f5}) {
    _particles = _makeParticles(_UniformRandom(seed));
    snapTo(false);
  }

  static const trackWidth = 432.0;
  static const trackHeight = 224.0;
  static const trackRadius = 72.0;
  static const trackPadding = 13.0;
  static const restingKnobHalfSize = 99.0;
  static const restingKnobRadius = 58.0;
  static const knobTravel = 208.0;
  static const gridSize = 17;
  static const pixelPitch = 5.7;
  static const pixelSize = 4.6;
  static const lightIntensity = 1.89;
  static const stripHalfAngle = 0.92;
  static const refraction = 40.0;
  static const frost = 0.76;
  static const pixelGlow = 0.64;
  static const moonLightRgb = 0x6f86ff;
  static const sunLightRgb = 0xffa82e;

  static const _centerCell = 8.0;
  static const _knobStiffness = 129.0;
  static const _knobDampingRatio = 0.6;
  static const _phaseStiffness = 70.0;
  static const _swirl = 1.62;
  static const _burst = 0.38;

  late final List<_ParticleSpring> _particles;
  double _position = 0;
  double _velocity = 0;
  double _target = 0;
  double _hover = 0;
  double _hoverTarget = 0;
  double _press = 0;
  double _pressTarget = 0;
  double _kick = 0;
  double _phase = 0;
  double _phaseVelocity = 0;
  double _orbitDirection = 1;
  double _time = 0;
  bool _dragging = false;
  double _dragVelocity = 0;
  double _targetBeforeDrag = 0;
  bool _presentationControlled = false;
  bool _presentationPhaseControlled = false;

  /// The requested endpoint. Visual state can still be travelling toward it.
  bool get light => _target > 0.5;

  double get position => _position;
  double get velocity => _velocity;

  void setLight(bool value) {
    resumeDynamics();
    final next = value ? 1.0 : 0.0;
    if (_target == next) return;
    _target = next;
    _kick = 1;
  }

  /// Immediately establishes a settled endpoint, including the particle icon.
  void snapTo(bool value) {
    resumeDynamics();
    _target = value ? 1 : 0;
    _position = _target;
    _velocity = 0;
    _phase = _target;
    _phaseVelocity = 0;
    _orbitDirection = value ? -1 : 1;
    _kick = 0;
    _hover = _hoverTarget;
    _press = _pressTarget;
    _dragging = false;
    _dragVelocity = 0;
    for (final particle in _particles) {
      final goal = _particleGoal(particle, _target);
      particle
        ..x = goal.x
        ..y = goal.y
        ..vx = 0
        ..vy = 0
        ..initialized = true;
    }
  }

  void setHovered(bool value) => _hoverTarget = value ? 1 : 0;

  void setPressed(bool value) => _pressTarget = value ? 1 : 0;

  /// Supplies measured design-space state for deterministic reference replay.
  ///
  /// Unlike [dragTo], these values receive no elastic resistance or filtering.
  /// Subsequent frames keep the supplied knob position/velocity while particle
  /// springs continue integrating. Supplying [orbitPhase] also holds the light
  /// phase, in 0..1. [resumeDynamics], [setLight], [snapTo], or [dragTo] restores
  /// ordinary spring control without resetting the particles.
  void setPresentation({
    double? position,
    double? velocity,
    double? orbitPhase,
  }) {
    for (final value in [position, velocity, orbitPhase]) {
      if (value != null && !value.isFinite) {
        throw ArgumentError('Measured presentation values must be finite.');
      }
    }
    _presentationControlled = true;
    if (position != null) _position = position;
    if (velocity != null) _velocity = velocity;
    if (orbitPhase != null) {
      _phase = _unit(orbitPhase);
      _phaseVelocity = 0;
      _presentationPhaseControlled = true;
    }
  }

  void resumeDynamics() {
    _presentationControlled = false;
    _presentationPhaseControlled = false;
  }

  /// Captures a moving handle immediately, without resetting its momentum.
  void beginDrag() {
    resumeDynamics();
    if (_dragging) return;
    _dragging = true;
    _targetBeforeDrag = _target;
    _dragVelocity = 0;
  }

  /// Takes raw normalized position and velocity in normalized units per second.
  ///
  /// Values outside 0..1 receive elastic resistance here, and incoming velocity
  /// receives the same resistance before the drag filter. Pointer input should
  /// supply [elapsedSeconds] so crossing an elastic endpoint uses the actual
  /// resisted displacement, rather than scaling the entire velocity sample.
  void dragTo(double position, double velocity, {double? elapsedSeconds}) {
    if (!position.isFinite || !velocity.isFinite) {
      throw ArgumentError('Drag position and velocity must be finite.');
    }
    if (elapsedSeconds != null &&
        (!elapsedSeconds.isFinite || elapsedSeconds <= 0)) {
      throw ArgumentError('Pointer intervals must be positive and finite.');
    }
    beginDrag();
    final outside = position < 0 || position > 1;
    final resisted = position < 0
        ? position * 0.22
        : position > 1
        ? 1 + (position - 1) * 0.22
        : position;
    final instantaneous = elapsedSeconds == null
        ? velocity * (outside ? 0.22 : 1)
        : (resisted - _position) / elapsedSeconds;
    _dragVelocity = _dragVelocity * 0.6 + instantaneous * 0.4;
    _position = resisted;
    _velocity = _dragVelocity;
  }

  /// Releases toward the endpoint predicted by position and drag momentum.
  /// Cancellation keeps the endpoint that was selected when the drag began.
  void releaseDrag({bool cancel = false}) {
    _pressTarget = 0;
    if (!_dragging) return;
    _dragging = false;
    _target = cancel
        ? _targetBeforeDrag
        : _position + _dragVelocity * 0.15 > 0.5
        ? 1
        : 0;
    _kick = cancel ? 0 : 0.6;
  }

  /// Advances one rendered frame; [time] is absolute animation time in seconds.
  ///
  /// A frame integrates at most 1/30 second, matching the reference's dropped
  /// frame policy. The caller supplies real presentation intervals rather than
  /// making this model assume a fixed display refresh rate.
  void advance(double dt, double time) {
    if (!dt.isFinite || dt < 0 || !time.isFinite) {
      throw ArgumentError('Frame time must be finite with nonnegative dt.');
    }
    final step = math.min(dt, 1 / 30);
    _time = time;

    if (!_dragging && !_presentationControlled) {
      final damping = 2 * math.sqrt(_knobStiffness) * _knobDampingRatio;
      final substep = step / 4;
      for (var i = 0; i < 4; i++) {
        final acceleration =
            -_knobStiffness * (_position - _target) - damping * _velocity;
        _velocity += acceleration * substep;
        _position += _velocity * substep;
      }
    }

    _hover += (_hoverTarget - _hover) * math.min(1, step * 10);
    _press += (_pressTarget - _press) * math.min(1, step * 18);
    _kick *= math.exp(-step * 3.5);

    final progress = _unit(_position);
    if (!_presentationPhaseControlled) {
      final desiredPhase = _cubicInOut(progress);
      final phaseAcceleration =
          -_phaseStiffness * (_phase - desiredPhase) -
          2 * math.sqrt(_phaseStiffness) * _phaseVelocity;
      _phaseVelocity += phaseAcceleration * step;
      _phase += _phaseVelocity * step;
    }
    final phase = _unit(_phase);
    if (phase < 0.015) {
      _orbitDirection = 1;
    } else if (phase > 0.985) {
      _orbitDirection = -1;
    }

    for (final particle in _particles) {
      final goal = _particleGoal(particle, progress);
      if (!particle.initialized) {
        particle
          ..x = goal.x
          ..y = goal.y
          ..vx = 0
          ..vy = 0
          ..initialized = true;
      }
      final damping = 2 * math.sqrt(particle.stiffness) * 0.72;
      particle.vx +=
          (-particle.stiffness * (particle.x - goal.x) -
              damping * particle.vx) *
          step;
      particle.vy +=
          (-particle.stiffness * (particle.y - goal.y) -
              damping * particle.vy) *
          step;
      particle.x += particle.vx * step;
      particle.y += particle.vy * step;
    }
  }

  /// All coordinates are in the 432×224 design space, relative to scene centre.
  ThemeSwitchSnapshot get snapshot {
    final progress = _unit(_position);
    final overshoot = math.max(math.max(-_position, _position - 1), 0);
    final stretch = math.min(_velocity.abs() * 6.5, 16);
    final squeeze = 1 - _press * 0.035;
    final halfWidth =
        (restingKnobHalfSize + stretch - overshoot * 110) * squeeze;
    final halfHeight =
        math.min(
          restingKnobHalfSize - stretch * 0.45 + overshoot * 30,
          restingKnobHalfSize + 5,
        ) *
        squeeze;
    var knobX = -knobTravel / 2 + knobTravel * progress;
    if (_position > 1) {
      knobX += overshoot * 110;
    } else if (_position < 0) {
      knobX -= overshoot * 110;
    }
    final phase = _unit(_phase);
    final theta = _orbitDirection > 0
        ? math.pi / 2 - math.pi * phase
        : -math.pi / 2 - math.pi * (1 - phase);
    final led =
        (1 +
            _hover * 0.08 +
            math.min(_velocity.abs() * 0.05, 0.18) +
            _kick * 0.12) *
        lightIntensity;
    final knobVelocity = _velocity * knobTravel;
    final drawnParticles = <ThemeSwitchParticle>[];
    for (final particle in _particles) {
      final goal = _particleGoal(particle, progress);
      final inertia = (-knobVelocity * particle.motionDrag).clamp(-14.0, 14.0);
      drawnParticles.add(
        ThemeSwitchParticle(
          x: knobX + (particle.initialized ? particle.x : goal.x) + inertia,
          y: particle.initialized ? particle.y : goal.y,
          size: goal.size,
          alpha: _unit(goal.brightness),
        ),
      );
    }
    return ThemeSwitchSnapshot(
      position: _position,
      velocity: _velocity,
      theme: _smooth(0.18, 0.82, progress),
      knobX: knobX,
      halfWidth: halfWidth,
      halfHeight: halfHeight,
      radius: math.min(
        restingKnobRadius,
        math.min(halfWidth - 1, halfHeight - 1),
      ),
      theta: theta,
      led: led,
      lift: _hover * (1 - _press),
      particles: List.unmodifiable(drawnParticles),
    );
  }

  _ParticleGoal _particleGoal(_ParticleSpring particle, double progress) {
    final blend = _cubicInOut(_unit((progress - particle.delay) / 0.62));
    final startX = (particle.moon.x - _centerCell) * pixelPitch;
    final startY = (particle.moon.y - _centerCell) * pixelPitch;
    final endX = (particle.sun.x - _centerCell) * pixelPitch;
    final endY = (particle.sun.y - _centerCell) * pixelPitch;
    final dx = endX - startX;
    final dy = endY - startY;
    final distance = math.sqrt(dx * dx + dy * dy);
    final denominator = distance == 0 ? 1 : distance;
    final arc = math.sin(math.pi * blend);
    var x =
        startX + dx * blend - dy / denominator * particle.curl * _swirl * arc;
    var y =
        startY + dy * blend + dx / denominator * particle.curl * _swirl * arc;
    final radius = math.sqrt(x * x + y * y);
    final radialDenominator = radius == 0 ? 1 : radius;
    final expansion = particle.radialLift * arc * 1.4 * _burst;
    x += x / radialDenominator * expansion;
    y += y / radialDenominator * expansion;

    var moonBrightness = particle.moon.brightness;
    var sunBrightness = particle.sun.brightness;
    if (particle.moon.kind == _CellKind.star) {
      final twinkle = math.sin(_time * particle.twinkleRate + particle.phase);
      moonBrightness *= 0.45 + 0.55 * twinkle * twinkle;
    }
    if (particle.sun.kind == _CellKind.ray) {
      sunBrightness *=
          0.78 +
          0.22 * (0.5 + 0.5 * math.sin(_time * 2.2 - particle.sun.angle));
    }
    return _ParticleGoal(
      x,
      y,
      (moonBrightness + (sunBrightness - moonBrightness) * blend) *
          (1 + 0.3 * arc),
      pixelSize * (1 - 0.45 * arc),
    );
  }

  static List<_ParticleSpring> _makeParticles(_UniformRandom random) {
    final moon = _moonCells()..sort(_compareCells);
    final sun = _sunCells()..sort(_compareCells);
    final moonHasMoreCells = moon.length >= sun.length;
    final larger = moonHasMoreCells ? moon : sun;
    final smaller = moonHasMoreCells ? sun : moon;
    final particles = <_ParticleSpring>[];
    var previousSmallIndex = -1;
    for (var i = 0; i < larger.length; i++) {
      final smallIndex = i * smaller.length ~/ larger.length;
      final smallerCell = smallIndex == previousSmallIndex
          ? smaller[smallIndex].withBrightness(0)
          : smaller[smallIndex];
      previousSmallIndex = smallIndex;
      final moonCell = moonHasMoreCells ? larger[i] : smallerCell;
      final sunCell = moonHasMoreCells ? smallerCell : larger[i];
      particles.add(
        _ParticleSpring(
          moon: moonCell,
          sun: sunCell,
          delay:
              0.04 +
              (1 - moonCell.x / (gridSize - 1)) * 0.26 +
              random.between(0, 0.06),
          curl: random.between(-1, 1) * 16 + (moonCell.y - _centerCell) * 0.9,
          radialLift: random.between(2, 12),
          stiffness: random.between(260, 460),
          motionDrag: random.between(0.004, 0.016),
          phase: random.between(0, math.pi * 2),
          twinkleRate: random.between(1.5, 3.2),
        ),
      );
    }
    return particles;
  }

  static List<_IconCell> _moonCells() {
    final cells = <_IconCell>[];
    for (var y = 0; y < gridSize; y++) {
      for (var x = 0; x < gridSize; x++) {
        final dx = x - _centerCell;
        final dy = y - _centerCell;
        final shadowX = x - 11.3;
        final shadowY = y - 5.6;
        final body = dx * dx + dy * dy <= 6.6 * 6.6;
        final shadow = shadowX * shadowX + shadowY * shadowY <= 5.4 * 5.4;
        if (!body) continue;
        if (!shadow) {
          final dimmed =
              (x == 3 && y == 9) || (x == 6 && y == 12) || (x == 4 && y == 12);
          cells.add(
            _IconCell(
              x.toDouble(),
              y.toDouble(),
              dimmed ? 0.5 : 1,
              _CellKind.body,
            ),
          );
        } else if ((x + y).isEven) {
          cells.add(
            _IconCell(x.toDouble(), y.toDouble(), 0.2, _CellKind.shadow),
          );
        }
      }
    }
    for (final star in const [
      (15.0, 1.0, 1.0),
      (14.0, 1.0, 0.45),
      (16.0, 1.0, 0.45),
      (15.0, 0.0, 0.45),
      (15.0, 2.0, 0.45),
      (11.0, 0.0, 0.75),
      (16.0, 5.0, 0.6),
    ]) {
      cells.add(_IconCell(star.$1, star.$2, star.$3, _CellKind.star));
    }
    return cells;
  }

  static List<_IconCell> _sunCells() {
    final cells = <(int, int), _IconCell>{};
    void add(int x, int y, _CellKind kind, [double angle = 0]) {
      cells.putIfAbsent((
        x,
        y,
      ), () => _IconCell(x.toDouble(), y.toDouble(), 1, kind, angle));
    }

    for (var y = 0; y < gridSize; y++) {
      for (var x = 0; x < gridSize; x++) {
        final dx = x - _centerCell;
        final dy = y - _centerCell;
        if (dx * dx + dy * dy <= 3.7 * 3.7) add(x, y, _CellKind.core);
      }
    }
    for (var ray = 0; ray < 8; ray++) {
      final angle = ray * math.pi / 4;
      final lengths = ray.isOdd ? const [5.9, 7.2] : const [5.6, 6.6, 7.6];
      for (final radius in lengths) {
        add(
          (_centerCell + math.cos(angle) * radius).round(),
          (_centerCell + math.sin(angle) * radius).round(),
          _CellKind.ray,
          angle,
        );
      }
    }
    return cells.values.toList();
  }

  static int _compareCells(_IconCell a, _IconCell b) {
    double key(_IconCell cell) {
      final dx = cell.x - _centerCell;
      final dy = cell.y - _centerCell;
      final angle =
          (math.atan2(dy, dx) + math.pi * 0.75 + math.pi * 2) % (math.pi * 2);
      return angle + math.sqrt(dx * dx + dy * dy) * 0.001;
    }

    return key(a).compareTo(key(b));
  }
}

/// Immutable values consumed by the renderer for one animation frame.
class ThemeSwitchSnapshot {
  const ThemeSwitchSnapshot({
    required this.position,
    required this.velocity,
    required this.theme,
    required this.knobX,
    required this.halfWidth,
    required this.halfHeight,
    required this.radius,
    required this.theta,
    required this.led,
    required this.lift,
    required this.particles,
  });

  final double position;
  final double velocity;
  final double theme;
  final double knobX;
  final double halfWidth;
  final double halfHeight;
  final double radius;
  final double theta;

  /// Shader-ready intensity, including [ThemeSwitchSimulation.lightIntensity].
  final double led;
  final double lift;
  final List<ThemeSwitchParticle> particles;

  ThemeSwitchSnapshot copyWith({
    double? position,
    double? velocity,
    double? theme,
    double? knobX,
    double? halfWidth,
    double? halfHeight,
    double? radius,
    double? theta,
    double? led,
    double? lift,
    List<ThemeSwitchParticle>? particles,
  }) => ThemeSwitchSnapshot(
    position: position ?? this.position,
    velocity: velocity ?? this.velocity,
    theme: theme ?? this.theme,
    knobX: knobX ?? this.knobX,
    halfWidth: halfWidth ?? this.halfWidth,
    halfHeight: halfHeight ?? this.halfHeight,
    radius: radius ?? this.radius,
    theta: theta ?? this.theta,
    led: led ?? this.led,
    lift: lift ?? this.lift,
    particles: particles == null
        ? this.particles
        : List.unmodifiable(particles),
  );
}

class ThemeSwitchParticle {
  const ThemeSwitchParticle({
    required this.x,
    required this.y,
    required this.size,
    required this.alpha,
  });

  final double x;
  final double y;
  final double size;
  final double alpha;

  ThemeSwitchParticle copyWith({
    double? x,
    double? y,
    double? size,
    double? alpha,
  }) => ThemeSwitchParticle(
    x: x ?? this.x,
    y: y ?? this.y,
    size: size ?? this.size,
    alpha: alpha ?? this.alpha,
  );
}

enum _CellKind { body, shadow, star, core, ray }

class _IconCell {
  const _IconCell(this.x, this.y, this.brightness, this.kind, [this.angle = 0]);

  final double x;
  final double y;
  final double brightness;
  final _CellKind kind;
  final double angle;

  _IconCell withBrightness(double value) => _IconCell(x, y, value, kind, angle);
}

class _ParticleSpring {
  _ParticleSpring({
    required this.moon,
    required this.sun,
    required this.delay,
    required this.curl,
    required this.radialLift,
    required this.stiffness,
    required this.motionDrag,
    required this.phase,
    required this.twinkleRate,
  });

  final _IconCell moon;
  final _IconCell sun;
  final double delay;
  final double curl;
  final double radialLift;
  final double stiffness;
  final double motionDrag;
  final double phase;
  final double twinkleRate;
  double x = 0;
  double y = 0;
  double vx = 0;
  double vy = 0;
  bool initialized = false;
}

class _ParticleGoal {
  const _ParticleGoal(this.x, this.y, this.brightness, this.size);

  final double x;
  final double y;
  final double brightness;
  final double size;
}

class _UniformRandom {
  _UniformRandom(int seed) : _state = seed & 0xffffffff;

  int _state;

  double between(double minimum, double maximum) {
    _state = (1664525 * _state + 1013904223) & 0xffffffff;
    return minimum + (_state / 4294967296) * (maximum - minimum);
  }
}

double _unit(double value) => value.clamp(0.0, 1.0);

double _smooth(double minimum, double maximum, double value) {
  final t = _unit((value - minimum) / (maximum - minimum));
  return t * t * (3 - 2 * t);
}

double _cubicInOut(double value) => value < 0.5
    ? 4 * value * value * value
    : 1 - math.pow(-2 * value + 2, 3) / 2;
