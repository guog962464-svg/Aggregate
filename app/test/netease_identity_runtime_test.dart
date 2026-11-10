import 'dart:io';

import 'package:aggregate/platform/macos/mac_runtime.dart';
import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('unverified namesake stays a generic CLI', () async {
    final directory = await Directory.systemTemp.createTemp(
      'aggregate-ncm-fake-',
    );
    final executable = File('${directory.path}/ncm-cli');
    await executable.writeAsString('#!/bin/sh\nexit 0\n');
    final chmod = await Process.run('/bin/chmod', ['+x', executable.path]);
    expect(chmod.exitCode, 0);
    final runtime = await MacRuntime.open(
      dataDirectory: Directory('${directory.path}/data'),
    );
    try {
      final connection = await runtime.addConnection(
        ConnectionSpec(
          kind: ConnectionKind.cli,
          label: 'Unverified namesake',
          executable: executable.path,
        ),
      );
      expect(connection.status, ConnectionStatus.ready);
      expect(connection.diagnostic, contains('无法确认'));
      expect(await runtime.loadActionManifest(connection.id), isNull);
      expect(await runtime.readAccount(connection.id), isNull);
      await expectLater(
        runtime.logoutAccount(connection.id, confirmed: true),
        throwsStateError,
      );
      final capabilities = await runtime.searchCapabilities(
        const SearchQuery(''),
      );
      expect(capabilities, hasLength(1));
      expect(capabilities.single.id.kind, CapabilityKind.cliCommand);
    } finally {
      await runtime.dispose();
      await directory.delete(recursive: true);
    }
  });
}
