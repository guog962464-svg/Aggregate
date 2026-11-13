import 'dart:convert';

import 'package:aggregate_connectors/aggregate_connectors.dart';
import 'package:aggregate_contracts/aggregate_contracts.dart';

import '../../host/host_wss_protocol.dart';

const hostRpcMaxFrameBytes = 1024 * 1024;
const maxHostEventSequence = 9007199254740991;
const _maxJsonDepth = 64;
const _maxRpcIdLength = 128;
const _maxOperationIdLength = 128;
const _maxSetupArguments = 256;
const _maxManifestActions = 256;
const _maxManifestArgv = 256;
const _maxManifestProperties = 128;
const _maxManifestRequiredFields = 128;
final _rpcIdPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$');

enum HostRpcErrorCode {
  parseError(-32700, 'Parse error'),
  invalidRequest(-32600, 'Invalid request'),
  methodNotFound(-32601, 'Method not found'),
  invalidParams(-32602, 'Invalid params'),
  internalError(-32603, 'Internal error'),
  unsupportedVersion(-32001, 'Unsupported protocol version'),
  unauthorized(-32002, 'Unauthorized'),
  idempotencyConflict(-32003, 'Idempotency conflict'),
  outcomeUnknown(-32004, 'Operation outcome unknown'),
  cursorExpired(-32005, 'Event cursor expired'),
  payloadTooLarge(-32006, 'Payload too large'),
  operationNotFound(-32007, 'Operation not found'),
  operationLedgerFull(-32008, 'Operation ledger is full'),
  resourceLimitExceeded(-32009, 'Host resource limit exceeded'),
  pairingInvitationExpired(-32010, 'Pairing invitation expired'),
  pairingApprovalRequired(-32011, 'Pairing approval required'),
  deviceAlreadyPaired(-32012, 'Device is already paired'),
  expiredSession(-32013, 'Session expired'),
  replayedRequest(-32014, 'Request replayed'),
  pairingStorageFailure(-32015, 'Pairing storage failed');

  const HostRpcErrorCode(this.value, this.message);

  final int value;
  final String message;
}

enum HostRpcValueKind {
  string,
  identifier,
  integer,
  boolean,
  object,
  stringMap,
  secretStringMap,
  capabilityId,
  resourceRef,
  promptRef,
  setupDraft,
  connectorManifest,
}

final class HostRpcParameter {
  const HostRpcParameter(
    this.name,
    this.kind, {
    this.required = true,
    this.maxLength = 4096,
    this.minValue = 0,
    this.maxValue,
    this.allowEmpty = false,
  });

  final String name;
  final HostRpcValueKind kind;
  final bool required;
  final int maxLength;
  final int? minValue;
  final int? maxValue;
  final bool allowEmpty;
}

final class HostRpcMethodDefinition {
  const HostRpcMethodDefinition(this.name, this.parameters);

  final String name;
  final List<HostRpcParameter> parameters;

  bool get requiresOperationId =>
      name != 'operation.read' &&
      parameters.any(
        (parameter) => parameter.name == 'operationId' && parameter.required,
      );
}

const _str = HostRpcValueKind.string;
const _identifier = HostRpcValueKind.identifier;
const _int = HostRpcValueKind.integer;
const _bool = HostRpcValueKind.boolean;
const _obj = HostRpcValueKind.object;
const _secretStrings = HostRpcValueKind.secretStringMap;
const _capabilityId = HostRpcValueKind.capabilityId;
const _resourceRef = HostRpcValueKind.resourceRef;
const _promptRef = HostRpcValueKind.promptRef;
const _setupDraft = HostRpcValueKind.setupDraft;
const _connectorManifest = HostRpcValueKind.connectorManifest;
const _op = HostRpcParameter(
  'operationId',
  _identifier,
  maxLength: _maxOperationIdLength,
);
const _connectionId = HostRpcParameter(
  'connectionId',
  _identifier,
  maxLength: 128,
);
const _terminalId = HostRpcParameter('terminalId', _identifier, maxLength: 128);
const _draftHandle = HostRpcParameter(
  'draftHandle',
  _identifier,
  maxLength: 128,
);

/// The closed v1 method directory. Adding a method requires an explicit DTO
/// schema here before a later dispatcher can register a handler for it.
final hostRpcMethodCatalog = Map<String, HostRpcMethodDefinition>.unmodifiable({
  for (final method in <HostRpcMethodDefinition>[
    const HostRpcMethodDefinition('host.hello', [
      HostRpcParameter('protocolVersion', _int),
    ]),
    const HostRpcMethodDefinition('host.status', []),
    const HostRpcMethodDefinition('host.pair.request', [
      HostRpcParameter('hostId', _identifier, maxLength: 64),
      HostRpcParameter('deviceId', _identifier, maxLength: 64),
      HostRpcParameter('publicKeySpki', _str, maxLength: 344),
      HostRpcParameter('displayName', _str, maxLength: 80),
      HostRpcParameter('platform', _str, maxLength: 16),
      HostRpcParameter('invitationNonce', _identifier, maxLength: 128),
      HostRpcParameter('timestampSeconds', _int, maxValue: 9007199254740991),
      HostRpcParameter('signatureDer', _str, maxLength: 108),
    ]),
    const HostRpcMethodDefinition('host.auth.begin', [
      HostRpcParameter('deviceId', _identifier, maxLength: 64),
    ]),
    const HostRpcMethodDefinition('host.auth.prove', [
      HostRpcParameter('connectionId', _identifier, maxLength: 128),
      HostRpcParameter('signatureDer', _str, maxLength: 108),
    ]),
    const HostRpcMethodDefinition('operation.read', [_op]),
    const HostRpcMethodDefinition('connection.list', []),
    const HostRpcMethodDefinition('connection.refresh', [_op, _connectionId]),
    const HostRpcMethodDefinition('connection.remove', [_op, _connectionId]),
    const HostRpcMethodDefinition('connection.move', [
      _op,
      _connectionId,
      HostRpcParameter('offset', _int, minValue: -1, maxValue: 1),
    ]),
    const HostRpcMethodDefinition('setup.adapters', []),
    const HostRpcMethodDefinition('setup.detectExecutable', [
      HostRpcParameter('adapterId', _identifier, maxLength: 128),
    ]),
    const HostRpcMethodDefinition('setup.test', [
      _op,
      HostRpcParameter('draft', _setupDraft),
      HostRpcParameter('secretValues', _secretStrings, required: false),
    ]),
    const HostRpcMethodDefinition('setup.save', [_op, _draftHandle]),
    const HostRpcMethodDefinition('setup.discard', [_op, _draftHandle]),
    const HostRpcMethodDefinition('capability.search', [
      HostRpcParameter('query', _str, maxLength: 512, allowEmpty: true),
    ]),
    const HostRpcMethodDefinition('run.invoke', [
      _op,
      HostRpcParameter('capability', _capabilityId),
      HostRpcParameter('arguments', _obj),
    ]),
    const HostRpcMethodDefinition('run.subscribe', [
      HostRpcParameter('runId', _identifier, maxLength: 128),
      HostRpcParameter('afterSequence', _int, required: false),
    ]),
    const HostRpcMethodDefinition('run.cancel', [
      _op,
      HostRpcParameter('runId', _identifier, maxLength: 128),
    ]),
    const HostRpcMethodDefinition('run.listRecent', [
      HostRpcParameter('limit', _int, required: false, maxValue: 100),
    ]),
    const HostRpcMethodDefinition('activity.clear', [_op]),
    const HostRpcMethodDefinition('resource.read', [
      HostRpcParameter('ref', _resourceRef),
    ]),
    const HostRpcMethodDefinition('prompt.get', [
      HostRpcParameter('ref', _promptRef),
      HostRpcParameter('arguments', _obj),
    ]),
    const HostRpcMethodDefinition('manifest.get', [_connectionId]),
    const HostRpcMethodDefinition('manifest.save', [
      _op,
      _connectionId,
      HostRpcParameter('manifest', _connectorManifest),
    ]),
    const HostRpcMethodDefinition('manifest.readContent', [
      _connectionId,
      HostRpcParameter('manifestRef', _identifier, maxLength: 128),
    ]),
    const HostRpcMethodDefinition('manifest.exportContent', [
      _op,
      _connectionId,
      HostRpcParameter('manifestRef', _identifier, maxLength: 128),
      HostRpcParameter('transferHandle', _identifier, maxLength: 128),
    ]),
    const HostRpcMethodDefinition('account.read', [_connectionId]),
    const HostRpcMethodDefinition('account.beginLogin', [_op, _connectionId]),
    const HostRpcMethodDefinition('account.waitLogin', [
      HostRpcParameter('sessionId', _identifier, maxLength: 128),
    ]),
    const HostRpcMethodDefinition('account.logout', [
      _op,
      _connectionId,
      HostRpcParameter('confirmed', _bool),
    ]),
    const HostRpcMethodDefinition('terminal.open', [_op, _connectionId]),
    const HostRpcMethodDefinition('terminal.subscribe', [
      _terminalId,
      HostRpcParameter('afterSequence', _int, required: false),
    ]),
    const HostRpcMethodDefinition('terminal.write', [
      _op,
      _terminalId,
      HostRpcParameter('text', _str, maxLength: hostRpcMaxFrameBytes),
    ]),
    const HostRpcMethodDefinition('terminal.resize', [
      _op,
      _terminalId,
      HostRpcParameter('columns', _int, minValue: 1, maxValue: 400),
      HostRpcParameter('rows', _int, minValue: 1, maxValue: 200),
    ]),
    const HostRpcMethodDefinition('terminal.interrupt', [_op, _terminalId]),
    const HostRpcMethodDefinition('terminal.close', [_op, _terminalId]),
  ])
    method.name: method,
});

final class HostRpcProtocolException implements Exception {
  const HostRpcProtocolException(this.code, {this.requestId});

  final HostRpcErrorCode code;
  final String? requestId;

  JsonMap toResponse() => {
    'jsonrpc': '2.0',
    'id': requestId,
    'error': {'code': code.value, 'message': code.message},
  };

  @override
  String toString() => 'HostRpcProtocolException(${code.name})';
}

final class HostRpcRequest {
  const HostRpcRequest({
    required this.id,
    required this.method,
    required this.params,
    this.operationId,
  });

  final String id;
  final String method;
  final JsonMap params;
  final String? operationId;

  /// The canonicalizer hashes this method/params pair for idempotency. The
  /// request ID and operation ID are deliberately excluded.
  JsonMap get operationPayload => {
    'method': method,
    'params': Map<String, Object?>.of(params)..remove('operationId'),
  };
}

/// Public setup fields and opaque Host-issued references only. Raw Mac paths
/// are rejected by the DTO shape; secret values travel in a separate map.
final class HostSetupDraftPayload {
  const HostSetupDraftPayload({
    required this.adapterId,
    required this.label,
    required this.fieldValues,
    this.url,
    this.executableRef,
    this.manifestRef,
    this.arguments = const [],
  });

  final String adapterId;
  final String label;
  final Map<String, String> fieldValues;
  final String? url;
  final String? executableRef;
  final String? manifestRef;
  final List<String> arguments;

  JsonMap toJson() => {
    'adapterId': adapterId,
    'label': label,
    'fieldValues': fieldValues,
    if (url != null) 'url': url,
    if (executableRef != null) 'executableRef': executableRef,
    if (manifestRef != null) 'manifestRef': manifestRef,
    if (arguments.isNotEmpty) 'arguments': arguments,
  };

  factory HostSetupDraftPayload.fromJson(Object? value) {
    if (value is! Map || value.keys.any((key) => key is! String)) {
      throw const FormatException('Host setup draft is invalid');
    }
    final json = value.cast<String, Object?>();
    if (!_onlyKeys(json, const {
          'adapterId',
          'label',
          'fieldValues',
          'url',
          'executableRef',
          'manifestRef',
          'arguments',
        }) ||
        json['adapterId'] is! String ||
        !_validRpcId(json['adapterId']! as String) ||
        json['label'] is! String ||
        (json['label']! as String).trim().isEmpty ||
        (json['label']! as String).length > 100 ||
        !_isStringMap(json['fieldValues']) ||
        (json['url'] != null &&
            (json['url'] is! String ||
                !_isHostHttpUrl(json['url']! as String))) ||
        (json['executableRef'] != null &&
            (json['executableRef'] is! String ||
                !_validRpcId(json['executableRef']! as String))) ||
        (json['manifestRef'] != null &&
            (json['manifestRef'] is! String ||
                !_validRpcId(json['manifestRef']! as String))) ||
        (json['arguments'] != null &&
            (json['arguments'] is! List ||
                (json['arguments']! as List).length > _maxSetupArguments ||
                (json['arguments']! as List).any(
                  (argument) =>
                      argument is! String ||
                      argument.length > 4096 ||
                      argument.contains('\u0000'),
                )))) {
      throw const FormatException('Host setup draft is invalid');
    }
    return HostSetupDraftPayload(
      adapterId: json['adapterId']! as String,
      label: json['label']! as String,
      fieldValues: Map.unmodifiable(
        (json['fieldValues']! as Map).cast<String, String>(),
      ),
      url: json['url'] as String?,
      executableRef: json['executableRef'] as String?,
      manifestRef: json['manifestRef'] as String?,
      arguments: List.unmodifiable(
        (json['arguments'] as List? ?? const []).cast<String>(),
      ),
    );
  }
}

/// Manifest editing data uses an opaque executable reference. The Mac-side
/// dispatcher resolves it to the already registered executable path.
final class HostConnectorManifestPayload {
  const HostConnectorManifestPayload({
    required this.executableRef,
    required this.manifest,
  });

  final String executableRef;
  final ConnectorManifest manifest;

  JsonMap toJson() {
    final fields = manifest.toJson()..remove('executable');
    return {...fields, 'executableRef': executableRef};
  }

  factory HostConnectorManifestPayload.fromJson(Object? value) {
    if (value is! Map || value.keys.any((key) => key is! String)) {
      throw const FormatException('Host manifest is invalid');
    }
    final json = value.cast<String, Object?>();
    if (!_onlyKeys(json, const {
          'schemaVersion',
          'id',
          'displayName',
          'platforms',
          'executableRef',
          'actions',
        }) ||
        json['schemaVersion'] != 1 ||
        json['id'] is! String ||
        !_validRpcId(json['id']! as String) ||
        json['displayName'] is! String ||
        (json['displayName']! as String).trim().isEmpty ||
        json['executableRef'] is! String ||
        !_validRpcId(json['executableRef']! as String) ||
        json['platforms'] is! List ||
        (json['platforms']! as List).length > 6 ||
        (json['platforms']! as List).any((platform) => platform is! String) ||
        !_hasStrictConnectorActions(json['actions'])) {
      throw const FormatException('Host manifest is invalid');
    }

    final manifest = ConnectorManifest.fromJson({
      ...json,
      'executable': '/host-opaque-reference-placeholder',
    });
    if (!manifest.supports('macos')) {
      throw const FormatException('Host manifest must support macOS');
    }
    return HostConnectorManifestPayload(
      executableRef: json['executableRef']! as String,
      manifest: manifest,
    );
  }
}

final class HostEventCursor {
  const HostEventCursor(this.sequence)
    : assert(sequence >= 0 && sequence <= maxHostEventSequence);

  final int sequence;

  JsonMap toJson() => {'sequence': sequence};

  factory HostEventCursor.fromJson(Object? value) {
    if (value is! Map ||
        value.keys.any((key) => key is! String) ||
        value.keys.toSet().difference(const {'sequence'}).isNotEmpty ||
        value['sequence'] is! int ||
        (value['sequence']! as int) < 0 ||
        (value['sequence']! as int) > maxHostEventSequence) {
      throw const FormatException('Host event cursor is invalid');
    }
    return HostEventCursor(value['sequence']! as int);
  }
}

final class HostRunEventNotification {
  const HostRunEventNotification({
    required this.subscriptionId,
    required this.event,
  });

  final String subscriptionId;
  final RunEvent event;

  JsonMap toJson() => {
    'jsonrpc': '2.0',
    'method': 'run.event',
    'params': {
      'subscriptionId': subscriptionId,
      'sequence': event.sequence,
      'event': event.toJson(),
    },
  };

  factory HostRunEventNotification.fromJson(Object? value) {
    final json = _strictJsonObject(value, const {
      'jsonrpc',
      'method',
      'params',
    });
    if (json['jsonrpc'] != '2.0' || json['method'] != 'run.event') {
      throw const FormatException('Host run event is invalid');
    }
    final params = _strictJsonObject(json['params'], const {
      'subscriptionId',
      'sequence',
      'event',
    });
    if (params['subscriptionId'] is! String ||
        !_validRpcId(params['subscriptionId']! as String) ||
        params['sequence'] is! int ||
        (params['sequence']! as int) < 0 ||
        (params['sequence']! as int) > maxHostEventSequence) {
      throw const FormatException('Host run event is invalid');
    }
    final rawEvent = _strictJsonObject(
      params['event'],
      const {'runId', 'sequence', 'state', 'occurredAt', 'blocks', 'failure'},
      optional: const {'failure'},
    );
    final event = RunEvent.fromJson(rawEvent);
    if (event.sequence != params['sequence']) {
      throw const FormatException('Host run event sequence mismatch');
    }
    return HostRunEventNotification(
      subscriptionId: params['subscriptionId']! as String,
      event: event,
    );
  }
}

enum HostTerminalEventKind { output, closed, failed }

final class HostTerminalEvent {
  const HostTerminalEvent({
    required this.terminalId,
    required this.sequence,
    required this.kind,
    this.text,
  }) : assert(sequence >= 0 && sequence <= maxHostEventSequence);

  final String terminalId;
  final int sequence;
  final HostTerminalEventKind kind;
  final String? text;

  JsonMap toJson() => {
    'terminalId': terminalId,
    'sequence': sequence,
    'kind': kind.name,
    if (text != null) 'text': text,
  };

  factory HostTerminalEvent.fromJson(Object? value) {
    final json = _strictJsonObject(
      value,
      const {'terminalId', 'sequence', 'kind', 'text'},
      optional: const {'text'},
    );
    final kindName = json['kind'];
    final kinds = HostTerminalEventKind.values.where(
      (kind) => kind.name == kindName,
    );
    final text = json['text'];
    if (json['terminalId'] is! String ||
        !_validRpcId(json['terminalId']! as String) ||
        json['sequence'] is! int ||
        (json['sequence']! as int) < 0 ||
        (json['sequence']! as int) > maxHostEventSequence ||
        kinds.isEmpty ||
        (text != null &&
            (text is! String ||
                text.length > hostRpcMaxFrameBytes ||
                text.contains('\u0000')))) {
      throw const FormatException('Host terminal event is invalid');
    }
    final kind = kinds.single;
    if ((kind == HostTerminalEventKind.output) != (text is String)) {
      throw const FormatException('Host terminal event is invalid');
    }
    return HostTerminalEvent(
      terminalId: json['terminalId']! as String,
      sequence: json['sequence']! as int,
      kind: kind,
      text: text as String?,
    );
  }
}

final class HostTerminalEventNotification {
  const HostTerminalEventNotification({
    required this.subscriptionId,
    required this.event,
  });

  final String subscriptionId;
  final HostTerminalEvent event;

  JsonMap toJson() => {
    'jsonrpc': '2.0',
    'method': 'terminal.event',
    'params': {
      'subscriptionId': subscriptionId,
      'sequence': event.sequence,
      'event': event.toJson(),
    },
  };

  factory HostTerminalEventNotification.fromJson(Object? value) {
    final json = _strictJsonObject(value, const {
      'jsonrpc',
      'method',
      'params',
    });
    if (json['jsonrpc'] != '2.0' || json['method'] != 'terminal.event') {
      throw const FormatException('Host terminal notification is invalid');
    }
    final params = _strictJsonObject(json['params'], const {
      'subscriptionId',
      'sequence',
      'event',
    });
    final event = HostTerminalEvent.fromJson(params['event']);
    if (params['subscriptionId'] is! String ||
        !_validRpcId(params['subscriptionId']! as String) ||
        params['sequence'] is! int ||
        (params['sequence']! as int) > maxHostEventSequence ||
        params['sequence'] != event.sequence) {
      throw const FormatException('Host terminal notification is invalid');
    }
    return HostTerminalEventNotification(
      subscriptionId: params['subscriptionId']! as String,
      event: event,
    );
  }
}

abstract final class HostRpcCodec {
  /// Decodes a bounded JSON object with exactly the expected keys. Used for
  /// authenticated transport envelopes that are not RPC requests themselves.
  static JsonMap decodeStrictObject(String text, Set<String> expectedKeys) {
    if (utf8.encode(text).length > hostRpcMaxFrameBytes) {
      throw const HostRpcProtocolException(HostRpcErrorCode.payloadTooLarge);
    }
    if (_exceedsJsonDepth(text)) {
      throw const HostRpcProtocolException(HostRpcErrorCode.invalidRequest);
    }
    Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      throw const HostRpcProtocolException(HostRpcErrorCode.parseError);
    }
    if (_hasDuplicateJsonKeys(text) ||
        decoded is! Map ||
        decoded.keys.any((key) => key is! String)) {
      throw const HostRpcProtocolException(HostRpcErrorCode.invalidRequest);
    }
    final json = decoded.cast<String, Object?>();
    if (json.keys.toSet().difference(expectedKeys).isNotEmpty ||
        expectedKeys.difference(json.keys.toSet()).isNotEmpty) {
      throw const HostRpcProtocolException(HostRpcErrorCode.invalidRequest);
    }
    return Map.unmodifiable(json);
  }

  static HostRpcRequest decodeRequest(String text) {
    if (utf8.encode(text).length > hostRpcMaxFrameBytes) {
      throw const HostRpcProtocolException(HostRpcErrorCode.payloadTooLarge);
    }
    if (_exceedsJsonDepth(text)) {
      throw const HostRpcProtocolException(HostRpcErrorCode.invalidRequest);
    }

    Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      throw const HostRpcProtocolException(HostRpcErrorCode.parseError);
    }
    if (_hasDuplicateJsonKeys(text)) {
      throw const HostRpcProtocolException(HostRpcErrorCode.invalidRequest);
    }
    if (decoded is! Map) {
      throw const HostRpcProtocolException(HostRpcErrorCode.invalidRequest);
    }
    if (decoded.keys.any((key) => key is! String)) {
      throw const HostRpcProtocolException(HostRpcErrorCode.invalidRequest);
    }
    final json = decoded.cast<String, Object?>();
    final idValue = json['id'];
    final requestId = idValue is String && _validRpcId(idValue)
        ? idValue
        : null;
    if (!_onlyKeys(json, const {'jsonrpc', 'id', 'method', 'params'}) ||
        json['jsonrpc'] != '2.0' ||
        requestId == null ||
        json['method'] is! String) {
      throw HostRpcProtocolException(
        HostRpcErrorCode.invalidRequest,
        requestId: requestId,
      );
    }

    final methodName = json['method']! as String;
    final definition = hostRpcMethodCatalog[methodName];
    if (definition == null) {
      throw HostRpcProtocolException(
        HostRpcErrorCode.methodNotFound,
        requestId: requestId,
      );
    }
    final rawParams = json['params'];
    if (rawParams is! Map || rawParams.keys.any((key) => key is! String)) {
      throw HostRpcProtocolException(
        HostRpcErrorCode.invalidParams,
        requestId: requestId,
      );
    }
    final params = rawParams.cast<String, Object?>();
    _validateParams(definition, params, requestId);
    return HostRpcRequest(
      id: requestId,
      method: methodName,
      params: Map<String, Object?>.unmodifiable(params),
      operationId: params['operationId'] as String?,
    );
  }

  /// Encodes a response or notification and enforces the frame limit in both
  /// directions. Event DTOs use this before writing their JSON over a socket.
  static String encodeFrame(Object? frame) {
    final text = jsonEncode(frame);
    if (_exceedsJsonDepth(text) ||
        utf8.encode(text).length > hostRpcMaxFrameBytes) {
      throw const HostRpcProtocolException(HostRpcErrorCode.payloadTooLarge);
    }
    return text;
  }

  static String encodeSuccess(String requestId, Object? result) =>
      encodeFrame({'jsonrpc': '2.0', 'id': requestId, 'result': result});

  static String encodeError(String? requestId, HostRpcErrorCode code) =>
      encodeFrame({
        'jsonrpc': '2.0',
        'id': requestId,
        'error': {'code': code.value, 'message': code.message},
      });

  static void _validateParams(
    HostRpcMethodDefinition definition,
    JsonMap params,
    String requestId,
  ) {
    final allowed = definition.parameters.map((field) => field.name).toSet();
    if (params.keys.any((key) => !allowed.contains(key))) {
      throw HostRpcProtocolException(
        HostRpcErrorCode.invalidParams,
        requestId: requestId,
      );
    }
    for (final field in definition.parameters) {
      if (!params.containsKey(field.name)) {
        if (field.required) {
          throw HostRpcProtocolException(
            HostRpcErrorCode.invalidParams,
            requestId: requestId,
          );
        }
        continue;
      }
      final value = params[field.name];
      final valid = switch (field.kind) {
        HostRpcValueKind.string =>
          value is String &&
              (field.allowEmpty || value.isNotEmpty) &&
              value.length <= field.maxLength &&
              !value.contains('\u0000'),
        HostRpcValueKind.identifier =>
          value is String &&
              value.length <= field.maxLength &&
              _validRpcId(value),
        HostRpcValueKind.integer =>
          value is int &&
              (field.minValue == null || value >= field.minValue!) &&
              (field.maxValue == null || value <= field.maxValue!),
        HostRpcValueKind.boolean => value is bool,
        HostRpcValueKind.object => value is Map,
        HostRpcValueKind.stringMap => _isStringMap(value),
        HostRpcValueKind.secretStringMap => _isSecretStringMap(value),
        HostRpcValueKind.capabilityId => _isCapabilityId(value),
        HostRpcValueKind.resourceRef => _isResourceRef(value),
        HostRpcValueKind.promptRef => _isPromptRef(value),
        HostRpcValueKind.setupDraft => _isSetupDraft(value),
        HostRpcValueKind.connectorManifest => _isConnectorManifest(value),
      };
      if (!valid) {
        throw HostRpcProtocolException(
          HostRpcErrorCode.invalidParams,
          requestId: requestId,
        );
      }
      if (field.name == 'offset' && value != -1 && value != 1) {
        throw HostRpcProtocolException(
          HostRpcErrorCode.invalidParams,
          requestId: requestId,
        );
      }
      if (field.name == 'afterSequence' &&
          (value! as int) > maxHostEventSequence) {
        throw HostRpcProtocolException(
          HostRpcErrorCode.invalidParams,
          requestId: requestId,
        );
      }
      if (field.name == 'protocolVersion' && value != hostProtocolVersion) {
        throw HostRpcProtocolException(
          HostRpcErrorCode.unsupportedVersion,
          requestId: requestId,
        );
      }
    }
  }
}

JsonMap _strictJsonObject(
  Object? value,
  Set<String> allowed, {
  Set<String> optional = const {},
}) {
  if (value is! Map || value.keys.any((key) => key is! String)) {
    throw const FormatException('Host DTO object is invalid');
  }
  final json = value.cast<String, Object?>();
  if (json.keys.any((key) => !allowed.contains(key)) ||
      allowed.difference(optional).any((key) => !json.containsKey(key))) {
    throw const FormatException('Host DTO object is invalid');
  }
  return json;
}

bool _onlyKeys(Map<String, Object?> json, Set<String> allowed) =>
    json.keys.every(allowed.contains);

bool _validRpcId(String value) =>
    value.length <= _maxRpcIdLength && _rpcIdPattern.hasMatch(value);

bool _isStringMap(Object? value) =>
    value is Map &&
    value.length <= 128 &&
    value.entries.every(
      (entry) =>
          entry.key is String &&
          (entry.key as String).isNotEmpty &&
          (entry.key as String).length <= 128 &&
          entry.value is String &&
          (entry.value as String).length <= 4096,
    );

bool _isSecretStringMap(Object? value) =>
    value is Map &&
    value.length <= 16 &&
    value.entries.every(
      (entry) =>
          entry.key is String &&
          _validRpcId(entry.key as String) &&
          entry.value is String &&
          (entry.value as String).length <= 32 * 1024 &&
          !(entry.value as String).contains('\u0000'),
    );

bool _isHostHttpUrl(String value) {
  if (value.isEmpty ||
      value.length > 2048 ||
      RegExp(r'[\x00-\x1f\x7f]').hasMatch(value)) {
    return false;
  }
  final uri = Uri.tryParse(value);
  return uri != null &&
      uri.hasAuthority &&
      const {'http', 'https'}.contains(uri.scheme) &&
      uri.userInfo.isEmpty;
}

bool _isCapabilityId(Object? value) {
  if (value is! Map ||
      value.keys.any((key) => key is! String) ||
      !_onlyKeys(value.cast<String, Object?>(), const {
        'connection',
        'kind',
        'name',
      })) {
    return false;
  }
  final json = value.cast<String, Object?>();
  final connection = json['connection'];
  return connection is Map &&
      connection.keys.every((key) => key == 'value') &&
      connection.length == 1 &&
      connection['value'] is String &&
      _validRpcId(connection['value']! as String) &&
      json['kind'] is String &&
      CapabilityKind.values.any((kind) => kind.name == json['kind']) &&
      json['name'] is String &&
      _validRpcId(json['name']! as String);
}

bool _isResourceRef(Object? value) {
  if (value is! Map ||
      value.keys.any((key) => key is! String) ||
      !_onlyKeys(value.cast<String, Object?>(), const {'capability', 'uri'})) {
    return false;
  }
  final json = value.cast<String, Object?>();
  return _isCapabilityId(json['capability']) &&
      json['uri'] is String &&
      (json['uri']! as String).isNotEmpty &&
      Uri.tryParse(json['uri']! as String) != null;
}

bool _isPromptRef(Object? value) {
  if (value is! Map ||
      value.keys.any((key) => key is! String) ||
      !_onlyKeys(value.cast<String, Object?>(), const {'capability'})) {
    return false;
  }
  return _isCapabilityId(value['capability']);
}

bool _isSetupDraft(Object? value) {
  try {
    HostSetupDraftPayload.fromJson(value);
    return true;
  } on FormatException {
    return false;
  } on TypeError {
    return false;
  }
}

bool _isConnectorManifest(Object? value) {
  try {
    HostConnectorManifestPayload.fromJson(value);
    return true;
  } on FormatException {
    return false;
  } on TypeError {
    return false;
  }
}

bool _hasStrictConnectorActions(Object? value) {
  if (value is! List || value.isEmpty || value.length > _maxManifestActions) {
    return false;
  }
  for (final item in value) {
    if (item is! Map || item.keys.any((key) => key is! String)) return false;
    final action = item.cast<String, Object?>();
    if (!_onlyKeys(action, const {
          'id',
          'title',
          'argv',
          'inputSchema',
          'output',
          'permission',
          'timeoutMs',
          'presentation',
        }) ||
        action.keys.toSet().difference(const {
              'id',
              'title',
              'argv',
              'inputSchema',
              'output',
              'permission',
              'timeoutMs',
            }).length >
            1) {
      return false;
    }
    final argv = action['argv'];
    if (argv is! List ||
        argv.isEmpty ||
        argv.length > _maxManifestArgv ||
        argv.any(
          (argument) =>
              argument is! String || argument.isEmpty || argument.length > 4096,
        )) {
      return false;
    }
    final inputSchema = action['inputSchema'];
    if (inputSchema is! Map || inputSchema.keys.any((key) => key is! String)) {
      return false;
    }
    final schema = inputSchema.cast<String, Object?>();
    if (!_onlyKeys(schema, const {
          'type',
          'properties',
          'required',
          'additionalProperties',
        }) ||
        schema['type'] != 'object' ||
        schema['properties'] is! Map ||
        (schema['properties']! as Map).length > _maxManifestProperties ||
        (schema['additionalProperties'] != null &&
            schema['additionalProperties'] != false)) {
      return false;
    }
    final properties = schema['properties']! as Map;
    if (properties.keys.any((key) => key is! String)) return false;
    final required = schema['required'];
    if (required != null &&
        (required is! List ||
            required.length > _maxManifestRequiredFields ||
            required.any((field) => field is! String || field.isEmpty))) {
      return false;
    }
    for (final property in properties.values) {
      if (property is! Map || property.keys.any((key) => key is! String)) {
        return false;
      }
      final definition = property.cast<String, Object?>();
      if (!_onlyKeys(definition, const {
            'type',
            'title',
            'minimum',
            'maximum',
          }) ||
          !const {
            'string',
            'integer',
            'number',
            'boolean',
          }.contains(definition['type'])) {
        return false;
      }
    }
  }
  return true;
}

bool _exceedsJsonDepth(String text) {
  var depth = 0;
  var inString = false;
  var escaped = false;
  for (var index = 0; index < text.length; index++) {
    final code = text.codeUnitAt(index);
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (code == 0x5c) {
        escaped = true;
      } else if (code == 0x22) {
        inString = false;
      }
      continue;
    }
    if (code == 0x22) {
      inString = true;
    } else if (code == 0x7b || code == 0x5b) {
      depth++;
      if (depth > _maxJsonDepth) return true;
    } else if (code == 0x7d || code == 0x5d) {
      depth--;
    }
  }
  return false;
}

bool _hasDuplicateJsonKeys(String text) {
  final scanner = _DuplicateJsonKeyScanner(text);
  scanner.scanValue();
  return scanner.foundDuplicate;
}

/// jsonDecode keeps the last value for duplicate object keys. Reject them
/// before schema validation so the sender and receiver cannot disagree about
/// which value was signed or authorized.
final class _DuplicateJsonKeyScanner {
  _DuplicateJsonKeyScanner(this.text);

  final String text;
  var index = 0;
  var foundDuplicate = false;

  void scanValue() {
    _skipWhitespace();
    if (index >= text.length) return;
    switch (text.codeUnitAt(index)) {
      case 0x7b: // {
        _scanObject();
      case 0x5b: // [
        _scanArray();
      case 0x22: // "
        _scanString();
      default:
        while (index < text.length &&
            !_isValueDelimiter(text.codeUnitAt(index))) {
          index++;
        }
    }
  }

  void _scanObject() {
    index++;
    _skipWhitespace();
    if (_consume(0x7d)) return;
    final keys = <String>{};
    while (index < text.length && !foundDuplicate) {
      _skipWhitespace();
      final key = _scanString();
      if (!keys.add(key)) {
        foundDuplicate = true;
        return;
      }
      _skipWhitespace();
      _consume(0x3a); // :
      scanValue();
      _skipWhitespace();
      if (_consume(0x7d)) return;
      if (!_consume(0x2c)) return; // ,
    }
  }

  void _scanArray() {
    index++;
    _skipWhitespace();
    if (_consume(0x5d)) return;
    while (index < text.length && !foundDuplicate) {
      scanValue();
      _skipWhitespace();
      if (_consume(0x5d)) return;
      if (!_consume(0x2c)) return; // ,
    }
  }

  String _scanString() {
    final start = index;
    index++;
    while (index < text.length) {
      final code = text.codeUnitAt(index++);
      if (code == 0x5c) {
        if (index < text.length) index++;
      } else if (code == 0x22) {
        return jsonDecode(text.substring(start, index)) as String;
      }
    }
    return '';
  }

  bool _consume(int code) {
    if (index < text.length && text.codeUnitAt(index) == code) {
      index++;
      return true;
    }
    return false;
  }

  void _skipWhitespace() {
    while (index < text.length &&
        const [0x20, 0x09, 0x0a, 0x0d].contains(text.codeUnitAt(index))) {
      index++;
    }
  }

  bool _isValueDelimiter(int code) =>
      const [0x20, 0x09, 0x0a, 0x0d, 0x2c, 0x5d, 0x7d].contains(code);
}
