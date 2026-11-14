import 'dart:math' as math;

/// Immutable parameters for a live theme-switch model, never a frame sequence.
///
/// [reference] retains the independent source-model oracle. A fitted product
/// profile is supplied explicitly so updating it cannot silently rewrite that
/// oracle. Compiled profiles use const particle lists; [fromJson] defensively
/// freezes lists read by calibration tools.
class ThemeSwitchCalibration {
  const ThemeSwitchCalibration({
    this.seed = 0x6d2b79f5,
    this.timeOriginSeconds = 0,
    this.particleParameters,
    this.motion = const ThemeSwitchMotion(),
    this.optics = const ThemeSwitchOptics(),
    this.scene = const ThemeSwitchScene(),
  });

  static const reference = ThemeSwitchCalibration();
  static const particleCount = 113;

  final int seed;
  final double timeOriginSeconds;
  final List<ThemeSwitchParticleParameters>? particleParameters;
  final ThemeSwitchMotion motion;
  final ThemeSwitchOptics optics;
  final ThemeSwitchScene scene;

  factory ThemeSwitchCalibration.fromJson(Object? value) {
    final json = _object(value, 'calibration');
    _allowKeys(json, const {
      'schemaVersion',
      'seed',
      'timeOriginSeconds',
      'particleParameters',
      'motion',
      'optics',
      'scene',
    });
    if (json['schemaVersion'] != 1) {
      throw const FormatException(
        'Unsupported theme-switch calibration schema.',
      );
    }
    final rawParticles = json['particleParameters'];
    if (rawParticles != null && rawParticles is! List) {
      throw const FormatException('particleParameters must be a list or null.');
    }
    final result = ThemeSwitchCalibration(
      seed: _integer(json, 'seed', reference.seed),
      timeOriginSeconds: _number(json, 'timeOriginSeconds', 0),
      particleParameters: rawParticles == null
          ? null
          : List.unmodifiable(
              (rawParticles as List).map(
                ThemeSwitchParticleParameters.fromJson,
              ),
            ),
      motion: json['motion'] == null
          ? reference.motion
          : ThemeSwitchMotion.fromJson(json['motion']),
      optics: json['optics'] == null
          ? reference.optics
          : ThemeSwitchOptics.fromJson(json['optics']),
      scene: json['scene'] == null
          ? reference.scene
          : ThemeSwitchScene.fromJson(json['scene']),
    );
    result.validate();
    return result;
  }

  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'seed': seed,
    'timeOriginSeconds': timeOriginSeconds,
    'particleParameters': particleParameters
        ?.map((value) => value.toJson())
        .toList(growable: false),
    'motion': motion.toJson(),
    'optics': optics.toJson(),
    'scene': scene.toJson(),
  };

  void validate() {
    if (seed < 0 || seed > 0xffffffff) {
      throw const FormatException('seed must be an unsigned 32-bit integer.');
    }
    _range('timeOriginSeconds', timeOriginSeconds, -86400, 86400);
    motion.validate();
    optics.validate();
    scene.validate();
    final particles = particleParameters;
    if (particles == null) {
      _stableSpring('generated particle', 460, motion.particleDamping, 1 / 30);
      if (0.36 + motion.morphSpan > 1 + 1e-12) {
        throw const FormatException(
          'Generated particle delay plus morphSpan must not exceed 1.',
        );
      }
    } else {
      if (particles.length != particleCount) {
        throw const FormatException(
          'A particle profile must contain exactly 113 entries.',
        );
      }
      for (var i = 0; i < particles.length; i++) {
        final particle = particles[i];
        particle.validate();
        _stableSpring(
          'particle $i',
          particle.stiffness,
          motion.particleDamping,
          1 / 30,
        );
        if (particle.delay + motion.morphSpan > 1 + 1e-12) {
          throw FormatException(
            'Particle $i delay plus morphSpan exceeds the light endpoint.',
          );
        }
      }
    }
  }
}

class ThemeSwitchParticleParameters {
  const ThemeSwitchParticleParameters({
    required this.delay,
    required this.curl,
    required this.lift,
    required this.stiffness,
    required this.drag,
    required this.phase,
    required this.twinkle,
  });

  final double delay;
  final double curl;
  final double lift;
  final double stiffness;
  final double drag;
  final double phase;
  final double twinkle;

  factory ThemeSwitchParticleParameters.fromJson(Object? value) {
    final json = _object(value, 'particle parameters');
    const keys = {
      'delay',
      'curl',
      'lift',
      'stiffness',
      'drag',
      'phase',
      'twinkle',
    };
    _allowKeys(json, keys);
    if (!keys.every(json.containsKey)) {
      throw const FormatException('Every particle parameter is required.');
    }
    final result = ThemeSwitchParticleParameters(
      delay: _number(json, 'delay'),
      curl: _number(json, 'curl'),
      lift: _number(json, 'lift'),
      stiffness: _number(json, 'stiffness'),
      drag: _number(json, 'drag'),
      phase: _number(json, 'phase'),
      twinkle: _number(json, 'twinkle'),
    );
    result.validate();
    return result;
  }

  Map<String, Object?> toJson() => {
    'delay': delay,
    'curl': curl,
    'lift': lift,
    'stiffness': stiffness,
    'drag': drag,
    'phase': phase,
    'twinkle': twinkle,
  };

  void validate() {
    _range('particle.delay', delay, 0, 1);
    _range('particle.curl', curl, -64, 64);
    _range('particle.lift', lift, 0, 24);
    _range('particle.stiffness', stiffness, 1, 1000);
    _range('particle.drag', drag, 0, 0.04);
    _range('particle.phase', phase, 0, math.pi * 2);
    _range('particle.twinkle', twinkle, 0.1, 10);
  }
}

class ThemeSwitchMotion {
  const ThemeSwitchMotion({
    this.knobStiffness = 129,
    this.knobDamping = 0.6,
    this.phaseStiffness = 70,
    this.phaseDamping = 1,
    this.particleDamping = 0.72,
    this.stretchRate = 6.5,
    this.maxStretch = 16,
    this.verticalStretch = 0.45,
    this.pressSqueeze = 0.035,
    this.elasticity = 0.22,
    this.overshootHorizontal = 110,
    this.overshootVertical = 30,
    this.restingKnobHalfSize = 99,
    this.restingKnobRadius = 58,
    this.knobTravel = 208,
    this.velocityRetention = 0.6,
    this.releaseProjection = 0.15,
    this.hoverResponse = 10,
    this.pressResponse = 18,
    this.kickDecay = 3.5,
    this.swirl = 1.62,
    this.burst = 0.38,
    this.morphSpan = 0.62,
    this.sunRayRate = 2.2,
    this.sunRayPhase = 0,
  });

  final double knobStiffness;
  final double knobDamping;
  final double phaseStiffness;
  final double phaseDamping;
  final double particleDamping;
  final double stretchRate;
  final double maxStretch;
  final double verticalStretch;
  final double pressSqueeze;
  final double elasticity;
  final double overshootHorizontal;
  final double overshootVertical;
  final double restingKnobHalfSize;
  final double restingKnobRadius;
  final double knobTravel;
  final double velocityRetention;
  final double releaseProjection;
  final double hoverResponse;
  final double pressResponse;
  final double kickDecay;
  final double swirl;
  final double burst;
  final double morphSpan;
  final double sunRayRate;
  final double sunRayPhase;

  factory ThemeSwitchMotion.fromJson(Object? value) {
    final json = _object(value, 'motion');
    const defaults = ThemeSwitchMotion();
    _allowKeys(json, defaults.toJson().keys.toSet());
    final result = ThemeSwitchMotion(
      knobStiffness: _number(json, 'knobStiffness', defaults.knobStiffness),
      knobDamping: _number(json, 'knobDamping', defaults.knobDamping),
      phaseStiffness: _number(json, 'phaseStiffness', defaults.phaseStiffness),
      phaseDamping: _number(json, 'phaseDamping', defaults.phaseDamping),
      particleDamping: _number(
        json,
        'particleDamping',
        defaults.particleDamping,
      ),
      stretchRate: _number(json, 'stretchRate', defaults.stretchRate),
      maxStretch: _number(json, 'maxStretch', defaults.maxStretch),
      verticalStretch: _number(
        json,
        'verticalStretch',
        defaults.verticalStretch,
      ),
      pressSqueeze: _number(json, 'pressSqueeze', defaults.pressSqueeze),
      elasticity: _number(json, 'elasticity', defaults.elasticity),
      overshootHorizontal: _number(
        json,
        'overshootHorizontal',
        defaults.overshootHorizontal,
      ),
      overshootVertical: _number(
        json,
        'overshootVertical',
        defaults.overshootVertical,
      ),
      restingKnobHalfSize: _number(
        json,
        'restingKnobHalfSize',
        defaults.restingKnobHalfSize,
      ),
      restingKnobRadius: _number(
        json,
        'restingKnobRadius',
        defaults.restingKnobRadius,
      ),
      knobTravel: _number(json, 'knobTravel', defaults.knobTravel),
      velocityRetention: _number(
        json,
        'velocityRetention',
        defaults.velocityRetention,
      ),
      releaseProjection: _number(
        json,
        'releaseProjection',
        defaults.releaseProjection,
      ),
      hoverResponse: _number(json, 'hoverResponse', defaults.hoverResponse),
      pressResponse: _number(json, 'pressResponse', defaults.pressResponse),
      kickDecay: _number(json, 'kickDecay', defaults.kickDecay),
      swirl: _number(json, 'swirl', defaults.swirl),
      burst: _number(json, 'burst', defaults.burst),
      morphSpan: _number(json, 'morphSpan', defaults.morphSpan),
      sunRayRate: _number(json, 'sunRayRate', defaults.sunRayRate),
      sunRayPhase: _number(json, 'sunRayPhase', defaults.sunRayPhase),
    );
    result.validate();
    return result;
  }

  Map<String, Object?> toJson() => {
    'knobStiffness': knobStiffness,
    'knobDamping': knobDamping,
    'phaseStiffness': phaseStiffness,
    'phaseDamping': phaseDamping,
    'particleDamping': particleDamping,
    'stretchRate': stretchRate,
    'maxStretch': maxStretch,
    'verticalStretch': verticalStretch,
    'pressSqueeze': pressSqueeze,
    'elasticity': elasticity,
    'overshootHorizontal': overshootHorizontal,
    'overshootVertical': overshootVertical,
    'restingKnobHalfSize': restingKnobHalfSize,
    'restingKnobRadius': restingKnobRadius,
    'knobTravel': knobTravel,
    'velocityRetention': velocityRetention,
    'releaseProjection': releaseProjection,
    'hoverResponse': hoverResponse,
    'pressResponse': pressResponse,
    'kickDecay': kickDecay,
    'swirl': swirl,
    'burst': burst,
    'morphSpan': morphSpan,
    'sunRayRate': sunRayRate,
    'sunRayPhase': sunRayPhase,
  };

  void validate() {
    _range('motion.knobStiffness', knobStiffness, 1, 1000);
    _range('motion.knobDamping', knobDamping, 0.1, 2);
    _range('motion.phaseStiffness', phaseStiffness, 1, 300);
    _range('motion.phaseDamping', phaseDamping, 0.1, 2);
    _range('motion.particleDamping', particleDamping, 0.1, 2);
    _stableSpring('knob', knobStiffness, knobDamping, 1 / 120);
    _stableSpring('phase', phaseStiffness, phaseDamping, 1 / 30);
    _range('motion.stretchRate', stretchRate, 0, 50);
    _range('motion.maxStretch', maxStretch, 0, 50);
    _range('motion.verticalStretch', verticalStretch, 0, 1);
    _range('motion.pressSqueeze', pressSqueeze, 0, 0.25);
    _range('motion.elasticity', elasticity, 0.01, 1);
    _range('motion.overshootHorizontal', overshootHorizontal, 1, 208);
    _range('motion.overshootVertical', overshootVertical, 0, 100);
    _range('motion.restingKnobHalfSize', restingKnobHalfSize, 2, 111);
    _range(
      'motion.restingKnobRadius',
      restingKnobRadius,
      1,
      restingKnobHalfSize - 1,
    );
    _range('motion.knobTravel', knobTravel, 1, 2 * (216 - restingKnobHalfSize));
    _range('motion.velocityRetention', velocityRetention, 0, 0.99);
    _range('motion.releaseProjection', releaseProjection, 0, 1);
    _range('motion.hoverResponse', hoverResponse, 0, 30);
    _range('motion.pressResponse', pressResponse, 0, 30);
    _range('motion.kickDecay', kickDecay, 0, 20);
    _range('motion.swirl', swirl, 0, 5);
    _range('motion.burst', burst, 0, 2);
    _range('motion.morphSpan', morphSpan, 0.05, 1);
    _range('motion.sunRayRate', sunRayRate, 0.1, 10);
    _range('motion.sunRayPhase', sunRayPhase, 0, math.pi * 2);
  }
}

/// Responsive scene framing, expressed at a 720-pixel reference width.
class ThemeSwitchScene {
  const ThemeSwitchScene({
    this.scale = 0.76,
    this.offsetX = 0,
    this.offsetY = -3,
  });

  final double scale;
  final double offsetX;
  final double offsetY;

  factory ThemeSwitchScene.fromJson(Object? value) {
    final json = _object(value, 'scene');
    _allowKeys(json, const {'scale', 'offsetX', 'offsetY'});
    final result = ThemeSwitchScene(
      scale: _number(json, 'scale', 0.76),
      offsetX: _number(json, 'offsetX', 0),
      offsetY: _number(json, 'offsetY', -3),
    );
    result.validate();
    return result;
  }

  Map<String, Object?> toJson() => {
    'scale': scale,
    'offsetX': offsetX,
    'offsetY': offsetY,
  };

  void validate() {
    _range('scene.scale', scale, 0.1, 1.5);
    _range('scene.offsetX', offsetX, -100, 100);
    _range('scene.offsetY', offsetY, -100, 100);
  }
}

class ThemeSwitchOptics {
  const ThemeSwitchOptics({
    this.refraction = 40,
    this.frost = 0.76,
    this.pixelGlow = 0.64,
    this.stripHalfAngle = 0.92,
    this.lightIntensity = 1.89,
    this.moonRgb = 0x6f86ff,
    this.sunRgb = 0xffa82e,
  });

  final double refraction;
  final double frost;
  final double pixelGlow;
  final double stripHalfAngle;
  final double lightIntensity;
  final int moonRgb;
  final int sunRgb;

  factory ThemeSwitchOptics.fromJson(Object? value) {
    final json = _object(value, 'optics');
    const defaults = ThemeSwitchOptics();
    _allowKeys(json, defaults.toJson().keys.toSet());
    final result = ThemeSwitchOptics(
      refraction: _number(json, 'refraction', defaults.refraction),
      frost: _number(json, 'frost', defaults.frost),
      pixelGlow: _number(json, 'pixelGlow', defaults.pixelGlow),
      stripHalfAngle: _number(json, 'stripHalfAngle', defaults.stripHalfAngle),
      lightIntensity: _number(json, 'lightIntensity', defaults.lightIntensity),
      moonRgb: _integer(json, 'moonRgb', defaults.moonRgb),
      sunRgb: _integer(json, 'sunRgb', defaults.sunRgb),
    );
    result.validate();
    return result;
  }

  Map<String, Object?> toJson() => {
    'refraction': refraction,
    'frost': frost,
    'pixelGlow': pixelGlow,
    'stripHalfAngle': stripHalfAngle,
    'lightIntensity': lightIntensity,
    'moonRgb': moonRgb,
    'sunRgb': sunRgb,
  };

  void validate() {
    _range('optics.refraction', refraction, 0, 100);
    _range('optics.frost', frost, 0, 1);
    _range('optics.pixelGlow', pixelGlow, 0, 2);
    _range('optics.stripHalfAngle', stripHalfAngle, 0.01, math.pi);
    _range('optics.lightIntensity', lightIntensity, 0, 5);
    if (moonRgb < 0 || moonRgb > 0xffffff || sunRgb < 0 || sunRgb > 0xffffff) {
      throw const FormatException(
        'Lamp colors must be unsigned 24-bit RGB values.',
      );
    }
  }
}

Map<String, Object?> _object(Object? value, String name) {
  if (value is! Map || value.keys.any((key) => key is! String)) {
    throw FormatException('$name must be an object with string keys.');
  }
  return Map<String, Object?>.from(value);
}

void _allowKeys(Map<String, Object?> json, Set<String> allowed) {
  final unknown = json.keys.where((key) => !allowed.contains(key)).toList();
  if (unknown.isNotEmpty) {
    throw FormatException('Unknown calibration fields: $unknown.');
  }
}

double _number(Map<String, Object?> json, String key, [double? fallback]) {
  final raw = json.containsKey(key) ? json[key] : fallback;
  if (raw is! num || !raw.isFinite) {
    throw FormatException('$key must be a finite number.');
  }
  return raw.toDouble();
}

int _integer(Map<String, Object?> json, String key, int fallback) {
  final raw = json.containsKey(key) ? json[key] : fallback;
  if (raw is! int) throw FormatException('$key must be an integer.');
  return raw;
}

void _range(String name, double value, double minimum, double maximum) {
  if (!value.isFinite || value < minimum || value > maximum) {
    throw FormatException(
      '$name must be finite and within $minimum..$maximum.',
    );
  }
}

void _stableSpring(String name, double stiffness, double damping, double step) {
  // Semi-implicit Euler's damped oscillator stability boundary. Validation uses
  // the largest step accepted by the preserved source-model integrator.
  final stability =
      stiffness * step * step + 4 * damping * math.sqrt(stiffness) * step;
  if (!stability.isFinite || stability >= 4) {
    throw FormatException(
      '$name spring is unstable at the supported frame step.',
    );
  }
}
