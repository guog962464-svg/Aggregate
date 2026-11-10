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
      expect(current?.nickname, isNull);
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

  test('missing CLI search command gives an actionable failure', () async {
    final fixture = await NeteaseAccountFixture.create();
    try {
      final capability = (await fixture.runtime.searchCapabilities(
        const SearchQuery(''),
      )).firstWhere((item) => item.presentation == 'music.search');
      final handle = await fixture.runtime.invoke(capability.id, {
        'keyword': '测试',
      }, permissionGranted: true);
      final event = await fixture.runtime
          .watchRun(handle.id)
          .firstWhere((item) => item.state == RunState.failed)
          .timeout(const Duration(seconds: 5));
      expect(event.failure?.code, RuntimeErrorCode.connectionFailed);
      expect(event.failure?.message, contains('未加载搜索命令'));
      expect(event.failure?.message, contains('开放平台应用的接口权限'));
      expect(event.failure?.message, contains('当前账号能否使用该应用'));
      expect(
        event.blocks.map((block) => '${block.value}').join(),
        isNot(contains("unknown command 'search'")),
      );
    } finally {
      await fixture.dispose();
    }
  });
}
