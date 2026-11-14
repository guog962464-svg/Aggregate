import 'dart:convert';

import 'package:aggregate/features/settings/theme_switch_calibration.dart';
import 'package:aggregate/features/settings/theme_switch_simulation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'reference calibration round-trips without changing the source model',
    () {
      const reference = ThemeSwitchCalibration.reference;
      final decoded = ThemeSwitchCalibration.fromJson(
        jsonDecode(jsonEncode(reference.toJson())),
      );
      expect(decoded.toJson(), reference.toJson());
      final actual = ThemeSwitchSimulation(calibration: decoded);
      final expected = ThemeSwitchSimulation();
      actual.setLight(true);
      expected.setLight(true);
      for (var i = 0; i <= 90; i++) {
        actual.advance(i == 0 ? 0 : 1 / 60, i / 60);
        expected.advance(i == 0 ? 0 : 1 / 60, i / 60);
        _sameSnapshot(actual.snapshot, expected.snapshot);
      }
    },
  );

  test(
    'resolved particles can be injected independently of the generation seed',
    () {
      final original = ThemeSwitchSimulation(seed: 123456);
      final profile = ThemeSwitchCalibration(
        seed: 987654,
        particleParameters: original.particleParameters,
      );
      final injected = ThemeSwitchSimulation(
        calibration: ThemeSwitchCalibration.fromJson(profile.toJson()),
      );
      expect(injected.seed, 987654);
      expect(injected.particleParameters.length, 113);
      expect(() => injected.particleParameters.clear(), throwsUnsupportedError);
      expect(
        () => injected.calibration.particleParameters!.clear(),
        throwsUnsupportedError,
      );
      original.setLight(true);
      injected.setLight(true);
      for (var i = 0; i <= 90; i++) {
        original.advance(i == 0 ? 0 : 1 / 60, i / 60);
        injected.advance(i == 0 ? 0 : 1 / 60, i / 60);
        _sameSnapshot(injected.snapshot, original.snapshot);
      }
    },
  );

  test(
    'live model consumes fitted particle, motion, and energy parameters',
    () {
      final baseline = ThemeSwitchSimulation();
      final fittedParticles = baseline.particleParameters.toList();
      final old = fittedParticles[50];
      fittedParticles[50] = ThemeSwitchParticleParameters(
        delay: 0,
        curl: 32,
        lift: old.lift,
        stiffness: old.stiffness,
        drag: old.drag,
        phase: old.phase,
        twinkle: old.twinkle,
      );
      final fitted = ThemeSwitchSimulation(
        calibration: ThemeSwitchCalibration(
          particleParameters: fittedParticles,
          motion: const ThemeSwitchMotion(
            knobStiffness: 80,
            maxStretch: 7,
            verticalStretch: 0.2,
          ),
          optics: const ThemeSwitchOptics(lightIntensity: 2.3),
        ),
      );
      baseline.setPresentation(position: 0.5, velocity: 10);
      fitted.setPresentation(position: 0.5, velocity: 10);
      for (var i = 1; i <= 10; i++) {
        baseline.advance(1 / 60, i / 60);
        fitted.advance(1 / 60, i / 60);
      }
      expect(fitted.snapshot.halfWidth, 106);
      expect(fitted.snapshot.halfHeight, closeTo(97.6, 1e-12));
      expect(
        fitted.snapshot.particles[50].x,
        isNot(closeTo(baseline.snapshot.particles[50].x, 1e-6)),
      );
      fitted.snapTo(false);
      expect(fitted.snapshot.led, 2.3);
      fitted.setLight(true);
      baseline.snapTo(false);
      baseline.setLight(true);
      fitted.advance(0.03, 1);
      baseline.advance(0.03, 1);
      expect(fitted.position, lessThan(baseline.position));
    },
  );

  test('caller supplies the shared clock origin exactly once', () {
    final shifted = ThemeSwitchSimulation(
      calibration: const ThemeSwitchCalibration(timeOriginSeconds: 6.5),
    );
    final reference = ThemeSwitchSimulation();
    shifted.advanceRealtime(0, 6.5);
    reference.advanceRealtime(0, 6.5);
    _sameSnapshot(shifted.snapshot, reference.snapshot);
  });

  test('JSON input rejects nonfinite, malformed, and unstable profiles', () {
    final source = ThemeSwitchCalibration.reference.toJson();
    for (final invalid in [
      {...source, 'seed': -1},
      {...source, 'seed': 0x100000000},
      {...source, 'timeOriginSeconds': double.infinity},
      {...source, 'unrecognizedProfileField': 1},
      {...source, 'particleParameters': <Object?>[]},
      {
        ...source,
        'motion': {'phaseStiffness': 300, 'phaseDamping': 2},
      },
      {
        ...source,
        'optics': {'frost': double.nan},
      },
      {
        ...source,
        'optics': {'moonRgb': 0x1000000},
      },
    ]) {
      expect(
        () => ThemeSwitchCalibration.fromJson(invalid),
        throwsFormatException,
      );
    }
    final parameters = ThemeSwitchSimulation().particleParameters;
    final malformed = parameters.map((p) => p.toJson()).toList();
    malformed[0] = {...malformed.first, 'stiffness': 1000};
    expect(
      () => ThemeSwitchCalibration.fromJson({
        ...source,
        'particleParameters': malformed,
      }),
      throwsFormatException,
      reason: 'A bounded but numerically unstable particle spring must be rejected.',
    );
    malformed[0] = {...parameters.first.toJson(), 'delay': 0.9};
    expect(
      () => ThemeSwitchCalibration.fromJson({
        ...source,
        'particleParameters': malformed,
      }),
      throwsFormatException,
      reason: 'A morph must reach the sun endpoint before position 1.',
    );
  });
}

void _sameSnapshot(ThemeSwitchSnapshot actual, ThemeSwitchSnapshot expected) {
  expect(actual.position, expected.position);
  expect(actual.velocity, expected.velocity);
  expect(actual.theta, expected.theta);
  expect(actual.led, expected.led);
  expect(actual.particles.length, expected.particles.length);
  for (var i = 0; i < actual.particles.length; i++) {
    final a = actual.particles[i];
    final b = expected.particles[i];
    expect([a.x, a.y, a.size, a.alpha], [b.x, b.y, b.size, b.alpha]);
  }
}
