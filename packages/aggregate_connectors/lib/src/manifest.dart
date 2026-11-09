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
}

final class ConnectorAction {
  ConnectorAction._(
    this.id,
    this.title,
    this.argv,
    this.inputSchema,
    this.output,
    this.permission,
    this.timeoutMs,
  );

  final String id;
  final String title;
  final List<String> argv;
  final JsonMap inputSchema;
  final String output;
  final PermissionLevel permission;
  final int timeoutMs;

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
    return ConnectorAction._(
      jsonString(json, 'id'),
      jsonString(json, 'title'),
      argv,
      schema,
      output,
      jsonEnum(PermissionLevel.values, json, 'permission'),
      timeout,
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
