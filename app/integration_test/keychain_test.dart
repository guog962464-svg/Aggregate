import 'package:aggregate/platform/macos/keychain_credential_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const phase = String.fromEnvironment(
  'AGG_KEYCHAIN_PHASE',
  defaultValue: 'roundtrip',
);
const connectionId = String.fromEnvironment(
  'AGG_KEYCHAIN_TEST_ID',
  defaultValue: 'integration-roundtrip',
);
const value = 'integration-token-value';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('macOS Keychain persists and deletes MCP credentials', (
    tester,
  ) async {
    final store = const KeychainCredentialStore();
    if (phase == 'write') {
      await store.write(connectionId, value);
      expect(await store.read(connectionId), value);
      return;
    }
    if (phase == 'read') {
      expect(await store.read(connectionId), value);
      await store.delete(connectionId);
      expect(await store.read(connectionId), isNull);
      return;
    }
    await store.write(connectionId, value);
    expect(await store.read(connectionId), value);
    await store.delete(connectionId);
    expect(await store.read(connectionId), isNull);
  });
}
