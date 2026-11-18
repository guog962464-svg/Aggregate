import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../features/settings/glass_theme_switch.dart';
import '../features/settings/theme_switch_calibration.dart';
import '../features/settings/theme_switch_simulation.dart';

const _modelInputPath = String.fromEnvironment('THEME_SWITCH_MODEL_INPUT');
const _exportPath = String.fromEnvironment('THEME_SWITCH_EXPORT_DIR');
const _size = Size(720, 540);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _NativeCaptureApp());
}

class _NativeCaptureApp extends StatelessWidget {
  const _NativeCaptureApp();

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Theme Switch Native Capture',
    home: const _NativeCapturePage(),
  );
}

class _NativeCapturePage extends StatefulWidget {
  const _NativeCapturePage();

  @override
  State<_NativeCapturePage> createState() => _NativeCapturePageState();
}

class _NativeCapturePageState extends State<_NativeCapturePage> {
  final _boundaryKey = GlobalKey();
  ThemeSwitchSnapshot? _frame;
  ui.FragmentProgram? _program;
  double _time = 0;
  var _started = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_started) return;
      _started = true;
      unawaited(_captureFrames());
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xff101218),
    body: Center(
      child: _frame == null
          ? const SizedBox.shrink()
          : MediaQuery(
              data: const MediaQueryData(size: _size, devicePixelRatio: 1),
              child: RepaintBoundary(
                key: _boundaryKey,
                child: SizedBox.fromSize(
                  size: _size,
                  child: ThemeSwitchArtwork(
                    frame: _frame!,
                    time: _time,
                    program: _program,
                    scale: .76,
                    center: const Offset(360, 270),
                    optics: const ThemeSwitchOptics(),
                  ),
                ),
              ),
            ),
    ),
  );

  Future<void> _captureFrames() async {
    try {
      if (_modelInputPath.isEmpty || _exportPath.isEmpty) {
        throw StateError(
          'Set THEME_SWITCH_MODEL_INPUT and THEME_SWITCH_EXPORT_DIR.',
        );
      }
      final input = File(_modelInputPath).absolute;
      final sourceRoot = input.parent;
      final output = Directory(_exportPath).absolute
        ..createSync(recursive: true);
      final sourceManifestFile = File(
        '${sourceRoot.path}/source-manifest.json',
      );
      final sourceManifestBytes = sourceManifestFile.readAsBytesSync();
      final sourceManifest =
          jsonDecode(utf8.decode(sourceManifestBytes)) as Map<String, dynamic>;
      final sourceFrames = (sourceManifest['frameIndices'] as List<dynamic>)
          .cast<int>();
      final rows = (jsonDecode(input.readAsStringSync()) as List<dynamic>)
          .cast<Map<String, dynamic>>();
      if (rows.length != 151) {
        throw StateError('Expected the full 151-frame source.');
      }
      if (sourceFrames.length != rows.length ||
          rows.any(
            (row) => (row['particles'] as List<dynamic>).length != 113,
          )) {
        throw StateError(
          'Source manifest or particle dimensions do not match.',
        );
      }
      final modelInputBytes = input.readAsBytesSync();
      _program = await ThemeSwitchArtwork.loadProgram();

      final frames = <Map<String, Object?>>[];
      var previousTime = 0.0;
      for (
        var expectedIndex = 0;
        expectedIndex < rows.length;
        expectedIndex++
      ) {
        final row = rows[expectedIndex];
        final index = (row['i'] as num).toInt();
        final framesPerSecond = (sourceManifest['framesPerSecond'] as num)
            .toDouble();
        final time = _number(row, 'time');
        if (index != expectedIndex ||
            sourceFrames[expectedIndex] != index ||
            (time - index / framesPerSecond).abs() > 1e-9) {
          throw StateError('Source frames must be contiguous.');
        }
        final snapshot = _snapshotFrom(row);
        setState(() {
          _frame = snapshot;
          _time = time;
        });
        await WidgetsBinding.instance.endOfFrame;

        final renderObject = _boundaryKey.currentContext?.findRenderObject();
        if (renderObject is! RenderRepaintBoundary) {
          throw StateError(
            'Native capture boundary is unavailable at frame $index.',
          );
        }
        final image = await renderObject.toImage(pixelRatio: 1);
        try {
          if (image.width != 720 || image.height != 540) {
            throw StateError('Unexpected native image size at frame $index.');
          }
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          if (png == null) {
            throw StateError('PNG encoding failed at frame $index.');
          }
          final renderPath = '${output.path}/profile-render-$index.png';
          await File(renderPath).writeAsBytes(
            png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
          );
          frames.add({
            'index': index,
            'pts': time,
            'dt': time - previousTime,
            'referencePath': '${sourceRoot.path}/original-render-$index.png',
            'renderPath': renderPath,
            'comparisonEligible': true,
            'confidence': 'profile-engine-same-state',
          });
          previousTime = time;
        } finally {
          image.dispose();
        }
      }

      final manifest = {
        'schemaVersion': 1,
        'sourceMode': 'profile-model-input',
        'modelInput': input.path,
        'modelInputSha256': sha256.convert(modelInputBytes).toString(),
        'sourceManifest': sourceManifestFile.absolute.path,
        'sourceManifestSha256': sha256.convert(sourceManifestBytes).toString(),
        'sourceUrl': sourceManifest['sourceUrl'],
        'sourceJsSha256': sourceManifest['sourceSha256'],
        'particleTrajectorySha256': sourceManifest['particleTrajectorySha256'],
        'seed': sourceManifest['seed'],
        'framesPerSecond': sourceManifest['framesPerSecond'],
        'exportRoot': output.path,
        'renderer':
            'Aggregate Flutter macOS Profile renderer; RepaintBoundary.toImage',
        'frameCount': frames.length,
        'scene': {
          'width': 720,
          'height': 540,
          'devicePixelRatio': 1,
          'scale': .76,
          'centerX': 360,
          'centerY': 270,
        },
        'limitations': [
          'This is an offline same-state Profile renderer capture.',
          'RepaintBoundary capture is not physical display-present timing.',
          'It does not establish identity with the recorded pointer motion or random seed.',
        ],
        'frames': frames,
      };
      File(
        '${output.path}/manifest.json',
      ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(manifest));
      stdout.writeln(
        'CAPTURE_COMPLETE frames=${frames.length} output=${output.path}',
      );
      exit(0);
    } catch (error, stack) {
      stderr.writeln('CAPTURE_FAILED $error\n$stack');
      exit(1);
    }
  }

  ThemeSwitchSnapshot _snapshotFrom(Map<String, dynamic> row) {
    final halfWidth = _number(row, 'hx');
    final halfHeight = _number(row, 'hy');
    final particles = (row['particles'] as List<dynamic>)
        .map((raw) {
          final values = (raw as List<dynamic>).cast<num>();
          return ThemeSwitchParticle(
            x: values[0].toDouble(),
            y: values[1].toDouble(),
            size: values[2].toDouble(),
            alpha: values[3].toDouble(),
          );
        })
        .toList(growable: false);
    return ThemeSwitchSnapshot(
      position: _number(row, 'p'),
      velocity: _number(row, 'v'),
      theme: _number(row, 'theme'),
      knobX: _number(row, 'x'),
      halfWidth: halfWidth,
      halfHeight: halfHeight,
      radius: halfWidth > 58 && halfHeight > 58
          ? 58
          : (halfWidth < halfHeight ? halfWidth : halfHeight) - 1,
      theta: _number(row, 'theta'),
      led: _number(row, 'led'),
      lift: _number(row, 'lift'),
      particles: particles,
    );
  }

  double _number(Map<String, dynamic> row, String key) =>
      (row[key] as num).toDouble();
}
