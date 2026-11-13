import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:aggregate_contracts/aggregate_contracts.dart';

import 'host_rpc_protocol.dart';

const _hostSetupAdapterIds = {'netease-music', 'cli', 'mcp-stdio', 'mcp-http'};
final _hostSetupReferencePattern = RegExp(
  r'^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$',
);
const _maxHostSetupDrafts = 256;
const _maxHostSetupDraftsPerDevice = 16;
const _maxHostExecutableReferences = 256;
const _safeSetupCheckLabels = {
  '程序与配置',
  '账号登录',
  '搜索接口',
  '程序检查',
  '功能验证',
  '连通性',
  '连接测试',
};

final class HostSetupFieldPayload {
  const HostSetupFieldPayload({
    required this.key,
    required this.label,
    required this.kind,
    required this.required,
    this.hint,
    required this.readFileContent,
  });

  final String key;
  final String label;
  final SetupFieldKind kind;
  final bool required;
  final String? hint;
  final bool readFileContent;

  JsonMap toJson() => {
    'key': key,
    'label': label,
    'kind': kind.name,
    'required': required,
    if (hint != null) 'hint': hint,
    'readFileContent': readFileContent,
  };
}

final class HostSetupAdapterPayload {
  const HostSetupAdapterPayload({
    required this.id,
    required this.label,
    required this.kind,
    required this.fields,
    this.defaultLabel,
    this.description,
    required this.showGenericCliFields,
    required this.autoDetectExecutable,
  });

  final String id;
  final String label;
  final ConnectionKind kind;
  final List<HostSetupFieldPayload> fields;
  final String? defaultLabel;
  final String? description;
  final bool showGenericCliFields;
  final bool autoDetectExecutable;

  factory HostSetupAdapterPayload.fromAdapter(ConnectionAdapter adapter) =>
      HostSetupAdapterPayload(
        id: adapter.id,
        label: adapter.label,
        kind: adapter.kind,
        fields: List.unmodifiable([
          for (final field in adapter.fields)
            HostSetupFieldPayload(
              key: field.key,
              label: field.label,
              kind: field.kind,
              required: field.required,
              hint: field.hint,
              readFileContent: field.readFileContent,
            ),
        ]),
        defaultLabel: adapter.defaultLabel,
        description: adapter.description,
        showGenericCliFields: adapter.showGenericCliFields,
        autoDetectExecutable: adapter.autoDetectExecutable,
      );

  JsonMap toJson() => {
    'id': id,
    'label': label,
    'kind': kind.name,
    'fields': [for (final field in fields) field.toJson()],
    if (defaultLabel != null) 'defaultLabel': defaultLabel,
    if (description != null) 'description': description,
    'showGenericCliFields': showGenericCliFields,
    'autoDetectExecutable': autoDetectExecutable,
  };
}

final class HostDetectedExecutable {
  const HostDetectedExecutable({
    required this.executableRef,
    required this.displayLocation,
    required this.expiresAt,
  });

  final String executableRef;
  final String displayLocation;
  final DateTime expiresAt;

  JsonMap toJson() => {
    'executableRef': executableRef,
    'displayLocation': displayLocation,
    'expiresAt': expiresAt.toUtc().toIso8601String(),
  };
}

final class HostSetupCheckPayload {
  const HostSetupCheckPayload({
    required this.label,
    required this.status,
    required this.detail,
  });

  final String label;
  final SetupCheckStatus status;
  final String detail;

  JsonMap toJson() => {'label': label, 'status': status.name, 'detail': detail};
}

final class HostSetupTestResult {
  const HostSetupTestResult({
    required this.canSave,
    required this.checks,
    this.draftHandle,
  });

  final bool canSave;
  final List<HostSetupCheckPayload> checks;
  final String? draftHandle;

  JsonMap toJson() => {
    'canSave': canSave,
    if (draftHandle != null) 'draftHandle': draftHandle,
    'checks': [for (final check in checks) check.toJson()],
  };
}

final class HostSetupSavedConnection {
  const HostSetupSavedConnection({
    required this.connectionId,
    required this.kind,
    required this.label,
    required this.status,
  });

  final String connectionId;
  final ConnectionKind kind;
  final String label;
  final ConnectionStatus status;

  JsonMap toJson() => {
    'connectionId': connectionId,
    'kind': kind.name,
    'label': label,
    'status': status.name,
    'executionLocation': 'Mac 主机',
  };
}

/// Applies Host adapter policy around the existing Mac connection setup port.
/// Raw paths and secret values stay inside this process and the runtime.
///
/// The caller must pass an identity from a verified session and enforce grants;
/// this component does not authenticate a device or open a network listener.
final class HostSetupCoordinator {
  HostSetupCoordinator({
    required this.setup,
    DateTime Function()? now,
    Random? random,
    this.referenceLifetime = const Duration(minutes: 10),
    Set<String> allowedAdapterIds = _hostSetupAdapterIds,
  }) : _now = now ?? DateTime.now,
       _random = random ?? Random.secure(),
       _allowedAdapterIds = Set.unmodifiable(allowedAdapterIds) {
    if (referenceLifetime <= Duration.zero ||
        _allowedAdapterIds.isEmpty ||
        _allowedAdapterIds.any(
          (id) => !_hostSetupReferencePattern.hasMatch(id),
        )) {
      throw ArgumentError('Invalid Host setup policy');
    }
  }

  final ConnectionSetupPort setup;
  final Duration referenceLifetime;
  final DateTime Function() _now;
  final Random _random;
  final Set<String> _allowedAdapterIds;
  final Map<String, _HostExecutableRecord> _executables = {};
  final Map<String, _HostDraftRecord> _drafts = {};
  final Set<String> _closedDevices = {};
  final Set<String> _pendingCleanup = {};
  Future<void> _tail = Future<void>.value();

  List<HostSetupAdapterPayload> listAdapters() => List.unmodifiable([
    for (final adapter in setup.connectionAdapters)
      if (_allowedAdapterIds.contains(adapter.id) &&
          !_hasUnresolvedFilePathField(adapter))
        HostSetupAdapterPayload.fromAdapter(adapter),
  ]);

  /// Clears a local revocation marker after the pairing authority approves the
  /// same stable device identity again. This does not grant RPC permissions.
  void admitPairedDevice(String deviceId) {
    _validateDeviceId(deviceId);
    _closedDevices.remove(deviceId);
  }

  Future<HostDetectedExecutable?> detectExecutable({
    required String deviceId,
    required String adapterId,
  }) => _serialize(() async {
    _validateDeviceId(deviceId);
    _ensureDeviceOpen(deviceId);
    await _sweepExpired();
    final adapter = _adapter(adapterId);
    if (!adapter.autoDetectExecutable) _throw(HostRpcErrorCode.invalidParams);
    final path = await setup.detectExecutable(adapterId);
    if (path == null) return null;
    if (!path.startsWith('/') || path.contains('\u0000')) {
      _throw(HostRpcErrorCode.internalError);
    }
    for (final entry in _executables.entries.toList()) {
      final record = entry.value;
      if (record.deviceId == deviceId && record.adapterId == adapterId) {
        _executables.remove(entry.key);
      }
    }
    if (_executables.length >= _maxHostExecutableReferences) {
      _throw(HostRpcErrorCode.resourceLimitExceeded);
    }
    final reference = _newReference();
    final expiry = _utcNow().add(referenceLifetime);
    _executables[_key(deviceId, reference)] = _HostExecutableRecord(
      deviceId: deviceId,
      adapterId: adapterId,
      path: path,
      expiresAt: expiry,
    );
    return HostDetectedExecutable(
      executableRef: reference,
      displayLocation: 'Mac 主机 · ${_programLabel(adapterId)}',
      expiresAt: expiry,
    );
  });

  Future<HostSetupTestResult> testConnectionSetup({
    required String deviceId,
    required HostSetupDraftPayload draft,
    Map<String, String> secretValues = const {},
  }) => _serialize(() async {
    _validateDeviceId(deviceId);
    _ensureDeviceOpen(deviceId);
    await _sweepExpired();
    _ensureDraftCapacity(deviceId);
    final adapter = _adapter(draft.adapterId);
    final runtimeDraft = _buildRuntimeDraft(
      adapter,
      draft,
      secretValues,
      deviceId,
    );
    late final ConnectionSetupReport report;
    try {
      report = await setup.testConnectionSetup(runtimeDraft);
    } catch (_) {
      _throw(HostRpcErrorCode.internalError);
    }
    final checks = List<HostSetupCheckPayload>.unmodifiable([
      for (final check in report.checks)
        HostSetupCheckPayload(
          label: _safeLabel(check.label),
          status: check.status,
          detail: switch (check.status) {
            SetupCheckStatus.passed => '检查通过。',
            SetupCheckStatus.actionRequired => '需要在 Mac 主机或对应服务中完成后续设置。',
            SetupCheckStatus.failed => '检查未通过，请在 Mac 主机检查程序与配置。',
          },
        ),
    ]);
    if (!report.canSave) {
      await _discardRuntimeDraft(report.draftId);
      return HostSetupTestResult(canSave: false, checks: checks);
    }
    if (_drafts.length >= _maxHostSetupDrafts) {
      await _discardRuntimeDraft(report.draftId);
      _throw(HostRpcErrorCode.resourceLimitExceeded);
    }
    final handle = _newReference();
    final expiry = _utcNow().add(referenceLifetime);
    _drafts[_key(deviceId, handle)] = _HostDraftRecord(
      deviceId: deviceId,
      handle: handle,
      runtimeDraftId: report.draftId,
      expiresAt: expiry,
    );
    return HostSetupTestResult(
      canSave: true,
      draftHandle: handle,
      checks: checks,
    );
  });

  Future<HostSetupSavedConnection> saveConnectionSetup({
    required String deviceId,
    required String draftHandle,
  }) => _serialize(() async {
    _validateDeviceId(deviceId);
    _ensureDeviceOpen(deviceId);
    await _sweepExpired();
    final key = _key(deviceId, draftHandle);
    final draft = _drafts[key];
    if (draft == null) _throw(HostRpcErrorCode.operationNotFound);
    if (draft.saveOutcomeUnknown) _throw(HostRpcErrorCode.outcomeUnknown);
    try {
      final connection = await setup.saveConnectionSetup(draft.runtimeDraftId);
      _drafts.remove(key);
      return HostSetupSavedConnection(
        connectionId: connection.id.value,
        kind: connection.kind,
        label: connection.label,
        status: connection.status,
      );
    } catch (_) {
      draft.saveOutcomeUnknown = true;
      _throw(HostRpcErrorCode.outcomeUnknown);
    }
  });

  Future<void> discardConnectionSetup({
    required String deviceId,
    required String draftHandle,
  }) => _serialize(() async {
    _validateDeviceId(deviceId);
    final key = _key(deviceId, draftHandle);
    final draft = _drafts[key];
    if (draft == null) return;
    if (draft.saveOutcomeUnknown) _throw(HostRpcErrorCode.outcomeUnknown);
    await _discardRuntimeDraft(draft.runtimeDraftId);
    _drafts.remove(key);
  });

  /// Clears all references and tested drafts when Host stops.
  Future<void> closeAll() => _serialize(() async {
    _executables.clear();
    for (final entry in _drafts.entries.toList()) {
      final draft = entry.value;
      if (!draft.saveOutcomeUnknown) {
        await _discardRuntimeDraft(draft.runtimeDraftId);
      }
      _drafts.remove(entry.key);
    }
    await _retryPendingCleanup();
  });

  /// Revocation invalidates references before attempting any runtime cleanup.
  Future<void> closeDevice(String deviceId) => _serialize(() async {
    _validateDeviceId(deviceId);
    _closedDevices.add(deviceId);
    _executables.removeWhere((_, record) => record.deviceId == deviceId);
    for (final entry in _drafts.entries.toList()) {
      final draft = entry.value;
      if (draft.deviceId != deviceId) continue;
      if (!draft.saveOutcomeUnknown) {
        await _discardRuntimeDraft(draft.runtimeDraftId);
      }
      _drafts.remove(entry.key);
    }
    await _retryPendingCleanup();
  });

  ConnectionSetupDraft _buildRuntimeDraft(
    ConnectionAdapter adapter,
    HostSetupDraftPayload draft,
    Map<String, String> secretValues,
    String deviceId,
  ) {
    if (draft.label.trim().isEmpty || draft.label.length > 100) {
      _throw(HostRpcErrorCode.invalidParams);
    }
    if (draft.fieldValues.length > 128 ||
        draft.fieldValues.entries.any(
          (entry) =>
              entry.key.isEmpty ||
              entry.key.length > 128 ||
              entry.value.length > 4096 ||
              entry.value.contains('\u0000'),
        ) ||
        secretValues.length > 16 ||
        secretValues.entries.any(
          (entry) =>
              !_hostSetupReferencePattern.hasMatch(entry.key) ||
              entry.value.length > 32 * 1024 ||
              entry.value.contains('\u0000'),
        ) ||
        draft.arguments.length > 256 ||
        draft.arguments.any(
          (argument) => argument.length > 4096 || argument.contains('\u0000'),
        )) {
      _throw(HostRpcErrorCode.invalidParams);
    }
    if (draft.url != null) {
      final uri = Uri.tryParse(draft.url!);
      if (draft.url!.isEmpty ||
          draft.url!.length > 2048 ||
          RegExp(r'[\x00-\x1f\x7f]').hasMatch(draft.url!) ||
          uri == null ||
          !uri.hasAuthority ||
          !const {'http', 'https'}.contains(uri.scheme) ||
          uri.userInfo.isNotEmpty) {
        _throw(HostRpcErrorCode.invalidParams);
      }
    }
    final declared = <String, SetupField>{};
    for (final field in adapter.fields) {
      if (declared.containsKey(field.key)) {
        _throw(HostRpcErrorCode.internalError);
      }
      declared[field.key] = field;
    }
    final publicFields = declared.values
        .where((field) => field.kind != SetupFieldKind.secret)
        .map((field) => field.key)
        .toSet();
    final secretFields = declared.values
        .where((field) => field.kind == SetupFieldKind.secret)
        .map((field) => field.key)
        .toSet();
    if (draft.fieldValues.keys.any((key) => !publicFields.contains(key))) {
      _throw(HostRpcErrorCode.invalidParams);
    }

    final allowedSecrets = adapter.kind == ConnectionKind.mcpHttp
        ? const {'authToken'}
        : secretFields;
    if (secretValues.keys.any((key) => !allowedSecrets.contains(key))) {
      _throw(HostRpcErrorCode.invalidParams);
    }
    final values = <String, String>{};
    for (final field in declared.values) {
      final isSecret = field.kind == SetupFieldKind.secret;
      final value = isSecret
          ? secretValues[field.key]
          : draft.fieldValues[field.key];
      if (!isSecret && secretValues.containsKey(field.key) ||
          isSecret && draft.fieldValues.containsKey(field.key)) {
        _throw(HostRpcErrorCode.invalidParams);
      }
      if (field.required && (value == null || value.trim().isEmpty)) {
        _throw(HostRpcErrorCode.invalidParams);
      }
      if (value != null) values[field.key] = value;
    }

    if (draft.manifestRef != null) _throw(HostRpcErrorCode.invalidParams);
    final executable = switch (adapter.kind) {
      ConnectionKind.mcpHttp => null,
      ConnectionKind.cli ||
      ConnectionKind.mcpStdio => _resolveExecutable(adapter, draft, deviceId),
    };
    if (adapter.kind == ConnectionKind.mcpHttp) {
      if (draft.url == null ||
          draft.executableRef != null ||
          draft.arguments.isNotEmpty ||
          secretValues.keys.any((key) => key != 'authToken')) {
        _throw(HostRpcErrorCode.invalidParams);
      }
    } else if (draft.url != null ||
        secretValues.containsKey('authToken') &&
            !secretFields.contains('authToken') ||
        !adapter.showGenericCliFields && draft.arguments.isNotEmpty) {
      _throw(HostRpcErrorCode.invalidParams);
    }

    return ConnectionSetupDraft(
      adapterId: adapter.id,
      spec: ConnectionSpec(
        kind: adapter.kind,
        label: draft.label,
        executable: executable,
        arguments: List.unmodifiable(draft.arguments),
        url: draft.url,
        authToken: secretValues['authToken'],
      ),
      values: Map.unmodifiable(values),
    );
  }

  String _resolveExecutable(
    ConnectionAdapter adapter,
    HostSetupDraftPayload draft,
    String deviceId,
  ) {
    final reference = draft.executableRef;
    if (reference == null) _throw(HostRpcErrorCode.invalidParams);
    final record = _executables[_key(deviceId, reference)];
    if (record == null || record.adapterId != adapter.id) {
      _throw(HostRpcErrorCode.unauthorized);
    }
    if (!_utcNow().isBefore(record.expiresAt)) {
      _executables.remove(_key(deviceId, reference));
      _throw(HostRpcErrorCode.operationNotFound);
    }
    return record.path;
  }

  ConnectionAdapter _adapter(String adapterId) {
    if (!_allowedAdapterIds.contains(adapterId)) {
      _throw(HostRpcErrorCode.invalidParams);
    }
    final matches = setup.connectionAdapters
        .where(
          (adapter) =>
              adapter.id == adapterId && !_hasUnresolvedFilePathField(adapter),
        )
        .toList();
    if (matches.length != 1) _throw(HostRpcErrorCode.invalidParams);
    return matches.single;
  }

  void _ensureDraftCapacity(String deviceId) {
    final count = _drafts.values
        .where((draft) => draft.deviceId == deviceId)
        .length;
    if (_drafts.length >= _maxHostSetupDrafts ||
        count >= _maxHostSetupDraftsPerDevice) {
      _throw(HostRpcErrorCode.resourceLimitExceeded);
    }
  }

  Future<void> _sweepExpired() async {
    final now = _utcNow();
    _executables.removeWhere((_, record) => !now.isBefore(record.expiresAt));
    for (final entry in _drafts.entries.toList()) {
      final draft = entry.value;
      if (now.isBefore(draft.expiresAt)) continue;
      if (!draft.saveOutcomeUnknown) {
        await _discardRuntimeDraft(draft.runtimeDraftId);
      }
      _drafts.remove(entry.key);
    }
    await _retryPendingCleanup();
  }

  Future<void> _discardRuntimeDraft(String runtimeDraftId) async {
    try {
      await setup.discardConnectionSetup(runtimeDraftId);
      _pendingCleanup.remove(runtimeDraftId);
    } catch (_) {
      _pendingCleanup.add(runtimeDraftId);
      _throw(HostRpcErrorCode.internalError);
    }
  }

  Future<void> _retryPendingCleanup() async {
    for (final id in _pendingCleanup.toList()) {
      try {
        await setup.discardConnectionSetup(id);
        _pendingCleanup.remove(id);
      } catch (_) {
        // Retain the opaque runtime draft ID for a later cleanup attempt.
      }
    }
  }

  DateTime _utcNow() => _now().toUtc();

  String _newReference() {
    final bytes = List<int>.generate(24, (_) => _random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  static String _key(String deviceId, String reference) =>
      '$deviceId\u0000$reference';

  static String _programLabel(String adapterId) => switch (adapterId) {
    'netease-music' => 'ncm-cli',
    _ => 'CLI 程序',
  };

  static String _safeLabel(String value) =>
      _safeSetupCheckLabels.contains(value) ? value : 'Host 检查';

  static bool _hasUnresolvedFilePathField(ConnectionAdapter adapter) =>
      adapter.fields.any(
        (field) => field.kind == SetupFieldKind.file && !field.readFileContent,
      );

  void _validateDeviceId(String value) {
    if (!_hostSetupReferencePattern.hasMatch(value)) {
      _throw(HostRpcErrorCode.invalidParams);
    }
  }

  void _ensureDeviceOpen(String deviceId) {
    if (_closedDevices.contains(deviceId)) {
      _throw(HostRpcErrorCode.unauthorized);
    }
  }

  Future<T> _serialize<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Never _throw(HostRpcErrorCode code) => throw HostRpcProtocolException(code);
}

final class _HostExecutableRecord {
  const _HostExecutableRecord({
    required this.deviceId,
    required this.adapterId,
    required this.path,
    required this.expiresAt,
  });

  final String deviceId;
  final String adapterId;
  final String path;
  final DateTime expiresAt;
}

final class _HostDraftRecord {
  _HostDraftRecord({
    required this.deviceId,
    required this.handle,
    required this.runtimeDraftId,
    required this.expiresAt,
  });

  final String deviceId;
  final String handle;
  final String runtimeDraftId;
  final DateTime expiresAt;
  bool saveOutcomeUnknown = false;
}
