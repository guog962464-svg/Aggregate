typedef JsonMap = Map<String, Object?>;

JsonMap jsonObject(Object? value, String field) {
  if (value is! Map) throw FormatException('$field must be an object');
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) {
      throw FormatException('$field has a non-string key');
    }
    result[entry.key as String] = entry.value;
  }
  return result;
}

String jsonString(JsonMap json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('$key must be a non-empty string');
  }
  return value;
}

T jsonEnum<T extends Enum>(List<T> values, JsonMap json, String key) {
  final name = jsonString(json, key);
  for (final value in values) {
    if (value.name == name) return value;
  }
  throw FormatException('unknown $key: $name');
}

enum ConnectionKind { cli, mcpStdio, mcpHttp }

enum ConnectionStatus { ready, connecting, unavailable }

enum CapabilityKind { cliCommand, cliAction, mcpTool, mcpResource, mcpPrompt }

enum PermissionLevel { read, localControl, externalWrite, unknown }

enum RunState {
  created,
  validating,
  awaitingPermission,
  running,
  succeeded,
  failed,
  cancelled,
  timedOut,
  outcomeUnknown,
}

enum RuntimeErrorCode {
  invalidArguments,
  executableMissing,
  connectionFailed,
  authenticationRequired,
  permissionDenied,
  protocolError,
  timedOut,
  cancelled,
  outputLimitExceeded,
  outcomeUnknown,
  unsupported,
  internal,
}

enum ResultKind { text, json, image, file, terminal }

final class ConnectionId {
  const ConnectionId(this.value);
  final String value;
  JsonMap toJson() => {'value': value};
  factory ConnectionId.fromJson(Object? value) =>
      ConnectionId(jsonString(jsonObject(value, 'connectionId'), 'value'));
}

final class CapabilityId {
  const CapabilityId(this.connection, this.kind, this.name);
  final ConnectionId connection;
  final CapabilityKind kind;
  final String name;
  String get key => '${connection.value}:${kind.name}:$name';
  JsonMap toJson() => {
    'connection': connection.toJson(),
    'kind': kind.name,
    'name': name,
  };
  factory CapabilityId.fromJson(Object? value) {
    final json = jsonObject(value, 'capabilityId');
    return CapabilityId(
      ConnectionId.fromJson(json['connection']),
      jsonEnum(CapabilityKind.values, json, 'kind'),
      jsonString(json, 'name'),
    );
  }
}

final class RunId {
  const RunId(this.value);
  final String value;
  JsonMap toJson() => {'value': value};
  factory RunId.fromJson(Object? value) =>
      RunId(jsonString(jsonObject(value, 'runId'), 'value'));
}

final class Connection {
  const Connection({
    required this.id,
    required this.kind,
    required this.label,
    required this.location,
    this.status = ConnectionStatus.ready,
    this.protocolVersion,
  });
  final ConnectionId id;
  final ConnectionKind kind;
  final String label;
  final String location;
  final ConnectionStatus status;
  final String? protocolVersion;
  JsonMap toJson() => {
    'id': id.toJson(),
    'kind': kind.name,
    'label': label,
    'location': location,
    'status': status.name,
    if (protocolVersion != null) 'protocolVersion': protocolVersion,
  };
  factory Connection.fromJson(Object? value) {
    final json = jsonObject(value, 'connection');
    return Connection(
      id: ConnectionId.fromJson(json['id']),
      kind: jsonEnum(ConnectionKind.values, json, 'kind'),
      label: jsonString(json, 'label'),
      location: jsonString(json, 'location'),
      status: jsonEnum(ConnectionStatus.values, json, 'status'),
      protocolVersion: json['protocolVersion'] as String?,
    );
  }
}

final class Capability {
  const Capability({
    required this.id,
    required this.title,
    required this.description,
    required this.permission,
    this.inputSchema = const {},
  });
  final CapabilityId id;
  final String title;
  final String description;
  final PermissionLevel permission;
  final JsonMap inputSchema;
  JsonMap toJson() => {
    'id': id.toJson(),
    'title': title,
    'description': description,
    'permission': permission.name,
    'inputSchema': inputSchema,
  };
  factory Capability.fromJson(Object? value) {
    final json = jsonObject(value, 'capability');
    return Capability(
      id: CapabilityId.fromJson(json['id']),
      title: jsonString(json, 'title'),
      description: jsonString(json, 'description'),
      permission: jsonEnum(PermissionLevel.values, json, 'permission'),
      inputSchema: jsonObject(json['inputSchema'], 'inputSchema'),
    );
  }
}

final class RuntimeFailure {
  const RuntimeFailure(this.code, this.message, {this.phase});
  final RuntimeErrorCode code;
  final String message;
  final String? phase;
  JsonMap toJson() => {
    'code': code.name,
    'message': message,
    if (phase != null) 'phase': phase,
  };
  factory RuntimeFailure.fromJson(Object? value) {
    final json = jsonObject(value, 'failure');
    return RuntimeFailure(
      jsonEnum(RuntimeErrorCode.values, json, 'code'),
      jsonString(json, 'message'),
      phase: json['phase'] as String?,
    );
  }
}

final class ResultBlock {
  const ResultBlock(this.kind, this.value);
  final ResultKind kind;
  final Object? value;
  JsonMap toJson() => {'kind': kind.name, 'value': value};
  factory ResultBlock.fromJson(Object? value) {
    final json = jsonObject(value, 'resultBlock');
    return ResultBlock(
      jsonEnum(ResultKind.values, json, 'kind'),
      json['value'],
    );
  }
}

final class RunEvent {
  const RunEvent({
    required this.runId,
    required this.sequence,
    required this.state,
    required this.occurredAt,
    this.blocks = const [],
    this.failure,
  });
  final RunId runId;
  final int sequence;
  final RunState state;
  final DateTime occurredAt;
  final List<ResultBlock> blocks;
  final RuntimeFailure? failure;
  JsonMap toJson() => {
    'runId': runId.toJson(),
    'sequence': sequence,
    'state': state.name,
    'occurredAt': occurredAt.toUtc().toIso8601String(),
    'blocks': blocks.map((item) => item.toJson()).toList(),
    if (failure != null) 'failure': failure!.toJson(),
  };
  factory RunEvent.fromJson(Object? value) {
    final json = jsonObject(value, 'runEvent');
    final sequence = json['sequence'];
    final blocks = json['blocks'];
    if (sequence is! int || sequence < 0 || blocks is! List) {
      throw const FormatException('invalid run event sequence or blocks');
    }
    return RunEvent(
      runId: RunId.fromJson(json['runId']),
      sequence: sequence,
      state: jsonEnum(RunState.values, json, 'state'),
      occurredAt: DateTime.parse(jsonString(json, 'occurredAt')),
      blocks: blocks.map(ResultBlock.fromJson).toList(),
      failure: json['failure'] == null
          ? null
          : RuntimeFailure.fromJson(json['failure']),
    );
  }
}

final class RunHandle {
  const RunHandle(this.id);
  final RunId id;
  JsonMap toJson() => {'id': id.toJson()};
  factory RunHandle.fromJson(Object? value) =>
      RunHandle(RunId.fromJson(jsonObject(value, 'runHandle')['id']));
}

final class RunSummary {
  const RunSummary(this.id, this.capability, this.latest);
  final RunId id;
  final CapabilityId capability;
  final RunEvent latest;
  JsonMap toJson() => {
    'id': id.toJson(),
    'capability': capability.toJson(),
    'latest': latest.toJson(),
  };
  factory RunSummary.fromJson(Object? value) {
    final json = jsonObject(value, 'runSummary');
    return RunSummary(
      RunId.fromJson(json['id']),
      CapabilityId.fromJson(json['capability']),
      RunEvent.fromJson(json['latest']),
    );
  }
}

final class SearchQuery {
  const SearchQuery(this.text, {this.kind});
  final String text;
  final CapabilityKind? kind;
  JsonMap toJson() => {'text': text, if (kind != null) 'kind': kind!.name};
  factory SearchQuery.fromJson(Object? value) {
    final json = jsonObject(value, 'searchQuery');
    if (json['text'] is! String) {
      throw const FormatException('search text must be a string');
    }
    return SearchQuery(
      json['text'] as String,
      kind: json['kind'] == null
          ? null
          : jsonEnum(CapabilityKind.values, json, 'kind'),
    );
  }
}

final class ResourceRef {
  const ResourceRef(this.capability, this.uri);
  final CapabilityId capability;
  final Uri uri;
  JsonMap toJson() => {
    'capability': capability.toJson(),
    'uri': uri.toString(),
  };
  factory ResourceRef.fromJson(Object? value) {
    final json = jsonObject(value, 'resourceRef');
    return ResourceRef(
      CapabilityId.fromJson(json['capability']),
      Uri.parse(jsonString(json, 'uri')),
    );
  }
}

final class PromptRef {
  const PromptRef(this.capability);
  final CapabilityId capability;
  JsonMap toJson() => {'capability': capability.toJson()};
  factory PromptRef.fromJson(Object? value) => PromptRef(
    CapabilityId.fromJson(jsonObject(value, 'promptRef')['capability']),
  );
}

final class CliCommand {
  const CliCommand(this.connection, this.arguments);
  final ConnectionId connection;
  final List<String> arguments;
  JsonMap toJson() => {
    'connection': connection.toJson(),
    'arguments': arguments,
  };
  factory CliCommand.fromJson(Object? value) {
    final json = jsonObject(value, 'cliCommand');
    final arguments = json['arguments'];
    if (arguments is! List || arguments.any((item) => item is! String)) {
      throw const FormatException('arguments must be a string list');
    }
    return CliCommand(
      ConnectionId.fromJson(json['connection']),
      arguments.cast<String>(),
    );
  }
}

final class TerminalSession {
  const TerminalSession(this.id);
  final String id;
  JsonMap toJson() => {'id': id};
  factory TerminalSession.fromJson(Object? value) =>
      TerminalSession(jsonString(jsonObject(value, 'terminalSession'), 'id'));
}
