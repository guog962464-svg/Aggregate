import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/support/netease_account_fixture.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('verified CLI login completes through the native PTY', (_) async {
    final fixture = await NeteaseAccountFixture.create();
    try {
      await fixture.runtime.logoutAccount(
        fixture.connection.id,
        confirmed: true,
      );
      final terminal = await fixture.runtime.beginAccountLogin(
        fixture.connection.id,
      );
      expect(await fixture.runtime.waitAccountLogin(terminal), 0);
      expect(
        (await fixture.runtime.readAccount(fixture.connection.id))?.state,
        AccountState.signedIn,
      );
      await fixture.runtime.closeTerminal(terminal);

      await fixture.runtime.logoutAccount(
        fixture.connection.id,
        confirmed: true,
      );
      await fixture.holdLogin.writeAsString('yes');
      final pending = await fixture.runtime.beginAccountLogin(
        fixture.connection.id,
      );
      final completion = fixture.runtime.waitAccountLogin(pending);
      await fixture.runtime.closeTerminal(pending);
      expect(await completion.timeout(const Duration(seconds: 5)), -1);
      expect(await fixture.state.exists(), isFalse);
    } finally {
      await fixture.dispose();
    }
  });
}
