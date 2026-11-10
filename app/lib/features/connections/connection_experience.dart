import 'package:aggregate_contracts/aggregate_contracts.dart';

/// Selects a connection's home from its published capabilities. Presentation
/// metadata chooses a specialized UI; protocol kind provides a safe fallback.
enum ConnectionExperience { music, cli, mcp }

ConnectionExperience experienceFor(
  Connection connection,
  Iterable<Capability> catalog,
) {
  if (connection.kind == ConnectionKind.cli) {
    final presentations = catalog
        .where((item) => item.id.connection.value == connection.id.value)
        .map((item) => item.presentation)
        .toSet();
    if (presentations.contains('music.search') &&
        presentations.contains('music.play')) {
      return ConnectionExperience.music;
    }
    return ConnectionExperience.cli;
  }
  return ConnectionExperience.mcp;
}
