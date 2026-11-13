import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'host_rpc_protocol.dart';

const _maxLedgerBytes = 4 * 1024 * 1024;
const _maxLedgerEntries = 10000;
final _identifierPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$');
final _sha256Pattern = RegExp(r'^[a-f0-9]{64}$');

enum HostOperationState { started, completed, outcomeUnknown }

final class HostOperationRecord {
  const HostOperationRecord({
    required this.deviceId,
    required this.operationId,
    required this.payloadHash,
    required this.state,
    required this.createdAtMicros,
  });

  final String deviceId;
  final String operationId;
  final String payloadHash;
  final HostOperationState state;
  final int createdAtMicros;

  HostOperationRecord withState(HostOperationState next) => HostOperationRecord(
    deviceId: deviceId,
    operationId: operationId,
    payloadHash: payloadHash,
    state: next,
    createdAtMicros: createdAtMicros,
  );

  Map<String, Object?> toJson() => {
    'deviceId': deviceId,
    'operationId': operationId,
    'payloadHash': payloadHash,
    'state': state.name,
    'createdAtMicros': createdAtMicros,
  };

  factory HostOperationRecord.fromJson(Object? value) {
    if (value is! Map || value.keys.any((key) => key is! String)) {
      throw const FormatException('Host operation record is invalid');
    }
    final json = value.cast<String, Object?>();
    if (json.keys.toSet().difference(const {
          'deviceId',
          'operationId',
          'payloadHash',
          'state',
          'createdAtMicros',
        }).isNotEmpty ||
        json.length != 5) {
      throw const FormatException('Host operation record is invalid');
    }
    final deviceId = json['deviceId'];
    final operationId = json['operationId'];
    final payloadHash = json['payloadHash'];
    final stateName = json['state'];
    final createdAtMicros = json['createdAtMicros'];
    if (deviceId is! String || !_identifierPattern.hasMatch(deviceId)) {
      throw const FormatException('Host operation record is invalid');
    }
    if (operationId is! String ||
        !_identifierPattern.hasMatch(operationId) ||
        payloadHash is! String ||
        !_sha256Pattern.hasMatch(payloadHash) ||
        stateName is! String ||
        createdAtMicros is! int ||
        createdAtMicros < 0) {
      throw const FormatException('Host operation record is invalid');
    }
    final state = HostOperationState.values.where(
      (item) => item.name == stateName,
    );
    if (state.isEmpty) {
      throw const FormatException('Host operation record is invalid');
    }
    return HostOperationRecord(
      deviceId: deviceId,
      operationId: operationId,
      payloadHash: payloadHash,
      state: state.single,
      createdAtMicros: createdAtMicros,
    );
  }
}

final class HostOperationBegin {
  const HostOperationBegin({required this.record, required this.shouldExecute});

  final HostOperationRecord record;
  final bool shouldExecute;
}

final class HostOperationLedgerException implements Exception {
  const HostOperationLedgerException(this.code);

  final HostRpcErrorCode code;

  @override
  String toString() => 'HostOperationLedgerException(${code.name})';
}

/// Durable, secret-free operation state used to prevent replay after retries
/// and process restarts. The caller supplies the JCS payload hash.
final class FileHostOperationLedger {
  FileHostOperationLedger._(this.file, this.maxEntries, this._records);

  final File file;
  final int maxEntries;
  final Map<String, HostOperationRecord> _records;
  Future<void> _writeTail = Future<void>.value();

  static Future<FileHostOperationLedger> open(
    File file, {
    int maxEntries = _maxLedgerEntries,
  }) async {
    if (maxEntries < 1 || maxEntries > _maxLedgerEntries) {
      throw ArgumentError.value(maxEntries, 'maxEntries');
    }
    final records = <String, HostOperationRecord>{};
    if (await file.exists()) {
      if (await file.length() > _maxLedgerBytes) {
        throw const FormatException('Host operation ledger is too large');
      }
      final raw = jsonDecode(await file.readAsString());
      if (raw is! Map ||
          raw['schemaVersion'] != 1 ||
          raw['operations'] is! List ||
          raw.keys.toSet().difference(const {
            'schemaVersion',
            'operations',
          }).isNotEmpty) {
        throw const FormatException('Host operation ledger is invalid');
      }
      final operations = raw['operations'] as List;
      if (operations.length > maxEntries) {
        throw const FormatException('Host operation ledger is full');
      }
      for (final item in operations) {
        final record = HostOperationRecord.fromJson(item);
        final key = _recordKey(record.deviceId, record.operationId);
        if (records.containsKey(key)) {
          throw const FormatException('Host operation ledger has duplicates');
        }
        records[key] = record.state == HostOperationState.started
            ? record.withState(HostOperationState.outcomeUnknown)
            : record;
      }
    }
    final ledger = FileHostOperationLedger._(file, maxEntries, records);
    if (records.values.any(
      (record) => record.state == HostOperationState.outcomeUnknown,
    )) {
      await ledger._persist();
    }
    return ledger;
  }

  Future<HostOperationBegin> begin({
    required String deviceId,
    required String operationId,
    required String payloadHash,
  }) => _serialize(() async {
    _validateInput(deviceId, operationId, payloadHash);
    final key = _recordKey(deviceId, operationId);
    final previous = _records[key];
    if (previous != null) {
      if (previous.payloadHash != payloadHash) {
        throw const HostOperationLedgerException(
          HostRpcErrorCode.idempotencyConflict,
        );
      }
      return HostOperationBegin(record: previous, shouldExecute: false);
    }
    if (_records.length >= maxEntries) {
      throw const HostOperationLedgerException(
        HostRpcErrorCode.operationLedgerFull,
      );
    }
    final record = HostOperationRecord(
      deviceId: deviceId,
      operationId: operationId,
      payloadHash: payloadHash,
      state: HostOperationState.started,
      createdAtMicros: DateTime.now().toUtc().microsecondsSinceEpoch,
    );
    _records[key] = record;
    try {
      await _persist();
    } catch (_) {
      _records.remove(key);
      throw const HostOperationLedgerException(HostRpcErrorCode.internalError);
    }
    return HostOperationBegin(record: record, shouldExecute: true);
  });

  Future<HostOperationRecord> complete({
    required String deviceId,
    required String operationId,
  }) => _serialize(() async {
    _validateIdentifier(deviceId);
    _validateIdentifier(operationId);
    final key = _recordKey(deviceId, operationId);
    final previous = _records[key];
    if (previous == null) {
      throw const HostOperationLedgerException(
        HostRpcErrorCode.operationNotFound,
      );
    }
    if (previous.state == HostOperationState.outcomeUnknown) {
      throw const HostOperationLedgerException(HostRpcErrorCode.outcomeUnknown);
    }
    if (previous.state == HostOperationState.completed) return previous;

    final completed = previous.withState(HostOperationState.completed);
    _records[key] = completed;
    try {
      await _persist();
    } catch (_) {
      _records[key] = previous;
      throw const HostOperationLedgerException(HostRpcErrorCode.internalError);
    }
    return completed;
  });

  Future<HostOperationRecord?> read({
    required String deviceId,
    required String operationId,
  }) async {
    _validateIdentifier(deviceId);
    _validateIdentifier(operationId);
    await _writeTail;
    return _records[_recordKey(deviceId, operationId)];
  }

  Future<void> _persist() async {
    final json = {
      'schemaVersion': 1,
      'operations': [for (final item in _records.values) item.toJson()],
    };
    final contents = jsonEncode(json);
    if (utf8.encode(contents).length > _maxLedgerBytes) {
      throw const HostOperationLedgerException(
        HostRpcErrorCode.operationLedgerFull,
      );
    }
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(contents, flush: true);
    await temporary.rename(file.path);
  }

  Future<T> _serialize<T>(Future<T> Function() action) {
    final result = _writeTail.then((_) => action());
    _writeTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  static String _recordKey(String deviceId, String operationId) =>
      jsonEncode([deviceId, operationId]);

  static void _validateInput(
    String deviceId,
    String operationId,
    String payloadHash,
  ) {
    _validateIdentifier(deviceId);
    _validateIdentifier(operationId);
    if (!_sha256Pattern.hasMatch(payloadHash)) {
      throw const HostOperationLedgerException(HostRpcErrorCode.invalidParams);
    }
  }

  static void _validateIdentifier(String value) {
    if (!_identifierPattern.hasMatch(value)) {
      throw const HostOperationLedgerException(HostRpcErrorCode.invalidParams);
    }
  }
}
