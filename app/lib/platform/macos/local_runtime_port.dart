import 'package:aggregate_contracts/aggregate_contracts.dart';

import 'host/host_control_port.dart';
import 'host/host_transport_port.dart';
import 'host/mac_host_module.dart';
import 'mac_runtime.dart';
import 'keychain_credential_store.dart';

final class LocalRuntimePort
    implements RuntimePort, ConnectionAccountPort, ConnectionSetupPort {
  LocalRuntimePort.live(
    MacRuntime runtime, {
    HostTransportPort hostTransport = const PairingRequiredHostTransport(),
  }) : _delegate = runtime,
       hostControl = MacHostModule(
         runtimeBindings: MacHostRuntimeBindings(
           runtime: runtime,
           connectionSetup: runtime,
           accounts: runtime,
         ),
         hostTransport: hostTransport,
       );

  static Future<LocalRuntimePort> createLive() async => LocalRuntimePort.live(
    await MacRuntime.open(credentialStore: const KeychainCredentialStore()),
  );

  final RuntimePort _delegate;
  final HostControlPort hostControl;

  ConnectionSetupPort get _setup => _delegate as ConnectionSetupPort;

  @override
  List<ConnectionAdapter> get connectionAdapters => _setup.connectionAdapters;
  @override
  Future<String?> detectExecutable(String adapterId) =>
      _setup.detectExecutable(adapterId);
  @override
  Future<ConnectionSetupReport> testConnectionSetup(
    ConnectionSetupDraft draft,
  ) => _setup.testConnectionSetup(draft);
  @override
  Future<Connection> saveConnectionSetup(String draftId) =>
      _setup.saveConnectionSetup(draftId);
  @override
  Future<void> discardConnectionSetup(String draftId) =>
      _setup.discardConnectionSetup(draftId);

  @override
  bool get isPreview => _delegate.isPreview;
  @override
  RuntimeFeatures get features => _delegate.features;
  @override
  List<String> get startupNotices => _delegate.startupNotices;

  @override
  Future<UserPreferences> loadPreferences() => _delegate.loadPreferences();
  @override
  Future<void> savePreferences(UserPreferences preferences) =>
      _delegate.savePreferences(preferences);
  @override
  Future<void> clearActivity() => _delegate.clearActivity();

  @override
  Future<List<Connection>> listConnections() => _delegate.listConnections();
  @override
  Future<Connection> addConnection(ConnectionSpec spec) =>
      _delegate.addConnection(spec);
  @override
  Future<void> removeConnection(ConnectionId id) =>
      _delegate.removeConnection(id);
  @override
  Future<void> moveConnection(ConnectionId id, int offset) =>
      _delegate.moveConnection(id, offset);
  @override
  Future<Connection> refreshConnection(ConnectionId id) =>
      _delegate.refreshConnection(id);
  @override
  Future<JsonMap?> loadActionManifest(ConnectionId id) =>
      _delegate.loadActionManifest(id);
  @override
  Future<JsonMap> readActionManifestFile(String path) =>
      _delegate.readActionManifestFile(path);
  @override
  Future<void> saveActionManifest(ConnectionId id, JsonMap manifest) =>
      _delegate.saveActionManifest(id, manifest);
  @override
  Future<void> exportActionManifest(
    ConnectionId id,
    JsonMap manifest,
    String path,
  ) => _delegate.exportActionManifest(id, manifest, path);
  @override
  Future<List<Capability>> searchCapabilities(SearchQuery query) =>
      _delegate.searchCapabilities(query);
  @override
  Future<RunHandle> invoke(
    CapabilityId id,
    JsonMap arguments, {
    bool permissionGranted = false,
  }) => _delegate.invoke(id, arguments, permissionGranted: permissionGranted);
  @override
  Stream<RunEvent> watchRun(RunId id) => _delegate.watchRun(id);
  @override
  Future<List<RunSummary>> listRecentRuns() => _delegate.listRecentRuns();
  @override
  Future<void> cancel(RunId id) => _delegate.cancel(id);
  @override
  Future<List<ResultBlock>> readResource(ResourceRef ref) =>
      _delegate.readResource(ref);
  @override
  Future<List<ResultBlock>> getPrompt(PromptRef ref, JsonMap arguments) =>
      _delegate.getPrompt(ref, arguments);
  @override
  Future<List<ResultBlock>> previewLocalFile(String path) =>
      _delegate.previewLocalFile(path);
  @override
  Future<void> revealLocalFile(String path) => _delegate.revealLocalFile(path);
  @override
  Future<TerminalSession> openTerminal(CliCommand command) =>
      _delegate.openTerminal(command);
  @override
  Stream<String> watchTerminal(TerminalSession session) =>
      _delegate.watchTerminal(session);
  @override
  Future<void> writeTerminal(TerminalSession session, String text) =>
      _delegate.writeTerminal(session, text);
  @override
  Future<void> resizeTerminal(TerminalSession session, int columns, int rows) =>
      _delegate.resizeTerminal(session, columns, rows);
  @override
  Future<void> interruptTerminal(TerminalSession session) =>
      _delegate.interruptTerminal(session);
  @override
  Future<void> closeTerminal(TerminalSession session) =>
      _delegate.closeTerminal(session);

  ConnectionAccountPort get _accounts => _delegate as ConnectionAccountPort;

  @override
  Future<AccountSnapshot?> readAccount(ConnectionId connection) =>
      _accounts.readAccount(connection);

  @override
  Future<TerminalSession> beginAccountLogin(ConnectionId connection) =>
      _accounts.beginAccountLogin(connection);

  @override
  Future<int> waitAccountLogin(TerminalSession session) =>
      _accounts.waitAccountLogin(session);

  @override
  Future<AccountSnapshot> logoutAccount(
    ConnectionId connection, {
    required bool confirmed,
  }) => _accounts.logoutAccount(connection, confirmed: confirmed);
}
