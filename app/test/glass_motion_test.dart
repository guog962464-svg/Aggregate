import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aggregate/widgets/glass/glass_action_button.dart';
import 'package:aggregate/widgets/glass/glass_glyph.dart';
import 'package:aggregate/widgets/glass/glass_motion.dart';

void main() {
  group('GlassMotionController', () {
    late ManualGlassMotionClock clock;
    late GlobalKey<GlassMotionScopeState> scopeKey;

    setUp(() {
      clock = ManualGlassMotionClock();
      scopeKey = GlobalKey<GlassMotionScopeState>();
    });

    testWidgets(
      '12 action families use smooth sin-squared energy and exact durations',
      (tester) async {
        await _mountMotionScope(tester, scopeKey, clock);
        addTearDown(() => _cleanup(tester, clock));
        const cases = <(GlassGlyph, GlassMotionAction)>[
          (GlassGlyph.play, GlassMotionAction.play),
          (GlassGlyph.pause, GlassMotionAction.pause),
          (GlassGlyph.plus, GlassMotionAction.add),
          (GlassGlyph.refresh, GlassMotionAction.refresh),
          (GlassGlyph.copy, GlassMotionAction.copy),
          (GlassGlyph.save, GlassMotionAction.save),
          (GlassGlyph.search, GlassMotionAction.search),
          (GlassGlyph.externalLink, GlassMotionAction.open),
          (GlassGlyph.stop, GlassMotionAction.stop),
          (GlassGlyph.trash, GlassMotionAction.remove),
          (GlassGlyph.network, GlassMotionAction.connect),
          (GlassGlyph.shield, GlassMotionAction.allowAccess),
        ];
        for (final (glyph, action) in cases) {
          final controller = _controller(scopeKey, glyph);
          final idleController = _controller(scopeKey, glyph);
          expect(GlassMotionActionDetails.forGlyph(glyph), action);
          final beforeClick = controller.sample;
          controller.trigger();
          _expectDotPosesClose(controller.sample, beforeClick);
          expect(controller.sample.energy, 0);
          final duration = action.duration;
          for (final (fraction, expectedEnergy) in const <(double, double)>[
            (0, 0),
            (.25, .5),
            (.5, 1),
            (.75, .5),
            (1, 0),
          ]) {
            final sample = controller.sampleAt(
              Duration(
                microseconds: (duration.inMicroseconds * fraction).round(),
              ),
            );
            expect(sample.action, action);
            expect(sample.energy, closeTo(expectedEnergy, .00001));
            expect(sample.actionProgress, inInclusiveRange(0, 1));
          }
          _expectDotPosesClose(
            controller.sampleAt(duration),
            idleController.sampleAt(duration),
          );
          idleController.dispose();
          controller.dispose();
        }
      },
    );

    testWidgets(
      'ten repeated clicks preserve the in-flight glyph pose and energy',
      (tester) async {
        await _mountMotionScope(tester, scopeKey, clock);
        addTearDown(() => _cleanup(tester, clock));
        final controller = _controller(scopeKey, GlassGlyph.refresh);
        controller.trigger();
        var previousProgress = 0.0;
        for (var index = 1; index < 10; index++) {
          clock.advanceBy(const Duration(milliseconds: 100));
          final before = controller.sample;
          controller.trigger();
          final after = controller.sample;
          expect(_dotTuples(after), _dotTuples(before));
          expect(after.energy, closeTo(before.energy, .00001));
          expect(after.actionProgress, greaterThanOrEqualTo(previousProgress));
          previousProgress = after.actionProgress;
        }
        controller.dispose();
      },
    );

    testWidgets(
      'pose samples are independent of 30, 60, 120 Hz and irregular cadence',
      (tester) async {
        await _mountMotionScope(tester, scopeKey, clock);
        addTearDown(() => _cleanup(tester, clock));
        final checkpoints = [
          const Duration(milliseconds: 127),
          const Duration(milliseconds: 284),
          const Duration(milliseconds: 517),
        ];
        final reference = <Duration, GlassMotionSample>{};
        for (final checkpoint in checkpoints) {
          final controller = _controller(scopeKey, GlassGlyph.refresh);
          controller.trigger();
          reference[checkpoint] = controller.sampleAt(checkpoint);
          controller.dispose();
        }

        for (final cadence in [30, 60, 120]) {
          final sampleClock = ManualGlassMotionClock();
          final sampleScopeKey = GlobalKey<GlassMotionScopeState>();
          await tester.pumpWidget(
            MaterialApp(
              home: GlassMotionScope(
                key: sampleScopeKey,
                clock: sampleClock,
                child: const SizedBox(),
              ),
            ),
          );
          await tester.pump();
          final controller = _controller(sampleScopeKey, GlassGlyph.refresh);
          controller.trigger();
          final step = Duration(microseconds: (1000000 / cadence).round());
          var time = Duration.zero;
          for (final checkpoint in checkpoints) {
            while (time < checkpoint) {
              time = time + step < checkpoint ? time + step : checkpoint;
              sampleClock.advanceTo(time);
            }
            expect(
              _dotTuples(controller.sample),
              _dotTuples(reference[checkpoint]!),
            );
          }
          controller.dispose();
          await tester.pumpWidget(const SizedBox.shrink());
          sampleClock.dispose();
        }

        final irregularClock = ManualGlassMotionClock();
        final irregularScopeKey = GlobalKey<GlassMotionScopeState>();
        await tester.pumpWidget(
          MaterialApp(
            home: GlassMotionScope(
              key: irregularScopeKey,
              clock: irregularClock,
              child: const SizedBox(),
            ),
          ),
        );
        await tester.pump();
        final irregular = _controller(irregularScopeKey, GlassGlyph.refresh)
          ..trigger();
        for (final time in const [
          Duration(milliseconds: 17),
          Duration(milliseconds: 91),
          Duration(milliseconds: 127),
          Duration(milliseconds: 284),
          Duration(milliseconds: 517),
        ]) {
          irregularClock.advanceTo(time);
          if (time == checkpoints[0] ||
              time == checkpoints[1] ||
              time == checkpoints[2]) {
            expect(_dotTuples(irregular.sample), _dotTuples(reference[time]!));
          }
        }
        irregular.dispose();
        await tester.pumpWidget(const SizedBox.shrink());
        irregularClock.dispose();
      },
    );

    testWidgets(
      'play and pause reversals start from the currently rendered dots',
      (tester) async {
        await _mountMotionScope(tester, scopeKey, clock);
        addTearDown(() => _cleanup(tester, clock));
        final controller = _controller(scopeKey, GlassGlyph.play);
        controller.setGlyph(GlassGlyph.pause);
        var lastTime = Duration.zero;
        for (final time in const [
          Duration(milliseconds: 100),
          Duration(milliseconds: 200),
          Duration(milliseconds: 350),
        ]) {
          clock.advanceBy(time - lastTime);
          lastTime = time;
          final before = controller.sample;
          controller.setGlyph(
            controller.glyph == GlassGlyph.pause
                ? GlassGlyph.play
                : GlassGlyph.pause,
          );
          final after = controller.sample;
          expect(_dotTuples(after), _dotTuples(before));
          expect(after.isMorphing, isTrue);
        }
        clock.advanceBy(const Duration(milliseconds: 360));
        final settled = controller.sample;
        expect(settled.isMorphing, isFalse);
        expect(
          settled.dots,
          hasLength(GlassGlyphFactory.pointsFor(controller.glyph).length),
        );
        controller.dispose();
      },
    );

    testWidgets('hover stays subtle and never starts refresh rotation', (
      tester,
    ) async {
      await _mountMotionScope(tester, scopeKey, clock);
      addTearDown(() => _cleanup(tester, clock));
      final controller = _controller(scopeKey, GlassGlyph.refresh);
      final still = _controller(scopeKey, GlassGlyph.refresh);
      controller.setInteraction(hovered: true, focused: false);
      clock.advanceBy(const Duration(milliseconds: 160));
      final sample = controller.sample;
      final idle = still.sampleAt(clock.now);
      expect(sample.energy, closeTo(.04, .00001));
      expect(sample.energy, lessThanOrEqualTo(.15));
      expect(sample.actionProgress, 0);
      expect(_dotTuples(sample), _dotTuples(idle));
      controller.setInteraction(hovered: false, focused: false);
      clock.advanceBy(const Duration(milliseconds: 320));
      expect(controller.sample.energy, closeTo(0, .00001));
      controller.dispose();
      still.dispose();
    });
  });

  testWidgets('reduced motion unregisters decoration but keeps tap behavior', (
    tester,
  ) async {
    final clock = ManualGlassMotionClock();
    final scopeKey = GlobalKey<GlassMotionScopeState>();
    addTearDown(() => _cleanup(tester, clock));
    var calls = 0;
    Widget buildPage(bool reducedMotion) => MaterialApp(
      home: GlassMotionScope(
        key: scopeKey,
        clock: clock,
        child: MediaQuery(
          data: MediaQueryData(disableAnimations: reducedMotion),
          child: Center(
            child: GlassActionButton(
              label: '刷新',
              glyph: GlassGlyph.refresh,
              onPressed: () => calls++,
            ),
          ),
        ),
      ),
    );
    await tester.pumpWidget(buildPage(true));
    await tester.pump();
    expect(scopeKey.currentState!.registeredClientCountForTesting, 0);
    final button = find.bySemanticsLabel('刷新');
    await tester.tap(button);
    expect(calls, 1);

    await tester.pumpWidget(buildPage(false));
    await tester.pump();
    expect(scopeKey.currentState!.registeredClientCountForTesting, 1);
    clock.advanceBy(const Duration(milliseconds: 100));
    await tester.tap(button);
    expect(calls, 2);
    expect(scopeKey.currentState!.registeredClientCountForTesting, 1);
  });

  testWidgets('fully offscreen buttons leave the shared clock', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 300);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    final clock = ManualGlassMotionClock();
    final scopeKey = GlobalKey<GlassMotionScopeState>();
    addTearDown(() => _cleanup(tester, clock));
    await tester.pumpWidget(
      MaterialApp(
        home: GlassMotionScope(
          key: scopeKey,
          clock: clock,
          child: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  const SizedBox(height: 420),
                  GlassActionButton(
                    label: '隐藏控件',
                    glyph: GlassGlyph.refresh,
                    onPressed: () {},
                  ),
                  const SizedBox(height: 420),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(scopeKey.currentState!.registeredClientCountForTesting, 0);
    tester.view.physicalSize = const Size(400, 500);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
    expect(scopeKey.currentState!.registeredClientCountForTesting, 1);
    tester.view.physicalSize = const Size(400, 300);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
    expect(scopeKey.currentState!.registeredClientCountForTesting, 0);
    await tester.drag(find.byType(Scrollable), const Offset(0, -300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(scopeKey.currentState!.registeredClientCountForTesting, 1);
    await tester.drag(find.byType(Scrollable), const Offset(0, 500));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(scopeKey.currentState!.registeredClientCountForTesting, 0);
  });

  testWidgets('TickerMode and app lifecycle resume at elapsed clock time', (
    tester,
  ) async {
    final clock = ManualGlassMotionClock();
    final scopeKey = GlobalKey<GlassMotionScopeState>();
    addTearDown(() => _cleanup(tester, clock));

    Widget buildPage(bool routeActive) => MaterialApp(
      home: TickerMode(
        enabled: routeActive,
        child: GlassMotionScope(
          key: scopeKey,
          clock: clock,
          child: const SizedBox(),
        ),
      ),
    );

    await tester.pumpWidget(buildPage(true));
    await tester.pump();
    final controller = _controller(scopeKey, GlassGlyph.refresh);
    var updates = 0;
    controller.addListener(() => updates++);
    controller.trigger();

    await tester.pumpWidget(buildPage(false));
    await tester.pump();
    final mutedUpdates = updates;
    clock.advanceBy(const Duration(milliseconds: 100));
    expect(updates, mutedUpdates);

    await tester.pumpWidget(buildPage(true));
    await tester.pump();
    expect(updates, greaterThan(mutedUpdates));
    expect(
      controller.sample.energy,
      closeTo(_pulseEnergy(100, GlassMotionAction.refresh.duration), .00001),
    );

    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.inactive,
    );
    await tester.pump();
    final backgroundUpdates = updates;
    clock.advanceBy(const Duration(milliseconds: 120));
    expect(updates, backgroundUpdates);
    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
    await tester.pump();
    expect(updates, greaterThan(backgroundUpdates));
    expect(
      controller.sample.energy,
      closeTo(_pulseEnergy(220, GlassMotionAction.refresh.duration), .00001),
    );
    controller.dispose();
  });

  testWidgets('dragging a pressed button outside cancels the operation', (
    tester,
  ) async {
    final clock = ManualGlassMotionClock();
    final scopeKey = GlobalKey<GlassMotionScopeState>();
    addTearDown(() => _cleanup(tester, clock));
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: GlassMotionScope(
          key: scopeKey,
          clock: clock,
          child: Scaffold(
            body: Center(
              child: GlassActionButton(
                label: '刷新',
                glyph: GlassGlyph.refresh,
                onPressed: () => calls++,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final button = find.bySemanticsLabel('刷新');
    final gesture = await tester.startGesture(tester.getCenter(button));
    await gesture.moveTo(const Offset(900, 900));
    await gesture.up();
    await tester.pump();
    expect(calls, 0);
    await tester.tap(button);
    expect(calls, 1);
  });

  testWidgets('ten accepted taps keep every existing business callback', (
    tester,
  ) async {
    final clock = ManualGlassMotionClock();
    final scopeKey = GlobalKey<GlassMotionScopeState>();
    addTearDown(() => _cleanup(tester, clock));
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: GlassMotionScope(
          key: scopeKey,
          clock: clock,
          child: Scaffold(
            body: Center(
              child: GlassActionButton(
                label: '刷新',
                glyph: GlassGlyph.refresh,
                onPressed: () => calls++,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final button = find.bySemanticsLabel('刷新');
    for (var index = 0; index < 10; index++) {
      await tester.tap(button);
      await tester.pump();
      if (index < 9) clock.advanceBy(const Duration(milliseconds: 100));
    }
    expect(calls, 10);
  });
}

Future<void> _mountMotionScope(
  WidgetTester tester,
  GlobalKey<GlassMotionScopeState> key,
  ManualGlassMotionClock clock,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: GlassMotionScope(key: key, clock: clock, child: const SizedBox()),
    ),
  );
  await tester.pump();
}

Future<void> _cleanup(WidgetTester tester, ManualGlassMotionClock clock) async {
  await tester.pumpWidget(const SizedBox.shrink());
  clock.dispose();
}

GlassMotionController _controller(
  GlobalKey<GlassMotionScopeState> scopeKey,
  GlassGlyph glyph,
) => GlassMotionController(initialGlyph: glyph, phaseSeed: 11)
  ..configure(scope: scopeKey.currentState, visible: true, motionAllowed: true);

List<(double, double, double)> _dotTuples(GlassMotionSample sample) {
  final result = <(double, double, double)>[
    for (final dot in sample.dots)
      if (dot.opacity > 0) (dot.position.dx, dot.position.dy, dot.opacity),
  ];
  result.sort((left, right) {
    final vertical = left.$2.compareTo(right.$2);
    if (vertical != 0) return vertical;
    final horizontal = left.$1.compareTo(right.$1);
    return horizontal != 0 ? horizontal : left.$3.compareTo(right.$3);
  });
  return result;
}

double _pulseEnergy(int milliseconds, Duration duration) {
  final phase = milliseconds / duration.inMilliseconds;
  final sine = math.sin(math.pi * phase);
  return sine * sine;
}

void _expectDotPosesClose(
  GlassMotionSample actual,
  GlassMotionSample expected,
) {
  expect(actual.dots, hasLength(expected.dots.length));
  for (var index = 0; index < actual.dots.length; index++) {
    expect(
      (actual.dots[index].position - expected.dots[index].position).distance,
      lessThan(.001),
    );
    expect(
      actual.dots[index].opacity,
      closeTo(expected.dots[index].opacity, .00001),
    );
  }
}
