import 'models.dart';
import 'execution_target.dart';

enum SetupFieldKind { text, secret, file }

final class SetupField {
  const SetupField({
    required this.key,
    required this.label,
    this.kind = SetupFieldKind.text,
    this.required = true,
    this.hint,
    this.readFileContent = false,
  });

  final String key;
  final String label;
  final SetupFieldKind kind;
  final bool required;
  final String? hint;
  final bool readFileContent;
}

final class ConnectionAdapter {
  const ConnectionAdapter({
    required this.id,
    required this.label,
    required this.kind,
    this.executionTarget = ExecutionTarget.device,
    this.fields = const [],
    this.defaultLabel,
    this.description,
    this.showGenericCliFields = true,
    this.autoDetectExecutable = false,
  });

  final String id;
  final String label;
  final ConnectionKind kind;
  final ExecutionTarget executionTarget;
  final List<SetupField> fields;
  final String? defaultLabel;
  final String? description;
  final bool showGenericCliFields;
  final bool autoDetectExecutable;
}

/// In-memory only. Values can contain secrets and must never be serialized.
final class ConnectionSetupDraft {
  const ConnectionSetupDraft({
    required this.adapterId,
    required this.spec,
    this.values = const {},
    this.executableReference,
  });

  final String adapterId;
  final ConnectionSpec spec;
  final Map<String, String> values;

  /// Optional short-lived executable reference issued by the target runtime.
  /// It is never part of a saved connection.
  final String? executableReference;
}

final class ConnectionSetupTargetOption {
  const ConnectionSetupTargetOption({
    required this.target,
    required this.label,
    required this.detail,
    this.selectable = true,
  });

  final ExecutionTarget target;
  final String label;
  final String detail;
  final bool selectable;
}

abstract interface class ConnectionSetupTargetPort {
  Future<List<ConnectionSetupTargetOption>> listSetupTargets();
  Future<ConnectionSetupPort> setupForTarget(ExecutionTarget target);
}

final class DetectedExecutableSelection {
  const DetectedExecutableSelection({
    required this.displayLocation,
    this.path,
    this.reference,
  });

  final String displayLocation;
  final String? path;
  final String? reference;
}

abstract interface class ConnectionSetupExecutableSelectionPort {
  Future<DetectedExecutableSelection?> detectExecutableSelection(
    String adapterId, {
    String? executableName,
  });
}

abstract interface class ExecutableLookupPort {
  /// Finds a runtime-local command name without exposing its path to callers.
  Future<String?> findExecutable(String name);
}

final class ConnectionSetupOutcomeUnknown implements Exception {
  const ConnectionSetupOutcomeUnknown();

  @override
  String toString() => 'Connection setup save outcome is unknown';
}

enum SetupCheckStatus { passed, actionRequired, failed }

final class SetupCheck {
  const SetupCheck(this.label, this.status, this.detail);

  final String label;
  final SetupCheckStatus status;
  final String detail;
}

final class ConnectionSetupReport {
  const ConnectionSetupReport({
    required this.draftId,
    required this.checks,
    required this.canSave,
  });

  final String draftId;
  final List<SetupCheck> checks;
  final bool canSave;
}

/// Tests a draft before it appears in the saved connection list.
abstract interface class ConnectionSetupPort {
  List<ConnectionAdapter> get connectionAdapters;
  Future<String?> detectExecutable(String adapterId);
  Future<ConnectionSetupReport> testConnectionSetup(ConnectionSetupDraft draft);
  Future<Connection> saveConnectionSetup(String draftId);
  Future<void> discardConnectionSetup(String draftId);
}
