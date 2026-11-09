import 'dart:convert';

import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:test/test.dart';

void main() {
  test('connection, capability and event survive JSON round trip', () {
    const connection = Connection(
      id: ConnectionId('76aaf452-0d77-4cda-a492-c2ebf037b81b'),
      kind: ConnectionKind.mcpHttp,
      label: 'Project MCP',
      location: 'https://example.invalid/mcp',
      protocolVersion: '2026-07-28',
    );
    final restoredConnection = Connection.fromJson(
      jsonDecode(jsonEncode(connection.toJson())),
    );
    expect(restoredConnection.id.value, connection.id.value);
    expect(restoredConnection.protocolVersion, '2026-07-28');

    final capability = Capability(
      id: CapabilityId(connection.id, CapabilityKind.mcpTool, 'add'),
      title: 'Add',
      description: 'Add integers',
      permission: PermissionLevel.read,
      inputSchema: {'type': 'object', 'properties': {}},
    );
    final restoredCapability = Capability.fromJson(
      jsonDecode(jsonEncode(capability.toJson())),
    );
    expect(restoredCapability.id.key, capability.id.key);
    expect(restoredCapability.permission, PermissionLevel.read);

    final event = RunEvent(
      runId: const RunId('run-1'),
      sequence: 3,
      state: RunState.succeeded,
      occurredAt: DateTime.utc(2026, 11, 9),
      blocks: const [
        ResultBlock(ResultKind.json, {'sum': 12}),
      ],
    );
    final restored = RunEvent.fromJson(jsonDecode(jsonEncode(event.toJson())));
    expect(restored.state, RunState.succeeded);
    expect(restored.blocks.single.value, {'sum': 12});
  });

  test('unknown enum and malformed event fail closed', () {
    final connection = {
      'id': {'value': 'one'},
      'kind': 'futureKind',
      'label': 'Unknown',
      'location': 'local',
      'status': 'ready',
    };
    expect(() => Connection.fromJson(connection), throwsFormatException);
    expect(
      () => RunEvent.fromJson({'state': 'running'}),
      throwsFormatException,
    );
  });

  test('resource, prompt, command and terminal contracts serialize', () {
    const connection = ConnectionId('source-one');
    const resourceId = CapabilityId(
      connection,
      CapabilityKind.mcpResource,
      'readme',
    );
    const promptId = CapabilityId(
      connection,
      CapabilityKind.mcpPrompt,
      'summary',
    );
    final resource = ResourceRef(
      resourceId,
      Uri.parse('memo://fixture/readme'),
    );
    expect(
      ResourceRef.fromJson(jsonDecode(jsonEncode(resource.toJson()))).uri,
      resource.uri,
    );
    expect(
      PromptRef.fromJson(
        jsonDecode(jsonEncode(const PromptRef(promptId).toJson())),
      ).capability.key,
      promptId.key,
    );
    const command = CliCommand(connection, ['status', '--short']);
    expect(
      CliCommand.fromJson(jsonDecode(jsonEncode(command.toJson()))).arguments,
      command.arguments,
    );
    expect(
      TerminalSession.fromJson(
        jsonDecode(jsonEncode(const TerminalSession('term-1').toJson())),
      ).id,
      'term-1',
    );
    expect(
      RunHandle.fromJson(
        jsonDecode(jsonEncode(const RunHandle(RunId('run-1')).toJson())),
      ).id.value,
      'run-1',
    );
    expect(
      SearchQuery.fromJson(
        jsonDecode(jsonEncode(const SearchQuery('').toJson())),
      ).text,
      '',
    );
  });
}
