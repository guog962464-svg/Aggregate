import 'models.dart';

abstract interface class RuntimePort {
  Future<List<Connection>> listConnections();
  Future<List<Capability>> searchCapabilities(SearchQuery query);
  Future<RunHandle> invoke(CapabilityId id, JsonMap arguments);
  Stream<RunEvent> watchRun(RunId id);
  Future<List<RunSummary>> listRecentRuns();
  Future<void> cancel(RunId id);
  Future<List<ResultBlock>> readResource(ResourceRef ref);
  Future<List<ResultBlock>> getPrompt(PromptRef ref, JsonMap arguments);
  Future<TerminalSession> openTerminal(CliCommand command);
}

abstract interface class McpClientPort<Session> {
  Future<Session> connect(Connection connection);
  Future<List<Capability>> listTools(Session session);
  Future<List<ResultBlock>> callTool(
    Session session,
    String name,
    JsonMap arguments,
  );
  Future<List<Capability>> listResources(Session session);
  Future<List<ResultBlock>> readResource(Session session, Uri uri);
  Future<List<Capability>> listPrompts(Session session);
  Future<List<ResultBlock>> getPrompt(
    Session session,
    String name,
    JsonMap arguments,
  );
  Future<void> close(Session session);
}
