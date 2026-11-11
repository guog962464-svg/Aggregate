import 'dart:io';

import 'package:aggregate/platform/android/android_runtime_port.dart';
import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('A2 Android runtime advertises only HTTP MCP', () async {
    final directory = await Directory.systemTemp.createTemp(
      'aggregate-android-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final runtime = await AndroidRuntimePort.open(dataDirectory: directory);
    addTearDown(runtime.dispose);
    expect(runtime.isPreview, isFalse);
    expect(runtime.features.connectionKinds, {ConnectionKind.mcpHttp});
    expect(runtime.connectionAdapters.map((item) => item.id), ['mcp-http']);
    expect(runtime.features.terminal, isFalse);
    expect(runtime.features.localFilePreview, isFalse);
    expect(runtime.features.localFileReveal, isFalse);
    expect(await runtime.listConnections(), isEmpty);
    expect(await runtime.searchCapabilities(const SearchQuery('')), isEmpty);
    expect(await runtime.listRecentRuns(), isEmpty);
    await expectLater(
      runtime.addConnection(
        const ConnectionSpec(
          kind: ConnectionKind.cli,
          label: 'Unavailable',
          executable: '/bin/sh',
        ),
      ),
      throwsStateError,
    );
    await expectLater(
      runtime.readActionManifestFile('/Users/guo/Desktop/actions.json'),
      throwsUnsupportedError,
    );
    await expectLater(
      runtime.previewLocalFile('/Users/guo/Desktop/output.txt'),
      throwsUnsupportedError,
    );
    await expectLater(
      runtime.revealLocalFile('/Users/guo/Desktop/output.txt'),
      throwsUnsupportedError,
    );
  });
}
