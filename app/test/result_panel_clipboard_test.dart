import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:aggregate/widgets/glass/glass_design_tokens.dart';
import 'package:aggregate/widgets/glass/glass_motion.dart';
import 'package:aggregate/widgets/result_panel.dart';

const _macOS = TargetPlatformVariant({TargetPlatform.macOS});

void main() {
  testWidgets(
    'result copy formats blocks through an intercepted platform channel',
    (tester) async {
      final semantics = tester.ensureSemantics();
      String? clipboardPayload;
      var clipboardWrites = 0;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          final arguments = call.arguments as Map<Object?, Object?>;
          clipboardPayload = arguments['text'] as String?;
          clipboardWrites++;
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );

      final tokens = GlassDesignTokens.forBrightness(Brightness.light);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: Brightness.light)
              .copyWith(extensions: [tokens]),
          builder: (context, child) => GlassMotionScope(child: child!),
          home: const Scaffold(
            body: ResultPanel(
              state: RunState.succeeded,
              blocks: [
                ResultBlock(ResultKind.text, '已完成'),
                ResultBlock(ResultKind.json, {'count': 2, 'ok': true}),
              ],
            ),
          ),
        ),
      );

      await tester.tap(find.bySemanticsLabel('复制结果'));
      await tester.pump();

      expect(clipboardWrites, 1);
      expect(clipboardPayload, '已完成\n\n{\n  "count": 2,\n  "ok": true\n}');
      expect(find.text('已复制结果'), findsOneWidget);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
    variant: _macOS,
  );
}
