import 'package:aggregate_contracts/aggregate_contracts.dart';

import 'host_jcs.dart';
import 'host_operation_ledger.dart';
import 'host_rpc_protocol.dart';
import 'host_setup_coordinator.dart';

const _hostSetupRpcMethods = {
  'operation.read',
  'setup.adapters',
  'setup.detectExecutable',
  'setup.resolveExecutable',
  'setup.test',
  'setup.save',
  'setup.discard',
};
final _hostDeviceIdPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$');

/// Authorizes an already authenticated device for an RPC method and payload.
/// Authentication and grant storage are supplied by the later pairing layer.
abstract interface class HostRpcAuthorizationPort {
  Future<bool> isAuthorized({
    required String deviceId,
    required String method,
    required JsonMap params,
  });
}

abstract interface class HostRpcDispatcherPort {
  Future<String?> dispatch(
    String frame, {
    required String authenticatedDeviceId,
    String? sessionId,
    void Function(JsonMap notification)? notify,
  });

  Future<void> closeSession({
    required String authenticatedDeviceId,
    required String sessionId,
  });

  Future<void> revokeDevice(String deviceId);
}

/// Dispatches the setup RPC subset. The caller must pass a device ID obtained
/// from a verified session; this class does not accept or create sockets.
final class HostSetupRpcDispatcher implements HostRpcDispatcherPort {
  const HostSetupRpcDispatcher({
    required this.setup,
    required this.ledger,
    required this.authorization,
  });

  final HostSetupCoordinator setup;
  final FileHostOperationLedger ledger;
  final HostRpcAuthorizationPort authorization;

  /// Returns null for methods owned by another dispatcher in the Host stack.
  @override
  Future<String?> dispatch(
    String frame, {
    required String authenticatedDeviceId,
    String? sessionId,
    void Function(JsonMap notification)? notify,
  }) async {
    HostRpcRequest request;
    try {
      request = HostRpcCodec.decodeRequest(frame);
    } on HostRpcProtocolException catch (error) {
      return HostRpcCodec.encodeError(error.requestId, error.code);
    } catch (_) {
      return HostRpcCodec.encodeError(null, HostRpcErrorCode.internalError);
    }
    if (!_hostSetupRpcMethods.contains(request.method)) return null;
    if (!_hostDeviceIdPattern.hasMatch(authenticatedDeviceId)) {
      return HostRpcCodec.encodeError(
        request.id,
        HostRpcErrorCode.unauthorized,
      );
    }

    try {
      final allowed = await authorization.isAuthorized(
        deviceId: authenticatedDeviceId,
        method: request.method,
        params: Map.unmodifiable(
          Map<String, Object?>.of(request.params)..remove('secretValues'),
        ),
      );
      if (!allowed) {
        throw const HostRpcProtocolException(HostRpcErrorCode.unauthorized);
      }
      final result = await _dispatchAuthorized(request, authenticatedDeviceId);
      if (result == null) return null;
      return HostRpcCodec.encodeSuccess(request.id, result);
    } on HostRpcProtocolException catch (error) {
      return HostRpcCodec.encodeError(request.id, error.code);
    } on HostOperationLedgerException catch (error) {
      return HostRpcCodec.encodeError(request.id, error.code);
    } catch (_) {
      return HostRpcCodec.encodeError(
        request.id,
        HostRpcErrorCode.internalError,
      );
    }
  }

  @override
  Future<void> closeSession({
    required String authenticatedDeviceId,
    required String sessionId,
  }) async {}

  @override
  Future<void> revokeDevice(String deviceId) async {}

  Future<Object?> _dispatchAuthorized(
    HostRpcRequest request,
    String deviceId,
  ) async {
    switch (request.method) {
      case 'operation.read':
        final record = await ledger.read(
          deviceId: deviceId,
          operationId: request.params['operationId']! as String,
        );
        if (record == null) {
          throw const HostRpcProtocolException(
            HostRpcErrorCode.operationNotFound,
          );
        }
        return {
          'operationId': record.operationId,
          'state': record.state.name,
          'createdAtMicros': record.createdAtMicros,
        };
      case 'setup.adapters':
        return {
          'adapters': [
            for (final adapter in setup.listAdapters()) adapter.toJson(),
          ],
        };
      case 'setup.detectExecutable':
        final detected = await setup.detectExecutable(
          deviceId: deviceId,
          adapterId: request.params['adapterId']! as String,
        );
        return {
          'detected': detected != null,
          if (detected != null) ...detected.toJson(),
        };
      case 'setup.resolveExecutable':
        final detected = await setup.resolveExecutable(
          deviceId: deviceId,
          adapterId: request.params['adapterId']! as String,
          executableName: request.params['executableName']! as String,
        );
        return {
          'detected': detected != null,
          if (detected != null) ...detected.toJson(),
        };
      case 'setup.test':
        final draft = HostSetupDraftPayload.fromJson(request.params['draft']);
        final secretValues = _secretValues(request.params['secretValues']);
        return _executeOperation(request, deviceId, () async {
          final result = await setup.testConnectionSetup(
            deviceId: deviceId,
            draft: draft,
            secretValues: secretValues,
          );
          return result.toJson();
        });
      case 'setup.save':
        final draftHandle = request.params['draftHandle']! as String;
        return _executeOperation(request, deviceId, () async {
          final result = await setup.saveConnectionSetup(
            deviceId: deviceId,
            draftHandle: draftHandle,
          );
          return result.toJson();
        });
      case 'setup.discard':
        final draftHandle = request.params['draftHandle']! as String;
        return _executeOperation(request, deviceId, () async {
          await setup.discardConnectionSetup(
            deviceId: deviceId,
            draftHandle: draftHandle,
          );
          return {'discarded': true};
        });
      default:
        return null;
    }
  }

  Future<Object?> _executeOperation(
    HostRpcRequest request,
    String deviceId,
    Future<Object?> Function() execute,
  ) async {
    final operationId = request.operationId;
    if (operationId == null) {
      throw const HostRpcProtocolException(HostRpcErrorCode.invalidParams);
    }
    final begun = await ledger.begin(
      deviceId: deviceId,
      operationId: operationId,
      payloadHash: hashHostOperationPayload(request.operationPayload),
    );
    if (!begun.shouldExecute) {
      return {
        'operationId': operationId,
        'state': begun.record.state.name,
        'replayed': true,
      };
    }

    late final Object? result;
    try {
      result = await execute();
    } on HostRpcProtocolException catch (error) {
      if (error.code == HostRpcErrorCode.internalError ||
          error.code == HostRpcErrorCode.outcomeUnknown) {
        await _markUnknown(deviceId, operationId);
      } else {
        await _completeKnownFailure(deviceId, operationId);
      }
      rethrow;
    } catch (_) {
      await _markUnknown(deviceId, operationId);
      throw const HostRpcProtocolException(HostRpcErrorCode.internalError);
    }

    try {
      await ledger.complete(deviceId: deviceId, operationId: operationId);
    } on HostOperationLedgerException {
      await _markUnknown(deviceId, operationId);
      rethrow;
    }
    return result;
  }

  Future<void> _completeKnownFailure(
    String deviceId,
    String operationId,
  ) async {
    try {
      await ledger.complete(deviceId: deviceId, operationId: operationId);
    } catch (_) {
      await _markUnknown(deviceId, operationId);
    }
  }

  Future<void> _markUnknown(String deviceId, String operationId) async {
    try {
      await ledger.markOutcomeUnknown(
        deviceId: deviceId,
        operationId: operationId,
      );
    } catch (_) {
      // A persisted started record becomes outcomeUnknown on the next open.
    }
  }

  static Map<String, String> _secretValues(Object? value) {
    if (value == null) return const {};
    if (value is! Map || value.keys.any((key) => key is! String)) {
      throw const HostRpcProtocolException(HostRpcErrorCode.invalidParams);
    }
    try {
      return Map.unmodifiable(value.cast<String, String>());
    } on TypeError {
      throw const HostRpcProtocolException(HostRpcErrorCode.invalidParams);
    }
  }
}
