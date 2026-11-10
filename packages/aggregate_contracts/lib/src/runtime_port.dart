import 'models.dart';

abstract interface class RuntimePort {
  bool get isPreview;
  RuntimeFeatures get features;
  List<String> get startupNotices;
  Future<UserPreferences> loadPreferences();
  Future<void> savePreferences(UserPreferences preferences);
  Future<void> clearActivity();
  Future<List<Connection>> listConnections();
  Future<Connection> addConnection(ConnectionSpec spec);
  Future<void> removeConnection(ConnectionId id);
  Future<void> moveConnection(ConnectionId id, int offset);
  Future<Connection> refreshConnection(ConnectionId id);
  Future<JsonMap?> loadActionManifest(ConnectionId id);
  Future<JsonMap> readActionManifestFile(String path);
  Future<void> saveActionManifest(ConnectionId id, JsonMap manifest);
  Future<void> exportActionManifest(
    ConnectionId id,
    JsonMap manifest,
    String path,
  );
  Future<List<Capability>> searchCapabilities(SearchQuery query);
  Future<RunHandle> invoke(
    CapabilityId id,
    JsonMap arguments, {
    bool permissionGranted = false,
  });
  Stream<RunEvent> watchRun(RunId id);
  Future<List<RunSummary>> listRecentRuns();
  Future<void> cancel(RunId id);
  Future<List<ResultBlock>> readResource(ResourceRef ref);
  Future<List<ResultBlock>> getPrompt(PromptRef ref, JsonMap arguments);
  Future<List<ResultBlock>> previewLocalFile(String path);
  Future<void> revealLocalFile(String path);
  Future<TerminalSession> openTerminal(CliCommand command);
  Stream<String> watchTerminal(TerminalSession session);
  Future<void> writeTerminal(TerminalSession session, String text);
  Future<void> resizeTerminal(TerminalSession session, int columns, int rows);
  Future<void> interruptTerminal(TerminalSession session);
  Future<void> closeTerminal(TerminalSession session);
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
