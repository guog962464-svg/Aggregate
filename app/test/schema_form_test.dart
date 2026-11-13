import 'package:aggregate/features/invocation/schema_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
