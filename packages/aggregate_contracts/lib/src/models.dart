import 'execution_target.dart';

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

enum AppearancePreference { system, light, dark }

/// Features available through a RuntimePort instance, independent of the UI
/// device's operating system. A remote runtime can expose a different set from
/// a local runtime on the same device.
final class RuntimeFeatures {
  const RuntimeFeatures({
    this.connectionKinds = const {
      ConnectionKind.cli,
      ConnectionKind.mcpStdio,
      ConnectionKind.mcpHttp,
    },
    this.terminal = true,
    this.localFilePreview = true,
    this.localFileReveal = true,
  });

  static const localDesktop = RuntimeFeatures();
  static const httpOnly = RuntimeFeatures(
    connectionKinds: {ConnectionKind.mcpHttp},
    terminal: false,
    localFilePreview: false,
    localFileReveal: false,
  );

  final Set<ConnectionKind> connectionKinds;
  final bool terminal;
  final bool localFilePreview;
  final bool localFileReveal;

  bool canAdd(ConnectionKind kind) => connectionKinds.contains(kind);

  JsonMap toJson() => {
    'schemaVersion': 1,
    'connectionKinds': [for (final kind in connectionKinds) kind.name],
    'terminal': terminal,
    'localFilePreview': localFilePreview,
    'localFileReveal': localFileReveal,
  };

  factory RuntimeFeatures.fromJson(Object? value) {
    final json = jsonObject(value, 'runtimeFeatures');
    if (json['schemaVersion'] != 1) {
      throw const FormatException('unsupported runtimeFeatures schemaVersion');
    }
    final kinds = json['connectionKinds'];
    if (kinds is! List || kinds.any((kind) => kind is! String)) {
      throw const FormatException('invalid connectionKinds');
    }
    for (final key in ['terminal', 'localFilePreview', 'localFileReveal']) {
      if (json[key] is! bool) throw FormatException('invalid $key');
    }
    return RuntimeFeatures(
      connectionKinds: Set.unmodifiable(
        kinds.map(
          (kind) => jsonEnum(ConnectionKind.values, {'kind': kind}, 'kind'),
        ),
      ),
      terminal: json['terminal'] as bool,
      localFilePreview: json['localFilePreview'] as bool,
      localFileReveal: json['localFileReveal'] as bool,
    );
  }
}

final class UserPreferences {
  const UserPreferences({
    this.appearance = AppearancePreference.system,
    this.activityRetentionDays = 30,
    this.favoriteCapabilityKeys = const [],
    this.preferredConnectionId,
  });

  final AppearancePreference appearance;
  final int activityRetentionDays;
  final List<String> favoriteCapabilityKeys;
  final String? preferredConnectionId;

  UserPreferences copyWith({
    AppearancePreference? appearance,
    int? activityRetentionDays,
    List<String>? favoriteCapabilityKeys,
    String? preferredConnectionId,
  }) => UserPreferences(
    appearance: appearance ?? this.appearance,
    activityRetentionDays: activityRetentionDays ?? this.activityRetentionDays,
    favoriteCapabilityKeys:
        favoriteCapabilityKeys ?? this.favoriteCapabilityKeys,
    preferredConnectionId: preferredConnectionId ?? this.preferredConnectionId,
  );

  JsonMap toJson() => {
    'schemaVersion': 1,
    'appearance': appearance.name,
    'activityRetentionDays': activityRetentionDays,
    'favoriteCapabilityKeys': favoriteCapabilityKeys,
    if (preferredConnectionId != null)
      'preferredConnectionId': preferredConnectionId,
  };

  factory UserPreferences.fromJson(Object? value) {
    final json = jsonObject(value, 'preferences');
    if (json['schemaVersion'] != 1) {
      throw const FormatException('unsupported preferences schemaVersion');
    }
    final retention = json['activityRetentionDays'];
    final favorites = json['favoriteCapabilityKeys'];
    final preferred = json['preferredConnectionId'];
    if (retention is! int ||
        !{7, 30, 90}.contains(retention) ||
        favorites is! List ||
        favorites.any((item) => item is! String) ||
        preferred != null && (preferred is! String || preferred.isEmpty)) {
      throw const FormatException('invalid preferences');
    }
    return UserPreferences(
      appearance: jsonEnum(AppearancePreference.values, json, 'appearance'),
      activityRetentionDays: retention,
      favoriteCapabilityKeys: favorites.cast<String>(),
      preferredConnectionId: preferred as String?,
    );
  }
}

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
    this.executionTarget = ExecutionTarget.device,
    this.status = ConnectionStatus.ready,
    this.protocolVersion,
    this.diagnostic,
  });
  final ConnectionId id;
  final ConnectionKind kind;
  final String label;
  final String location;
  final ExecutionTarget executionTarget;
  final ConnectionStatus status;
  final String? protocolVersion;
  final String? diagnostic;
  JsonMap toJson() => {
    'id': id.toJson(),
    'kind': kind.name,
    'label': label,
    'location': location,
    if (executionTarget.kind == ExecutionTargetKind.host)
      'executionTarget': executionTarget.toJson(),
    'status': status.name,
    if (protocolVersion != null) 'protocolVersion': protocolVersion,
    if (diagnostic != null) 'diagnostic': diagnostic,
  };
  factory Connection.fromJson(Object? value) {
    final json = jsonObject(value, 'connection');
    return Connection(
      id: ConnectionId.fromJson(json['id']),
      kind: jsonEnum(ConnectionKind.values, json, 'kind'),
      label: jsonString(json, 'label'),
      location: jsonString(json, 'location'),
      executionTarget: ExecutionTarget.fromJson(json['executionTarget']),
      status: jsonEnum(ConnectionStatus.values, json, 'status'),
      protocolVersion: json['protocolVersion'] as String?,
      diagnostic: json['diagnostic'] as String?,
    );
  }
}

/// User supplied connection details. Executables must be absolute paths.
final class ConnectionSpec {
  const ConnectionSpec({
    required this.kind,
    required this.label,
    this.executionTarget = ExecutionTarget.device,
    this.executable,
    this.arguments = const [],
    this.workingDirectory,
    this.url,
    this.manifestPath,
    this.profileId,
    this.hasCredential = false,
    this.authToken,
  });

  final ConnectionKind kind;
  final String label;
  final ExecutionTarget executionTarget;
  final String? executable;
  final List<String> arguments;
  final String? workingDirectory;
  final String? url;
  final String? manifestPath;

  /// Runtime-owned profile for a connector that supports isolated state.
  final String? profileId;
  final bool hasCredential;

  /// Only used while adding a connection; never written to config JSON.
  final String? authToken;

  JsonMap toJson() => {
    'kind': kind.name,
    'label': label,
    if (executionTarget.kind == ExecutionTargetKind.host)
      'executionTarget': executionTarget.toJson(),
    if (executable != null) 'executable': executable,
    'arguments': arguments,
    if (workingDirectory != null) 'workingDirectory': workingDirectory,
    if (url != null) 'url': url,
    if (manifestPath != null) 'manifestPath': manifestPath,
    if (profileId != null) 'profileId': profileId,
    if (hasCredential) 'hasCredential': true,
  };

  factory ConnectionSpec.fromJson(Object? value) {
    final json = jsonObject(value, 'connectionSpec');
    final rawArguments = json['arguments'] ?? const <String>[];
    if (rawArguments is! List || rawArguments.any((item) => item is! String)) {
      throw const FormatException('arguments must be a string list');
    }
    return ConnectionSpec(
      kind: jsonEnum(ConnectionKind.values, json, 'kind'),
      label: jsonString(json, 'label'),
      executionTarget: ExecutionTarget.fromJson(json['executionTarget']),
      executable: json['executable'] as String?,
      arguments: rawArguments.cast<String>(),
      workingDirectory: json['workingDirectory'] as String?,
      url: json['url'] as String?,
      manifestPath: json['manifestPath'] as String?,
      profileId: json['profileId'] as String?,
      hasCredential: json['hasCredential'] == true,
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
    this.presentation,
  });
  final CapabilityId id;
  final String title;
  final String description;
  final PermissionLevel permission;
  final JsonMap inputSchema;

  /// Optional UI role supplied by a connector, for example `music.pause`.
  final String? presentation;
  JsonMap toJson() => {
    'id': id.toJson(),
    'title': title,
    'description': description,
    'permission': permission.name,
    'inputSchema': inputSchema,
    if (presentation != null) 'presentation': presentation,
  };
  factory Capability.fromJson(Object? value) {
    final json = jsonObject(value, 'capability');
    return Capability(
      id: CapabilityId.fromJson(json['id']),
      title: jsonString(json, 'title'),
      description: jsonString(json, 'description'),
      permission: jsonEnum(PermissionLevel.values, json, 'permission'),
      inputSchema: jsonObject(json['inputSchema'], 'inputSchema'),
      presentation: json['presentation'] as String?,
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
