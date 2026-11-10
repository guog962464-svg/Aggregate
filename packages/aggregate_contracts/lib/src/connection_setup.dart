import 'models.dart';

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
    this.fields = const [],
    this.defaultLabel,
    this.description,
    this.showGenericCliFields = true,
  });

  final String id;
  final String label;
  final ConnectionKind kind;
  final List<SetupField> fields;
  final String? defaultLabel;
  final String? description;
  final bool showGenericCliFields;
}

/// In-memory only. Values can contain secrets and must never be serialized.
final class ConnectionSetupDraft {
  const ConnectionSetupDraft({
    required this.adapterId,
    required this.spec,
    this.values = const {},
  });

  final String adapterId;
  final ConnectionSpec spec;
  final Map<String, String> values;
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
  Future<ConnectionSetupReport> testConnectionSetup(ConnectionSetupDraft draft);
  Future<Connection> saveConnectionSetup(String draftId);
  Future<void> discardConnectionSetup(String draftId);
}
