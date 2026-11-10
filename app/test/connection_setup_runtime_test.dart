import 'dart:convert';
import 'dart:io';

import 'package:aggregate/platform/macos/mac_runtime.dart';
import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'NCM setup isolates credentials and only saves a tested profile',
    () async {
      final root = await Directory.systemTemp.createTemp('aggregate-setup-');
      final key = File('${root.path}/fixture-key.pem');
      final generated = await Process.run('/usr/bin/openssl', [
        'genrsa',
        '-out',
        key.path,
        '2048',
      ]);
      expect(generated.exitCode, 0);
      final package = Directory('${root.path}/package');
      final dist = Directory('${package.path}/dist');
      await dist.create(recursive: true);
      final script = File('${dist.path}/index.js');
      await script.writeAsString(r'''#!/bin/sh
case "$1" in
  --version) echo '0.1.7' ;;
  --help) echo 'fake ncm-cli' ;;
  config)
    if [ "$2" = set ] && [ "$3" = appId ]; then
      printf '%s' "$4" > "$HOME/.app-id"
    elif [ "$2" = set ] && [ "$3" = privateKey ]; then
      test -f "$4" || exit 3
      printf 'accepted' > "$HOME/.key-accepted"
    else
      exit 3
    fi ;;
  login)
    if [ "$2" = '--check' ]; then
      echo '{"success":false}'
      exit 1
    fi ;;
  *) exit 0 ;;
esac
''');
      final chmod = await Process.run('/bin/chmod', ['700', script.path]);
      expect(chmod.exitCode, 0);
      await File('${package.path}/package.json').writeAsString(
        jsonEncode({
          'name': '@music163/ncm-cli',
          'bin': {'ncm-cli': 'dist/index.js'},
        }),
      );
      final executable = Link('${package.path}/ncm-cli');
      await executable.create(script.path);
      var runtime = await MacRuntime.open(
        dataDirectory: Directory('${root.path}/data'),
      );
      try {
        ConnectionSetupDraft draft() => ConnectionSetupDraft(
          adapterId: 'netease-music',
          spec: ConnectionSpec(
            kind: ConnectionKind.cli,
            label: '网易云测试',
            executable: executable.path,
          ),
          values: {
            'appId': 'fixture-app',
            'privateKey': key.readAsStringSync(),
          },
        );

        final discarded = await runtime.testConnectionSetup(draft());
        expect(discarded.canSave, isTrue);
        expect(
          discarded.checks.map((item) => item.status),
          contains(SetupCheckStatus.actionRequired),
        );
        expect(await runtime.listConnections(), isEmpty);
        final profiles = Directory('${root.path}/data/connector-profiles');
        final temporary = Directory('${profiles.path}/${discarded.draftId}');
        expect(
          await File('${temporary.path}/.app-id').readAsString(),
          'fixture-app',
        );
        expect(
          await File('${temporary.path}/.setup-private-key.pem').exists(),
          isFalse,
        );
        await runtime.discardConnectionSetup(discarded.draftId);
        expect(await temporary.exists(), isFalse);

        final tested = await runtime.testConnectionSetup(draft());
        final connection = await runtime.saveConnectionSetup(tested.draftId);
        expect(connection.status, ConnectionStatus.ready);
        expect(
          await runtime.detectExecutable('netease-music'),
          executable.path,
        );
        expect(await runtime.detectExecutable('cli'), isNull);
        final saved = await File('${root.path}/data/connections.json')
            .readAsString();
        expect(saved, contains(tested.draftId));
        expect(saved, isNot(contains('fixture-app')));
        expect(saved, isNot(contains('PRIVATE KEY')));
        await runtime.dispose();
        runtime = await MacRuntime.open(
          dataDirectory: Directory('${root.path}/data'),
        );
        expect(
          (await runtime.listConnections()).single.id.value,
          connection.id.value,
        );
        expect(
          (await runtime.readAccount(connection.id))?.state,
          AccountState.signedOut,
        );
        await runtime.removeConnection(connection.id);
        expect(
          await Directory('${profiles.path}/${tested.draftId}').exists(),
          isFalse,
        );
      } finally {
        await runtime.dispose();
        await root.delete(recursive: true);
      }
    },
  );

  test('generic CLI is probed before it appears in connections', () async {
    final root = await Directory.systemTemp.createTemp('aggregate-setup-cli-');
    final runtime = await MacRuntime.open(dataDirectory: root);
    try {
      final report = await runtime.testConnectionSetup(
        const ConnectionSetupDraft(
          adapterId: 'cli',
          spec: ConnectionSpec(
            kind: ConnectionKind.cli,
            label: '打印',
            executable: '/usr/bin/printf',
          ),
        ),
      );
      expect(report.canSave, isTrue);
      expect(await runtime.listConnections(), isEmpty);
      await runtime.saveConnectionSetup(report.draftId);
      expect(await runtime.listConnections(), hasLength(1));
    } finally {
      await runtime.dispose();
      await root.delete(recursive: true);
    }
  });

  test(
    'HTTP MCP draft uses its token without persisting a failed probe',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'aggregate-setup-http-',
      );
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      String? observedAuthorization;
      final subscription = server.listen((request) async {
        observedAuthorization = request.headers.value('authorization');
        request.response.statusCode = HttpStatus.unauthorized;
        await request.response.close();
      });
      final runtime = await MacRuntime.open(dataDirectory: root);
      try {
        final report = await runtime.testConnectionSetup(
          ConnectionSetupDraft(
            adapterId: 'mcp-http',
            spec: ConnectionSpec(
              kind: ConnectionKind.mcpHttp,
              label: '测试 MCP',
              url: 'http://127.0.0.1:${server.port}/mcp',
              authToken: 'temporary-token',
            ),
          ),
        );
        expect(report.canSave, isFalse);
        expect(report.checks.last.detail, contains('认证'));
        expect(report.checks.last.detail, isNot(contains('temporary-token')));
        expect(observedAuthorization, 'Bearer temporary-token');
        expect(await runtime.listConnections(), isEmpty);
      } finally {
        await runtime.dispose();
        await subscription.cancel();
        await server.close(force: true);
        await root.delete(recursive: true);
      }
    },
  );
}
