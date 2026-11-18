import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:aggregate/platform/macos/mac_runtime.dart';
import 'package:aggregate/platform/macos/host/host_device_signature_verifier.dart';
import 'package:aggregate/platform/macos/host/host_operation_ledger.dart';
import 'package:aggregate/platform/macos/host/host_pairing_authority.dart';
import 'package:aggregate/platform/macos/host/host_runtime_rpc_dispatcher.dart';
import 'package:aggregate/platform/macos/host/host_setup_coordinator.dart';
import 'package:aggregate/platform/macos/host/host_setup_rpc_dispatcher.dart';
import 'package:aggregate/platform/macos/host/host_tls_identity.dart';
import 'package:aggregate/platform/macos/host/host_wss_transport.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mcp_dart/mcp_dart.dart' as mcp;

import 'fixtures/android_host_mcp_fixture.dart';
import 'fixtures/android_host_tcp_tunnel.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'serves an isolated WSS setup fixture for a real Android Keystore client',
    (_) async {
      const fixtureDirectoryPath = String.fromEnvironment(
        'aggregateHostSetupFixtureDirectory',
      );
      expect(fixtureDirectoryPath, isNotEmpty);
      final fixtureDirectory = Directory(fixtureDirectoryPath);
      await fixtureDirectory.create(recursive: true);

      final provider = _FixtureIdentityProvider(
        certificatePem: await File('test/fixtures/host_test_cert.pem')
            .readAsString(),
        privateKeyPem: await File('test/fixtures/host_test_key.pem')
            .readAsString(),
      );
      final identity = await HostTlsIdentityStore(provider: provider)
          .loadOrCreate();
      final fixtureHome = Platform.environment['HOME']!;
      expect(fixtureHome.startsWith(fixtureDirectory.path), isTrue);
      final executable = File('$fixtureHome/.local/bin/ncm-cli');
      expect(await executable.exists(), isTrue);
      final runtimeDirectory = Directory('${fixtureDirectory.path}/runtime');
      final runtime = await MacRuntime.open(dataDirectory: runtimeDirectory);
      final httpMcpServer = mcp.StreamableMcpServer(
        serverFactory: (_) {
          return createAndroidHostMcpFixture(
            name: 'aggregate-http-fixture',
            resourceUri: 'aggregate://http-fixture/resource',
            resourceText: 'http-fixture-resource',
          );
        },
        host: '127.0.0.1',
        port: 0,
        path: '/mcp',
        allowedHosts: const {'127.0.0.1'},
      );
      final androidResultFile = File(
        '${fixtureDirectory.path}/android-result.txt',
      );
      final cliManifestFile = File(
        '${fixtureDirectory.path}/cli-manifest.json',
      );
      await cliManifestFile.writeAsString(
        jsonEncode({
          'schemaVersion': 1,
          'id': 'android-host-cli-fixture',
          'displayName': 'Android Host CLI fixture',
          'platforms': ['macos'],
          'executable': '/usr/bin/printf',
          'actions': [
            {
              'id': 'echo',
              'title': 'Fixture CLI echo',
              'argv': ['plain-cli:%s\\n', '{{value}}'],
              'inputSchema': {
                'type': 'object',
                'properties': {
                  'value': {'type': 'string'},
                },
                'required': ['value'],
                'additionalProperties': false,
              },
              'output': 'text',
              'permission': 'externalWrite',
              'timeoutMs': 30000,
            },
          ],
        }),
        flush: true,
      );
      final coordinator = HostSetupCoordinator(
        setup: runtime,
        random: Random(41),
      );
      final pairing = HostPairingAuthority(
        identity: identity,
        store: InMemoryHostPairingStore(),
        signatureVerifier: const MacHostDeviceSignatureVerifier(),
        setupCoordinator: coordinator,
        random: Random(43),
      );
      final ledger = await FileHostOperationLedger.open(
        File('${fixtureDirectory.path}/operations.json'),
      );
      final setupDispatcher = HostSetupRpcDispatcher(
        setup: coordinator,
        ledger: ledger,
        authorization: pairing,
      );
      final dispatcher = HostRuntimeRpcDispatcher(
        runtime: runtime,
        accounts: runtime,
        setupDispatcher: setupDispatcher,
        ledger: ledger,
        authorization: pairing,
      );
      final transport = HostWssTransport(
        loadServices: () async => HostWssServices(
          identity: identity,
          pairing: pairing,
          dispatcher: dispatcher,
        ),
        bindAddressProvider: const _LoopbackAddressProvider(),
        bonjourPublisher: const NoopHostBonjourPublisher(),
        requestedPort: 0,
      );

      var approving = false;
      Object? approvalError;
      Timer? approvalTimer;
      AndroidHostTcpTunnelProxy? tcpTunnelProxy;
      HttpServer? dropControlServer;
      late Connection ncmFixtureConnection;
      late Connection cliFixtureConnection;
      late Connection httpMcpConnection;
      late Connection stdioMcpConnection;

      try {
        await httpMcpServer.start();
        ncmFixtureConnection = await runtime.addConnection(
          ConnectionSpec(
            kind: ConnectionKind.cli,
            label: 'Android isolated Netease CLI fixture',
            executable: executable.path,
          ),
        );
        cliFixtureConnection = await runtime.addConnection(
          ConnectionSpec(
            kind: ConnectionKind.cli,
            label: 'Android isolated plain CLI fixture',
            executable: '/usr/bin/printf',
            manifestPath: cliManifestFile.path,
          ),
        );
        httpMcpConnection = await runtime.addConnection(
          ConnectionSpec(
            kind: ConnectionKind.mcpHttp,
            label: 'Android isolated HTTP MCP fixture',
            url: 'http://127.0.0.1:${httpMcpServer.boundPort}/mcp',
          ),
        );
        stdioMcpConnection = await runtime.addConnection(
          ConnectionSpec(
            kind: ConnectionKind.mcpStdio,
            label: 'Android isolated stdio MCP fixture',
            executable: Platform.environment['AGGREGATE_DART_EXECUTABLE']!,
            arguments: [
              '${Directory.current.path}/integration_test/fixtures/android_host_stdio_mcp_server.dart',
            ],
            workingDirectory: Directory.current.path,
          ),
        );
        expect(
          httpMcpConnection.status,
          ConnectionStatus.ready,
          reason:
              httpMcpConnection.diagnostic ?? 'HTTP MCP fixture is unavailable',
        );
        expect(
          stdioMcpConnection.status,
          ConnectionStatus.ready,
          reason:
              stdioMcpConnection.diagnostic ??
              'stdio MCP fixture is unavailable',
        );
        await transport.start();
        approvalTimer = Timer.periodic(const Duration(milliseconds: 100), (
          _,
        ) async {
          if (approving) return;
          approving = true;
          try {
            final requests = await transport.pendingRequests();
            for (final request in requests) {
              final mcpToolsPairing =
                  request.displayName == 'Android MCP integration fixture';
              await transport.approvePending(
                request.deviceId,
                scopes: mcpToolsPairing
                    ? const {HostGrantScope.readConnections}
                    : const {
                        HostGrantScope.connectionSetup,
                        HostGrantScope.readConnections,
                        HostGrantScope.account,
                        HostGrantScope.terminal,
                      },
                connectionPermissions: mcpToolsPairing
                    ? {
                        ncmFixtureConnection.id.value: const {
                          PermissionLevel.read,
                        },
                        cliFixtureConnection.id.value: const {
                          PermissionLevel.read,
                          PermissionLevel.externalWrite,
                        },
                        httpMcpConnection.id.value: const {
                          PermissionLevel.read,
                          PermissionLevel.externalWrite,
                        },
                        stdioMcpConnection.id.value: const {
                          PermissionLevel.read,
                          PermissionLevel.externalWrite,
                        },
                      }
                    : const {},
              );
            }
          } on Object catch (error) {
            approvalError = error;
          } finally {
            approving = false;
          }
        });
        final issuedInvitation = await transport.createInvitation();
        final issuedMcpInvitation = await transport.createInvitation();
        final issuedPayload =
            jsonDecode(issuedInvitation.qrPayload) as Map<String, Object?>;
        final issuedEndpoints = issuedPayload['endpoints']! as List<Object?>;
        final hostPort = Uri.parse(
          (issuedEndpoints.single! as Map<String, Object?>)['uri']! as String,
        ).port;
        final proxy = await AndroidHostTcpTunnelProxy.start(
          targetPort: hostPort,
        );
        tcpTunnelProxy = proxy;
        final controlServer = await HttpServer.bind(
          InternetAddress.loopbackIPv4,
          0,
        );
        dropControlServer = controlServer;
        controlServer.listen((request) async {
          if (request.method != 'POST' ||
              request.uri.path != '/drop-active-tunnels') {
            request.response.statusCode = HttpStatus.notFound;
            await request.response.close();
            return;
          }
          try {
            await proxy.dropActiveTunnels();
            request.response.statusCode = HttpStatus.noContent;
          } on Object catch (error) {
            request.response
              ..statusCode = HttpStatus.internalServerError
              ..write(error.runtimeType);
          }
          await request.response.close();
        });
        await File('${fixtureDirectory.path}/drop-control-port.txt')
            .writeAsString('${controlServer.port}', flush: true);
        final invitationPayload = _routeInvitationThroughProxy(
          issuedInvitation.qrPayload,
          proxy.port,
        );
        final mcpInvitationPayload = _routeInvitationThroughProxy(
          issuedMcpInvitation.qrPayload,
          proxy.port,
        );
        await File('${fixtureDirectory.path}/invitation.json')
            .writeAsString(invitationPayload, flush: true);
        await File('${fixtureDirectory.path}/mcp-invitation.json')
            .writeAsString(mcpInvitationPayload, flush: true);
        final androidResult = await _waitForAndroidResult(androidResultFile);
        expect(androidResult, 'passed', reason: 'Android setup flow failed');
        expect(approvalError, isNull);
        final terminalPidFile = File('$fixtureHome/host-terminal-pid');
        await _waitForFile(terminalPidFile);
        final terminalPid = int.parse(await terminalPidFile.readAsString());
        await _waitForProcessExit(terminalPid);
        final savedConnections = File(
          '${runtimeDirectory.path}/connections.json',
        );
        final savedJson = await savedConnections.readAsString();
        final fixtureSecret = (await File(
          '${fixtureDirectory.path}/setup-private-key.pem',
        ).readAsString()).trim();
        expect(savedJson, isNot(contains(fixtureSecret)));
        final root = jsonDecode(savedJson) as Map<String, Object?>;
        final connections = root['connections']! as List;
        expect(connections, hasLength(5));
        final savedSpec = (connections
            .map((item) => (item as Map<String, Object?>)['spec']!)
            .cast<Map<String, Object?>>()
            .singleWhere(
              (spec) => spec['label'] == 'Android isolated physical fixture',
            ));
        expect(savedSpec['label'], 'Android isolated physical fixture');
        expect(savedSpec['executable'], executable.path);
        final profileId = savedSpec['profileId']! as String;
        final profile = Directory(
          '${runtimeDirectory.path}/connector-profiles/$profileId',
        );
        final storedKey = File('${profile.path}/private-key.pem');
        expect(
          await File('${profile.path}/app-id.txt').readAsString(),
          'fixture-app',
        );
        expect((await storedKey.readAsString()).trim(), fixtureSecret);
        expect((await storedKey.stat()).mode & 0x180, 0x180);
        expect(
          await File('${profile.path}/.setup-private-key.pem').exists(),
          isFalse,
        );
        expect((await profile.stat()).mode & 0x3f, 0);
        expect((await storedKey.stat()).mode & 0x3f, 0);
      } finally {
        approvalTimer?.cancel();
        await dropControlServer?.close(force: true);
        await tcpTunnelProxy?.close();
        await transport.stop();
        await runtime.dispose();
        await httpMcpServer.stop();
      }
    },
    // This test hosts services for Android and does not build or inspect a
    // widget tree; enabling semantics only creates an unused live-test handle.
    semanticsEnabled: false,
    timeout: const Timeout(Duration(minutes: 15)),
  );
}

String _routeInvitationThroughProxy(String payload, int port) {
  final invitation = jsonDecode(payload) as Map<String, Object?>;
  final endpoints = invitation['endpoints']! as List<Object?>;
  for (var index = 0; index < endpoints.length; index++) {
    final endpoint = Map<String, Object?>.from(
      endpoints[index]! as Map<String, Object?>,
    );
    endpoint['uri'] = Uri(
      scheme: 'wss',
      host: InternetAddress.loopbackIPv4.address,
      port: port,
      path: '/host',
    ).toString();
    endpoints[index] = endpoint;
  }
  return jsonEncode(invitation);
}

Future<String> _waitForAndroidResult(File resultFile) async {
  final deadline = DateTime.now().add(const Duration(minutes: 12));
  while (DateTime.now().isBefore(deadline)) {
    if (await resultFile.exists()) return resultFile.readAsString();
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  throw TimeoutException('Android fixture did not report its result');
}

Future<void> _waitForFile(File file) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (DateTime.now().isBefore(deadline)) {
    if (await file.exists()) return;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  throw TimeoutException('Host did not stop its terminal after disconnect');
}

Future<void> _waitForProcessExit(int pid) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (DateTime.now().isBefore(deadline)) {
    final result = await Process.run('/bin/kill', ['-0', '$pid']);
    if (result.exitCode != 0) return;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  throw TimeoutException('Host terminal process $pid remained alive');
}

final class _LoopbackAddressProvider implements HostWssBindAddressProvider {
  const _LoopbackAddressProvider();

  @override
  Future<List<HostWssBindTarget>> addresses() async => [
    HostWssBindTarget(address: InternetAddress.loopbackIPv4, interfaceIndex: 1),
  ];
}

final class _FixtureIdentityProvider implements HostTlsIdentityProvider {
  const _FixtureIdentityProvider({
    required this.certificatePem,
    required this.privateKeyPem,
  });

  final String certificatePem;
  final String privateKeyPem;

  @override
  Future<HostTlsIdentityMaterial> loadOrCreate() async =>
      HostTlsIdentityMaterial(
        hostId: 'host-0123456789abcdef0123456789abcdef',
        certificatePem: certificatePem,
        privateKeyPem: privateKeyPem,
      );

  @override
  Future<HostTlsIdentityMaterial> rotate() => loadOrCreate();
}
