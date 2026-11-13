import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:aggregate/platform/macos/host/host_rpc_protocol.dart';
import 'package:aggregate/platform/macos/host/host_setup_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Host setup adapter catalog', () {
    test('publishes only allowlisted metadata and marks secret fields', () {
      final setup = _SetupFixture(includeUnlistedAdapter: true);
      final coordinator = HostSetupCoordinator(setup: setup);
      final adapters = coordinator.listAdapters();

      expect(adapters.map((adapter) => adapter.id), [
        'netease-music',
        'cli',
        'mcp-stdio',
        'mcp-http',
      ]);
      final netease = adapters.first;
      expect(netease.fields.map((field) => (field.key, field.kind)), [
        ('appId', SetupFieldKind.text),
        ('privateKey', SetupFieldKind.secret),
      ]);
      final encoded = adapters.map((adapter) => adapter.toJson()).toString();
      expect(encoded, isNot(contains('/Users/')));
    });

    test(
      'hides adapters that require an unregistered Host file path',
      () async {
        final coordinator = HostSetupCoordinator(
          setup: _SetupFixture(includePathAdapter: true),
          allowedAdapterIds: const {'path-cli'},
        );
        expect(coordinator.listAdapters(), isEmpty);
        await expectLater(
          coordinator.detectExecutable(
            deviceId: 'device-1',
            adapterId: 'path-cli',
          ),
          throwsA(_rpcCode(HostRpcErrorCode.invalidParams)),
        );
      },
    );

    test(
      'returns opaque, device-bound references for detected programs',
      () async {
        final setup = _SetupFixture();
        final coordinator = HostSetupCoordinator(setup: setup);
        final result = await coordinator.detectExecutable(
          deviceId: 'device-1',
          adapterId: 'netease-music',
        );

        expect(result, isNotNull);
        expect(result!.executableRef, matches(RegExp(r'^[a-f0-9]{48}$')));
        expect(result.displayLocation, 'Mac 主机 · ncm-cli');
        expect(
          result.toJson().toString(),
          isNot(contains(_SetupFixture.detectedPath)),
        );
        await expectLater(
          coordinator.detectExecutable(deviceId: 'device-1', adapterId: 'cli'),
          throwsA(_rpcCode(HostRpcErrorCode.invalidParams)),
        );
      },
    );

    test(
      'resolves a typed command name on the Host without returning its path',
      () async {
        final setup = _SetupFixture();
        final coordinator = HostSetupCoordinator(setup: setup);
        final result = await coordinator.resolveExecutable(
          deviceId: 'device-1',
          adapterId: 'cli',
          executableName: 'custom-cli',
        );

        expect(result, isNotNull);
        expect(result!.executableRef, matches(RegExp(r'^[a-f0-9]{48}$')));
        expect(result.displayLocation, 'Mac 主机 · CLI 程序');
        expect(result.toJson().toString(), isNot(contains('/Users/host/bin')));
        await expectLater(
          coordinator.resolveExecutable(
            deviceId: 'device-1',
            adapterId: 'cli',
            executableName: '/Users/host/bin/custom-cli',
          ),
          throwsA(_rpcCode(HostRpcErrorCode.invalidParams)),
        );

        await coordinator.testConnectionSetup(
          deviceId: 'device-1',
          draft: HostSetupDraftPayload(
            adapterId: 'cli',
            label: 'Custom CLI',
            fieldValues: const {},
            executableRef: result.executableRef,
          ),
        );
        expect(
          setup.latestDraft!.spec.executable,
          '/Users/host/bin/custom-cli',
        );
      },
    );
  });

  group('Host setup coordinator', () {
    test('splits secrets from public fields and sanitizes checks', () async {
      final setup = _SetupFixture();
      final coordinator = HostSetupCoordinator(setup: setup);
      final executable = await coordinator.detectExecutable(
        deviceId: 'device-1',
        adapterId: 'netease-music',
      );
      const privateKey = '-----BEGIN PRIVATE KEY-----\nprivate-data\n';
      final result = await coordinator.testConnectionSetup(
        deviceId: 'device-1',
        draft: HostSetupDraftPayload(
          adapterId: 'netease-music',
          label: '音乐',
          fieldValues: const {'appId': 'app-123'},
          executableRef: executable!.executableRef,
        ),
        secretValues: const {'privateKey': privateKey},
      );

      expect(result.canSave, isTrue);
      expect(result.draftHandle, isNotNull);
      expect(setup.latestDraft!.spec.executable, _SetupFixture.detectedPath);
      expect(setup.latestDraft!.values, {
        'appId': 'app-123',
        'privateKey': privateKey,
      });
      expect(result.checks.first.detail, '检查通过。');
      expect(result.checks.last.detail, '需要在 Mac 主机或对应服务中完成后续设置。');
      final publicJson = result.toJson().toString();
      expect(publicJson, isNot(contains(privateKey)));
      expect(publicJson, isNot(contains(_SetupFixture.detectedPath)));
      expect(publicJson, isNot(contains('runtime-draft')));
      expect(setup.latestDraft!.values['privateKey'], privateKey);
    });

    test(
      'rejects secrets in public fields and missing required secrets',
      () async {
        final setup = _SetupFixture();
        final coordinator = HostSetupCoordinator(setup: setup);
        final executable = await coordinator.detectExecutable(
          deviceId: 'device-1',
          adapterId: 'netease-music',
        );

        await expectLater(
          coordinator.testConnectionSetup(
            deviceId: 'device-1',
            draft: HostSetupDraftPayload(
              adapterId: 'netease-music',
              label: '音乐',
              fieldValues: const {
                'appId': 'app-123',
                'privateKey': 'public-channel-secret',
              },
              executableRef: executable!.executableRef,
            ),
          ),
          throwsA(_rpcCode(HostRpcErrorCode.invalidParams)),
        );
        await expectLater(
          coordinator.testConnectionSetup(
            deviceId: 'device-1',
            draft: HostSetupDraftPayload(
              adapterId: 'netease-music',
              label: '音乐',
              fieldValues: const {'appId': 'app-123'},
              executableRef: executable.executableRef,
            ),
          ),
          throwsA(_rpcCode(HostRpcErrorCode.invalidParams)),
        );
        expect(setup.testCount, 0);
      },
    );

    test(
      'cleans up failed runtime tests without issuing a draft handle',
      () async {
        final setup = _SetupFixture()..canSave = false;
        final coordinator = HostSetupCoordinator(setup: setup);
        final executable = await coordinator.detectExecutable(
          deviceId: 'device-1',
          adapterId: 'netease-music',
        );
        final result = await coordinator.testConnectionSetup(
          deviceId: 'device-1',
          draft: HostSetupDraftPayload(
            adapterId: 'netease-music',
            label: '音乐',
            fieldValues: const {'appId': 'app-123'},
            executableRef: executable!.executableRef,
          ),
          secretValues: const {'privateKey': 'private'},
        );

        expect(result.canSave, isFalse);
        expect(result.draftHandle, isNull);
        expect(setup.discardedDrafts, ['runtime-draft-1']);
      },
    );

    test('binds HTTP bearer tokens to the separate secret map', () async {
      final setup = _SetupFixture();
      final coordinator = HostSetupCoordinator(setup: setup);
      final result = await coordinator.testConnectionSetup(
        deviceId: 'device-1',
        draft: const HostSetupDraftPayload(
          adapterId: 'mcp-http',
          label: 'Remote MCP',
          fieldValues: {},
          url: 'https://mcp.example.test/api',
        ),
        secretValues: const {'authToken': 'bearer-secret-value'},
      );

      expect(result.canSave, isTrue);
      expect(setup.latestDraft!.spec.url, 'https://mcp.example.test/api');
      expect(setup.latestDraft!.spec.authToken, 'bearer-secret-value');
      expect(
        result.toJson().toString(),
        isNot(contains('bearer-secret-value')),
      );
    });

    test('binds executable references to a device and adapter', () async {
      final setup = _SetupFixture();
      final coordinator = HostSetupCoordinator(setup: setup);
      final executable = await coordinator.detectExecutable(
        deviceId: 'device-1',
        adapterId: 'netease-music',
      );
      final draft = HostSetupDraftPayload(
        adapterId: 'netease-music',
        label: '音乐',
        fieldValues: const {'appId': 'app-123'},
        executableRef: executable!.executableRef,
      );

      await expectLater(
        coordinator.testConnectionSetup(
          deviceId: 'device-2',
          draft: draft,
          secretValues: const {'privateKey': 'private'},
        ),
        throwsA(_rpcCode(HostRpcErrorCode.unauthorized)),
      );
      await expectLater(
        coordinator.testConnectionSetup(
          deviceId: 'device-1',
          draft: HostSetupDraftPayload(
            adapterId: 'cli',
            label: 'CLI',
            fieldValues: const {},
            executableRef: executable.executableRef,
          ),
        ),
        throwsA(_rpcCode(HostRpcErrorCode.unauthorized)),
      );
      expect(setup.testCount, 0);
    });

    test('hides the Mac location when returning a saved connection', () async {
      final setup = _SetupFixture();
      final coordinator = HostSetupCoordinator(setup: setup);
      final executable = await coordinator.detectExecutable(
        deviceId: 'device-1',
        adapterId: 'netease-music',
      );
      final tested = await coordinator.testConnectionSetup(
        deviceId: 'device-1',
        draft: HostSetupDraftPayload(
          adapterId: 'netease-music',
          label: '音乐',
          fieldValues: const {'appId': 'app-123'},
          executableRef: executable!.executableRef,
        ),
        secretValues: const {'privateKey': 'private'},
      );

      final saved = await coordinator.saveConnectionSetup(
        deviceId: 'device-1',
        draftHandle: tested.draftHandle!,
      );
      expect(saved.connectionId, 'connection-1');
      expect(saved.toJson()['executionLocation'], 'Mac 主机');
      expect(saved.toJson().toString(), isNot(contains('/Users/')));
      await expectLater(
        coordinator.saveConnectionSetup(
          deviceId: 'device-1',
          draftHandle: tested.draftHandle!,
        ),
        throwsA(_rpcCode(HostRpcErrorCode.operationNotFound)),
      );
    });

    test('expires drafts and discards the Mac runtime draft', () async {
      var now = DateTime.utc(2026, 11, 13);
      final setup = _SetupFixture();
      final coordinator = HostSetupCoordinator(
        setup: setup,
        now: () => now,
        referenceLifetime: const Duration(minutes: 1),
      );
      final executable = await coordinator.detectExecutable(
        deviceId: 'device-1',
        adapterId: 'netease-music',
      );
      final tested = await coordinator.testConnectionSetup(
        deviceId: 'device-1',
        draft: HostSetupDraftPayload(
          adapterId: 'netease-music',
          label: '音乐',
          fieldValues: const {'appId': 'app-123'},
          executableRef: executable!.executableRef,
        ),
        secretValues: const {'privateKey': 'private'},
      );

      now = now.add(const Duration(minutes: 2));
      await expectLater(
        coordinator.saveConnectionSetup(
          deviceId: 'device-1',
          draftHandle: tested.draftHandle!,
        ),
        throwsA(_rpcCode(HostRpcErrorCode.operationNotFound)),
      );
      expect(setup.discardedDrafts, ['runtime-draft-1']);
    });

    test('does not retry or delete a draft after an uncertain save', () async {
      final setup = _SetupFixture()..failSave = true;
      final coordinator = HostSetupCoordinator(setup: setup);
      final executable = await coordinator.detectExecutable(
        deviceId: 'device-1',
        adapterId: 'netease-music',
      );
      final tested = await coordinator.testConnectionSetup(
        deviceId: 'device-1',
        draft: HostSetupDraftPayload(
          adapterId: 'netease-music',
          label: '音乐',
          fieldValues: const {'appId': 'app-123'},
          executableRef: executable!.executableRef,
        ),
        secretValues: const {'privateKey': 'private'},
      );

      for (var attempt = 0; attempt < 2; attempt++) {
        await expectLater(
          coordinator.saveConnectionSetup(
            deviceId: 'device-1',
            draftHandle: tested.draftHandle!,
          ),
          throwsA(_rpcCode(HostRpcErrorCode.outcomeUnknown)),
        );
      }
      await coordinator.closeDevice('device-1');
      expect(setup.saveCount, 1);
      expect(setup.discardedDrafts, isEmpty);
    });

    test(
      'revocation invalidates references and cleans tested drafts',
      () async {
        final setup = _SetupFixture();
        final coordinator = HostSetupCoordinator(setup: setup);
        final executable = await coordinator.detectExecutable(
          deviceId: 'device-1',
          adapterId: 'netease-music',
        );
        final tested = await coordinator.testConnectionSetup(
          deviceId: 'device-1',
          draft: HostSetupDraftPayload(
            adapterId: 'netease-music',
            label: '音乐',
            fieldValues: const {'appId': 'app-123'},
            executableRef: executable!.executableRef,
          ),
          secretValues: const {'privateKey': 'private'},
        );

        await coordinator.closeDevice('device-1');
        expect(setup.discardedDrafts, ['runtime-draft-1']);
        await expectLater(
          coordinator.detectExecutable(
            deviceId: 'device-1',
            adapterId: 'netease-music',
          ),
          throwsA(_rpcCode(HostRpcErrorCode.unauthorized)),
        );
        await expectLater(
          coordinator.saveConnectionSetup(
            deviceId: 'device-1',
            draftHandle: tested.draftHandle!,
          ),
          throwsA(_rpcCode(HostRpcErrorCode.unauthorized)),
        );
        coordinator.admitPairedDevice('device-1');
        final reapproved = await coordinator.detectExecutable(
          deviceId: 'device-1',
          adapterId: 'netease-music',
        );
        expect(reapproved, isNotNull);
        expect(reapproved!.executableRef, isNot(executable.executableRef));
      },
    );
  });
}

Matcher _rpcCode(HostRpcErrorCode code) =>
    isA<HostRpcProtocolException>().having((error) => error.code, 'code', code);

final class _SetupFixture implements ConnectionSetupPort, ExecutableLookupPort {
  _SetupFixture({
    this.includeUnlistedAdapter = false,
    this.includePathAdapter = false,
  });

  static const detectedPath = '/Users/host/bin/ncm-cli';
  final bool includeUnlistedAdapter;
  final bool includePathAdapter;
  final discardedDrafts = <String>[];
  ConnectionSetupDraft? latestDraft;
  var testCount = 0;
  var saveCount = 0;
  var failSave = false;
  var canSave = true;

  @override
  List<ConnectionAdapter> get connectionAdapters => [
    const ConnectionAdapter(
      id: 'netease-music',
      label: '网易云音乐',
      kind: ConnectionKind.cli,
      fields: [
        SetupField(key: 'appId', label: 'App ID'),
        SetupField(
          key: 'privateKey',
          label: 'Private Key',
          kind: SetupFieldKind.secret,
        ),
      ],
      autoDetectExecutable: true,
      showGenericCliFields: false,
    ),
    const ConnectionAdapter(
      id: 'cli',
      label: '自定义 CLI',
      kind: ConnectionKind.cli,
    ),
    const ConnectionAdapter(
      id: 'mcp-stdio',
      label: 'stdio MCP',
      kind: ConnectionKind.mcpStdio,
    ),
    const ConnectionAdapter(
      id: 'mcp-http',
      label: 'HTTP MCP',
      kind: ConnectionKind.mcpHttp,
    ),
    if (includeUnlistedAdapter)
      const ConnectionAdapter(
        id: 'unsupported-adapter',
        label: 'Unsupported',
        kind: ConnectionKind.cli,
      ),
    if (includePathAdapter)
      const ConnectionAdapter(
        id: 'path-cli',
        label: 'Path CLI',
        kind: ConnectionKind.cli,
        fields: [
          SetupField(
            key: 'workingDirectory',
            label: 'Working directory',
            kind: SetupFieldKind.file,
          ),
        ],
      ),
  ];

  @override
  Future<String?> detectExecutable(String adapterId) async =>
      adapterId == 'netease-music' ? detectedPath : null;

  @override
  Future<String?> findExecutable(String name) async =>
      name == 'custom-cli' ? '/Users/host/bin/custom-cli' : null;

  @override
  Future<ConnectionSetupReport> testConnectionSetup(
    ConnectionSetupDraft draft,
  ) async {
    testCount++;
    latestDraft = draft;
    return ConnectionSetupReport(
      draftId: 'runtime-draft-1',
      canSave: canSave,
      checks: const [
        SetupCheck('程序检查', SetupCheckStatus.passed, '/Users/host/bin/ncm-cli'),
        SetupCheck('账号登录', SetupCheckStatus.actionRequired, 'secret output'),
      ],
    );
  }

  @override
  Future<Connection> saveConnectionSetup(String draftId) async {
    saveCount++;
    if (failSave) throw StateError('uncertain save outcome');
    final draft = latestDraft!;
    return Connection(
      id: const ConnectionId('connection-1'),
      kind: draft.spec.kind,
      label: draft.spec.label,
      location: '/Users/host/bin/ncm-cli',
    );
  }

  @override
  Future<void> discardConnectionSetup(String draftId) async {
    discardedDrafts.add(draftId);
  }
}
