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
}
