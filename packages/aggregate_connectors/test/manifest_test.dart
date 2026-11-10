import 'dart:convert';
import 'dart:io';

import 'package:aggregate_connectors/aggregate_connectors.dart';
import 'package:test/test.dart';

void main() {
  final sample = jsonDecode(
    File('connectors/examples/git-status.json').readAsStringSync(),
  ) as Map<String, dynamic>;

  test('non-music sample loads and is macOS scoped', () {
    final manifest = ConnectorManifest.fromJson(sample);
    expect(manifest.supports('macos'), isTrue);
    expect(manifest.supports('web'), isFalse);
    expect(manifest.actions.first.expand({}), ['status', '--short']);
  });

  test('unknown placeholder and wrong argument type are rejected', () {
    final invalid = jsonDecode(jsonEncode(sample)) as Map<String, dynamic>;
    final action = (invalid['actions'] as List).first as Map<String, dynamic>;
    action['argv'] = ['status', '{{missing}}'];
    expect(() => ConnectorManifest.fromJson(invalid), throwsFormatException);

    final withInput = jsonDecode(jsonEncode(sample)) as Map<String, dynamic>;
    final inputAction =
        (withInput['actions'] as List).first as Map<String, dynamic>;
    inputAction['argv'] = ['show', '{{count}}'];
    inputAction['inputSchema'] = {
      'type': 'object',
      'properties': {
        'count': {'type': 'integer'},
      },
      'required': ['count'],
    };
    final parsed = ConnectorManifest.fromJson(withInput);
    expect(
      () => parsed.actions.first.expand({'count': 'bad'}),
      throwsFormatException,
    );
    expect(parsed.actions.first.expand({'count': 2}), ['show', '2']);

    final malformed = jsonDecode(jsonEncode(sample)) as Map<String, dynamic>;
    ((malformed['actions'] as List).first as Map<String, dynamic>)['argv'] = [
      'status',
      '{{count}',
    ];
    expect(() => ConnectorManifest.fromJson(malformed), throwsFormatException);
  });

  test('built-in music actions expand exact CLI argument arrays', () {
    final manifest = ConnectorManifest.neteaseCli('/tmp/ncm-cli');
    final search = manifest.actions.singleWhere((item) => item.id == 'search');
    final play = manifest.actions.singleWhere((item) => item.id == 'play');
    expect(search.presentation, 'music.search');
    expect(search.expand({'keyword': '海阔天空'}), [
      'search',
      'song',
      '--keyword',
      '海阔天空',
    ]);
    expect(play.expand({'encryptedId': 'encrypted', 'originalId': '123'}), [
      'play',
      '--song',
      '--encrypted-id',
      'encrypted',
      '--original-id',
      '123',
    ]);
    final queue = manifest.actions.singleWhere((item) => item.id == 'queueAdd');
    expect(queue.presentation, 'music.queueAdd');
    expect(queue.expand({'encryptedId': 'encrypted', 'originalId': '123'}), [
      'queue',
      'add',
      '--encrypted-id',
      'encrypted',
      '--original-id',
      '123',
      '--next',
    ]);
    expect(
      manifest.actions.singleWhere((item) => item.id == 'volume').expand({
        'value': 60,
      }),
      ['volume', '60'],
    );
  });

  test('manifest serialization preserves editable actions', () {
    final manifest = ConnectorManifest.fromJson(sample);
    final restored = ConnectorManifest.fromJson(manifest.toJson());
    expect(restored.id, manifest.id);
    expect(restored.actions.first.argv, manifest.actions.first.argv);
    expect(
      restored.actions.first.permission,
      manifest.actions.first.permission,
    );
    expect(restored.actions.first.expand({}), ['status', '--short']);
  });
}
