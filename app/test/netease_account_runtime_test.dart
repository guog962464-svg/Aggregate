import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/netease_account_fixture.dart';

void main() {
  test('verified CLI account reads and confirms logout', () async {
    final fixture = await NeteaseAccountFixture.create();
    try {
      expect(fixture.connection.status, ConnectionStatus.ready);
      final current = await fixture.runtime.readAccount(fixture.connection.id);
      expect(current?.state, AccountState.signedIn);
      expect(current?.nickname, '测试账号');
      expect(await fixture.runtime.listRecentRuns(), isEmpty);

      await expectLater(
        fixture.runtime.logoutAccount(fixture.connection.id, confirmed: false),
        throwsStateError,
      );
      expect(await fixture.state.exists(), isTrue);
      final signedOut = await fixture.runtime.logoutAccount(
        fixture.connection.id,
        confirmed: true,
      );
      expect(signedOut.state, AccountState.signedOut);
      expect(await fixture.state.exists(), isFalse);
      expect(await fixture.runtime.listRecentRuns(), isEmpty);
    } finally {
      await fixture.dispose();
    }
  });
}
