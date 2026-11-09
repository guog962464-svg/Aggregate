import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:aggregate_domain/aggregate_domain.dart';
import 'package:test/test.dart';

void main() {
  test('run state cannot leave a terminal state', () {
    final run = RunLifecycle(RunState.created);
    run.transition(RunState.validating);
    run.transition(RunState.running);
    run.transition(RunState.succeeded);
    expect(() => run.transition(RunState.running), throwsStateError);
  });

  test(
    'search distinguishes duplicate names by connection and keeps favorites',
    () {
      const a = Connection(
        id: ConnectionId('a'),
        kind: ConnectionKind.cli,
        label: 'Git CLI',
        location: '/usr/bin/git',
      );
      const b = Connection(
        id: ConnectionId('b'),
        kind: ConnectionKind.mcpHttp,
        label: 'Project MCP',
        location: 'https://example.invalid',
      );
      final one = Capability(
        id: CapabilityId(a.id, CapabilityKind.cliAction, 'status'),
        title: 'Status',
        description: 'Git status',
        permission: PermissionLevel.read,
      );
      final two = Capability(
        id: CapabilityId(b.id, CapabilityKind.mcpTool, 'status'),
        title: 'Status',
        description: 'Project status',
        permission: PermissionLevel.read,
      );
      final catalog = CapabilityCatalog(
        connections: [a, b],
        capabilities: [one, two],
      );
      expect(catalog.search(const SearchQuery('status')).length, 2);
      expect(
        catalog.search(const SearchQuery('Git')).single.id.connection.value,
        'a',
      );
      catalog.setFavorite(two.id, true);
      expect(
        catalog.search(const SearchQuery('status')).first.id.connection.value,
        'b',
      );
      catalog.markUsed(one.id);
      expect(catalog.recent.single.id.key, one.id.key);
    },
  );

  test('MCP result keeps structured content and text blocks', () {
    final blocks = ResultNormalizer.fromMcp({
      'structuredContent': {'sum': 12},
      'content': [
        {'type': 'text', 'text': '12'},
      ],
    });
    expect(blocks.map((item) => item.kind), [ResultKind.json, ResultKind.text]);
  });
}
