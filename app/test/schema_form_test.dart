import 'package:aggregate/features/invocation/schema_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'large schema form lazily builds fields but validates offscreen required fields',
    (tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final key = GlobalKey<SchemaFormState>();
      final properties = <String, Object?>{
        for (var index = 0; index < 90; index++)
          'field-$index': {'type': 'string', 'title': '参数 $index'},
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SchemaForm(
              key: key,
              schema: {
                'properties': properties,
                'required': ['field-89'],
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      const lastField = Key('field-field-89');
      expect(find.byKey(lastField), findsNothing);
      expect(key.currentState!.validate(), isFalse);
      await tester.pumpAndSettle();
      expect(find.text('请检查标红字段后重试。'), findsOneWidget);
      expect(find.textContaining('参数 89'), findsOneWidget);

      final scrollable = find
          .descendant(
            of: find.byKey(const Key('schema-field-list')),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.byKey(lastField),
        240,
        scrollable: scrollable,
      );
      expect(find.byKey(lastField), findsOneWidget);
      expect(key.currentState!.validate(), isFalse);
      await tester.pumpAndSettle();
      expect(find.text('请输入参数 89 *'), findsOneWidget);

      await tester.enterText(find.byKey(lastField), 'accepted');
      expect(key.currentState!.validate(), isTrue);
      expect(key.currentState!.arguments(), {'field-89': 'accepted'});
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('JSON parameters format and expand for mobile editing', (
    tester,
  ) async {
    final key = GlobalKey<SchemaFormState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SchemaForm(
              key: key,
              schema: const {
                'properties': {
                  'payload': {'type': 'object', 'title': '复杂参数'},
                },
                'required': ['payload'],
              },
            ),
          ),
        ),
      ),
    );

    final field = find.byKey(const Key('field-payload'));
    await tester.enterText(field, '{"query":"hello","options":{"limit":5}}');
    await tester.tap(find.byTooltip('格式化 复杂参数'));
    await tester.pump();
    expect(
      tester.widget<TextFormField>(field).controller!.text,
      '{\n  "query": "hello",\n  "options": {\n    "limit": 5\n  }\n}',
    );
    final textField = find.descendant(
      of: field,
      matching: find.byType(TextField),
    );
    expect(
      tester.widget<TextField>(textField).keyboardType,
      TextInputType.multiline,
    );

    await tester.tap(find.text('展开 JSON 编辑器'));
    await tester.pump();
    expect(tester.widget<TextField>(textField).maxLines, 14);
    expect(key.currentState!.validate(), isTrue);
    expect(key.currentState!.arguments(), {
      'payload': {
        'query': 'hello',
        'options': {'limit': 5},
      },
    });
  });

  testWidgets('invalid JSON stays next to its parameter', (tester) async {
    final key = GlobalKey<SchemaFormState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SchemaForm(
              key: key,
              schema: const {
                'properties': {
                  'payload': {'type': 'array', 'title': '列表'},
                },
                'required': ['payload'],
              },
            ),
          ),
        ),
      ),
    );
    await tester.enterText(find.byKey(const Key('field-payload')), '{bad');
    expect(key.currentState!.validate(), isFalse);
    await tester.pump();
    expect(find.text('请输入有效 JSON'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
