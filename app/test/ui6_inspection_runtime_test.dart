import 'package:aggregate/preview/ui6_inspection_runtime.dart';
import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'success result fixture matches the 17 item inspection catalog',
    () async {
      final runtime = Ui6InspectionRuntime();
      final capabilities = await runtime.searchCapabilities(
        const SearchQuery(''),
      );

      expect(capabilities, hasLength(17));
      final status = capabilities.singleWhere(
        (capability) => capability.id.name == 'status',
      );
      final run = await runtime.invoke(status.id, const {});
      final result = await runtime
          .watchRun(run.id)
          .firstWhere((event) => event.state == RunState.succeeded);

      expect(result.blocks, hasLength(1));
      expect(result.blocks.single.kind, ResultKind.text);
      expect(result.blocks.single.value, '预览结果：工作区干净');
    },
  );

  test('idle inspection fixture can omit music playback state', () async {
    final runtime = Ui6InspectionRuntime(includeMusicPlaybackState: false);
    final capabilities = await runtime.searchCapabilities(
      const SearchQuery(''),
    );

    expect(
      capabilities.any((item) => item.presentation == 'music.state'),
      isFalse,
    );
    expect(
      capabilities.any((item) => item.presentation == 'music.search'),
      isTrue,
    );
  });

  test(
    'v8.0 design fixture contains only its 12 user-facing sample actions',
    () async {
      final runtime = Ui6InspectionRuntime(
        includeInspectionCapabilities: false,
      );
      final capabilities = await runtime.searchCapabilities(
        const SearchQuery(''),
      );

      expect(capabilities, hasLength(12));
      expect(
        capabilities.map((item) => item.id.name),
        isNot(contains('inspect-terminal')),
      );
      expect(
        capabilities.map((item) => item.id.name),
        isNot(contains('write-sample')),
      );
    },
  );

  test(
    'v8.2 connection fixtures isolate Git and MCP while retaining music',
    () async {
      final gitRuntime = Ui6InspectionRuntime(
        capabilityScope: Ui6InspectionCapabilityScope.git,
        includeInspectionCapabilities: false,
      );
      final gitCapabilities = await gitRuntime.searchCapabilities(
        const SearchQuery(''),
      );
      expect(
        gitCapabilities
            .where(
              (item) =>
                  item.id.connection == const ConnectionId('ui6-review-git'),
            )
            .map((item) => item.id.name),
        ['status'],
      );
      expect(
        gitCapabilities.any((item) => item.presentation == 'music.state'),
        isTrue,
      );
      expect((await gitRuntime.listConnections()).map((item) => item.label), [
        '示例网易云音乐',
        '示例 Git CLI',
        '示例 MCP',
      ]);

      final mcpRuntime = Ui6InspectionRuntime(
        capabilityScope: Ui6InspectionCapabilityScope.mcp,
        includeInspectionCapabilities: false,
      );
      final mcpCapabilities = await mcpRuntime.searchCapabilities(
        const SearchQuery(''),
      );
      expect(
        mcpCapabilities
            .where(
              (item) =>
                  item.id.connection == const ConnectionId('ui6-review-mcp'),
            )
            .map((item) => item.id.name),
        unorderedEquals(['add', 'readme', 'summary']),
      );
      expect(
        mcpCapabilities.any((item) => item.presentation == 'music.state'),
        isTrue,
      );
      final readme = mcpCapabilities.singleWhere(
        (item) => item.id.name == 'readme',
      );
      expect(readme.title, '读取项目说明');
      expect(readme.description, '项目中的 README 文本');
    },
  );

  test('inspection catalog order matches the result design fixture', () async {
    final runtime = Ui6InspectionRuntime();
    final capabilities = await runtime.searchCapabilities(
      const SearchQuery(''),
    );

    expect(capabilities.map((capability) => capability.title), [
      '上一首',
      '下一首',
      '两个整数相加',
      '停止播放',
      '刷新播放状态',
      '加入播放队列',
      '打开预览终端',
      '搜索歌曲',
      '播放歌曲',
      '暂停播放',
      '查看 Git 状态',
      '演示写入权限确认',
      '演示恢复状态',
      '生成摘要提示',
      '继续播放',
      '编辑 JSON 参数',
      '读取项目说明',
    ]);
  });

  test(
    'activity fixture labels and timestamps match design board 04',
    () async {
      final runtime = Ui6InspectionRuntime();
      await runtime.seedActivityForInspection(includeFilterStates: true);
      final runs = await runtime.listRecentRuns();
      final presentation = runtime as RuntimePresentationPort;

      expect(runs.map((run) => run.latest.state), [
        RunState.timedOut,
        RunState.outcomeUnknown,
        RunState.cancelled,
        RunState.failed,
        RunState.succeeded,
      ]);
      expect(
        runs.map((run) => run.latest.occurredAt),
        everyElement(DateTime(2026, 11, 21, 12)),
      );
      expect(
        runs.map((run) => presentation.capabilityDisplayName(run.capability)),
        ['查看 Git 状态', '查看 Git 状态', '查看 Git 状态', '两个整数相加', '查看 Git 状态'],
      );
      expect(
        runs.map(
          (run) =>
              presentation.connectionDisplayName(run.capability.connection),
        ),
        ['示例 Git CLI', '示例 Git CLI', '示例 Git CLI', '示例 MCP', '示例 Git CLI'],
      );
    },
  );

  test(
    'inspection account login stays pending until the local stub closes',
    () async {
      final runtime = Ui6InspectionRuntime();
      const musicConnection = ConnectionId('ui6-review-music');
      final session = await runtime.beginAccountLogin(musicConnection);
      final waiting = runtime.waitAccountLogin(session);
      var completed = false;
      waiting.then((_) => completed = true);
      await Future<void>.delayed(Duration.zero);

      expect(completed, isFalse);
      await runtime.closeTerminal(session);
      expect(await waiting, 130);
    },
  );

  test(
    'terminal design fixture uses carriage returns between output rows',
    () async {
      final runtime = Ui6InspectionRuntime();
      final session = await runtime.openTerminal(
        const CliCommand(ConnectionId('ui6-review-git'), [
          'git',
          'status',
          '--short',
        ]),
      );
      final output = await runtime.watchTerminal(session).take(4).join();

      expect(
        output,
        contains(
          r'$ git status --short'
          '\r\n M README.md\r\n?? draft.md\r\n\r\n',
        ),
      );
      expect(output.replaceAll('\r\n', ''), isNot(contains('\n')));
      await runtime.closeTerminal(session);
    },
  );

  test('unknown result fixture emits one local terminal state', () async {
    final runtime = Ui6InspectionRuntime(resultUnknownFixture: true);
    final capabilities = await runtime.searchCapabilities(
      const SearchQuery(''),
    );

    expect(capabilities, hasLength(1));
    expect(capabilities.single.id.name, 'inspection-outcome-unknown');
    final run = await runtime.invoke(capabilities.single.id, const {});
    final result = await runtime.watchRun(run.id).single;
    final recentRuns = await runtime.listRecentRuns();

    expect(result.state, RunState.outcomeUnknown);
    expect(result.failure?.code, RuntimeErrorCode.outcomeUnknown);
    expect(recentRuns, hasLength(1));
    expect(recentRuns.single.latest.state, RunState.outcomeUnknown);
  });
}
