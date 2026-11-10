import 'package:aggregate/features/connections/connection_setup_dialog.dart';
import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final class _SetupFixture implements ConnectionSetupPort {
  _SetupFixture({this.withField = false});
  final bool withField;
  int tests = 0;
  final discarded = <String>[];
  ConnectionSetupDraft? latest;

  @override
  List<ConnectionAdapter> get connectionAdapters => withField
      ? const [
          ConnectionAdapter(
            id: 'special',
            label: '专用适配器',
            kind: ConnectionKind.cli,
            defaultLabel: '专用工具',
            showGenericCliFields: false,
            fields: [
              SetupField(
                key: 'secret',
                label: '令牌',
                kind: SetupFieldKind.secret,
              ),
            ],
          ),
        ]
      : const [
          ConnectionAdapter(
            id: 'cli',
            label: '自定义 CLI',
            kind: ConnectionKind.cli,
          ),
        ];

  @override
  Future<ConnectionSetupReport> testConnectionSetup(
    ConnectionSetupDraft draft,
  ) async {
    tests++;
    latest = draft;
    return ConnectionSetupReport(
      draftId: 'draft-$tests',
      checks: const [SetupCheck('连通性', SetupCheckStatus.passed, '程序可启动。')],
      canSave: true,
    );
  }

  @override
  Future<Connection> saveConnectionSetup(String draftId) async =>
      const Connection(
        id: ConnectionId('saved'),
        kind: ConnectionKind.cli,
        label: '测试工具',
        location: '/usr/bin/printf',
        status: ConnectionStatus.ready,
      );

  @override
  Future<void> discardConnectionSetup(String draftId) async {
    discarded.add(draftId);
  }
}

void main() {
  testWidgets('save requires a fresh successful connection test', (
    tester,
  ) async {
    final setup = _SetupFixture();
    Connection? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                saved = await showDialog<Connection>(
                  context: context,
                  builder: (_) => ConnectionSetupDialog(setup: setup),
                );
              },
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    FilledButton saveButton() =>
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, '保存连接'));
    expect(saveButton().onPressed, isNull);
    await tester.enterText(find.widgetWithText(TextField, '名称'), '测试工具');
    await tester.enterText(
      find.widgetWithText(TextField, '程序绝对路径'),
      '/usr/bin/printf',
    );
    await tester.tap(find.text('测试连接'));
    await tester.pumpAndSettle();
    expect(saveButton().onPressed, isNotNull);
    await tester.enterText(find.widgetWithText(TextField, '名称'), '测试工具 2');
    await tester.pump();
    expect(saveButton().onPressed, isNull);
    expect(setup.discarded, contains('draft-1'));
    await tester.tap(find.text('测试连接'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存连接'));
    await tester.pumpAndSettle();
    expect(saved?.id.value, 'saved');
  });

  testWidgets('adapter metadata renders and clears a secret field', (
    tester,
  ) async {
    final setup = _SetupFixture(withField: true);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<Connection>(
                context: context,
                builder: (_) => ConnectionSetupDialog(setup: setup),
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.text('专用工具'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, '程序绝对路径'),
      '/usr/bin/printf',
    );
    final secret = find.widgetWithText(TextField, '令牌');
    expect(tester.widget<TextField>(secret).obscureText, isTrue);
    await tester.enterText(secret, 'fixture-secret');
    await tester.tap(find.text('测试连接'));
    await tester.pumpAndSettle();
    expect(setup.latest?.values['secret'], 'fixture-secret');
    expect(tester.widget<TextField>(secret).controller?.text, isEmpty);
  });
}
