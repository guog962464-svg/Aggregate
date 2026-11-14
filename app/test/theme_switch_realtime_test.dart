import 'package:aggregate/features/settings/theme_switch_calibration.dart';
import 'package:aggregate/features/settings/theme_switch_simulation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('20, 30, 60 and 120 Hz advance the same live response and reversal', () {
    final expected = _sampleAtRefreshRate(60);
    for (final fps in [20, 30, 120]) {
      _samePresentation(_sampleAtRefreshRate(fps), expected);
    }
  });

  test(
    'irregular render intervals retain time instead of clamping each frame',
    () {
      final regular = ThemeSwitchSimulation()..setLight(true);
      final irregular = ThemeSwitchSimulation()..setLight(true);
      for (var i = 1; i <= 60; i++) {
        regular.advanceRealtime(1 / 60, i / 60);
      }
      var time = 0.0;
      for (var cycle = 0; cycle < 10; cycle++) {
        for (final dt in [0.005, 0.045, 0.012, 0.038]) {
          time += dt;
          irregular.advanceRealtime(dt, time);
        }
      }
      _samePresentation(irregular.snapshot, regular.snapshot);
    },
  );

  test(
    'long hidden intervals settle unheld motion and retain the real clock',
    () {
      final model = ThemeSwitchSimulation()..setLight(true);
      model.advanceRealtime(8, 8);
      final settled = model.snapshot;
      expect(settled.position, 1);
      expect(settled.velocity, 0);
      expect(settled.theme, 1);
      final sameClock = ThemeSwitchSimulation()..snapTo(true);
      sameClock.advance(0, 8);
      _samePresentation(settled, sameClock.snapshot);

      model.beginDrag();
      model.dragTo(0.4, 0);
      model.advanceRealtime(30, 38);
      expect(
        model.position,
        0.4,
        reason: 'A held knob must not snap to its target.',
      );
      _finiteGeometry(model.snapshot);
    },
  );

  test(
    'capturing overshoot and sending zero movement keeps the handle in place',
    () {
      for (final elasticity in [0.22, 0.4]) {
        final model = ThemeSwitchSimulation(
          calibration: ThemeSwitchCalibration(
            motion: ThemeSwitchMotion(elasticity: elasticity),
          ),
        );
        for (final position in [-0.08, 0.4, 1.05]) {
          model.setPresentation(position: position, velocity: 0);
          final anchor = model.unresistedPosition;
          final before = model.snapshot;
          model.beginDrag();
          model.dragTo(anchor, 0, elapsedSeconds: 1 / 60);
          expect(model.position, closeTo(position, 1e-12));
          expect(model.snapshot.knobX, closeTo(before.knobX, 1e-10));
          model.releaseDrag(cancel: true);
        }
      }
    },
  );

  test(
    'extreme outside drags and release always produce valid finite geometry',
    () {
      final model = ThemeSwitchSimulation();
      for (final position in [-100.0, 100.0, 1e308, -1e308]) {
        model.dragTo(position, position, elapsedSeconds: 0.001);
        _finiteGeometry(model.snapshot);
        model.advanceRealtime(1 / 60, 1);
        _finiteGeometry(model.snapshot);
        model.releaseDrag();
        for (var frame = 1; frame <= 120; frame++) {
          model.advanceRealtime(1 / 60, 1 + frame / 60);
          _finiteGeometry(model.snapshot);
        }
      }
    },
  );
}

ThemeSwitchSnapshot _sampleAtRefreshRate(int fps) {
  final model = ThemeSwitchSimulation()
    ..setLight(true)
    ..setHovered(true);
  for (var frame = 1; frame <= fps; frame++) {
    if (frame == (fps * 0.2).round() + 1) model.setLight(false);
    model.advanceRealtime(1 / fps, frame / fps);
  }
  return model.snapshot;
}

void _samePresentation(
  ThemeSwitchSnapshot actual,
  ThemeSwitchSnapshot expected,
) {
  final scalars = [
    (actual.position, expected.position),
    (actual.velocity, expected.velocity),
    (actual.theme, expected.theme),
    (actual.knobX, expected.knobX),
    (actual.halfWidth, expected.halfWidth),
    (actual.halfHeight, expected.halfHeight),
    (actual.theta, expected.theta),
    (actual.led, expected.led),
  ];
  for (final pair in scalars) {
    expect(pair.$1, closeTo(pair.$2, 1e-9));
  }
  for (var i = 0; i < actual.particles.length; i++) {
    final a = actual.particles[i];
    final b = expected.particles[i];
    for (final pair in [
      (a.x, b.x),
      (a.y, b.y),
      (a.size, b.size),
      (a.alpha, b.alpha),
    ]) {
      expect(pair.$1, closeTo(pair.$2, 1e-9));
    }
  }
}

void _finiteGeometry(ThemeSwitchSnapshot frame) {
  expect(
    [
      frame.position,
      frame.velocity,
      frame.theme,
      frame.knobX,
      frame.halfWidth,
      frame.halfHeight,
      frame.radius,
      frame.theta,
      frame.led,
    ].every((value) => value.isFinite),
    isTrue,
  );
  expect(frame.halfWidth, greaterThanOrEqualTo(2));
  expect(frame.halfHeight, greaterThanOrEqualTo(2));
  expect(frame.radius, greaterThan(0));
  expect(frame.radius, lessThan(frame.halfWidth));
  expect(frame.radius, lessThan(frame.halfHeight));
  for (final particle in frame.particles) {
    expect(
      [
        particle.x,
        particle.y,
        particle.size,
        particle.alpha,
      ].every((v) => v.isFinite),
      isTrue,
    );
  }
}
