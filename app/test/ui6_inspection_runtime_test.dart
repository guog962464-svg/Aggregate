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
