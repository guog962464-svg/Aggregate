import 'dart:async';
import 'dart:io';

import 'package:flutter_pty2/flutter_pty2.dart';

Future<void> main() async {
  final ordinary = await Process.run('/usr/bin/printf', ['ordinary-cli-ok']);
  if (ordinary.exitCode != 0 || ordinary.stdout != 'ordinary-cli-ok') {
    throw StateError('ordinary CLI failed: $ordinary');
  }
  print('PASS ordinary CLI');

  final session = await Pty.spawn(
    PtySpawnOptions(
      executable: '${Directory.current.path}/.venv/bin/python',
      arguments: ['tui_fixture.py'],
      size: const PtySize(columns: 80, rows: 24),
    ),
  );
  final output = StringBuffer();
  final subscription = session.utf8Output().listen(output.write);
  try {
    await _until(output, 'SIZE 80x24');
    session.resize(const PtySize(columns: 100, rows: 30));
    await _until(output, 'SIZE 100x30');
    await session.input.writeUtf8('ping\n');
    await _until(output, 'INPUT ping');
    await session.input.writeUtf8('quit\n');
    final exit = await session.done.timeout(const Duration(seconds: 5));
    if (exit is! PtyExitCode || exit.code != 0) {
      throw StateError('TUI exit: $exit');
    }
    print('PASS PTY input, resize, output, exit');
  } finally {
    await session.close();
    await subscription.cancel();
  }

  final interrupt = await Pty.spawn(
    const PtySpawnOptions(
      executable: '/bin/sh',
      arguments: ['-c', 'sleep 30 & wait'],
    ),
  );
  try {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final children = await Process.run('/usr/bin/pgrep', [
      '-P',
      '${interrupt.pid}',
    ]);
    final childPid = int.tryParse('${children.stdout}'.trim());
    if (childPid == null) {
      throw StateError('PTY fixture child process was not observed');
    }
    interrupt.sendSignal(
      PosixSignal.int_,
      target: PosixSignalTarget.shellProcessGroup,
    );
    await interrupt.done.timeout(const Duration(seconds: 5));
    final parentAlive = await Process.run('/bin/kill', [
      '-0',
      '${interrupt.pid}',
    ]);
    if (parentAlive.exitCode == 0) throw StateError('PTY parent still alive');
    final childAlive = await Process.run('/bin/kill', ['-0', '$childPid']);
    if (childAlive.exitCode == 0) {
      throw StateError('PTY child still alive: $childPid');
    }
    print('PASS PTY interrupt and process group cleanup');
  } finally {
    await interrupt.close();
  }
}

Future<void> _until(StringBuffer output, String needle) async {
  for (var i = 0; i < 100; i++) {
    if (output.toString().contains(needle)) return;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  throw StateError('missing $needle, output=$output');
}
