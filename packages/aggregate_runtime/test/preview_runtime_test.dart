import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:aggregate_runtime/aggregate_runtime.dart';
import 'package:test/test.dart';

void main() {
  const connection = Connection(
    id: ConnectionId('mcp'),
    kind: ConnectionKind.mcpHttp,
    label: 'Fixture',
    location: 'mcp://fixture',
  );
  final capability = Capability(
    id: CapabilityId(connection.id, CapabilityKind.mcpTool, 'add'),
    title: 'Add',
    description: 'Add integers',
    permission: PermissionLevel.read,
    inputSchema: {
      'type': 'object',
      'properties': {
        'a': {'type': 'integer'},
        'b': {'type': 'integer'},
      },
      'required': ['a', 'b'],
    },
  );

  test('valid call emits ordered states and structured result', () async {
    final runtime = PreviewRuntime(
      connections: [connection],
      capabilities: [capability],
    );
    addTearDown(runtime.dispose);
    final handle = await runtime.invoke(capability.id, {'a': 7, 'b': 5});
    final events = await runtime.watchRun(handle.id).take(4).toList();
    expect(events.map((item) => item.state), [
      RunState.created,
      RunState.validating,
      RunState.running,
      RunState.succeeded,
    ]);
    expect(events.map((item) => item.sequence), [0, 1, 2, 3]);
    expect(events.last.blocks.single.value, {'sum': 12});
    expect(
      (await runtime.listRecentRuns()).single.latest.state,
      RunState.succeeded,
    );
  });

  test('invalid input fails before running; cancel is terminal', () async {
    final runtime = PreviewRuntime(
      connections: [connection],
      capabilities: [capability],
      latency: const Duration(milliseconds: 500),
    );
    addTearDown(runtime.dispose);
    final bad = await runtime.invoke(capability.id, {'a': 'bad'});
    final failure = await runtime
        .watchRun(bad.id)
        .firstWhere((item) => item.state == RunState.failed);
    expect(failure.failure?.code, RuntimeErrorCode.invalidArguments);

    final running = await runtime.invoke(capability.id, {'a': 1, 'b': 2});
    await runtime.cancel(running.id);
    final cancelled = await runtime
        .watchRun(running.id)
        .firstWhere((item) => item.state == RunState.cancelled);
    expect(cancelled.failure?.code, RuntimeErrorCode.cancelled);
  });
}
