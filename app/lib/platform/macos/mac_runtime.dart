import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:aggregate_connectors/aggregate_connectors.dart';
import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:flutter_pty2/flutter_pty2.dart';
import 'package:mcp_dart/mcp_dart.dart' as mcp;
// The SDK keeps its full JSON Schema validator internal in 2.4.3. This import
// stays inside the replaceable macOS adapter until it has a public API.
// ignore: implementation_imports
import 'package:mcp_dart/src/shared/json_schema/json_schema_validator.dart';

import 'credential_store.dart';
import 'connection_diagnostic.dart';
import 'netease_cli_identity.dart';

File? _bundledCliLauncher() {
  final executable = File(Platform.resolvedExecutable);
  if (!executable.parent.path.endsWith('/Contents/MacOS')) return null;
  return File(
    '${executable.parent.parent.path}/Helpers/aggregate-cli-launcher',
  );
}

final class MacRuntime
    implements RuntimePort, ConnectionAccountPort, ConnectionSetupPort {
  MacRuntime._(this.dataDirectory, this._credentials, this._cliLauncher);

  static Future<MacRuntime> open({
    Directory? dataDirectory,
    CredentialStore? credentialStore,
    File? cliLauncher,
  }) async {
    final home = Platform.environment['HOME'];
    if (home == null || !home.startsWith('/')) {
      throw StateError('无法确定用户配置目录（HOME）');
    }
    final runtime = MacRuntime._(
      dataDirectory ?? Directory('$home/Library/Application Support/Aggregate'),
      credentialStore ?? const NoCredentialStore(),
      cliLauncher ?? _bundledCliLauncher(),
    );
    await runtime._load();
    return runtime;
  }

  final Directory dataDirectory;
  final CredentialStore _credentials;
  final File? _cliLauncher;
  final _entries = <String, _Entry>{};
  final _capabilities = <String, Capability>{};
  final _tools = <String, mcp.Tool>{};
  final _actions = <String, ConnectorAction>{};
  final _clients = <String, mcp.McpClient>{};
  final _events = StreamController<RunEvent>.broadcast(sync: true);
  final _runs = <String, _Run>{};
  final _activity = <RunSummary>[];
  UserPreferences _preferences = const UserPreferences();
  final _terminals = <String, _Terminal>{};
  final _accountLoginSessions = <String>{};
  final _reconnecting = <String>{};
  final _setupDrafts = <String, ConnectionSpec>{};
  bool _disposed = false;
  var _serial = 0;
  Future<void> _writeQueue = Future.value();
  static const _outputLimit = 1024 * 1024;
  static const _maxConcurrent = 3;
  static const _safeEnvironment = {
    'HOME',
    'PATH',
    'TMPDIR',
    'LANG',
    'LC_ALL',
    'USER',
    'LOGNAME',
  };

  @override
  bool get isPreview => false;

  @override
  RuntimeFeatures get features => RuntimeFeatures.localDesktop;

  final List<String> _startupNotices = [];
  @override
  List<String> get startupNotices => List.unmodifiable(_startupNotices);

  File get _connectionsFile => File('${dataDirectory.path}/connections.json');
  File get _activityFile => File('${dataDirectory.path}/activity.json');
  File get _preferencesFile => File('${dataDirectory.path}/preferences.json');

  Future<void> _load() async {
    await dataDirectory.create(recursive: true);
    if (await _preferencesFile.exists()) {
      try {
        _preferences = UserPreferences.fromJson(
          jsonDecode(await _preferencesFile.readAsString()),
        );
      } on FormatException {
        await _recoverDamaged(_preferencesFile, '外观与活动偏好');
        await _persistPreferences();
      } on TypeError {
        await _recoverDamaged(_preferencesFile, '外观与活动偏好');
        await _persistPreferences();
      }
    }
    if (await _connectionsFile.exists()) {
      try {
        final raw = jsonDecode(await _connectionsFile.readAsString());
        if (raw is! Map ||
            raw['schemaVersion'] != 1 ||
            raw['connections'] is! List) {
          throw const FormatException('连接配置格式无效');
        }
        for (final item in raw['connections'] as List) {
          final json = jsonObject(item, 'connection');
          final id = jsonString(json, 'id');
          _entries[id] = _Entry(id, ConnectionSpec.fromJson(json['spec']));
        }
      } on FormatException {
        _entries.clear();
        await _recoverDamaged(_connectionsFile, '连接配置');
        await _persistConnections();
      } on TypeError {
        _entries.clear();
        await _recoverDamaged(_connectionsFile, '连接配置');
        await _persistConnections();
      }
    }
    if (await _activityFile.exists()) {
      try {
        final raw = jsonDecode(await _activityFile.readAsString());
        if (raw is List) _activity.addAll(raw.map(RunSummary.fromJson));
      } on FormatException {
        // A damaged activity cache must not hide configured connections.
      }
    }
    _pruneActivity();
    for (final id in _entries.keys.toList()) {
      await _refreshConnection(ConnectionId(id), verifyLogin: false);
    }
  }

  Future<void> _recoverDamaged(File file, String label) async {
    final backup =
        '${file.path}.damaged-${DateTime.now().toUtc().microsecondsSinceEpoch}';
    await file.copy(backup);
    _startupNotices.add('$label无法读取，已备份到 $backup。请检查备份后重新配置。');
  }

  Future<void> _persistConnections() => _enqueueWrite(_connectionsFile, {
    'schemaVersion': 1,
    'connections': [
      for (final entry in _entries.values)
        {'id': entry.id, 'spec': entry.spec.toJson()},
    ],
  });

  Future<void> _persistActivity() => _enqueueWrite(_activityFile, [
    for (final item in _activity.take(100)) item.toJson(),
  ]);

  Future<void> _persistPreferences() =>
      _enqueueWrite(_preferencesFile, _preferences.toJson());

  void _pruneActivity() {
    final cutoff = DateTime.now().toUtc().subtract(
      Duration(days: _preferences.activityRetentionDays),
    );
    _activity.removeWhere((item) => item.latest.occurredAt.isBefore(cutoff));
  }

  @override
  Future<UserPreferences> loadPreferences() async => _preferences;

  @override
  Future<void> savePreferences(UserPreferences preferences) async {
    _preferences = preferences;
    _pruneActivity();
    await _persistPreferences();
    await _persistActivity();
  }

  @override
  Future<void> clearActivity() async {
    _activity.clear();
    await _persistActivity();
  }

  Future<void> _enqueueWrite(File file, Object value, {bool pretty = false}) {
    final encoded = pretty
        ? const JsonEncoder.withIndent('  ').convert(value)
        : jsonEncode(value);
    final pending = _writeQueue.then((_) async {
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(encoded, flush: true);
      await temporary.rename(file.path);
    });
    // A failed write is returned to its caller, while later writes still run.
    _writeQueue = pending.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return pending;
  }

  @override
  Future<List<Connection>> listConnections() async => [
    for (final entry in _entries.values) entry.connection,
  ];

  @override
  Future<void> moveConnection(ConnectionId id, int offset) async {
    if (offset != -1 && offset != 1) {
      throw ArgumentError('连接只能上移或下移一位');
    }
    final ids = _entries.keys.toList();
    final index = ids.indexOf(id.value);
    if (index < 0) throw ArgumentError('连接不存在');
    final target = index + offset;
    if (target < 0 || target >= ids.length) return;
    final original = Map<String, _Entry>.of(_entries);
    final moved = ids.removeAt(index);
    ids.insert(target, moved);
    _entries
      ..clear()
      ..addEntries(ids.map((key) => MapEntry(key, original[key]!)));
    try {
      await _persistConnections();
    } catch (_) {
      _entries
        ..clear()
        ..addAll(original);
      rethrow;
    }
  }

  _Entry _cliEntry(ConnectionId id) {
    final entry = _entries[id.value];
    if (entry == null || entry.spec.kind != ConnectionKind.cli) {
      throw ArgumentError('仅 CLI 连接可编辑动作');
    }
    return entry;
  }

  ConnectorManifest _validateActionManifest(ConnectionId id, JsonMap value) {
    final entry = _cliEntry(id);
    final manifest = ConnectorManifest.fromJson(value);
    if (!manifest.supports('macos') ||
        manifest.executable != entry.spec.executable) {
      throw const FormatException('清单的平台或程序路径与当前 CLI 连接不一致');
    }
    return manifest;
  }

  @override
  Future<JsonMap?> loadActionManifest(ConnectionId id) async {
    final entry = _cliEntry(id);
    final path = entry.spec.manifestPath;
    if (path != null && path.isNotEmpty) {
      return readActionManifestFile(path);
    }
    if (await isNeteaseCliPackage(entry.spec.executable!)) {
      return ConnectorManifest.neteaseCli(entry.spec.executable!).toJson();
    }
    return null;
  }

  @override
  Future<JsonMap> readActionManifestFile(String path) async {
    if (!path.startsWith('/') ||
        !await File(path).exists() ||
        await File(path).length() > 1024 * 1024) {
      throw const FormatException('请选择小于 1 MiB 的动作清单 JSON 文件');
    }
    return ConnectorManifest.fromJson(
      jsonDecode(await File(path).readAsString()),
    ).toJson();
  }

  @override
  Future<void> saveActionManifest(ConnectionId id, JsonMap value) async {
    final manifest = _validateActionManifest(id, value);
    final entry = _cliEntry(id);
    final filename = base64Url
        .encode(utf8.encode(id.value))
        .replaceAll('=', '');
    final directory = Directory('${dataDirectory.path}/manifests');
    await directory.create(recursive: true);
    final managed = File('${directory.path}/$filename.json');
    await _enqueueWrite(managed, manifest.toJson(), pretty: true);
    final previous = entry.spec;
    entry.spec = ConnectionSpec(
      kind: previous.kind,
      label: previous.label,
      executable: previous.executable,
      arguments: previous.arguments,
      workingDirectory: previous.workingDirectory,
      url: previous.url,
      manifestPath: managed.path,
      profileId: previous.profileId,
      hasCredential: previous.hasCredential,
    );
    try {
      await _persistConnections();
    } catch (_) {
      entry.spec = previous;
      rethrow;
    }
    await refreshConnection(id);
  }

  @override
  Future<void> exportActionManifest(
    ConnectionId id,
    JsonMap value,
    String path,
  ) async {
    if (!path.startsWith('/')) throw const FormatException('导出位置必须是绝对路径');
    final manifest = _validateActionManifest(id, value);
    await _enqueueWrite(File(path), manifest.toJson(), pretty: true);
  }

  @override
  Future<Connection> addConnection(ConnectionSpec spec) async {
    _validateSpec(spec);
    if (spec.profileId != null &&
        !await isNeteaseCliPackage(spec.executable ?? '')) {
      throw const FormatException('独立账号目录仅适用于网易云音乐适配器');
    }
    final id =
        'connection-${DateTime.now().microsecondsSinceEpoch}-${++_serial}';
    final token = spec.authToken?.trim();
    if (token != null && token.isNotEmpty) {
      await _credentials.write(id, token);
    }
    final stored = ConnectionSpec.fromJson({
      ...spec.toJson(),
      if (token != null && token.isNotEmpty) 'hasCredential': true,
    });
    _entries[id] = _Entry(id, stored);
    try {
      await _persistConnections();
    } catch (_) {
      _entries.remove(id);
      if (token != null && token.isNotEmpty) await _credentials.delete(id);
      rethrow;
    }
    return refreshConnection(ConnectionId(id));
  }

  @override
  List<ConnectionAdapter> get connectionAdapters => const [
    ConnectionAdapter(
      id: 'netease-music',
      label: '网易云音乐',
      kind: ConnectionKind.cli,
      defaultLabel: '网易云音乐',
      description: '先测试本机配置；保存后在播放器内扫码登录，系统会继续显示搜索权限状态。',
      showGenericCliFields: false,
      autoDetectExecutable: true,
      fields: [
        SetupField(key: 'appId', label: '开放平台 App ID'),
        SetupField(
          key: 'privateKey',
          label: 'Private Key（PEM）',
          kind: SetupFieldKind.secret,
          hint: '仅用于配置此连接；不会写入 Aggregate 的连接清单。',
          readFileContent: true,
        ),
      ],
    ),
    ConnectionAdapter(id: 'cli', label: '自定义 CLI', kind: ConnectionKind.cli),
    ConnectionAdapter(
      id: 'mcp-stdio',
      label: 'stdio MCP',
      kind: ConnectionKind.mcpStdio,
    ),
    ConnectionAdapter(
      id: 'mcp-http',
      label: 'HTTP MCP',
      kind: ConnectionKind.mcpHttp,
    ),
  ];

  @override
  Future<String?> detectExecutable(String adapterId) async {
    if (adapterId != 'netease-music') return null;
    final paths = <String>{
      for (final entry in _entries.values)
        if (entry.spec.kind == ConnectionKind.cli &&
            entry.spec.executable != null)
          entry.spec.executable!,
      for (final directory in _environment()['PATH']!.split(':'))
        '$directory/ncm-cli',
    };
    for (final path in paths) {
      if (!path.startsWith('/')) continue;
      try {
        final stat = await File(path).stat();
        if (stat.type == FileSystemEntityType.file &&
            stat.mode & 0x49 != 0 &&
            await isNeteaseCliPackage(path)) {
          return path;
        }
      } on FileSystemException {
        // Continue to the next installation location.
      }
    }
    return null;
  }

  Directory _setupProfile(String id) {
    if (!RegExp(r'^setup-[0-9]+-[0-9]+$').hasMatch(id)) {
      throw const FormatException('连接账号目录标识无效');
    }
    return Directory('${dataDirectory.path}/connector-profiles/$id');
  }

  Future<void> _deleteSetupProfile(String id) async {
    final directory = _setupProfile(id);
    final type = await FileSystemEntity.type(
      directory.path,
      followLinks: false,
    );
    if (type == FileSystemEntityType.link) {
      await Link(directory.path).delete();
    } else if (type == FileSystemEntityType.directory) {
      await directory.delete(recursive: true);
    }
  }

  @override
  Future<ConnectionSetupReport> testConnectionSetup(
    ConnectionSetupDraft draft,
  ) async {
    final adapter = connectionAdapters.where(
      (item) => item.id == draft.adapterId,
    );
    if (adapter.isEmpty || adapter.single.kind != draft.spec.kind) {
      throw const FormatException('请选择受支持的连接类型');
    }
    _validateSpec(draft.spec);
    final id = 'setup-${DateTime.now().microsecondsSinceEpoch}-${++_serial}';
    final checks = <SetupCheck>[];
    ConnectionSpec spec = draft.spec;
    try {
      if (draft.adapterId == 'netease-music') {
        if (draft.spec.arguments.isNotEmpty ||
            draft.spec.manifestPath != null ||
            draft.spec.workingDirectory != null ||
            !await isNeteaseCliPackage(draft.spec.executable!)) {
          throw const FormatException('请选择官方 @music163/ncm-cli 程序');
        }
        final appId = draft.values['appId']?.trim() ?? '';
        final privateKey = draft.values['privateKey']?.trim() ?? '';
        if (appId.isEmpty ||
            appId.length > 200 ||
            appId.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
          throw const FormatException('请输入有效的开放平台 App ID');
        }
        if (privateKey.length > 32 * 1024 ||
            !RegExp(r'-----BEGIN (?:RSA )?PRIVATE KEY-----')
                .hasMatch(privateKey) ||
            !privateKey.contains('-----END ')) {
          throw const FormatException('请输入 PEM 格式的 Private Key');
        }
        final profile = _setupProfile(id);
        await profile.create(recursive: true);
        final chmod = await Process.run('/bin/chmod', ['700', profile.path]);
        if (chmod.exitCode != 0) throw const FileSystemException('无法保护账号目录');
        final keyFile = File('${profile.path}/.setup-private-key.pem');
        try {
          await keyFile.writeAsString('$privateKey\n', flush: true);
          final keyMode = await Process.run('/bin/chmod', [
            '600',
            keyFile.path,
          ]);
          if (keyMode.exitCode != 0) {
            throw const FileSystemException('无法保护临时私钥');
          }
          final keyCheck = await Process.run('/usr/bin/openssl', [
            'pkey',
            '-in',
            keyFile.path,
            '-noout',
          ]).timeout(const Duration(seconds: 5));
          if (keyCheck.exitCode != 0) {
            throw const FormatException('Private Key 不是有效的 PEM 私钥');
          }
          await _setupCommand(draft.spec.executable!, [
            'config',
            'set',
            'appId',
            appId,
          ], id);
          await _setupCommand(draft.spec.executable!, [
            'config',
            'set',
            'privateKey',
            keyFile.path,
          ], id);
        } finally {
          if (await keyFile.exists()) await keyFile.delete();
        }
        spec = ConnectionSpec(
          kind: draft.spec.kind,
          label: draft.spec.label,
          executable: draft.spec.executable,
          profileId: id,
        );
        try {
          await _refreshCli(_Entry(id, spec), verifyLogin: false);
        } finally {
          _removeCapabilities(id);
        }
        checks.add(
          const SetupCheck(
            '程序与配置',
            SetupCheckStatus.passed,
            '官方 CLI 可运行，App ID 与 Private Key 已写入独立账号目录。',
          ),
        );
        var signedIn = false;
        try {
          final login = await _setupCommand(
            spec.executable!,
            ['login', '--check', '--output', 'json'],
            id,
            network: true,
            allowFailure: true,
          );
          final decoded = jsonDecode(login.stdout);
          signedIn =
              login.exitCode == 0 &&
              decoded is Map &&
              decoded['success'] == true;
        } on Exception {
          // Network and account failures do not invalidate local configuration.
        }
        checks.add(
          SetupCheck(
            '账号登录',
            signedIn
                ? SetupCheckStatus.passed
                : SetupCheckStatus.actionRequired,
            signedIn ? '账号已登录。' : '保存后在播放器内扫码登录，再测试搜索权限。',
          ),
        );
        if (signedIn) {
          var allowed = false;
          try {
            final search = await _setupCommand(
              spec.executable!,
              ['search', 'song', '--keyword', '音乐', '--output', 'json'],
              id,
              network: true,
              allowFailure: true,
            );
            allowed = search.exitCode == 0;
          } on Exception {
            // Preserve the tested connection and show the incomplete check.
          }
          checks.add(
            SetupCheck(
              '搜索接口',
              allowed
                  ? SetupCheckStatus.passed
                  : SetupCheckStatus.actionRequired,
              allowed ? '搜索接口可用。' : '搜索接口尚未通过，请检查开放平台应用的接口权限。',
            ),
          );
        } else {
          checks.add(
            const SetupCheck(
              '搜索接口',
              SetupCheckStatus.actionRequired,
              '登录后才能验证搜索权限。',
            ),
          );
        }
      } else {
        final entry = _Entry(id, spec);
        try {
          if (spec.kind == ConnectionKind.cli) {
            await _refreshCli(entry, verifyLogin: false);
          } else {
            await _refreshMcp(entry);
          }
          if (spec.kind == ConnectionKind.cli) {
            checks.add(
              const SetupCheck(
                '程序检查',
                SetupCheckStatus.passed,
                '程序路径、执行权限和动作清单已验证。',
              ),
            );
            checks.add(
              const SetupCheck(
                '功能验证',
                SetupCheckStatus.actionRequired,
                '普通 CLI 没有统一连通性协议；保存后请运行一个只读命令验证。',
              ),
            );
          } else {
            checks.add(
              const SetupCheck(
                '连通性',
                SetupCheckStatus.passed,
                'MCP 握手与功能发现成功。',
              ),
            );
          }
        } finally {
          await _clients.remove(id)?.close();
          _removeCapabilities(id);
        }
      }
      _setupDrafts[id] = spec;
      return ConnectionSetupReport(draftId: id, checks: checks, canSave: true);
    } catch (cause) {
      await _deleteSetupProfile(id);
      checks.add(
        SetupCheck(
          '连接测试',
          SetupCheckStatus.failed,
          draft.adapterId == 'netease-music'
              ? '配置失败：${_safeSetupError(cause)}'
              : describeConnectionFailure(draft.spec.kind, cause),
        ),
      );
      return ConnectionSetupReport(draftId: id, checks: checks, canSave: false);
    }
  }

  String _safeSetupError(Object cause) => switch (cause) {
    FormatException exception => exception.message,
    TimeoutException _ => '连接超时，请检查网络与程序路径。',
    FileSystemException _ => '无法访问程序或配置目录。',
    ProcessException _ => '无法启动 CLI，请检查程序和依赖。',
    _ => '连接失败，请检查输入与服务状态。',
  };

  Future<({int exitCode, String stdout})> _setupCommand(
    String executable,
    List<String> arguments,
    String profileId, {
    bool network = false,
    bool allowFailure = false,
  }) async {
    final process = await Process.start(
      executable,
      arguments,
      environment: _environment(networkProxy: network, profileId: profileId),
      includeParentEnvironment: false,
      runInShell: false,
    );
    Future<String> collect(Stream<List<int>> source) async {
      final output = BytesBuilder(copy: false);
      await for (final chunk in source) {
        if (output.length + chunk.length > 64 * 1024) {
          process.kill(ProcessSignal.sigterm);
          throw const FormatException('CLI 输出过大');
        }
        output.add(chunk);
      }
      return utf8.decode(output.takeBytes(), allowMalformed: true);
    }

    late final List<Object> result;
    try {
      result = await Future.wait<Object>([
        process.exitCode,
        collect(process.stdout),
        collect(process.stderr),
      ]).timeout(Duration(seconds: network ? 15 : 8));
    } catch (_) {
      process.kill(ProcessSignal.sigterm);
      rethrow;
    }
    final exitCode = result[0] as int;
    if (!allowFailure && exitCode != 0) {
      throw const FormatException('CLI 未接受配置，请检查 App ID 与 Private Key');
    }
    return (exitCode: exitCode, stdout: result[1] as String);
  }

  @override
  Future<Connection> saveConnectionSetup(String draftId) async {
    final spec = _setupDrafts[draftId];
    if (spec == null) throw StateError('连接测试已过期，请重新测试');
    final connection = await addConnection(spec);
    _setupDrafts.remove(draftId);
    return connection;
  }

  @override
  Future<void> discardConnectionSetup(String draftId) async {
    final spec = _setupDrafts.remove(draftId);
    if (spec?.profileId case final profile?) {
      await _deleteSetupProfile(profile);
    }
  }

  void _validateSpec(ConnectionSpec spec) {
    if (spec.profileId case final profile?) _setupProfile(profile);
    if (spec.label.trim().isEmpty || spec.label.length > 100) {
      throw const FormatException('连接名称应为 1–100 个字符');
    }
    if (spec.kind == ConnectionKind.mcpHttp) {
      final uri = Uri.tryParse(spec.url ?? '');
      if (uri == null ||
          !uri.hasAuthority ||
          !{'http', 'https'}.contains(uri.scheme) ||
          uri.userInfo.isNotEmpty) {
        throw const FormatException('请输入有效的 HTTP(S) MCP 地址，且不要把凭证写入 URL');
      }
      if (spec.authToken?.trim().isNotEmpty == true &&
          uri.scheme == 'http' &&
          uri.host != 'localhost' &&
          !(InternetAddress.tryParse(uri.host)?.isLoopback ?? false)) {
        throw const FormatException('带凭证的远程 MCP 地址必须使用 HTTPS');
      }
    } else {
      if (spec.authToken?.isNotEmpty == true || spec.hasCredential) {
        throw const FormatException('Bearer Token 只适用于 HTTP MCP');
      }
      final path = spec.executable;
      if (path == null || !path.startsWith('/') || path.contains('\x00')) {
        throw const FormatException('请选择绝对路径的可执行文件');
      }
    }
    if (spec.arguments.any((item) => item.contains('\x00'))) {
      throw const FormatException('参数不能包含 NUL 字符');
    }
    final directory = spec.workingDirectory;
    if (directory != null &&
        directory.isNotEmpty &&
        !directory.startsWith('/')) {
      throw const FormatException('工作目录必须是绝对路径');
    }
    if (spec.manifestPath != null && spec.kind != ConnectionKind.cli) {
      throw const FormatException('只有 CLI 连接可使用动作清单');
    }
  }

  @override
  Future<void> removeConnection(ConnectionId id) async {
    final entry = _entries.remove(id.value);
    if (entry == null) return;
    await _clients.remove(id.value)?.close();
    _removeCapabilities(id.value);
    await _persistConnections();
    if (entry.spec.hasCredential) await _credentials.delete(id.value);
    if (entry.spec.profileId case final profile?) {
      await _deleteSetupProfile(profile);
    }
  }

  void _removeCapabilities(String id) {
    final keys = _capabilities.keys
        .where((key) => key.startsWith('$id:'))
        .toList();
    for (final key in keys) {
      _capabilities.remove(key);
      _tools.remove(key);
      _actions.remove(key);
    }
  }

  @override
  Future<Connection> refreshConnection(ConnectionId id) =>
      _refreshConnection(id, verifyLogin: true);

  Future<Connection> _refreshConnection(
    ConnectionId id, {
    required bool verifyLogin,
  }) async {
    final entry = _entries[id.value];
    if (entry == null) throw ArgumentError('连接不存在');
    await _clients.remove(id.value)?.close();
    _removeCapabilities(id.value);
    entry.status = ConnectionStatus.connecting;
    entry.diagnostic = null;
    try {
      _validateSpec(entry.spec);
      if (entry.spec.kind == ConnectionKind.cli) {
        await _refreshCli(entry, verifyLogin: verifyLogin);
      } else {
        await _refreshMcp(entry);
      }
      entry.status = ConnectionStatus.ready;
    } catch (cause) {
      await _clients.remove(id.value)?.close();
      _removeCapabilities(id.value);
      entry.status = ConnectionStatus.unavailable;
      entry.diagnostic = describeConnectionFailure(entry.spec.kind, cause);
    }
    return entry.connection;
  }

  Future<void> _refreshCli(_Entry entry, {required bool verifyLogin}) async {
    final executable = File(entry.spec.executable!);
    final stat = await executable.stat();
    if (stat.type != FileSystemEntityType.file || stat.mode & 0x49 == 0) {
      throw const FileSystemException('程序不存在或不可执行');
    }
    if (entry.spec.workingDirectory case final directory?) {
      if (!await Directory(directory).exists()) {
        throw const FileSystemException('工作目录不存在');
      }
    }
    final command = Capability(
      id: CapabilityId(
        ConnectionId(entry.id),
        CapabilityKind.cliCommand,
        'run',
      ),
      title: '运行 ${entry.spec.label}',
      description: '输入参数数组，直接运行已登记程序',
      permission: PermissionLevel.unknown,
      inputSchema: const {
        'type': 'object',
        'properties': {
          'argv': {
            'type': 'array',
            'title': '参数数组',
            'items': {'type': 'string'},
          },
        },
        'required': ['argv'],
        'additionalProperties': false,
      },
    );
    _capabilities[command.id.key] = command;
    final manifestPath = entry.spec.manifestPath;
    final isNeteaseCli = await isNeteaseCliPackage(executable.path);
    if (!isNeteaseCli &&
        executable.uri.pathSegments.last == 'ncm-cli' &&
        (manifestPath == null || manifestPath.isEmpty)) {
      entry.diagnostic =
          '无法确认此程序属于 @music163/ncm-cli；仍可作为普通 CLI 使用。请检查安装来源或导入自定义动作清单。';
    }
    if (isNeteaseCli) {
      await _checkNeteaseEnvironment(entry, verifyLogin: verifyLogin);
    }
    if ((manifestPath == null || manifestPath.isEmpty) && !isNeteaseCli) {
      return;
    }
    final manifest = manifestPath == null || manifestPath.isEmpty
        ? ConnectorManifest.neteaseCli(entry.spec.executable!)
        : ConnectorManifest.fromJson(
            jsonDecode(await File(manifestPath).readAsString()),
          );
    if (!manifest.supports('macos') ||
        manifest.executable != entry.spec.executable) {
      throw const FormatException('动作清单的平台或程序路径与连接不一致');
    }
    for (final action in manifest.actions) {
      final capability = Capability(
        id: CapabilityId(
          ConnectionId(entry.id),
          CapabilityKind.cliAction,
          action.id,
        ),
        title: action.title,
        description: '${manifest.displayName} · ${action.argv.join(' ')}',
        // A local manifest is user supplied and cannot grant itself read-only
        // privileges. All CLI actions still require a confirmation.
        permission: action.permission == PermissionLevel.externalWrite
            ? PermissionLevel.externalWrite
            : PermissionLevel.unknown,
        inputSchema: action.inputSchema,
        presentation: action.presentation,
      );
      _capabilities[capability.id.key] = capability;
      _actions[capability.id.key] = action;
    }
  }

  Future<void> _checkNeteaseEnvironment(
    _Entry entry, {
    required bool verifyLogin,
  }) async {
    final environment = _environment(profileId: entry.spec.profileId);
    Future<ProcessResult> check(
      String command,
      List<String> arguments, {
      bool network = false,
    }) => Process.run(
      command,
      arguments,
      environment: network
          ? _environment(networkProxy: true, profileId: entry.spec.profileId)
          : environment,
      includeParentEnvironment: false,
      runInShell: false,
    ).timeout(Duration(seconds: network ? 12 : 5));
    try {
      final node = await check('node', ['--version']);
      final major = int.tryParse(
        RegExp(r'^v(\d+)').firstMatch('${node.stdout}'.trim())?.group(1) ?? '',
      );
      if (node.exitCode != 0 || major == null || major < 18) {
        throw const FormatException('请安装 Node.js 18 或更新版本');
      }
    } on ProcessException {
      throw const FormatException('未找到 Node.js。请安装 Node.js 18 或更新版本');
    }
    try {
      final mpv = await check('mpv', ['--version']);
      if (mpv.exitCode != 0) throw const FormatException('mpv 不可用');
    } on ProcessException {
      throw const FormatException('未找到 mpv。请安装播放器后刷新连接');
    }
    final version = await check(entry.spec.executable!, ['--version']);
    if (version.exitCode != 0) {
      throw const FormatException('ncm-cli 无法启动，请检查 Node.js 与程序路径');
    }
    final help = await check(entry.spec.executable!, ['--help']);
    final output = '${help.stdout}\n${help.stderr}';
    if (output.contains('API key 未设置')) {
      entry.diagnostic =
          '尚未配置网易云开放平台凭证。请在“管理连接”中重新添加网易云音乐连接并输入 App ID 与 Private Key。';
      return;
    }
    final notes = <String>[];
    try {
      final npm = await check('npm', ['--version']);
      if (npm.exitCode != 0) notes.add('npm 不可用；更新 ncm-cli 时需要 npm。');
    } on ProcessException {
      notes.add('未找到 npm；更新 ncm-cli 时需要 npm。');
    } on TimeoutException {
      notes.add('npm 检查超时。');
    }
    if (!verifyLogin) {
      notes.add('登录状态尚未检查；点“测试连接”可验证。');
    } else {
      try {
        final login = await check(entry.spec.executable!, [
          'login',
          '--check',
          '--output',
          'json',
        ], network: true);
        final response = jsonDecode('${login.stdout}');
        if (login.exitCode != 0 ||
            response is! Map ||
            response['success'] != true) {
          notes.add('网易云账号尚未登录。请在播放器内扫码登录。');
        }
      } on TimeoutException {
        notes.add('网易云登录检查超时，请检查网络或代理后重试。');
      } on FormatException {
        notes.add('网易云登录检查未返回可识别结果，请刷新连接。');
      } on ProcessException {
        notes.add('网易云登录检查无法启动，请刷新连接。');
      }
    }
    if (notes.isNotEmpty) {
      entry.diagnostic = notes.join(' ');
    }
  }

  Future<_Entry?> _accountEntry(ConnectionId connection) async {
    final entry = _entries[connection.value];
    if (entry?.spec.kind != ConnectionKind.cli ||
        !await isNeteaseCliPackage(entry!.spec.executable!)) {
      return null;
    }
    return entry;
  }

  @override
  Future<AccountSnapshot?> readAccount(ConnectionId connection) async {
    final entry = await _accountEntry(connection);
    if (entry == null) return null;
    if (entry.status != ConnectionStatus.ready) {
      return const AccountSnapshot(
        AccountState.unknown,
        message: '连接不可用，请在“管理连接”中检查。',
      );
    }
    try {
      final check = await _accountCommand(entry, [
        'login',
        '--check',
        '--output',
        'json',
      ]);
      if (check.output.trim().isEmpty) {
        return const AccountSnapshot(
          AccountState.unknown,
          message: '登录状态检查失败，请检查网络或开放平台配置。',
        );
      }
      final checkData = jsonDecode(check.output);
      if (checkData is! Map) throw const FormatException('invalid account');
      if (checkData['success'] == false) {
        return const AccountSnapshot(AccountState.signedOut);
      }
      if (check.exitCode != 0 || checkData['success'] != true) {
        throw const FormatException('invalid account');
      }
      return const AccountSnapshot(AccountState.signedIn);
    } on TimeoutException {
      return const AccountSnapshot(
        AccountState.unknown,
        message: '账号检查超时，请检查网络后重试。',
      );
    } on FormatException {
      return const AccountSnapshot(
        AccountState.unknown,
        message: '账号状态格式无法识别，请刷新后重试。',
      );
    } on ProcessException {
      return const AccountSnapshot(
        AccountState.unknown,
        message: '无法启动账号命令，请检查连接。',
      );
    }
  }

  @override
  Future<TerminalSession> beginAccountLogin(ConnectionId connection) async {
    if (await _accountEntry(connection) == null) {
      throw StateError('此连接不支持账号登录');
    }
    final session = await openTerminal(
      CliCommand(connection, const ['login', '--output', 'human']),
    );
    _accountLoginSessions.add(session.id);
    return session;
  }

  @override
  Future<int> waitAccountLogin(TerminalSession session) async {
    if (!_accountLoginSessions.contains(session.id)) {
      throw StateError('登录会话不存在');
    }
    final exit = await _terminal(session).session.done;
    return exit is PtyExitCode ? exit.code : -1;
  }

  @override
  Future<AccountSnapshot> logoutAccount(
    ConnectionId connection, {
    required bool confirmed,
  }) async {
    if (!confirmed) throw StateError('退出登录需要确认');
    final entry = await _accountEntry(connection);
    if (entry == null || entry.status != ConnectionStatus.ready) {
      throw StateError('网易云音乐连接不可用');
    }
    final result = await _accountCommand(entry, ['logout', '--output', 'json']);
    if (result.exitCode != 0) throw StateError('退出登录失败，请稍后重试');
    final status = await readAccount(connection);
    if (status?.state != AccountState.signedOut) {
      throw StateError('退出命令已执行，但账号状态尚未确认，请刷新');
    }
    return status!;
  }

  Future<({int exitCode, String output})> _accountCommand(
    _Entry entry,
    List<String> arguments,
  ) async {
    final launcher = _cliLauncher;
    final process = await Process.start(
      launcher?.path ?? entry.spec.executable!,
      launcher == null
          ? [...entry.spec.arguments, ...arguments]
          : [entry.spec.executable!, ...entry.spec.arguments, ...arguments],
      workingDirectory: entry.spec.workingDirectory,
      environment: _environment(
        networkProxy: true,
        profileId: entry.spec.profileId,
      ),
      includeParentEnvironment: false,
      runInShell: false,
    );
    void stop() {
      if (launcher != null &&
          Process.killPid(-process.pid, ProcessSignal.sigterm)) {
        return;
      }
      process.kill(ProcessSignal.sigterm);
    }

    Future<String> collect(Stream<List<int>> source) async {
      final output = BytesBuilder(copy: false);
      await for (final chunk in source) {
        if (output.length + chunk.length > 64 * 1024) {
          stop();
          throw const FormatException('account output too large');
        }
        output.add(chunk);
      }
      return utf8.decode(output.takeBytes(), allowMalformed: true);
    }

    try {
      final results = await Future.wait<Object>([
        process.exitCode,
        collect(process.stdout),
        collect(process.stderr),
      ]).timeout(const Duration(seconds: 15));
      return (exitCode: results[0] as int, output: results[1] as String);
    } catch (_) {
      stop();
      rethrow;
    }
  }

  Future<void> _refreshMcp(_Entry entry) async {
    final client = mcp.McpClient(
      const mcp.Implementation(name: 'aggregate', version: '0.3.0'),
    );
    try {
      final token =
          entry.spec.authToken ??
          (entry.spec.hasCredential ? await _credentials.read(entry.id) : null);
      if (entry.spec.hasCredential && (token == null || token.isEmpty)) {
        throw StateError('连接凭证缺失，请删除连接后重新添加');
      }
      final transport = entry.spec.kind == ConnectionKind.mcpStdio
          ? mcp.StdioClientTransport(
              mcp.StdioServerParameters(
                command: entry.spec.executable!,
                args: entry.spec.arguments,
                environment: _environment(),
                includeParentEnvironment: false,
                workingDirectory: entry.spec.workingDirectory,
                restartOnUnexpectedExit: false,
              ),
            )
          : mcp.StreamableHttpClientTransport(
              Uri.parse(entry.spec.url!),
              opts: token == null
                  ? null
                  : mcp.StreamableHttpClientTransportOptions(
                      requestInit: {
                        'headers': {'Authorization': 'Bearer $token'},
                      },
                    ),
            );
      await client.connect(transport).timeout(const Duration(seconds: 12));
      _clients[entry.id] = client;
      client.onclose = () {
        if (!identical(_clients[entry.id], client)) return;
        _clients.remove(entry.id);
        _removeCapabilities(entry.id);
        entry.status = ConnectionStatus.unavailable;
        entry.diagnostic = 'MCP 连接已断开。请检查服务进程和网络，然后点“测试连接”。';
        unawaited(_reconnectMcp(entry.id));
      };
      entry.version = client.getServerVersion()?.version;
      await _discover(entry.id, client);
    } catch (_) {
      _clients.remove(entry.id);
      await client.close();
      rethrow;
    }
  }

  Future<void> _discover(String id, mcp.McpClient client) async {
    String? cursor;
    final seen = <String>{};
    do {
      final page = await client
          .listTools(
            params: cursor == null
                ? null
                : mcp.ListToolsRequest(cursor: cursor),
          )
          .timeout(const Duration(seconds: 10));
      for (final tool in page.tools) {
        final capability = Capability(
          id: CapabilityId(ConnectionId(id), CapabilityKind.mcpTool, tool.name),
          title: tool.title ?? tool.name,
          description: tool.description ?? 'MCP 工具',
          permission: PermissionLevel.unknown,
          inputSchema: Map<String, Object?>.from(tool.inputSchema.toJson()),
        );
        _capabilities[capability.id.key] = capability;
        _tools[capability.id.key] = tool;
      }
      cursor = page.nextCursor;
    } while (cursor != null && seen.add(cursor) && seen.length < 100);

    cursor = null;
    seen.clear();
    do {
      final page = await client
          .listResources(
            params: cursor == null
                ? null
                : mcp.ListResourcesRequest(cursor: cursor),
          )
          .timeout(const Duration(seconds: 10));
      for (final resource in page.resources) {
        final capability = Capability(
          id: CapabilityId(
            ConnectionId(id),
            CapabilityKind.mcpResource,
            resource.uri,
          ),
          title: resource.title ?? resource.name,
          description: resource.description ?? resource.uri,
          permission: PermissionLevel.read,
        );
        _capabilities[capability.id.key] = capability;
      }
      cursor = page.nextCursor;
    } while (cursor != null && seen.add(cursor) && seen.length < 100);

    cursor = null;
    seen.clear();
    do {
      final page = await client
          .listPrompts(
            params: cursor == null
                ? null
                : mcp.ListPromptsRequest(cursor: cursor),
          )
          .timeout(const Duration(seconds: 10));
      for (final prompt in page.prompts) {
        final properties = <String, Object?>{};
        final required = <String>[];
        for (final argument in prompt.arguments ?? <mcp.PromptArgument>[]) {
          properties[argument.name] = {
            'type': 'string',
            'title': argument.title ?? argument.name,
          };
          if (argument.required == true) required.add(argument.name);
        }
        final capability = Capability(
          id: CapabilityId(
            ConnectionId(id),
            CapabilityKind.mcpPrompt,
            prompt.name,
          ),
          title: prompt.title ?? prompt.name,
          description: prompt.description ?? 'MCP 提示',
          permission: PermissionLevel.read,
          inputSchema: {
            'type': 'object',
            'properties': properties,
            'required': required,
          },
        );
        _capabilities[capability.id.key] = capability;
      }
      cursor = page.nextCursor;
    } while (cursor != null && seen.add(cursor) && seen.length < 100);
  }

  Map<String, String> _environment({
    bool networkProxy = false,
    String? profileId,
  }) {
    final home = Platform.environment['HOME'];
    final paths = <String>[
      if (home != null && home.isNotEmpty) '$home/.local/bin',
      '/opt/homebrew/bin',
      '/usr/local/bin',
      ...?Platform.environment['PATH']?.split(':'),
      '/usr/bin',
      '/bin',
    ];
    final environment = {
      for (final key in _safeEnvironment) key: ?Platform.environment[key],
      'PATH': paths.where((path) => path.isNotEmpty).toSet().join(':'),
    };
    if (profileId != null) {
      environment['HOME'] = _setupProfile(profileId).path;
    }
    if (networkProxy) {
      for (final key in const [
        'HTTP_PROXY',
        'HTTPS_PROXY',
        'ALL_PROXY',
        'NO_PROXY',
        'http_proxy',
        'https_proxy',
        'all_proxy',
        'no_proxy',
      ]) {
        final value = Platform.environment[key];
        if (value == null ||
            value.isEmpty ||
            value.length > 4096 ||
            value.contains('\n') ||
            value.contains('\x00')) {
          continue;
        }
        if (key.toLowerCase() != 'no_proxy') {
          final uri = Uri.tryParse(value);
          if (uri == null ||
              uri.userInfo.isNotEmpty ||
              !{'http', 'https', 'socks4', 'socks5'}.contains(uri.scheme)) {
            continue;
          }
        }
        environment[key] = value;
      }
    }
    return environment;
  }

  @override
  Future<List<Capability>> searchCapabilities(SearchQuery query) async {
    final needle = query.text.trim().toLowerCase();
    return [
      for (final capability in _capabilities.values)
        if ((query.kind == null || query.kind == capability.id.kind) &&
            (needle.isEmpty ||
                '${capability.title} ${capability.description} '
                        '${_entries[capability.id.connection.value]?.spec.label ?? ''}'
                    .toLowerCase()
                    .contains(needle)))
          capability,
    ];
  }

  @override
  Future<RunHandle> invoke(
    CapabilityId id,
    JsonMap arguments, {
    bool permissionGranted = false,
  }) async {
    final capability = _capabilities[id.key];
    if (capability == null) throw ArgumentError('功能不存在，请刷新连接');
    final entry = _entries[id.connection.value];
    if (entry == null || entry.status != ConnectionStatus.ready) {
      throw StateError('连接不可用，请先刷新');
    }
    final runId = RunId(
      'run-${DateTime.now().microsecondsSinceEpoch}-${++_serial}',
    );
    final run = _Run(runId, id);
    _runs[runId.value] = run;
    _emit(run, RunState.created);
    _emit(run, RunState.validating);
    if (capability.permission != PermissionLevel.read && !permissionGranted) {
      _emit(
        run,
        RunState.failed,
        failure: const RuntimeFailure(
          RuntimeErrorCode.permissionDenied,
          '需要确认此功能的执行权限',
          phase: 'permission',
        ),
      );
      return RunHandle(runId);
    }
    if (_runs.values.where((item) => item.state == RunState.running).length >=
        _maxConcurrent) {
      _emit(
        run,
        RunState.failed,
        failure: const RuntimeFailure(
          RuntimeErrorCode.internal,
          '同时运行的任务已达上限（3 个）',
          phase: 'scheduling',
        ),
      );
      return RunHandle(runId);
    }
    try {
      _validateArguments(capability, arguments);
    } catch (cause) {
      _emit(
        run,
        RunState.failed,
        failure: RuntimeFailure(
          RuntimeErrorCode.invalidArguments,
          _safeDiagnostic(cause),
          phase: 'validation',
        ),
      );
      return RunHandle(runId);
    }
    _emit(run, RunState.running);
    if (entry.spec.kind == ConnectionKind.cli) {
      unawaited(_runCli(run, entry.spec, arguments));
    } else {
      unawaited(_runMcp(run, arguments));
    }
    return RunHandle(runId);
  }

  void _validateArguments(Capability capability, JsonMap arguments) {
    final schema = capability.inputSchema;
    if (schema.isEmpty) return;
    final parsed = mcp.JsonSchema.fromJson(Map<String, dynamic>.from(schema));
    compileJsonSchemaValidator(parsed)(arguments);
  }

  Future<void> _runCli(_Run run, ConnectionSpec spec, JsonMap arguments) async {
    Process? process;
    Timer? timer;
    var timedOut = false;
    var exceeded = false;
    final stdoutOutput = BytesBuilder(copy: false);
    final stderrOutput = BytesBuilder(copy: false);
    var byteCount = 0;
    try {
      final action = _actions[run.capability.key];
      final argv = action == null
          ? (arguments['argv'] as List).cast<String>()
          : action.expand(arguments);
      final allArguments = [...spec.arguments, ...argv];
      final launcher = _cliLauncher;
      process = await Process.start(
        launcher?.path ?? spec.executable!,
        launcher == null ? allArguments : [spec.executable!, ...allArguments],
        workingDirectory: spec.workingDirectory,
        environment: _environment(
          networkProxy:
              _capabilities[run.capability.key]?.presentation?.startsWith(
                'music.',
              ) ==
              true,
          profileId: spec.profileId,
        ),
        includeParentEnvironment: false,
        runInShell: false,
      );
      run.process = process;
      run.processGroup = launcher != null;
      if (run.isTerminal) {
        _signalCliProcess(run, ProcessSignal.sigterm);
        return;
      }
      timer = Timer(Duration(milliseconds: action?.timeoutMs ?? 30000), () {
        timedOut = true;
        _signalCliProcess(run, ProcessSignal.sigterm);
      });
      Future<void> collect(
        Stream<List<int>> stream,
        BytesBuilder destination,
      ) async {
        await for (final chunk in stream) {
          byteCount += chunk.length;
          if (byteCount > _outputLimit) {
            exceeded = true;
            _signalCliProcess(run, ProcessSignal.sigterm);
            break;
          }
          destination.add(chunk);
        }
      }

      final stdout = collect(process.stdout, stdoutOutput);
      final stderr = collect(process.stderr, stderrOutput);
      final exit = await process.exitCode;
      await Future.wait([stdout, stderr]);
      if (run.isTerminal) return;
      final textOutput = stdoutOutput.length > 0
          ? utf8.decode(stdoutOutput.takeBytes(), allowMalformed: true)
          : '';
      final errorOutput = stderrOutput.length > 0
          ? utf8.decode(stderrOutput.takeBytes(), allowMalformed: true)
          : '';
      final isNeteasePlay =
          _capabilities[run.capability.key]?.presentation == 'music.play';
      final isMusicAction =
          _capabilities[run.capability.key]?.presentation?.startsWith(
            'music.',
          ) ==
          true;
      final missingNeteaseSearchCommand =
          _capabilities[run.capability.key]?.presentation == 'music.search' &&
          errorOutput.contains("unknown command 'search'");
      Object? decodedOutput;
      var invalidJsonOutput = false;
      if (action?.output == 'json' && textOutput.isNotEmpty) {
        try {
          decodedOutput = jsonDecode(textOutput);
        } on FormatException {
          invalidJsonOutput = true;
        }
      }
      Map? musicPayload;
      if (isMusicAction && textOutput.isNotEmpty) {
        try {
          final parsed = jsonDecode(textOutput);
          if (parsed is Map) musicPayload = parsed;
        } on FormatException {
          invalidJsonOutput = true;
        }
      }
      final blocks = <ResultBlock>[
        if (textOutput.isNotEmpty)
          switch (action?.output) {
            'json' when !invalidJsonOutput => ResultBlock(
              ResultKind.json,
              decodedOutput,
            ),
            'file' => ResultBlock(ResultKind.file, textOutput.trim()),
            _ => ResultBlock(ResultKind.text, textOutput),
          },
        if (errorOutput.isNotEmpty && !isMusicAction)
          ResultBlock(ResultKind.text, errorOutput),
        ResultBlock(ResultKind.json, {
          'exitCode': exit,
          'durationMs': DateTime.now().difference(run.startedAt).inMilliseconds,
        }),
      ];
      if (timedOut) {
        _emit(
          run,
          RunState.timedOut,
          blocks: blocks,
          failure: const RuntimeFailure(
            RuntimeErrorCode.timedOut,
            '程序运行超时',
            phase: 'execution',
          ),
        );
      } else if (exceeded) {
        _emit(
          run,
          RunState.failed,
          blocks: blocks,
          failure: const RuntimeFailure(
            RuntimeErrorCode.outputLimitExceeded,
            '输出超过 1 MiB 上限',
            phase: 'execution',
          ),
        );
      } else if (missingNeteaseSearchCommand) {
        _emit(
          run,
          RunState.failed,
          blocks: blocks,
          failure: const RuntimeFailure(
            RuntimeErrorCode.connectionFailed,
            'ncm-cli 未加载搜索命令。已登录不代表搜索接口可用；请核对 CLI 所用开放平台应用的接口权限，以及当前账号能否使用该应用，然后重试。',
            phase: 'execution',
          ),
        );
      } else if (invalidJsonOutput && exit == 0) {
        _emit(
          run,
          RunState.failed,
          blocks: blocks,
          failure: const RuntimeFailure(
            RuntimeErrorCode.protocolError,
            'CLI 动作返回的内容不是有效 JSON',
            phase: 'result',
          ),
        );
      } else if (isNeteasePlay &&
          musicPayload?['success'] == false &&
          _isDaemonDisconnected(musicPayload?['message'])) {
        _emit(
          run,
          RunState.outcomeUnknown,
          blocks: blocks,
          failure: const RuntimeFailure(
            RuntimeErrorCode.outcomeUnknown,
            '播放器后台连接中断，正在读取实际播放状态',
            phase: 'playback',
          ),
        );
      } else if (isMusicAction &&
          (musicPayload?['success'] == false ||
              (musicPayload?['code'] is num && musicPayload?['code'] != 200))) {
        _emit(
          run,
          RunState.failed,
          blocks: blocks,
          failure: RuntimeFailure(
            RuntimeErrorCode.connectionFailed,
            _safeMusicMessage(musicPayload?['message']),
            phase: 'result',
          ),
        );
      } else if (isNeteasePlay && exit == 0 && textOutput.isEmpty) {
        _emit(
          run,
          RunState.outcomeUnknown,
          blocks: blocks,
          failure: const RuntimeFailure(
            RuntimeErrorCode.outcomeUnknown,
            '播放服务未确认命令，正在读取实际播放状态',
            phase: 'playback',
          ),
        );
      } else if (exit == 0) {
        _emit(run, RunState.succeeded, blocks: blocks);
      } else {
        _emit(
          run,
          RunState.failed,
          blocks: blocks,
          failure: RuntimeFailure(
            RuntimeErrorCode.internal,
            '程序退出码：$exit',
            phase: 'execution',
          ),
        );
      }
    } on ProcessException {
      if (!run.isTerminal) {
        _emit(
          run,
          RunState.failed,
          failure: const RuntimeFailure(
            RuntimeErrorCode.executableMissing,
            '无法启动程序，请检查路径和权限',
            phase: 'spawn',
          ),
        );
      }
    } catch (cause) {
      if (!run.isTerminal) {
        _emit(
          run,
          RunState.failed,
          failure: RuntimeFailure(
            RuntimeErrorCode.internal,
            _safeDiagnostic(cause),
            phase: 'execution',
          ),
        );
      }
    } finally {
      timer?.cancel();
      run.process = null;
      run.processGroup = false;
    }
  }

  Future<void> _runMcp(_Run run, JsonMap arguments) async {
    final client = _clients[run.capability.connection.value];
    if (client == null) {
      _emit(
        run,
        RunState.failed,
        failure: const RuntimeFailure(
          RuntimeErrorCode.connectionFailed,
          'MCP 连接已断开',
          phase: 'connection',
        ),
      );
      return;
    }
    try {
      final result = await client
          .callTool(
            mcp.CallToolRequest(
              name: run.capability.name,
              arguments: arguments,
            ),
          )
          .timeout(const Duration(seconds: 30));
      if (run.isTerminal) return;
      final json = result.toJson();
      final blocks = [
        ..._blocks(json),
        ResultBlock(ResultKind.json, {
          'durationMs': DateTime.now().difference(run.startedAt).inMilliseconds,
        }),
      ];
      if (result.isError == true) {
        _emit(
          run,
          RunState.failed,
          blocks: blocks,
          failure: const RuntimeFailure(
            RuntimeErrorCode.protocolError,
            'MCP 工具返回错误',
            phase: 'call',
          ),
        );
      } else {
        _emit(run, RunState.succeeded, blocks: blocks);
      }
    } on TimeoutException {
      if (!run.isTerminal) {
        _emit(
          run,
          RunState.outcomeUnknown,
          failure: const RuntimeFailure(
            RuntimeErrorCode.outcomeUnknown,
            '等待 MCP 响应超时，远端是否执行成功尚不确定',
            phase: 'call',
          ),
        );
      }
    } catch (cause) {
      if (!run.isTerminal) {
        _emit(
          run,
          RunState.outcomeUnknown,
          failure: RuntimeFailure(
            RuntimeErrorCode.outcomeUnknown,
            'MCP 调用中断，结果待确认：${_safeDiagnostic(cause)}',
            phase: 'call',
          ),
        );
      }
      final entry = _entries[run.capability.connection.value];
      if (entry != null) {
        entry.diagnostic = describeConnectionFailure(entry.spec.kind, cause);
        if (!entry.diagnostic!.contains('认证') &&
            !entry.diagnostic!.contains('权限')) {
          unawaited(_reconnectMcp(entry.id, force: true));
        }
      }
    }
  }

  Future<void> _reconnectMcp(String id, {bool force = false}) async {
    if (_disposed || !_reconnecting.add(id)) return;
    try {
      for (final delay in const [1, 2, 4]) {
        await Future<void>.delayed(Duration(seconds: delay));
        if (_disposed || !_entries.containsKey(id)) return;
        if (!force &&
            _clients.containsKey(id) &&
            _entries[id]?.status == ConnectionStatus.ready) {
          return;
        }
        force = false;
        final connection = await _refreshConnection(
          ConnectionId(id),
          verifyLogin: false,
        );
        if (connection.status == ConnectionStatus.ready) return;
      }
    } finally {
      _reconnecting.remove(id);
    }
  }

  List<ResultBlock> _blocks(Map<String, dynamic> json) => [
    if (json['structuredContent'] != null)
      ResultBlock(ResultKind.json, json['structuredContent']),
    if (json['content'] is List)
      for (final item in json['content'] as List)
        if (item is Map)
          ResultBlock(
            item['type'] == 'text'
                ? ResultKind.text
                : item['type'] == 'image'
                ? ResultKind.image
                : ResultKind.json,
            item['type'] == 'text' ? item['text'] : item,
          ),
    if (json['contents'] is List)
      for (final item in json['contents'] as List)
        ResultBlock(ResultKind.json, item),
    if (json['messages'] is List)
      for (final item in json['messages'] as List)
        ResultBlock(ResultKind.json, item),
  ];

  void _emit(
    _Run run,
    RunState state, {
    List<ResultBlock> blocks = const [],
    RuntimeFailure? failure,
  }) {
    if (run.isTerminal) return;
    run.state = state;
    final event = RunEvent(
      runId: run.id,
      sequence: run.history.length,
      state: state,
      occurredAt: DateTime.now().toUtc(),
      blocks: blocks,
      failure: failure,
    );
    run.history.add(event);
    _events.add(event);
    if (run.isTerminal) {
      _activity.insert(
        0,
        RunSummary(
          run.id,
          run.capability,
          RunEvent(
            runId: run.id,
            sequence: event.sequence,
            state: state,
            occurredAt: event.occurredAt,
          ),
        ),
      );
      if (_activity.length > 100) _activity.removeLast();
      unawaited(_persistActivity());
    }
  }

  @override
  Stream<RunEvent> watchRun(RunId id) {
    final run = _runs[id.value];
    if (run == null) throw ArgumentError('运行不存在');
    return Stream.multi((controller) {
      final subscription = _events.stream
          .where((event) => event.runId.value == id.value)
          .listen(controller.add);
      for (final event in run.history) {
        controller.add(event);
      }
      controller.onCancel = subscription.cancel;
    });
  }

  @override
  Future<List<RunSummary>> listRecentRuns() async => [
    for (final item in _activity) item,
  ];

  void _signalCliProcess(_Run run, ProcessSignal signal) {
    final process = run.process;
    if (process == null) return;
    if (run.processGroup && Process.killPid(-process.pid, signal)) return;
    process.kill(signal);
  }

  @override
  Future<void> cancel(RunId id) async {
    final run = _runs[id.value];
    if (run == null || run.isTerminal) return;
    if (_entries[run.capability.connection.value]?.spec.kind ==
        ConnectionKind.cli) {
      _signalCliProcess(run, ProcessSignal.sigterm);
      _emit(
        run,
        RunState.cancelled,
        failure: const RuntimeFailure(
          RuntimeErrorCode.cancelled,
          '已取消',
          phase: 'execution',
        ),
      );
    } else {
      _emit(
        run,
        RunState.outcomeUnknown,
        failure: const RuntimeFailure(
          RuntimeErrorCode.outcomeUnknown,
          '已停止等待 MCP 结果，远端执行状态未知',
          phase: 'call',
        ),
      );
    }
  }

  @override
  Future<List<ResultBlock>> readResource(ResourceRef ref) async {
    final client = _clients[ref.capability.connection.value];
    if (client == null ||
        ref.capability.kind != CapabilityKind.mcpResource ||
        ref.uri.toString() != ref.capability.name) {
      throw ArgumentError('资源不可用');
    }
    final result = await client
        .readResource(mcp.ReadResourceRequest(uri: ref.uri.toString()))
        .timeout(const Duration(seconds: 20));
    return _blocks(result.toJson());
  }

  @override
  Future<List<ResultBlock>> getPrompt(PromptRef ref, JsonMap arguments) async {
    final capability = _capabilities[ref.capability.key];
    final client = _clients[ref.capability.connection.value];
    if (capability == null ||
        client == null ||
        ref.capability.kind != CapabilityKind.mcpPrompt) {
      throw ArgumentError('提示不可用');
    }
    _validateArguments(capability, arguments);
    final result = await client
        .getPrompt(
          mcp.GetPromptRequest(
            name: ref.capability.name,
            arguments: {
              for (final entry in arguments.entries)
                entry.key: '${entry.value}',
            },
          ),
        )
        .timeout(const Duration(seconds: 20));
    return _blocks(result.toJson());
  }

  Future<File> _localResultFile(String path) async {
    if (!path.startsWith('/') || path.contains('\x00')) {
      throw const FormatException('文件结果必须是本机绝对路径');
    }
    final file = File(await File(path).resolveSymbolicLinks());
    if ((await file.stat()).type != FileSystemEntityType.file) {
      throw const FormatException('文件不存在或不是普通文件');
    }
    return file;
  }

  @override
  Future<List<ResultBlock>> previewLocalFile(String path) async {
    final file = await _localResultFile(path);
    final extension = file.uri.pathSegments.last.split('.').last.toLowerCase();
    final image = {'png', 'jpg', 'jpeg', 'gif', 'webp'}.contains(extension);
    final readable = {
      'txt',
      'md',
      'json',
      'yaml',
      'yml',
      'csv',
      'log',
      'xml',
      'svg',
    }.contains(extension);
    if (!image && !readable) {
      throw const FormatException('此文件类型不支持内嵌预览，可在访达中查看');
    }
    final limit = image ? 5 * 1024 * 1024 : 512 * 1024;
    if (await file.length() > limit) {
      throw const FormatException('文件超过预览大小限制，可在访达中查看');
    }
    final builder = BytesBuilder(copy: false);
    await for (final chunk in file.openRead(0, limit + 1)) {
      builder.add(chunk);
    }
    final bytes = builder.takeBytes();
    if (bytes.length > limit) {
      throw const FormatException('文件超过预览大小限制，可在访达中查看');
    }
    return [
      image
          ? ResultBlock(ResultKind.image, {'data': base64Encode(bytes)})
          : ResultBlock(ResultKind.text, utf8.decode(bytes)),
    ];
  }

  @override
  Future<void> revealLocalFile(String path) async {
    final file = await _localResultFile(path);
    final result = await Process.run('/usr/bin/open', [
      '-R',
      file.path,
    ], runInShell: false);
    if (result.exitCode != 0) {
      throw const FileSystemException('无法在访达中显示文件');
    }
  }

  @override
  Future<TerminalSession> openTerminal(CliCommand command) async {
    final entry = _entries[command.connection.value];
    if (entry == null ||
        entry.spec.kind != ConnectionKind.cli ||
        entry.status != ConnectionStatus.ready) {
      throw ArgumentError('CLI 连接不可用');
    }
    if (command.arguments.any((item) => item.contains('\x00'))) {
      throw const FormatException('终端参数无效');
    }
    if (_terminals.length >= _maxConcurrent) {
      throw StateError('同时打开的终端已达上限（3 个）');
    }
    final accountLogin =
        command.arguments.length == 3 &&
        command.arguments[0] == 'login' &&
        command.arguments[1] == '--output' &&
        command.arguments[2] == 'human' &&
        await isNeteaseCliPackage(entry.spec.executable!);
    final session = await Pty.spawn(
      PtySpawnOptions(
        executable: entry.spec.executable!,
        arguments: [...entry.spec.arguments, ...command.arguments],
        workingDirectory: entry.spec.workingDirectory,
        environment: PtyEnvironment.replace({
          ..._environment(
            networkProxy: accountLogin,
            profileId: entry.spec.profileId,
          ),
          'TERM': 'xterm-256color',
        }),
        size: const PtySize(columns: 80, rows: 24),
      ),
    );
    final id = 'terminal-${DateTime.now().microsecondsSinceEpoch}-${++_serial}';
    final terminal = _Terminal(session);
    _terminals[id] = terminal;
    terminal.subscription = session.utf8Output().listen((text) {
      if (terminal.buffer.length < _outputLimit) {
        terminal.buffer.write(text);
        terminal.output.add(text);
      }
    });
    unawaited(
      session.done.then((exit) {
        if (!terminal.output.isClosed) {
          terminal.output.add('\r\n[进程退出：$exit]\r\n');
        }
      }),
    );
    return TerminalSession(id);
  }

  _Terminal _terminal(TerminalSession session) =>
      _terminals[session.id] ?? (throw ArgumentError('终端会话不存在'));

  @override
  Stream<String> watchTerminal(TerminalSession session) {
    final terminal = _terminal(session);
    return Stream.multi((controller) {
      final sub = terminal.output.stream.listen(controller.add);
      controller.add(terminal.buffer.toString());
      controller.onCancel = sub.cancel;
    });
  }

  @override
  Future<void> writeTerminal(TerminalSession session, String text) =>
      _terminal(session).session.input.writeUtf8(text);

  @override
  Future<void> resizeTerminal(
    TerminalSession session,
    int columns,
    int rows,
  ) async {
    if (columns < 1 || rows < 1 || columns > 500 || rows > 500) {
      throw RangeError('终端尺寸无效');
    }
    _terminal(session).session.resize(PtySize(columns: columns, rows: rows));
  }

  @override
  Future<void> interruptTerminal(TerminalSession session) async {
    _terminal(session).session.sendSignal(
      PosixSignal.int_,
      target: PosixSignalTarget.shellProcessGroup,
    );
  }

  @override
  Future<void> closeTerminal(TerminalSession session) async {
    _accountLoginSessions.remove(session.id);
    final terminal = _terminals.remove(session.id);
    if (terminal == null) return;
    try {
      terminal.session.sendSignal(
        PosixSignal.term,
        target: PosixSignalTarget.shellProcessGroup,
      );
    } catch (_) {
      // The child may have exited before the UI closed its view.
    }
    await terminal.session.close();
    await terminal.subscription?.cancel();
    await terminal.output.close();
  }

  Future<void> dispose() async {
    _disposed = true;
    for (final id in _setupDrafts.keys.toList()) {
      await discardConnectionSetup(id);
    }
    for (final id in _terminals.keys.toList()) {
      await closeTerminal(TerminalSession(id));
    }
    for (final run in _runs.values) {
      _signalCliProcess(run, ProcessSignal.sigterm);
    }
    for (final client in _clients.values.toList()) {
      await client.close();
    }
    await _writeQueue;
    await _events.close();
  }
}

final class _Entry {
  _Entry(this.id, this.spec);
  final String id;
  ConnectionSpec spec;
  ConnectionStatus status = ConnectionStatus.unavailable;
  String? diagnostic;
  String? version;
  Connection get connection => Connection(
    id: ConnectionId(id),
    kind: spec.kind,
    label: spec.label,
    location: spec.kind == ConnectionKind.mcpHttp
        ? spec.url!
        : spec.executable!,
    status: status,
    protocolVersion: version,
    diagnostic: diagnostic,
  );
}

final class _Run {
  _Run(this.id, this.capability) : startedAt = DateTime.now();
  final RunId id;
  final CapabilityId capability;
  final DateTime startedAt;
  final List<RunEvent> history = [];
  RunState state = RunState.created;
  Process? process;
  bool processGroup = false;
  bool get isTerminal => {
    RunState.succeeded,
    RunState.failed,
    RunState.cancelled,
    RunState.timedOut,
    RunState.outcomeUnknown,
  }.contains(state);
}

final class _Terminal {
  _Terminal(this.session);
  final PtySession session;
  final StringBuffer buffer = StringBuffer();
  final StreamController<String> output = StreamController.broadcast(
    sync: true,
  );
  StreamSubscription<String>? subscription;
}

String _safeDiagnostic(Object cause) => switch (cause) {
  FileSystemException error => error.message,
  FormatException error => error.message,
  JsonSchemaValidationException error => error.message,
  TimeoutException _ => '连接或操作超时',
  _ => '操作失败：${cause.runtimeType}',
};

String _safeMusicMessage(Object? message) {
  if (_isDaemonDisconnected(message)) {
    return '播放器后台连接中断。请在终端运行 ncm-cli stop，再刷新连接并重试。';
  }
  if (message is! String ||
      message.isEmpty ||
      message.length > 160 ||
      message.contains('\n') ||
      message.contains('\r') ||
      RegExp(
        r'private.?key|api.?key|token|authorization|app.?id',
        caseSensitive: false,
      ).hasMatch(message)) {
    return '网易云命令失败，请检查连接诊断与账号状态';
  }
  return '网易云命令失败：$message';
}

bool _isDaemonDisconnected(Object? message) =>
    message is String &&
    (message.toLowerCase().contains('controller disconnected') ||
        message.contains('daemon 无响应'));
