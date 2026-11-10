import 'dart:async';
import 'dart:io';

import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:aggregate/platform/macos/mac_runtime.dart';

Future<void> main() async {
  final root = Directory.current.absolute.path;
  final python = '$root/spikes/phase0/.venv/bin/python';
  final fixture = '$root/spikes/phase0/fixture_server.py';
  if (!await File(python).exists()) {
    throw StateError('请先在 spikes/phase0/.venv 安装 Python MCP fixture');
  }
  final directory = await Directory.systemTemp.createTemp('aggregate-stage2-');
  final runtime = await MacRuntime.open(dataDirectory: directory);
  Process? http;
  try {
    final cli = await runtime.addConnection(
      const ConnectionSpec(
        kind: ConnectionKind.cli,
        label: 'printf',
        executable: '/usr/bin/printf',
      ),
    );
    _ready(cli);
    final command = (await runtime.searchCapabilities(
      const SearchQuery('printf'),
    )).single;
    final run = await runtime.invoke(command.id, {
      'argv': ['stage2-cli-ok'],
    }, permissionGranted: true);
    final result = await _terminalEvent(runtime, run.id);
    _expect(
      result.state == RunState.succeeded &&
          result.blocks.any(
            (block) => '${block.value}'.contains('stage2-cli-ok'),
          ),
      'CLI output',
    );
    stdout.writeln('PASS CLI execution');

    final tui = await runtime.addConnection(
      const ConnectionSpec(
        kind: ConnectionKind.cli,
        label: 'cat',
        executable: '/bin/cat',
      ),
    );
    _ready(tui);
    final session = await runtime.openTerminal(CliCommand(tui.id, const []));
    final output = runtime
        .watchTerminal(session)
        .firstWhere((text) => text.contains('stage2-pty-ok'));
    await runtime.writeTerminal(session, 'stage2-pty-ok\n');
    await output.timeout(const Duration(seconds: 5));
    await runtime.resizeTerminal(session, 100, 30);
    await runtime.interruptTerminal(session);
    await runtime.closeTerminal(session);
    stdout.writeln('PASS PTY input, resize, interrupt, close');

    final stdio = await runtime.addConnection(
      ConnectionSpec(
        kind: ConnectionKind.mcpStdio,
        label: 'fixture stdio',
        executable: python,
        arguments: [fixture, 'stdio'],
      ),
    );
    _ready(stdio);
    await _verifyMcp(runtime, stdio.id, 'stdio');

    http = await Process.start(python, [fixture, 'http', '--port', '18765']);
    for (var attempt = 0; attempt < 50; attempt++) {
      try {
        final socket = await Socket.connect(
          '127.0.0.1',
          18765,
          timeout: const Duration(milliseconds: 100),
        );
        socket.destroy();
        break;
      } on SocketException {
        if (attempt == 49) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
    final remote = await runtime.addConnection(
      const ConnectionSpec(
        kind: ConnectionKind.mcpHttp,
        label: 'fixture http',
        url: 'http://127.0.0.1:18765/mcp',
      ),
    );
    _ready(remote);
    await _verifyMcp(runtime, remote.id, 'http');

    http.kill(ProcessSignal.sigterm);
    await http.exitCode;
    http = null;
    final disconnected = await runtime.refreshConnection(remote.id);
    _expect(
      disconnected.status == ConnectionStatus.unavailable &&
          (await runtime.searchCapabilities(const SearchQuery('')))
              .every((item) => item.id.connection.value != remote.id.value),
      'HTTP disconnect invalidates catalog',
    );
    stdout.writeln('PASS MCP disconnect invalidates catalog');

    final runs = await runtime.listRecentRuns();
    _expect(
      runs.isNotEmpty && runs.every((run) => run.latest.blocks.isEmpty),
      'activity redaction',
    );
    stdout.writeln('PASS redacted activity');
  } finally {
    await runtime.dispose();
    http?.kill(ProcessSignal.sigterm);
    await directory.delete(recursive: true);
  }
}

Future<void> _verifyMcp(
  MacRuntime runtime,
  ConnectionId connection,
  String transport,
) async {
  final all = await runtime.searchCapabilities(const SearchQuery(''));
  final capabilities = all
      .where((item) => item.id.connection.value == connection.value)
      .toList();
  _expect(
    capabilities.any((item) => item.id.kind == CapabilityKind.mcpTool),
    '$transport tool discovery',
  );
  _expect(
    capabilities.any((item) => item.id.kind == CapabilityKind.mcpResource),
    '$transport resource discovery',
  );
  _expect(
    capabilities.any((item) => item.id.kind == CapabilityKind.mcpPrompt),
    '$transport prompt discovery',
  );

  final tool = capabilities.firstWhere((item) => item.id.name == 'add');
  final run = await runtime.invoke(tool.id, {
    'a': 7,
    'b': 5,
  }, permissionGranted: true);
  final result = await _terminalEvent(runtime, run.id);
  _expect(
    result.state == RunState.succeeded &&
        result.blocks.any((block) => '${block.value}'.contains('12')),
    '$transport tool result',
  );

  final resource = capabilities.firstWhere(
    (item) => item.id.kind == CapabilityKind.mcpResource,
  );
  final content = await runtime.readResource(
    ResourceRef(resource.id, Uri.parse(resource.id.name)),
  );
  _expect(
    content
        .map((item) => item.value)
        .toString()
        .contains('Aggregate phase 0 resource'),
    '$transport resource content',
  );

  final prompt = capabilities.firstWhere(
    (item) => item.id.kind == CapabilityKind.mcpPrompt,
  );
  final messages = await runtime.getPrompt(PromptRef(prompt.id), {
    'name': 'Aggregate',
  });
  _expect(
    messages.map((item) => item.value).toString().contains('Greet Aggregate'),
    '$transport prompt content',
  );
  stdout.writeln('PASS MCP $transport tools/resources/prompts');
}

Future<RunEvent> _terminalEvent(MacRuntime runtime, RunId id) => runtime
    .watchRun(id)
    .firstWhere(
      (event) => {
        RunState.succeeded,
        RunState.failed,
        RunState.cancelled,
        RunState.timedOut,
        RunState.outcomeUnknown,
      }.contains(event.state),
    )
    .timeout(const Duration(seconds: 35));

void _ready(Connection connection) {
  if (connection.status != ConnectionStatus.ready) {
    throw StateError('${connection.label}: ${connection.diagnostic}');
  }
}

void _expect(bool value, String label) {
  if (!value) throw StateError('FAIL $label');
}
