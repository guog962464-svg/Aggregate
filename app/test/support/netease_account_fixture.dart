import 'dart:convert';
import 'dart:io';

import 'package:aggregate/platform/macos/mac_runtime.dart';
import 'package:aggregate_contracts/aggregate_contracts.dart';

final class NeteaseAccountFixture {
  NeteaseAccountFixture._(
    this.directory,
    this.state,
    this.holdLogin,
    this.runtime,
    this.connection,
  );

  final Directory directory;
  final File state;
  final File holdLogin;
  final MacRuntime runtime;
  final Connection connection;

  static Future<NeteaseAccountFixture> create() async {
    final directory = await Directory.systemTemp.createTemp(
      'aggregate-account-runtime-',
    );
    final package = Directory('${directory.path}/package');
    final dist = Directory('${package.path}/dist');
    await dist.create(recursive: true);
    final state = File('${directory.path}/signed-in');
    final holdLogin = File('${directory.path}/hold-login');
    await state.writeAsString('yes');
    final script = File('${dist.path}/index.js');
    await script.writeAsString('''#!/bin/sh
STATE='${state.path}'
HOLD='${holdLogin.path}'
case "\$1" in
  --version) echo '0.1.7' ;;
  --help) echo 'fake ncm-cli' ;;
  login)
    if [ "\$2" = '--check' ]; then
      if [ -f "\$STATE" ]; then
        echo '{"success":true,"message":"ok"}'
      else
        echo '{"success":false,"message":"signed out"}'
        exit 1
      fi
    else
      echo 'SCAN QR'
      if [ -f "\$HOLD" ]; then sleep 30; fi
      sleep 0.1
      touch "\$STATE"
      echo 'login done'
    fi ;;
  logout) rm -f "\$STATE"; echo '{"success":true}' ;;
  *) exit 2 ;;
esac
''');
    final chmod = await Process.run('/bin/chmod', ['+x', script.path]);
    if (chmod.exitCode != 0) throw StateError('fixture chmod failed');
    await File('${package.path}/package.json').writeAsString(
      jsonEncode({
        'name': '@music163/ncm-cli',
        'bin': {'ncm-cli': 'dist/index.js'},
      }),
    );
    final executable = Link('${package.path}/ncm-cli');
    await executable.create(script.path);
    final runtime = await MacRuntime.open(
      dataDirectory: Directory('${directory.path}/data'),
    );
    final connection = await runtime.addConnection(
      ConnectionSpec(
        kind: ConnectionKind.cli,
        label: '测试网易云音乐',
        executable: executable.path,
      ),
    );
    return NeteaseAccountFixture._(
      directory,
      state,
      holdLogin,
      runtime,
      connection,
    );
  }

  Future<void> dispose() async {
    await runtime.dispose();
    await directory.delete(recursive: true);
  }
}
