import 'package:aggregate_contracts/aggregate_contracts.dart';

final _placeholder = RegExp(r'\{\{([a-zA-Z][a-zA-Z0-9_]*)\}\}');

final class ConnectorManifest {
  ConnectorManifest._(
    this.id,
    this.displayName,
    this.platforms,
    this.executable,
    this.actions,
  );

  final String id;
  final String displayName;
  final List<String> platforms;
  final String executable;
  final List<ConnectorAction> actions;

  /// Built-in example connector. It still executes through RuntimePort and
  /// receives the same CLI confirmation as a user supplied manifest.
  factory ConnectorManifest.neteaseCli(String executable) =>
      ConnectorManifest.fromJson({
        'schemaVersion': 1,
        'id': 'netease-ncm-cli',
        'displayName': '网易云音乐',
        'platforms': ['macos'],
        'executable': executable,
        'actions': [
          _musicAction(
            'search',
            '搜索歌曲',
            ['search', 'song', '--keyword', '{{keyword}}'],
            'music.search',
            {
              'keyword': {'type': 'string', 'title': '关键词'},
            },
            ['keyword'],
          ),
          _musicAction(
            'play',
            '播放歌曲',
            [
              'play',
              '--song',
              '--encrypted-id',
              '{{encryptedId}}',
              '--original-id',
              '{{originalId}}',
            ],
            'music.play',
            {
              'encryptedId': {'type': 'string', 'title': '加密 ID'},
              'originalId': {'type': 'string', 'title': '原始 ID'},
            },
            ['encryptedId', 'originalId'],
          ),
          _musicAction(
            'queueAdd',
            '加入下一首',
            [
              'queue',
              'add',
              '--encrypted-id',
              '{{encryptedId}}',
              '--original-id',
              '{{originalId}}',
              '--next',
            ],
            'music.queueAdd',
            {
              'encryptedId': {'type': 'string', 'title': '加密 ID'},
              'originalId': {'type': 'string', 'title': '原始 ID'},
            },
            ['encryptedId', 'originalId'],
          ),
          _musicAction('pause', '暂停播放', ['pause'], 'music.pause'),
          _musicAction('resume', '继续播放', ['resume'], 'music.resume'),
          _musicAction('stop', '停止播放', ['stop'], 'music.stop'),
          _musicAction('next', '下一首', ['next'], 'music.next'),
          _musicAction('prev', '上一首', ['prev'], 'music.prev'),
          _musicAction('state', '播放状态', ['state'], 'music.state'),
          _musicAction(
            'volume',
            '调整音量',
            ['volume', '{{value}}'],
            'music.volume',
            {
              'value': {
                'type': 'integer',
                'title': '音量',
                'minimum': 0,
                'maximum': 100,
              },
            },
            ['value'],
          ),
        ],
      });

  factory ConnectorManifest.fromJson(Object? value) {
    final json = jsonObject(value, 'manifest');
    if (json['schemaVersion'] != 1) {
      throw const FormatException('unsupported schemaVersion');
    }
    final platforms = _strings(json['platforms'], 'platforms');
    if (platforms.isEmpty ||
        platforms.any(
          (item) => !{
            'macos',
            'windows',
            'linux',
            'android',
            'ios',
            'web',
          }.contains(item),
        )) {
      throw const FormatException('invalid platforms');
    }
    final rawActions = json['actions'];
    if (rawActions is! List || rawActions.isEmpty) {
      throw const FormatException('actions must be a non-empty list');
    }
    final actions = rawActions.map(ConnectorAction.fromJson).toList();
    if (actions.map((item) => item.id).toSet().length != actions.length) {
      throw const FormatException('duplicate action id');
    }
    return ConnectorManifest._(
      jsonString(json, 'id'),
      jsonString(json, 'displayName'),
      platforms,
      jsonString(json, 'executable'),
      actions,
    );
  }

  bool supports(String platform) => platforms.contains(platform);

  JsonMap toJson() => {
    'schemaVersion': 1,
    'id': id,
    'displayName': displayName,
    'platforms': platforms,
    'executable': executable,
    'actions': [for (final action in actions) action.toJson()],
  };
}

JsonMap _musicAction(
  String id,
  String title,
  List<String> argv,
  String presentation, [
  JsonMap properties = const {},
  List<String> required = const [],
]) => {
  'id': id,
  'title': title,
  'argv': argv,
  'inputSchema': {
    'type': 'object',
    'properties': properties,
    'required': required,
    'additionalProperties': false,
  },
  'output': 'text',
  'permission': id == 'search' || id == 'state' ? 'read' : 'localControl',
  'timeoutMs': 30000,
  'presentation': presentation,
};

final class ConnectorAction {
  ConnectorAction._(
    this.id,
    this.title,
    this.argv,
    this.inputSchema,
    this.output,
    this.permission,
    this.timeoutMs,
    this.presentation,
  );

  final String id;
  final String title;
  final List<String> argv;
  final JsonMap inputSchema;
  final String output;
  final PermissionLevel permission;
  final int timeoutMs;
  final String? presentation;

  JsonMap toJson() => {
    'id': id,
    'title': title,
    'argv': argv,
    'inputSchema': inputSchema,
    'output': output,
    'permission': permission.name,
    'timeoutMs': timeoutMs,
    if (presentation != null) 'presentation': presentation,
  };

  factory ConnectorAction.fromJson(Object? value) {
    final json = jsonObject(value, 'action');
    final argv = _strings(json['argv'], 'argv');
    if (argv.isEmpty) throw const FormatException('argv cannot be empty');
    final schema = jsonObject(json['inputSchema'], 'inputSchema');
    if (schema['type'] != 'object') {
      throw const FormatException('inputSchema must be object');
    }
    final properties = jsonObject(schema['properties'], 'properties');
    for (final argument in argv) {
      final matches = _placeholder.allMatches(argument).toList();
      final literal = argument.replaceAll(_placeholder, '');
      if (literal.contains('{') || literal.contains('}')) {
        throw const FormatException('malformed argv placeholder');
      }
      for (final match in matches) {
        if (!properties.containsKey(match.group(1))) {
          throw FormatException('unknown argv placeholder: ${match.group(1)}');
        }
      }
    }
    final requiredFields = _strings(
      schema['required'] ?? <String>[],
      'required',
    );
    if (requiredFields.any((name) => !properties.containsKey(name))) {
      throw const FormatException('required field absent from properties');
    }
    final output = jsonString(json, 'output');
    if (!{'text', 'json', 'file', 'terminal'}.contains(output)) {
      throw const FormatException('invalid output type');
    }
    final timeout = json['timeoutMs'];
    if (timeout is! int || timeout < 100 || timeout > 3600000) {
      throw const FormatException('invalid timeoutMs');
    }
    final presentation = json['presentation'];
    if (presentation != null &&
        (presentation is! String ||
            !{
              'music.search',
              'music.play',
              'music.queueAdd',
              'music.pause',
              'music.resume',
              'music.stop',
              'music.next',
              'music.prev',
              'music.volume',
              'music.state',
            }.contains(presentation))) {
      throw const FormatException('invalid presentation');
    }
    return ConnectorAction._(
      jsonString(json, 'id'),
      jsonString(json, 'title'),
      argv,
      schema,
      output,
      jsonEnum(PermissionLevel.values, json, 'permission'),
      timeout,
      presentation as String?,
    );
  }

  List<String> expand(JsonMap arguments) {
    final properties = jsonObject(inputSchema['properties'], 'properties');
    final required = _strings(
      inputSchema['required'] ?? <String>[],
      'required',
    );
    for (final field in required) {
      if (!arguments.containsKey(field)) {
        throw FormatException('missing argument: $field');
      }
    }
    for (final entry in arguments.entries) {
      if (!properties.containsKey(entry.key)) {
        throw FormatException('unknown argument: ${entry.key}');
      }
      final spec = jsonObject(properties[entry.key], entry.key);
      final valid = switch (spec['type']) {
        'string' => entry.value is String,
        'integer' => entry.value is int,
        'number' => entry.value is num,
        'boolean' => entry.value is bool,
        _ => false,
      };
      if (!valid) throw FormatException('invalid argument type: ${entry.key}');
    }
    return argv
        .map(
          (item) => item.replaceAllMapped(_placeholder, (match) {
            final name = match.group(1)!;
            if (!arguments.containsKey(name)) {
              throw FormatException('missing argument: $name');
            }
            return '${arguments[name]}';
          }),
        )
        .toList();
  }
}

List<String> _strings(Object? value, String field) {
  if (value is! List || value.any((item) => item is! String || item.isEmpty)) {
    throw FormatException('$field must be a string list');
  }
  return value.cast<String>();
}
