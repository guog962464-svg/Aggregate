// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:io';

import 'package:aggregate/platform/macos/mac_runtime.dart';
import 'package:aggregate_contracts/aggregate_contracts.dart';

const terminal = {
  RunState.succeeded,
  RunState.failed,
  RunState.cancelled,
  RunState.timedOut,
  RunState.outcomeUnknown,
};

Future<void> main() async {
  final root = Directory.current.absolute.path;
  final python = '$root/spikes/phase0/.venv/bin/python';
  final fixture = '$root/spikes/phase0/fixture_server.py';
  if (!await File(python).exists()) {
    throw StateError('缺少阶段 0 Python MCP fixture');
  }
  final reservation = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = reservation.port;
  await reservation.close();
  final data = await Directory.systemTemp.createTemp('aggregate-stage3-mcp-');
  final runtime = await MacRuntime.open(dataDirectory: data);
  Process? server;
  Future<Process> startServer() async {
    final process = await Process.start(python, [
      fixture,
      'http',
      '--port',
      '$port',
    ]);
    unawaited(process.stdout.drain());
    unawaited(process.stderr.drain());
    for (var attempt = 0; attempt < 50; attempt++) {
      try {
        final socket = await Socket.connect(
          '127.0.0.1',
          port,
          timeout: const Duration(milliseconds: 100),
        );
        socket.destroy();
        return process;
      } on SocketException {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
    throw StateError('MCP fixture 未启动');
  }

  try {
    server = await startServer();
    final connection = await runtime.addConnection(
      ConnectionSpec(
        kind: ConnectionKind.mcpHttp,
        label: 'Stage 3 reconnect fixture',
        url: 'http://127.0.0.1:$port/mcp',
      ),
    );
    if (connection.status != ConnectionStatus.ready) {
      throw StateError('初始 MCP 连接失败：${connection.diagnostic}');
    }
    final capability = (await runtime.searchCapabilities(const SearchQuery('')))
        .firstWhere(
          (item) =>
              item.id.connection.value == connection.id.value &&
              item.id.name == 'add',
        );
    Future<RunEvent> invoke() async {
      final handle = await runtime.invoke(capability.id, {
        'a': 2,
        'b': 3,
      }, permissionGranted: true);
      return runtime
          .watchRun(handle.id)
          .firstWhere((item) => terminal.contains(item.state))
          .timeout(const Duration(seconds: 15));
    }

    if ((await invoke()).state != RunState.succeeded) {
      throw StateError('MCP 基准调用失败');
    }
    server.kill(ProcessSignal.sigterm);
    await server.exitCode;
    server = null;
    try {
      await invoke();
    } on ArgumentError {
      // The close callback can remove stale capabilities before this call.
    }
    server = await startServer();
    var recovered = false;
    for (var attempt = 0; attempt < 80; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      final current = (await runtime.listConnections()).firstWhere(
        (item) => item.id.value == connection.id.value,
      );
      final catalog = await runtime.searchCapabilities(const SearchQuery(''));
      if (current.status == ConnectionStatus.ready &&
          catalog.any((item) => item.id.key == capability.id.key)) {
        recovered = true;
        break;
      }
    }
    if (!recovered) throw StateError('MCP 未自动重连');
    if ((await invoke()).state != RunState.succeeded) {
      throw StateError('重连后的 MCP 调用失败');
    }
    print('PASS MCP disconnect, reconnect, and call without replay');
  } finally {
    await runtime.dispose();
    if (server != null) {
      server.kill(ProcessSignal.sigterm);
      await server.exitCode;
    }
    await data.delete(recursive: true);
  }
}
