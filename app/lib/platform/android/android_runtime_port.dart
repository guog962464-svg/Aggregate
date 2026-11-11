import 'package:aggregate_contracts/aggregate_contracts.dart';

/// A1 Android shell. It advertises no connection or terminal capability until
/// the Android HTTP runtime is implemented in A2.
final class AndroidRuntimePort implements RuntimePort {
  UserPreferences _preferences = const UserPreferences();

  Never _unavailable() => throw UnsupportedError('此功能尚未在 Android 上开放');

  @override
  bool get isPreview => false;

  @override
  RuntimeFeatures get features => const RuntimeFeatures(
    connectionKinds: {},
    terminal: false,
    localFilePreview: false,
    localFileReveal: false,
  );

  @override
  List<String> get startupNotices => const [
    'Android 运行端已启动；连接功能将在后续阶段开放。设置仅在本次运行中保留。',
  ];

  @override
  Future<UserPreferences> loadPreferences() async => _preferences;

  @override
  Future<void> savePreferences(UserPreferences preferences) async {
    _preferences = preferences;
  }

  @override
  Future<void> clearActivity() async {}

  @override
  Future<List<Connection>> listConnections() async => const [];

  @override
  Future<List<Capability>> searchCapabilities(SearchQuery query) async =>
      const [];

  @override
  Future<List<RunSummary>> listRecentRuns() async => const [];

  @override
  Future<Connection> addConnection(ConnectionSpec spec) async => _unavailable();

  @override
  Future<void> removeConnection(ConnectionId id) async => _unavailable();

  @override
  Future<void> moveConnection(ConnectionId id, int offset) async =>
      _unavailable();

  @override
  Future<Connection> refreshConnection(ConnectionId id) async => _unavailable();

  @override
  Future<JsonMap?> loadActionManifest(ConnectionId id) async => _unavailable();

  @override
  Future<JsonMap> readActionManifestFile(String path) async => _unavailable();

  @override
  Future<void> saveActionManifest(ConnectionId id, JsonMap manifest) async =>
      _unavailable();

  @override
  Future<void> exportActionManifest(
    ConnectionId id,
    JsonMap manifest,
    String path,
  ) async => _unavailable();

  @override
  Future<RunHandle> invoke(
    CapabilityId id,
    JsonMap arguments, {
    bool permissionGranted = false,
  }) async => _unavailable();

  @override
  Stream<RunEvent> watchRun(RunId id) =>
      Stream.error(UnsupportedError('此功能尚未在 Android 上开放'));

  @override
  Future<void> cancel(RunId id) async => _unavailable();

  @override
  Future<List<ResultBlock>> readResource(ResourceRef ref) async =>
      _unavailable();

  @override
  Future<List<ResultBlock>> getPrompt(PromptRef ref, JsonMap arguments) async =>
      _unavailable();

  @override
  Future<List<ResultBlock>> previewLocalFile(String path) async =>
      _unavailable();

  @override
  Future<void> revealLocalFile(String path) async => _unavailable();

  @override
  Future<TerminalSession> openTerminal(CliCommand command) async =>
      _unavailable();

  @override
  Stream<String> watchTerminal(TerminalSession session) =>
      Stream.error(UnsupportedError('此功能尚未在 Android 上开放'));

  @override
  Future<void> writeTerminal(TerminalSession session, String text) async =>
      _unavailable();

  @override
  Future<void> resizeTerminal(
    TerminalSession session,
    int columns,
    int rows,
  ) async => _unavailable();

  @override
  Future<void> interruptTerminal(TerminalSession session) async =>
      _unavailable();

  @override
  Future<void> closeTerminal(TerminalSession session) async => _unavailable();
}
