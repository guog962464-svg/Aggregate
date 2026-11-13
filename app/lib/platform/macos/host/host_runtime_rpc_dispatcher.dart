import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:aggregate_contracts/aggregate_contracts.dart';

import 'host_operation_ledger.dart';
import 'host_jcs.dart';
import 'host_rpc_protocol.dart';
import 'host_setup_rpc_dispatcher.dart';

const _maxSubscriptionsPerSession = 16;
const _maxOwnedRunsPerDevice = 256;
const _maxTerminalHistoryEvents = 256;
const _maxRememberedSessions = 4096;
const _maxCapabilityReferencesPerDevice = 20000;
const _maxCompletedOperationResults = 4096;
final _hostPathPattern = RegExp(r'(?<![A-Za-z0-9])/(?:[^/\s]+/)+[^\s,;"<>]*');
final _urlPattern = RegExp(
  r'(?:https?://|file://)[^\s"<>]+',
  caseSensitive: false,
);
final _secretAssignmentPattern = RegExp(
  r'\b(bearer\s+|(?:access[_-]?token|refresh[_-]?token|api[_-]?key|authorization|password|private[_-]?key)\s*[:=]\s*)[^\s,;]+',
  caseSensitive: false,
);

/// Routes authenticated Host calls into the existing Mac runtime contracts.
/// Host IDs and permission grants stay at this seam; the runtime itself never
/// sees a remote device ID or a caller supplied Mac path.
final class HostRuntimeRpcDispatcher implements HostRpcDispatcherPort {
  HostRuntimeRpcDispatcher({
    required this.runtime,
    required this.accounts,
    required this.setupDispatcher,
    required this.ledger,
    required this.authorization,
    Random? random,
  }) : _random = random ?? Random.secure();

  final RuntimePort runtime;
  final ConnectionAccountPort accounts;
  final HostRpcDispatcherPort setupDispatcher;
  final FileHostOperationLedger ledger;
  final HostRpcAuthorizationPort authorization;
  final Random _random;

  final Map<String, _OwnedRun> _runs = {};
  final Map<String, _RemoteTerminal> _terminals = {};
  final Map<String, _SessionResources> _sessions = {};
  final Set<String> _closedSessions = {};
  final Map<String, Object?> _completedResults = {};
  final Map<String, String> _completedResultSessions = {};
  final Map<String, _DeviceCapabilityReferences> _capabilityReferences = {};

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

    final delegated = await setupDispatcher.dispatch(
      frame,
      authenticatedDeviceId: authenticatedDeviceId,
      sessionId: sessionId,
      notify: notify,
    );
    if (delegated != null) return delegated;
    if (!_runtimeMethods.contains(request.method)) return null;
    if (!_validDeviceId(authenticatedDeviceId)) {
      return HostRpcCodec.encodeError(
        request.id,
        HostRpcErrorCode.unauthorized,
      );
    }

    try {
      final allowed = await authorization.isAuthorized(
        deviceId: authenticatedDeviceId,
        method: request.method,
        params: _authorizationParams(request.params),
      );
      if (!allowed) {
        throw const HostRpcProtocolException(HostRpcErrorCode.unauthorized);
      }
      final result = await _dispatchAuthorized(
        request,
        authenticatedDeviceId,
        sessionId: sessionId,
        notify: notify,
      );
      return HostRpcCodec.encodeSuccess(request.id, result);
    } on HostRpcProtocolException catch (error) {
      return HostRpcCodec.encodeError(request.id, error.code);
    } on HostOperationLedgerException catch (error) {
      return HostRpcCodec.encodeError(request.id, error.code);
    } on FormatException {
      return HostRpcCodec.encodeError(
        request.id,
        HostRpcErrorCode.invalidParams,
      );
    } on ArgumentError {
      return HostRpcCodec.encodeError(
        request.id,
        HostRpcErrorCode.invalidParams,
      );
    } catch (_) {
      return HostRpcCodec.encodeError(
        request.id,
        HostRpcErrorCode.internalError,
      );
    }
  }

  Future<Object?> _dispatchAuthorized(
    HostRpcRequest request,
    String deviceId, {
    required String? sessionId,
    required void Function(JsonMap notification)? notify,
  }) async {
    final params = request.params;
    switch (request.method) {
      case 'connection.list':
        final connections = await runtime.listConnections();
        return {
          'connections': [
            for (final connection in connections)
              _safeConnectionJson(connection),
          ],
        };
      case 'connection.refresh':
        final id = ConnectionId(params['connectionId']! as String);
        await _authorizeConnectionRead(deviceId, id.value);
        return _safeConnectionJson(await runtime.refreshConnection(id));
      case 'connection.remove':
        final id = ConnectionId(params['connectionId']! as String);
        return _executeOperation(request, deviceId, () async {
          await runtime.removeConnection(id);
          return {'removed': true};
        });
      case 'connection.move':
        final id = ConnectionId(params['connectionId']! as String);
        final offset = params['offset']! as int;
        return _executeOperation(request, deviceId, () async {
          await runtime.moveConnection(id, offset);
          return {'moved': true};
        });
      case 'capability.search':
        final capabilities = await runtime.searchCapabilities(
          SearchQuery(params['query']! as String),
        );
        final visible = <Capability>[];
        for (final capability in capabilities) {
          if (await _canReadConnection(
            deviceId,
            capability.id.connection.value,
          )) {
            visible.add(capability);
          }
        }
        return {
          'capabilities': [
            for (final item in visible) _safeCapabilityJson(deviceId, item),
          ],
        };
      case 'run.invoke':
        final publicCapability = CapabilityId.fromJson(params['capability']);
        final capability = _resolveCapability(deviceId, publicCapability);
        final available = await runtime.searchCapabilities(
          const SearchQuery(''),
        );
        final selected = available.where(
          (item) => item.id.key == capability.key,
        );
        if (selected.length != 1) {
          throw const HostRpcProtocolException(HostRpcErrorCode.invalidParams);
        }
        final declaredPermission = PermissionLevel.values.where(
          (permission) => permission.name == params['permissionLevel'],
        );
        if (declaredPermission.length != 1 ||
            declaredPermission.single != selected.single.permission) {
          throw const HostRpcProtocolException(HostRpcErrorCode.unauthorized);
        }
        await _authorizeInvocation(
          deviceId,
          capability,
          selected.single.permission,
        );
        if (_runs.values.where((run) => run.deviceId == deviceId).length >=
            _maxOwnedRunsPerDevice) {
          throw const HostRpcProtocolException(
            HostRpcErrorCode.resourceLimitExceeded,
          );
        }
        return _executeOperation(request, deviceId, () async {
          final handle = await runtime.invoke(
            capability,
            jsonObject(params['arguments'], 'arguments'),
            permissionGranted: true,
          );
          _runs[handle.id.value] = _OwnedRun(
            deviceId: deviceId,
            capability: capability,
            permission: selected.single.permission,
          );
          return {'run': handle.toJson()};
        });
      case 'run.subscribe':
        final id = RunId(params['runId']! as String);
        final owner = _runs[id.value];
        if (owner == null || owner.deviceId != deviceId) {
          throw const HostRpcProtocolException(HostRpcErrorCode.unauthorized);
        }
        await _authorizeInvocation(
          deviceId,
          owner.capability,
          owner.permission,
        );
        return _subscribeRun(
          id,
          owner,
          params['afterSequence'] as int?,
          deviceId,
          sessionId,
          notify,
        );
      case 'run.cancel':
        final id = RunId(params['runId']! as String);
        final owner = _runs[id.value];
        if (owner == null || owner.deviceId != deviceId) {
          throw const HostRpcProtocolException(HostRpcErrorCode.unauthorized);
        }
        await _authorizeInvocation(
          deviceId,
          owner.capability,
          owner.permission,
        );
        return _executeOperation(request, deviceId, () async {
          await runtime.cancel(id);
          return {'cancelled': true};
        });
      case 'run.listRecent':
        final summaries = await runtime.listRecentRuns();
        final visible = <RunSummary>[];
        for (final summary in summaries) {
          final owner = _runs[summary.id.value];
          if (owner?.deviceId == deviceId ||
              await _canReadConnection(
                deviceId,
                summary.capability.connection.value,
              )) {
            visible.add(summary);
          }
        }
        return {
          'runs': [
            for (final item in visible) _safeRunSummaryJson(deviceId, item),
          ],
        };
      case 'activity.clear':
        return _executeOperation(request, deviceId, () async {
          await runtime.clearActivity();
          return {'cleared': true};
        });
      case 'resource.read':
        final suppliedRef = ResourceRef.fromJson(params['ref']);
        final actualCapability = _resolveCapability(
          deviceId,
          suppliedRef.capability,
        );
        if (actualCapability.kind != CapabilityKind.mcpResource ||
            suppliedRef.uri.toString() != suppliedRef.capability.name) {
          throw const HostRpcProtocolException(HostRpcErrorCode.invalidParams);
        }
        final ref = ResourceRef(
          actualCapability,
          Uri.parse(actualCapability.name),
        );
        await _authorizeInvocation(
          deviceId,
          ref.capability,
          PermissionLevel.read,
        );
        final blocks = await runtime.readResource(ref);
        return {
          'blocks': [for (final block in blocks) block.toJson()],
        };
      case 'prompt.get':
        final suppliedRef = PromptRef.fromJson(params['ref']);
        final actualCapability = _resolveCapability(
          deviceId,
          suppliedRef.capability,
        );
        if (actualCapability.kind != CapabilityKind.mcpPrompt) {
          throw const HostRpcProtocolException(HostRpcErrorCode.invalidParams);
        }
        final ref = PromptRef(actualCapability);
        await _authorizeInvocation(
          deviceId,
          ref.capability,
          PermissionLevel.read,
        );
        final blocks = await runtime.getPrompt(
          ref,
          jsonObject(params['arguments'], 'arguments'),
        );
        return {
          'blocks': [for (final block in blocks) block.toJson()],
        };
      case 'account.read':
        final id = ConnectionId(params['connectionId']! as String);
        await _authorizeConnectionRead(deviceId, id.value);
        return _accountSnapshotJson(await accounts.readAccount(id));
      case 'account.beginLogin':
        final id = ConnectionId(params['connectionId']! as String);
        await _authorizeConnectionRead(deviceId, id.value);
        await _authorizeTerminalScope(deviceId, id.value);
        final ownerSessionId = _requireSessionId(sessionId);
        final ownerNotify = _requireNotifier(notify);
        return _executeOperation(request, deviceId, () async {
          final actual = await accounts.beginAccountLogin(id);
          return _registerTerminal(
            actual,
            deviceId: deviceId,
            sessionId: ownerSessionId,
            notify: ownerNotify,
            accountLogin: true,
          );
        }, cacheSessionId: ownerSessionId);
      case 'account.waitLogin':
        final remoteId = params['sessionId']! as String;
        final terminal = _ownedTerminal(
          remoteId,
          deviceId: deviceId,
          sessionId: _requireSessionId(sessionId),
          accountLogin: true,
        );
        return {'exitCode': await accounts.waitAccountLogin(terminal.session)};
      case 'account.logout':
        final id = ConnectionId(params['connectionId']! as String);
        await _authorizeConnectionRead(deviceId, id.value);
        if (params['confirmed'] != true) {
          throw const HostRpcProtocolException(HostRpcErrorCode.unauthorized);
        }
        return _executeOperation(request, deviceId, () async {
          return _accountSnapshotJson(
            await accounts.logoutAccount(id, confirmed: true),
          );
        });
      case 'terminal.open':
        final id = ConnectionId(params['connectionId']! as String);
        await _authorizeConnectionRead(deviceId, id.value);
        final ownerSessionId = _requireSessionId(sessionId);
        final ownerNotify = _requireNotifier(notify);
        return _executeOperation(request, deviceId, () async {
          final actual = await runtime.openTerminal(CliCommand(id, const []));
          return _registerTerminal(
            actual,
            deviceId: deviceId,
            sessionId: ownerSessionId,
            notify: ownerNotify,
            accountLogin: false,
          );
        }, cacheSessionId: ownerSessionId);
      case 'terminal.subscribe':
        final remoteId = params['terminalId']! as String;
        final terminal = _ownedTerminal(
          remoteId,
          deviceId: deviceId,
          sessionId: _requireSessionId(sessionId),
        );
        return _subscribeTerminal(
          remoteId,
          terminal,
          params['afterSequence'] as int?,
          _requireSession(deviceId, sessionId, notify),
        );
      case 'terminal.write':
        final id = params['terminalId']! as String;
        final terminal = _ownedTerminal(
          id,
          deviceId: deviceId,
          sessionId: _requireSessionId(sessionId),
        );
        return _executeOperation(request, deviceId, () async {
          await runtime.writeTerminal(
            terminal.session,
            params['text']! as String,
          );
          return {'written': true};
        });
      case 'terminal.resize':
        final id = params['terminalId']! as String;
        final terminal = _ownedTerminal(
          id,
          deviceId: deviceId,
          sessionId: _requireSessionId(sessionId),
        );
        return _executeOperation(request, deviceId, () async {
          await runtime.resizeTerminal(
            terminal.session,
            params['columns']! as int,
            params['rows']! as int,
          );
          return {'resized': true};
        });
      case 'terminal.interrupt':
        final id = params['terminalId']! as String;
        final terminal = _ownedTerminal(
          id,
          deviceId: deviceId,
          sessionId: _requireSessionId(sessionId),
        );
        return _executeOperation(request, deviceId, () async {
          await runtime.interruptTerminal(terminal.session);
          return {'interrupted': true};
        });
      case 'terminal.close':
        final id = params['terminalId']! as String;
        final terminal = _ownedTerminal(
          id,
          deviceId: deviceId,
          sessionId: _requireSessionId(sessionId),
        );
        return _executeOperation(request, deviceId, () async {
          await _closeTerminal(id, terminal);
          return {'closed': true};
        });
      default:
        return null;
    }
  }

  Future<Object?> _subscribeRun(
    RunId id,
    _OwnedRun owner,
    int? afterSequence,
    String deviceId,
    String? sessionId,
    void Function(JsonMap notification)? notify,
  ) async {
    final session = _requireSession(deviceId, sessionId, notify);
    _ensureSubscriptionCapacity(session);
    final subscriptionId = _newToken('sub-');
    var lastSequence = afterSequence ?? -1;
    final subscription = runtime
        .watchRun(id)
        .listen(
          (event) {
            if (event.sequence <= lastSequence) return;
            lastSequence = event.sequence;
            _emit(
              session,
              HostRunEventNotification(
                subscriptionId: subscriptionId,
                event: _safeRunEvent(event),
              ).toJson(),
            );
          },
          onError: (_) {
            unawaited(_cancelSubscription(session, subscriptionId));
          },
        );
    session.subscriptions[subscriptionId] = subscription.cancel;
    return {'subscriptionId': subscriptionId, 'runId': id.toJson()};
  }

  Map<String, Object?> _registerTerminal(
    TerminalSession actual, {
    required String deviceId,
    required String sessionId,
    required void Function(JsonMap notification) notify,
    required bool accountLogin,
  }) {
    try {
      final session = _requireSession(deviceId, sessionId, notify);
      if (session.terminals.length >= 3) {
        throw const HostRpcProtocolException(
          HostRpcErrorCode.resourceLimitExceeded,
        );
      }
      final id = _newToken('terminal-');
      final remote = _RemoteTerminal(
        deviceId: deviceId,
        sessionId: sessionId,
        session: actual,
        accountLogin: accountLogin,
      );
      _terminals[id] = remote;
      session.terminals.add(id);
      remote.subscription = runtime
          .watchTerminal(actual)
          .listen(
            (text) => _recordTerminalOutput(id, remote, text),
            onError: (_) =>
                _recordTerminalClose(id, remote, HostTerminalEventKind.failed),
            onDone: () =>
                _recordTerminalClose(id, remote, HostTerminalEventKind.closed),
          );
      return {'terminalId': id, 'sessionId': id};
    } catch (_) {
      unawaited(runtime.closeTerminal(actual));
      rethrow;
    }
  }

  Map<String, Object?> _subscribeTerminal(
    String id,
    _RemoteTerminal terminal,
    int? afterSequence,
    _SessionResources session,
  ) {
    _ensureSubscriptionCapacity(session);
    final lastSequence = afterSequence ?? -1;
    if (afterSequence != null && afterSequence >= terminal.sequence) {
      throw const HostRpcProtocolException(HostRpcErrorCode.invalidParams);
    }
    if (terminal.history.isNotEmpty &&
        afterSequence != null &&
        afterSequence < terminal.history.first.sequence - 1) {
      throw const HostRpcProtocolException(HostRpcErrorCode.cursorExpired);
    }
    final subscriptionId = _newToken('sub-');
    terminal.activeSubscriptions[subscriptionId] = lastSequence;
    final key = 'terminal:$id:$subscriptionId';
    session.subscriptions[key] = () async {
      terminal.activeSubscriptions.remove(subscriptionId);
    };
    for (final event in terminal.history) {
      if (event.sequence > lastSequence) {
        _emitTerminal(session, subscriptionId, event);
      }
    }
    return {'subscriptionId': subscriptionId, 'terminalId': id};
  }

  void _recordTerminalOutput(String id, _RemoteTerminal terminal, String text) {
    var offset = 0;
    while (offset < text.length) {
      var end = min(offset + 8192, text.length);
      if (end < text.length && end > offset) {
        final codeUnit = text.codeUnitAt(end - 1);
        if (codeUnit >= 0xD800 && codeUnit <= 0xDBFF) end--;
      }
      if (end <= offset) end = min(offset + 2, text.length);
      _appendTerminalEvent(
        id,
        terminal,
        HostTerminalEvent(
          terminalId: id,
          sequence: terminal.sequence++,
          kind: HostTerminalEventKind.output,
          text: text.substring(offset, end),
        ),
      );
      offset = end;
    }
  }

  void _recordTerminalClose(
    String id,
    _RemoteTerminal terminal,
    HostTerminalEventKind kind,
  ) {
    if (terminal.closed) return;
    terminal.closed = true;
    _appendTerminalEvent(
      id,
      terminal,
      HostTerminalEvent(
        terminalId: id,
        sequence: terminal.sequence++,
        kind: kind,
      ),
    );
  }

  void _appendTerminalEvent(
    String id,
    _RemoteTerminal terminal,
    HostTerminalEvent event,
  ) {
    terminal.history.add(event);
    terminal.historyBytes += utf8.encode(event.text ?? '').length;
    if (terminal.history.length > _maxTerminalHistoryEvents) {
      terminal.historyBytes -= utf8
          .encode(terminal.history.removeAt(0).text ?? '')
          .length;
    }
    while (terminal.historyBytes > hostRpcMaxFrameBytes &&
        terminal.history.length > 1) {
      terminal.historyBytes -= utf8
          .encode(terminal.history.removeAt(0).text ?? '')
          .length;
    }
    for (final entry in terminal.activeSubscriptions.entries.toList()) {
      if (event.sequence <= entry.value) continue;
      final session = _sessions[terminal.sessionId];
      if (session == null || session.deviceId != terminal.deviceId) continue;
      _emitTerminal(session, entry.key, event);
      terminal.activeSubscriptions[entry.key] = event.sequence;
    }
    if (event.kind != HostTerminalEventKind.output) {
      final session = _sessions[terminal.sessionId];
      if (session != null) {
        for (final key
            in session.subscriptions.keys
                .where((key) => key.startsWith('terminal:$id:'))
                .toList()) {
          unawaited(_cancelSubscription(session, key));
        }
      }
    }
  }

  void _emitTerminal(
    _SessionResources session,
    String subscriptionId,
    HostTerminalEvent event,
  ) {
    _emit(
      session,
      HostTerminalEventNotification(
        subscriptionId: subscriptionId,
        event: event,
      ).toJson(),
    );
  }

  _RemoteTerminal _ownedTerminal(
    String id, {
    required String deviceId,
    required String sessionId,
    bool accountLogin = false,
  }) {
    final terminal = _terminals[id];
    if (terminal == null ||
        terminal.deviceId != deviceId ||
        terminal.sessionId != sessionId ||
        accountLogin && !terminal.accountLogin) {
      throw const HostRpcProtocolException(HostRpcErrorCode.unauthorized);
    }
    return terminal;
  }

  Future<void> _authorizeTerminalScope(
    String deviceId,
    String connectionId,
  ) async {
    if (!await authorization.isAuthorized(
      deviceId: deviceId,
      method: 'terminal.open',
      params: {'connectionId': connectionId},
    )) {
      throw const HostRpcProtocolException(HostRpcErrorCode.unauthorized);
    }
  }

  String _requireSessionId(String? value) {
    if (value == null) {
      throw const HostRpcProtocolException(HostRpcErrorCode.invalidRequest);
    }
    return value;
  }

  void Function(JsonMap notification) _requireNotifier(
    void Function(JsonMap notification)? value,
  ) {
    if (value == null) {
      throw const HostRpcProtocolException(HostRpcErrorCode.invalidRequest);
    }
    return value;
  }

  JsonMap? _accountSnapshotJson(AccountSnapshot? snapshot) => snapshot == null
      ? null
      : {
          'state': snapshot.state.name,
          if (snapshot.nickname != null)
            'nickname': _safeText(snapshot.nickname!),
          if (snapshot.message != null) 'message': _safeText(snapshot.message!),
        };

  Future<Object?> _executeOperation(
    HostRpcRequest request,
    String deviceId,
    Future<Object?> Function() execute, {
    String? cacheSessionId,
  }) async {
    final operationId = request.operationId;
    if (operationId == null) {
      throw const HostRpcProtocolException(HostRpcErrorCode.invalidParams);
    }
    final key = _operationKey(deviceId, operationId);
    final begun = await ledger.begin(
      deviceId: deviceId,
      operationId: operationId,
      payloadHash: hashHostOperationPayload(request.operationPayload),
    );
    if (!begun.shouldExecute) {
      if (_completedResults.containsKey(key)) {
        final resultSession = _completedResultSessions[key];
        if (resultSession == null || resultSession == cacheSessionId) {
          return _completedResults[key];
        }
      }
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
    _completedResults[key] = result;
    if (cacheSessionId != null) {
      _completedResultSessions[key] = cacheSessionId;
    }
    while (_completedResults.length > _maxCompletedOperationResults) {
      final oldest = _completedResults.keys.first;
      _completedResults.remove(oldest);
      _completedResultSessions.remove(oldest);
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
      // Any persisted started record is recovered as outcomeUnknown on open.
    }
  }

  Future<void> _authorizeInvocation(
    String deviceId,
    CapabilityId capability,
    PermissionLevel permission,
  ) async {
    if (permission == PermissionLevel.unknown) {
      throw const HostRpcProtocolException(HostRpcErrorCode.unauthorized);
    }
    final allowed = await authorization.isAuthorized(
      deviceId: deviceId,
      method: 'runtime.connection.invoke',
      params: {
        'connectionId': capability.connection.value,
        'permissionLevel': permission.name,
      },
    );
    if (!allowed) {
      throw const HostRpcProtocolException(HostRpcErrorCode.unauthorized);
    }
  }

  Future<void> _authorizeConnectionRead(
    String deviceId,
    String connectionId,
  ) async {
    if (!await _canReadConnection(deviceId, connectionId)) {
      throw const HostRpcProtocolException(HostRpcErrorCode.unauthorized);
    }
  }

  Future<bool> _canReadConnection(String deviceId, String connectionId) =>
      authorization.isAuthorized(
        deviceId: deviceId,
        method: 'runtime.connection.read',
        params: {'connectionId': connectionId},
      );

  _DeviceCapabilityReferences _referencesFor(String deviceId) =>
      _capabilityReferences.putIfAbsent(
        deviceId,
        _DeviceCapabilityReferences.new,
      );

  CapabilityId _publicCapabilityId(String deviceId, CapabilityId actual) {
    final references = _referencesFor(deviceId);
    final known = references.publicByActualKey[actual.key];
    if (known != null) return known;
    if (references.actualByPublicKey.length >=
        _maxCapabilityReferencesPerDevice) {
      throw const HostRpcProtocolException(
        HostRpcErrorCode.resourceLimitExceeded,
      );
    }
    final publicId = CapabilityId(
      actual.connection,
      actual.kind,
      _newToken('cap-'),
    );
    references.publicByActualKey[actual.key] = publicId;
    references.actualByPublicKey[publicId.key] = actual;
    return publicId;
  }

  CapabilityId _resolveCapability(String deviceId, CapabilityId publicId) {
    final actual =
        _capabilityReferences[deviceId]?.actualByPublicKey[publicId.key];
    if (actual == null) {
      throw const HostRpcProtocolException(HostRpcErrorCode.invalidParams);
    }
    return actual;
  }

  JsonMap _safeCapabilityJson(String deviceId, Capability capability) {
    final publicId = _publicCapabilityId(deviceId, capability.id);
    final safe = Capability(
      id: publicId,
      title: _safeText(capability.title),
      description: capability.id.kind == CapabilityKind.mcpResource
          ? 'MCP 资源'
          : _safeText(capability.description),
      permission: capability.permission,
      inputSchema: _safeSchema(capability.inputSchema),
      presentation: capability.presentation == null
          ? null
          : _safeText(capability.presentation!),
    );
    return safe.toJson();
  }

  JsonMap _safeRunSummaryJson(String deviceId, RunSummary summary) => {
    'id': summary.id.toJson(),
    'capability': _publicCapabilityId(deviceId, summary.capability).toJson(),
    'latest': _safeRunEvent(summary.latest).toJson(),
  };

  RunEvent _safeRunEvent(RunEvent event) => RunEvent(
    runId: event.runId,
    sequence: event.sequence,
    state: event.state,
    occurredAt: event.occurredAt,
    blocks: [
      for (final block in event.blocks)
        ResultBlock(block.kind, _safeResultValue(block.value)),
    ],
    failure: event.failure == null
        ? null
        : RuntimeFailure(
            event.failure!.code,
            _safeText(event.failure!.message),
            phase: event.failure!.phase,
          ),
  );

  Object? _safeResultValue(Object? value) {
    if (value is String) return _safeText(value);
    if (value is List) return value.map(_safeResultValue).toList();
    if (value is Map) {
      return {
        for (final entry in value.entries)
          if (entry.key is String)
            _safeText(entry.key as String): _safeResultValue(entry.value),
      };
    }
    return value;
  }

  JsonMap _safeSchema(JsonMap schema, {bool sensitive = false}) {
    final result = <String, Object?>{};
    for (final entry in schema.entries) {
      final key = entry.key;
      final childSensitive =
          sensitive ||
          RegExp(
            r'token|secret|password|credential|private.?key|authorization',
            caseSensitive: false,
          ).hasMatch(key);
      if (childSensitive &&
          const {
            'default',
            'example',
            'examples',
            'const',
            'enum',
          }.contains(key)) {
        continue;
      }
      final value = entry.value;
      result[key] = switch (value) {
        Map() => _safeSchema(
          value.cast<String, Object?>(),
          sensitive: childSensitive,
        ),
        List() => [
          for (final item in value)
            if (item is Map)
              _safeSchema(
                item.cast<String, Object?>(),
                sensitive: childSensitive,
              )
            else if (item is String)
              _safeText(item)
            else
              item,
        ],
        String() => _safeText(value),
        _ => value,
      };
    }
    return result;
  }

  String _safeText(String input) {
    var safe = input.replaceAll(_secretAssignmentPattern, r'$1[已隐藏]');
    safe = safe.replaceAllMapped(_urlPattern, (match) {
      final uri = Uri.tryParse(match[0]!);
      if (uri == null || uri.host.isEmpty) return '[URL]';
      final authority = uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;
      return '${uri.scheme}://$authority';
    });
    return safe.replaceAll(_hostPathPattern, '[Mac 路径]');
  }

  _SessionResources _requireSession(
    String deviceId,
    String? sessionId,
    void Function(JsonMap notification)? notify,
  ) {
    if (sessionId == null || notify == null) {
      throw const HostRpcProtocolException(HostRpcErrorCode.invalidRequest);
    }
    if (_closedSessions.contains(sessionId)) {
      throw const HostRpcProtocolException(HostRpcErrorCode.expiredSession);
    }
    final existing = _sessions[sessionId];
    if (existing != null && existing.deviceId != deviceId) {
      throw const HostRpcProtocolException(HostRpcErrorCode.unauthorized);
    }
    return _sessions.putIfAbsent(
      sessionId,
      () => _SessionResources(deviceId, notify),
    );
  }

  void _ensureSubscriptionCapacity(_SessionResources session) {
    if (session.subscriptions.length >= _maxSubscriptionsPerSession) {
      throw const HostRpcProtocolException(
        HostRpcErrorCode.resourceLimitExceeded,
      );
    }
  }

  void _emit(_SessionResources session, JsonMap event) {
    try {
      session.notify(event);
    } catch (_) {
      // The WebSocket owner closes and releases this session on send failure.
    }
  }

  Future<void> _cancelSubscription(
    _SessionResources session,
    String subscriptionId,
  ) async {
    final cancel = session.subscriptions.remove(subscriptionId);
    await cancel?.call();
  }

  @override
  Future<void> closeSession({
    required String authenticatedDeviceId,
    required String sessionId,
  }) async {
    _closedSessions.add(sessionId);
    if (_closedSessions.length > _maxRememberedSessions) {
      _closedSessions.remove(_closedSessions.first);
    }
    final session = _sessions.remove(sessionId);
    if (session != null && session.deviceId != authenticatedDeviceId) return;
    if (session != null) {
      await Future.wait([
        for (final cancel in session.subscriptions.values) cancel(),
      ]);
      session.subscriptions.clear();
    }
    for (final entry in _terminals.entries.toList()) {
      final terminal = entry.value;
      if (terminal.deviceId != authenticatedDeviceId ||
          terminal.sessionId != sessionId) {
        continue;
      }
      await _closeTerminal(entry.key, terminal);
    }
  }

  @override
  Future<void> revokeDevice(String deviceId) async {
    _capabilityReferences.remove(deviceId);
    final sessionIds = [
      for (final entry in _sessions.entries)
        if (entry.value.deviceId == deviceId) entry.key,
    ];
    for (final sessionId in sessionIds) {
      await closeSession(authenticatedDeviceId: deviceId, sessionId: sessionId);
    }
    for (final entry in _terminals.entries.toList()) {
      if (entry.value.deviceId == deviceId) {
        await _closeTerminal(entry.key, entry.value);
      }
    }
    for (final entry in _runs.entries.toList()) {
      if (entry.value.deviceId != deviceId) continue;
      try {
        await runtime.cancel(RunId(entry.key));
      } catch (_) {}
      _runs.remove(entry.key);
    }
  }

  Map<String, Object?> _safeConnectionJson(Connection connection) => {
    'id': connection.id.toJson(),
    'kind': connection.kind.name,
    'label': _safeText(connection.label),
    'location': switch (connection.kind) {
      ConnectionKind.cli => 'Mac 本机 CLI',
      ConnectionKind.mcpStdio => 'Mac 本机 stdio MCP',
      ConnectionKind.mcpHttp => _safeHttpLocation(connection.location),
    },
    'status': connection.status.name,
    if (connection.protocolVersion != null)
      'protocolVersion': connection.protocolVersion,
  };

  String _safeHttpLocation(String location) {
    final uri = Uri.tryParse(location);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return 'Mac 本机 HTTP MCP';
    }
    final authority = uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;
    return '${uri.scheme}://$authority';
  }

  Map<String, Object?> _authorizationParams(JsonMap params) =>
      Map.unmodifiable(Map<String, Object?>.of(params)..remove('secretValues'));

  String _newToken(String prefix) =>
      '$prefix${base64UrlEncode(List.generate(24, (_) => _random.nextInt(256))).replaceAll('=', '')}';

  bool _validDeviceId(String value) =>
      RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$').hasMatch(value);

  Future<void> _closeTerminal(String id, _RemoteTerminal terminal) async {
    _recordTerminalClose(id, terminal, HostTerminalEventKind.closed);
    _terminals.remove(id);
    await terminal.subscription?.cancel();
    try {
      await runtime.closeTerminal(terminal.session);
    } catch (_) {}
    final session = _sessions[terminal.sessionId];
    if (session != null) {
      session.terminals.remove(id);
      for (final entry in session.subscriptions.entries.toList()) {
        if (entry.key.startsWith('terminal:$id:')) {
          await _cancelSubscription(session, entry.key);
        }
      }
    }
  }

  static String _operationKey(String deviceId, String operationId) =>
      '$deviceId\u0000$operationId';
}

const _runtimeMethods = {
  'connection.list',
  'connection.refresh',
  'connection.remove',
  'connection.move',
  'capability.search',
  'run.invoke',
  'run.subscribe',
  'run.cancel',
  'run.listRecent',
  'activity.clear',
  'resource.read',
  'prompt.get',
  'account.read',
  'account.beginLogin',
  'account.waitLogin',
  'account.logout',
  'terminal.open',
  'terminal.subscribe',
  'terminal.write',
  'terminal.resize',
  'terminal.interrupt',
  'terminal.close',
};

final class _OwnedRun {
  const _OwnedRun({
    required this.deviceId,
    required this.capability,
    required this.permission,
  });

  final String deviceId;
  final CapabilityId capability;
  final PermissionLevel permission;
}

final class _DeviceCapabilityReferences {
  final Map<String, CapabilityId> publicByActualKey = {};
  final Map<String, CapabilityId> actualByPublicKey = {};
}

final class _SessionResources {
  _SessionResources(this.deviceId, this.notify);

  final String deviceId;
  final void Function(JsonMap notification) notify;
  final Map<String, Future<void> Function()> subscriptions = {};
  final Set<String> terminals = {};
}

final class _RemoteTerminal {
  _RemoteTerminal({
    required this.deviceId,
    required this.sessionId,
    required this.session,
    required this.accountLogin,
  });

  final String deviceId;
  final String sessionId;
  final TerminalSession session;
  final bool accountLogin;
  final List<HostTerminalEvent> history = [];
  final Map<String, int> activeSubscriptions = {};
  StreamSubscription<String>? subscription;
  int sequence = 0;
  bool closed = false;
  int historyBytes = 0;
}
