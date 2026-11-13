import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:aggregate/features/settings/glass_theme_switch.dart';
import 'package:aggregate/features/settings/theme_switch_simulation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

const _referenceRoot = String.fromEnvironment('THEME_SWITCH_REFERENCE_ROOT');
const _exportRoot = String.fromEnvironment('THEME_SWITCH_EXPORT_DIR');
const _modelInput = String.fromEnvironment('THEME_SWITCH_MODEL_INPUT');
const _seed = int.fromEnvironment(
  'THEME_SWITCH_SEED',
  defaultValue: 0x6d2b79f5,
);
const _timeOffsetText = String.fromEnvironment(
  'THEME_SWITCH_TIME_OFFSET',
  defaultValue: '6.5',
);
const _useMeasuredTheta = bool.fromEnvironment(
  'THEME_SWITCH_USE_MEASURED_THETA',
);
const _useFittedTheme = bool.fromEnvironment('THEME_SWITCH_USE_FITTED_THEME');
const _useFittedGeometry = bool.fromEnvironment(
  'THEME_SWITCH_USE_FITTED_GEOMETRY',
);
const _size = Size(720, 540);
const _scale = 0.76;
const _center = Offset(360, 267);
const _sourceCropTop = 444;

/// Explicit reference export. A normal `flutter test` does no file or GPU work.
///
/// flutter test --no-pub tool/theme_switch_reference_frames_test.dart \
///   --dart-define=THEME_SWITCH_REFERENCE_ROOT=/tmp/aggregate-reference-exact \
///   --dart-define=THEME_SWITCH_EXPORT_DIR=/tmp/aggregate-native-frames
void main() {
  testWidgets(
    'export the theme switch at source presentation timestamps',
    (tester) async {
      final output = Directory(_exportRoot).absolute;
      output.createSync(recursive: true);
      tester.view.physicalSize = _size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final program = await tester.runAsync(ThemeSwitchArtwork.loadProgram);
      expect(program, isNotNull);
      if (_modelInput.isNotEmpty) {
        await _exportModelFrames(tester, program!, output);
        await tester.pumpWidget(const SizedBox.shrink());
        return;
      }
      expect(
        _referenceRoot,
        isNotEmpty,
        reason: 'Set THEME_SWITCH_REFERENCE_ROOT for an explicit export.',
      );
      final timeOffset = double.parse(_timeOffsetText);
      expect(timeOffset.isFinite, isTrue);

      final root = Directory(_referenceRoot).absolute.path;
      final renders = Directory('${output.path}/renders');
      renders.createSync(recursive: true);
      final source = jsonDecode(
        File('$root/frames/frames.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final frames = (source['frames'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map(_ReferenceFrame.fromJson)
          .toList();
      final rawMeasurements = _readMeasurements(
        File('$root/measured-timeline.csv').readAsStringSync(),
      );
      expect(frames, isNotEmpty);
      expect(
        rawMeasurements.length,
        frames.length,
        reason: 'Every source frame needs a timeline row.',
      );
      final themeFitPath = '$root/fitted-optics.csv';
      final fittedCsv = _useFittedTheme || _useFittedGeometry
          ? File(themeFitPath).readAsStringSync()
          : '';
      final themeFits = _useFittedTheme
          ? _readFittedThemes(fittedCsv)
          : const <int, _FittedTheme>{};
      final geometryFits = _useFittedGeometry
          ? _readFittedGeometry(fittedCsv)
          : const <int, _FittedGeometry>{};
      if (_useFittedTheme) {
        expect(
          themeFits.length,
          frames.length,
          reason: 'Fitted background theme needs one value per source frame.',
        );
      }
      if (_useFittedGeometry) {
        expect(
          geometryFits.length,
          frames.length,
          reason: 'Fitted geometry needs one status per source frame.',
        );
      }
      final measurements = rawMeasurements.map((measurement) {
        final geometry = geometryFits[measurement.index];
        return geometry != null && geometry.eligible
            ? measurement.withGeometryCenter(geometry.centerX)
            : measurement;
      }).toList();
      final byIndex = {for (final item in measurements) item.index: item};
      final velocityEstimates = _estimateVelocities(measurements);

      final simulation = ThemeSwitchSimulation(seed: _seed);
      final manifestFrames = <Map<String, Object?>>[];
      var previousPts = frames.first.pts;
      _Measurement? previousMeasurement;
      double? previousVelocity;

      for (var i = 0; i < frames.length; i++) {
        final frame = frames[i];
        final measurement = byIndex[frame.index];
        expect(
          measurement,
          isNotNull,
          reason: 'Missing measurement for source frame ${frame.index}.',
        );
        final observed = measurement!;
        expect(
          (frame.pts - observed.pts).abs(),
          lessThan(0.000001),
          reason: 'Source and measured timeline PTS must agree.',
        );
        final dt = i == 0 ? 0.0 : frame.pts - previousPts;
        expect(dt, greaterThanOrEqualTo(0));
        final velocity = velocityEstimates[frame.index]!;
        final integrationSteps = previousMeasurement == null
            ? _initializeMeasuredState(
                simulation,
                observed,
                velocity.value,
                timeOffset,
              )
            : _integrateMeasuredInterval(
                simulation,
                previousMeasurement,
                previousVelocity!,
                observed,
                velocity.value,
                timeOffset,
              );
        final simulated = simulation.snapshot;
        var renderFrame = _useMeasuredTheta && observed.angle != null
            ? simulated.copyWith(theta: observed.angle! * math.pi / 180)
            : simulated;
        final themeFit = themeFits[frame.index];
        if (_useFittedTheme) {
          expect(
            themeFit,
            isNotNull,
            reason: 'Fitted background theme is missing frame ${frame.index}.',
          );
          expect(
            (themeFit!.pts - frame.pts).abs(),
            lessThan(0.000001),
            reason: 'Background fit and source frame PTS must agree.',
          );
          renderFrame = renderFrame.copyWith(theme: themeFit.theme);
        }
        final geometryFit = geometryFits[frame.index];
        if (_useFittedGeometry) {
          expect(
            geometryFit,
            isNotNull,
            reason: 'Fitted geometry is missing frame ${frame.index}.',
          );
          expect(
            (geometryFit!.pts - frame.pts).abs(),
            lessThan(0.000001),
            reason: 'Geometry fit and source frame PTS must agree.',
          );
          if (geometryFit.eligible) {
            final halfWidth = geometryFit.halfWidth / _scale;
            final halfHeight = geometryFit.halfHeight / _scale;
            renderFrame = renderFrame.copyWith(
              knobX: (geometryFit.centerX - _center.dx) / _scale,
              halfWidth: halfWidth,
              halfHeight: halfHeight,
              radius: math.min(58, math.min(halfWidth - 1, halfHeight - 1)),
            );
          }
        }
        final relativePath =
            'renders/frame_${frame.index.toString().padLeft(4, '0')}.png';
        final renderPath = '${output.path}/$relativePath';
        await _captureSnapshot(
          tester,
          program!,
          renderFrame,
          time: frame.pts + timeOffset,
          outputPath: renderPath,
          elapsed: Duration(microseconds: (dt * 1000000).round()),
        );

        manifestFrames.add({
          'index': frame.index,
          'pts': frame.pts,
          'dt': dt,
          'shaderTime': frame.pts + timeOffset,
          'referencePath': '$root/frames/${frame.file}',
          'renderPath': renderPath,
          'renderRelativePath': relativePath,
          'confidence': 'low',
          'comparisonEligible':
              !observed.loopBlend &&
              geometryFit?.exclude != 'player_loop_blend',
          'confidenceNotes': [
            'Geometry and glow fields are estimates, not exact recovered state.',
            'The recorded particle seed and shader time origin are unknown.',
            if (_useFittedTheme) 'Background fitting changes only optical theme/color; geometry and icon morphology still use the separate estimated position trajectory.',
            if (_useFittedGeometry) 'Geometry edge fitting is a measurement hypothesis for comparison, not recovered ground-truth input.',
            if (geometryFit != null && !geometryFit.eligible)
              'Geometry was not applied: ${geometryFit.fallbackReason}; legacy glyph-center motion and simulated dimensions are retained.',
            if (observed.loopBlend) 'The reference is a gallery loop blend; its measured knob state is unreliable.',
            if (observed.note.isNotEmpty) observed.note,
          ],
          'measurement': observed.fields,
          'positionSource': observed.geometryCenterUsed
              ? 'fitted-body-center'
              : 'legacy-glyph-center',
          if (themeFit != null)
            'themeFit': {
              'source': themeFitPath,
              'appliedFields': ['theme'],
              'theme': themeFit.theme,
              'theme_spatial_mad': themeFit.spatialMad,
              'background_rmse': themeFit.backgroundRmse,
              'geometryApplied': false,
            },
          if (geometryFit != null)
            'geometryFit': geometryFit.manifest(themeFitPath),
          'velocityEstimate': {
            'method': 'local linear regression within +/- 1/30 second',
            'sampleCount': velocity.sampleCount,
            'normalizedUnitsPerSecond': velocity.value,
          },
          'integration': {
            'steps': integrationSteps,
            'maximumStepSeconds': 1 / 60,
            'trajectory': 'linear interpolation between adjacent measured position/velocity values',
          },
          'state': _stateParameters(renderFrame),
        });
        previousPts = frame.pts;
        previousMeasurement = observed;
        previousVelocity = velocity.value;
      }

      await tester.pumpWidget(const SizedBox.shrink());
      final manifest = {
        'schemaVersion': 1,
        'referenceRoot': root,
        'exportRoot': output.path,
        'seed': _seed,
        'shaderTimeOffset': timeOffset,
        'sourceAnimationFramesPerSecond': 60,
        'maximumIntegrationStepSeconds': 1 / 60,
        'useMeasuredTheta': _useMeasuredTheta,
        'useFittedTheme': _useFittedTheme,
        'useFittedGeometry': _useFittedGeometry,
        if (_useFittedTheme)
          'fittedThemeSource': {
            'path': themeFitPath,
            'appliedFields': ['theme'],
            'uncertaintyFields': ['theme_spatial_mad', 'background_rmse'],
            'geometryApplied': false,
          },
        if (_useFittedGeometry)
          'fittedGeometrySource': {
            'path': themeFitPath,
            'minimumConfidence': 0.65,
            'excludedStatus': 'player_loop_blend',
            'appliedFields': ['knobX', 'halfWidth', 'halfHeight', 'radius'],
            'motionInput': 'eligible body-center observations; otherwise legacy glyph-center fallback',
            'centerYApplied': false,
            'scaleApplied': false,
            'thetaMeasurementCoordinatesChanged': false,
            'groundTruthEstablished': false,
          },
        'frameCount': manifestFrames.length,
        'scene': {
          'width': 720,
          'height': 540,
          'devicePixelRatio': 1,
          'scale': _scale,
          'centerX': _center.dx,
          'centerY': _center.dy,
          'referenceCrop': {
            'x': 0,
            'y': _sourceCropTop,
            'width': 720,
            'height': 540,
          },
        },
        'positionMethod': _useFittedGeometry
            ? 'eligible fitted body center: inverse knob travel, including 110-unit overshoot; low-confidence fallback: (glyph center - 360) / (0.76 * 208) + 0.5'
            : '(center_x_est - 360) / (0.76 * 208) + 0.5',
        'limitations': [
          'All timeline observations are low-confidence fitted measurements.',
          'The source pointer and gallery blend require explicit comparison masks.',
          'Rendered frames establish a measurable baseline, not proof of exact fidelity.',
          if (_useFittedTheme) 'The fitted background theme does not validate or override knob geometry.',
          if (_useFittedGeometry) 'Body-edge geometry fitting is confidence gated; retained fallback observations can affect velocity interpolation across mixed-confidence intervals.',
          if (_useFittedGeometry) 'Scene center Y, scene scale, and measured glow-angle coordinates remain fixed and are not validated by geometry fitting.',
        ],
        'frames': manifestFrames,
      };
      File(
        '${output.path}/manifest.json',
      ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(manifest));
      File('${output.path}/manifest.csv')
          .writeAsStringSync(_csvManifest(manifestFrames));
      // ignore: avoid_print
      print('Exported ${manifestFrames.length} frames to ${output.path}');
    },
    skip: _exportRoot.isEmpty,
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

int _initializeMeasuredState(
  ThemeSwitchSimulation simulation,
  _Measurement measurement,
  double velocity,
  double timeOffset,
) {
  simulation.setPresentation(
    position: measurement.position,
    velocity: velocity,
  );
  simulation.advance(0, measurement.pts + timeOffset);
  return 0;
}

int _integrateMeasuredInterval(
  ThemeSwitchSimulation simulation,
  _Measurement previous,
  double previousVelocity,
  _Measurement current,
  double currentVelocity,
  double timeOffset,
) {
  final interval = current.pts - previous.pts;
  if (interval <= 0) {
    return _initializeMeasuredState(
      simulation,
      current,
      currentVelocity,
      timeOffset,
    );
  }
  var cursor = previous.pts;
  var steps = 0;
  while (cursor + 1e-12 < current.pts) {
    final next = math.min(current.pts, cursor + 1 / 60);
    final fraction = (next - previous.pts) / interval;
    simulation.setPresentation(
      position:
          previous.position + (current.position - previous.position) * fraction,
      velocity:
          previousVelocity + (currentVelocity - previousVelocity) * fraction,
    );
    simulation.advance(next - cursor, next + timeOffset);
    cursor = next;
    steps++;
  }
  return steps;
}

Future<void> _captureSnapshot(
  WidgetTester tester,
  ui.FragmentProgram program,
  ThemeSwitchSnapshot frame, {
  required double time,
  required String outputPath,
  Duration elapsed = Duration.zero,
}) async {
  const boundaryKey = ValueKey('theme-switch-reference-boundary');
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        data: const MediaQueryData(size: _size, devicePixelRatio: 1),
        child: RepaintBoundary(
          key: boundaryKey,
          child: SizedBox.fromSize(
            size: _size,
            child: ThemeSwitchArtwork(
              frame: frame,
              time: time,
              program: program,
              scale: _scale,
              center: _center,
            ),
          ),
        ),
      ),
    ),
    duration: elapsed,
  );
  expect(
    tester.takeException(),
    isNull,
    reason: 'Rendering failed for $outputPath.',
  );
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(boundaryKey),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      expect(image.width, 720);
      expect(image.height, 540);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      expect(png, isNotNull);
      await File(outputPath).writeAsBytes(
        png!.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
      );
    } finally {
      image.dispose();
    }
  });
}

Future<void> _exportModelFrames(
  WidgetTester tester,
  ui.FragmentProgram program,
  Directory output,
) async {
  final input = File(_modelInput).absolute;
  final model = (jsonDecode(input.readAsStringSync()) as List<dynamic>)
      .cast<Map<String, dynamic>>();
  final byIndex = {for (final item in model) (item['i'] as num).toInt(): item};
  final frames = <Map<String, Object?>>[];
  var previousTime = 0.0;
  for (final index in const [0, 60, 70, 90, 110, 150]) {
    final row = byIndex[index];
    expect(row, isNotNull, reason: 'Model input has no frame $index.');
    final data = row!;
    double value(String key) => (data[key] as num).toDouble();
    final halfWidth = value('hx');
    final halfHeight = value('hy');
    final snapshot = ThemeSwitchSnapshot(
      position: value('p'),
      velocity: value('v'),
      theme: value('theme'),
      knobX: value('x'),
      halfWidth: halfWidth,
      halfHeight: halfHeight,
      radius: math.min(58, math.min(halfWidth - 1, halfHeight - 1)),
      theta: value('theta'),
      led: value('led'),
      lift: value('lift'),
      particles: (data['particles'] as List<dynamic>)
          .map((raw) {
            final particle = (raw as List<dynamic>).cast<num>();
            return ThemeSwitchParticle(
              x: particle[0].toDouble(),
              y: particle[1].toDouble(),
              size: particle[2].toDouble(),
              alpha: particle[3].toDouble(),
            );
          })
          .toList(growable: false),
    );
    final time = value('time');
    final renderPath = '${output.path}/native-render-$index.png';
    await _captureSnapshot(
      tester,
      program,
      snapshot,
      time: time,
      outputPath: renderPath,
      elapsed: Duration(
        microseconds: ((time - previousTime) * 1000000).round(),
      ),
    );
    frames.add({
      'index': index,
      'pts': time,
      'dt': time - previousTime,
      'referencePath': '${input.parent.path}/original-render-$index.png',
      'renderPath': renderPath,
      'comparisonEligible': true,
      'confidence': 'controlled-model-state',
      'state': _stateParameters(snapshot),
    });
    previousTime = time;
  }
  File('${output.path}/manifest.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({
      'schemaVersion': 1,
      'sourceMode': 'model-input',
      'modelInput': input.path,
      'exportRoot': output.path,
      'frameCount': frames.length,
      'scene': {
        'width': 720,
        'height': 540,
        'devicePixelRatio': 1,
        'scale': _scale,
        'centerX': _center.dx,
        'centerY': _center.dy,
      },
      'limitations': [
        'This mode compares optical implementations with identical supplied state.',
        'It does not establish identity with the recorded pointer motion or random seed.',
      ],
      'frames': frames,
    }),
  );
  File('${output.path}/manifest.csv').writeAsStringSync(_csvManifest(frames));
  // ignore: avoid_print
  print('Exported ${frames.length} controlled model frames to ${output.path}');
}

Map<String, Object?> _stateParameters(ThemeSwitchSnapshot frame) => {
  'position': frame.position,
  'velocity': frame.velocity,
  'theme': frame.theme,
  'knobX': frame.knobX,
  'halfWidth': frame.halfWidth,
  'halfHeight': frame.halfHeight,
  'radius': frame.radius,
  'theta': frame.theta,
  'led': frame.led,
  'lift': frame.lift,
  'particleCount': frame.particles.length,
};

class _ReferenceFrame {
  const _ReferenceFrame(this.index, this.pts, this.file);

  factory _ReferenceFrame.fromJson(Map<String, dynamic> json) =>
      _ReferenceFrame(
        (json['index'] as num).toInt(),
        (json['pts'] as num).toDouble(),
        json['file'] as String,
      );

  final int index;
  final double pts;
  final String file;
}

class _Measurement {
  _Measurement(this.fields, {double? geometryCenterX})
    : _geometryCenterX = geometryCenterX,
      index = int.parse(fields['index']!),
      pts = double.parse(fields['pts']!),
      centerX = geometryCenterX ?? double.parse(fields['center_x_est']!),
      angle = double.tryParse(fields['glow_angle_screen_deg_est'] ?? ''),
      loopBlend = fields['loop_blend']?.toLowerCase() == 'true',
      note = fields['occlusion_note'] ?? '';

  final Map<String, String> fields;
  final double? _geometryCenterX;
  final int index;
  final double pts;
  final double centerX;
  final double? angle;
  final bool loopBlend;
  final String note;

  bool get geometryCenterUsed => _geometryCenterX != null;

  _Measurement withGeometryCenter(double value) =>
      _Measurement(fields, geometryCenterX: value);

  double get position {
    final designX = (centerX - _center.dx) / _scale;
    if (geometryCenterUsed) {
      final halfTravel = ThemeSwitchSimulation.knobTravel / 2;
      if (designX < -halfTravel) return (designX + halfTravel) / 110;
      if (designX > halfTravel) return 1 + (designX - halfTravel) / 110;
    }
    return designX / ThemeSwitchSimulation.knobTravel + 0.5;
  }
}

class _FittedGeometry {
  _FittedGeometry(this.fields)
    : index = int.parse(fields['frame']!),
      pts = double.parse(fields['pts']!),
      centerX = double.parse(fields['knob_center_x']!),
      centerY = double.parse(fields['knob_center_y']!),
      halfWidth = double.parse(fields['halfwidthpx']!),
      halfHeight = double.parse(fields['halfheightpx']!),
      confidence = double.parse(fields['confidence']!),
      exclude = fields['exclude'] ?? '',
      status = fields['geometry_status'] ?? 'unknown';

  final Map<String, String> fields;
  final int index;
  final double pts;
  final double centerX;
  final double centerY;
  final double halfWidth;
  final double halfHeight;
  final double confidence;
  final String exclude;
  final String status;

  bool get eligible => confidence >= 0.65 && exclude != 'player_loop_blend';

  String get fallbackReason => exclude == 'player_loop_blend'
      ? 'excluded player loop blend'
      : 'confidence $confidence is below 0.65';

  Map<String, Object?> manifest(String source) => {
    'source': source,
    'status': status,
    'confidence': confidence,
    'exclude': exclude,
    'geometryApplied': eligible,
    'groundTruthEstablished': false,
    'appliedFields': eligible
        ? ['knobX', 'halfWidth', 'halfHeight', 'radius']
        : <String>[],
    'positionInputSource': eligible
        ? 'fitted-body-center'
        : 'legacy-glyph-center-fallback',
    if (!eligible) 'fallbackReason': fallbackReason,
    'observedSourcePixels': {
      'centerX': centerX,
      'centerY': centerY,
      'halfWidth': halfWidth,
      'halfHeight': halfHeight,
    },
    'sceneCenterYApplied': false,
    'sceneScaleApplied': false,
    'thetaMeasurementCoordinatesChanged': false,
    'errorsAndSupport': {
      for (final key in const [
        'edge_alignment_median_abs_px',
        'edge_alignment_p75_px',
        'edge_alignment_mad_px',
        'body_edge_support',
        'top_edge_coverage',
        'top_edge_samples',
        'edge_score',
        'edge_alternative_score',
        'geometry_resolution_px',
      ])
        key: double.tryParse(fields[key] ?? ''),
    },
  };
}

Map<int, _FittedGeometry> _readFittedGeometry(String source) {
  final rows = _parseCsv(source);
  if (rows.length < 2) {
    throw const FormatException('Fitted geometry CSV has no data.');
  }
  final header = rows.first;
  final fitted = <int, _FittedGeometry>{};
  for (final row in rows.skip(1)) {
    if (row.every((cell) => cell.isEmpty)) continue;
    if (row.length != header.length) {
      throw const FormatException('Fitted geometry CSV column count changed.');
    }
    final item = _FittedGeometry({
      for (var i = 0; i < header.length; i++) header[i]: row[i],
    });
    if (![
          item.pts,
          item.centerX,
          item.centerY,
          item.halfWidth,
          item.halfHeight,
          item.confidence,
        ].every((value) => value.isFinite) ||
        item.halfWidth <= 0 ||
        item.halfHeight <= 0) {
      throw FormatException('Invalid fitted geometry for frame ${item.index}.');
    }
    if (fitted.containsKey(item.index)) {
      throw FormatException('Duplicate fitted geometry frame ${item.index}.');
    }
    fitted[item.index] = item;
  }
  return fitted;
}

class _FittedTheme {
  const _FittedTheme({
    required this.index,
    required this.pts,
    required this.theme,
    required this.spatialMad,
    required this.backgroundRmse,
  });

  final int index;
  final double pts;
  final double theme;
  final double spatialMad;
  final double backgroundRmse;
}

Map<int, _FittedTheme> _readFittedThemes(String source) {
  final rows = _parseCsv(source);
  if (rows.length < 2) {
    throw const FormatException('Fitted theme CSV has no data.');
  }
  final header = rows.first;
  final fitted = <int, _FittedTheme>{};
  for (final row in rows.skip(1)) {
    if (row.every((cell) => cell.isEmpty)) continue;
    if (row.length != header.length) {
      throw const FormatException('Fitted theme CSV column count changed.');
    }
    final fields = {for (var i = 0; i < header.length; i++) header[i]: row[i]};
    double value(String key) {
      final parsed = double.parse(fields[key]!);
      if (!parsed.isFinite) {
        throw FormatException('Nonfinite fitted theme $key.');
      }
      return parsed;
    }

    final index = int.parse(fields['frame']!);
    final theme = value('theme');
    if (theme < 0 || theme > 1) {
      throw const FormatException('Fitted theme is outside 0..1.');
    }
    if (fitted.containsKey(index)) {
      throw FormatException('Duplicate fitted theme frame $index.');
    }
    // Only the fitted color parameter and its uncertainty measures are read.
    // Experimental geometry columns in this CSV intentionally have no effect.
    fitted[index] = _FittedTheme(
      index: index,
      pts: value('pts'),
      theme: theme,
      spatialMad: value('theme_spatial_mad'),
      backgroundRmse: value('background_rmse'),
    );
  }
  return fitted;
}

List<_Measurement> _readMeasurements(String source) {
  final rows = _parseCsv(source);
  if (rows.length < 2) throw const FormatException('Measured CSV has no data.');
  final header = rows.first;
  return rows.skip(1).where((row) => row.any((cell) => cell.isNotEmpty)).map((
    row,
  ) {
    if (row.length != header.length) {
      throw const FormatException('Measured CSV column count changed.');
    }
    return _Measurement({
      for (var i = 0; i < header.length; i++) header[i]: row[i],
    });
  }).toList();
}

List<List<String>> _parseCsv(String source) {
  final rows = <List<String>>[];
  var row = <String>[];
  var cell = StringBuffer();
  var quoted = false;
  for (var i = 0; i < source.length; i++) {
    final char = source[i];
    if (char == '"') {
      if (quoted && i + 1 < source.length && source[i + 1] == '"') {
        cell.write('"');
        i++;
      } else {
        quoted = !quoted;
      }
    } else if (char == ',' && !quoted) {
      row.add(cell.toString());
      cell = StringBuffer();
    } else if ((char == '\n' || char == '\r') && !quoted) {
      row.add(cell.toString());
      rows.add(row);
      row = [];
      cell = StringBuffer();
      if (char == '\r' && i + 1 < source.length && source[i + 1] == '\n') i++;
    } else {
      cell.write(char);
    }
  }
  if (quoted) throw const FormatException('Unclosed CSV quote.');
  if (cell.isNotEmpty || row.isNotEmpty) {
    row.add(cell.toString());
    rows.add(row);
  }
  return rows;
}

Map<int, ({double value, int sampleCount})> _estimateVelocities(
  List<_Measurement> measurements,
) {
  final result = <int, ({double value, int sampleCount})>{};
  for (var i = 0; i < measurements.length; i++) {
    final current = measurements[i];
    var neighbors = measurements
        .where((point) => (point.pts - current.pts).abs() <= 1 / 30)
        .toList();
    if (neighbors.length < 2) {
      neighbors = measurements.sublist(
        math.max(0, i - 1),
        math.min(measurements.length, i + 2),
      );
    }
    var timeMean = 0.0;
    var positionMean = 0.0;
    for (final point in neighbors) {
      timeMean += point.pts;
      positionMean += point.position;
    }
    timeMean /= neighbors.length;
    positionMean /= neighbors.length;
    var covariance = 0.0;
    var variance = 0.0;
    for (final point in neighbors) {
      final timeDelta = point.pts - timeMean;
      covariance += timeDelta * (point.position - positionMean);
      variance += timeDelta * timeDelta;
    }
    result[current.index] = (
      value: variance <= 1e-12 ? 0 : covariance / variance,
      sampleCount: neighbors.length,
    );
  }
  return result;
}

String _csvManifest(List<Map<String, Object?>> frames) {
  final buffer = StringBuffer(
    'index,pts,dt,position,velocity,theme,knob_x,theta,led,comparison_eligible,confidence,render_path\n',
  );
  for (final frame in frames) {
    final state = frame['state']! as Map<String, Object?>;
    final fields = [
      frame['index'],
      frame['pts'],
      frame['dt'],
      state['position'],
      state['velocity'],
      state['theme'],
      state['knobX'],
      state['theta'],
      state['led'],
      frame['comparisonEligible'],
      frame['confidence'],
      frame['renderPath'],
    ];
    buffer.writeln(
      fields.map((value) => '"${'$value'.replaceAll('"', '""')}"').join(','),
    );
  }
  return buffer.toString();
}
