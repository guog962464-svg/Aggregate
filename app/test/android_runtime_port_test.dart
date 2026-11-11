import 'package:aggregate/platform/android/android_runtime_port.dart';
import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('A1 Android shell advertises only implemented behavior', () async {
    final runtime = AndroidRuntimePort();
    expect(runtime.isPreview, isFalse);
    expect(runtime.features.connectionKinds, isEmpty);
    expect(runtime.features.terminal, isFalse);
    expect(await runtime.listConnections(), isEmpty);
    expect(await runtime.searchCapabilities(const SearchQuery('')), isEmpty);
    expect(await runtime.listRecentRuns(), isEmpty);
    await expectLater(
      runtime.addConnection(
        const ConnectionSpec(
          kind: ConnectionKind.mcpHttp,
          label: 'Unavailable',
          url: 'https://example.invalid/mcp',
        ),
      ),
      throwsUnsupportedError,
    );
  });
}
