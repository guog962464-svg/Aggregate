import 'package:aggregate/widgets/page_frame.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('PageFrame builds long content as it scrolls into view', (
    tester,
  ) async {
    final buildCounts = List<int>.filled(100, 0);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PageFrame(
            title: '长列表',
            lazyChildren: true,
            children: [
              for (var index = 0; index < buildCounts.length; index++)
                Builder(
                  builder: (context) {
                    buildCounts[index]++;
                    return SizedBox(height: 96, child: Text('样本项目 $index'));
                  },
                ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final initiallyBuilt = buildCounts.where((count) => count > 0).length;
    expect(initiallyBuilt, lessThan(30));
    final position = Scrollable.of(tester.element(find.text('样本项目 0')))
        .position;
    expect(position.maxScrollExtent, greaterThan(0));

    await tester.scrollUntilVisible(
      find.text('样本项目 99'),
      500,
      scrollable: find.byType(Scrollable).first,
    );

    expect(position.pixels, greaterThan(0));
    expect(buildCounts.last, greaterThan(0));
    expect(
      buildCounts.where((count) => count > 0).length,
      greaterThan(initiallyBuilt),
    );
    expect(tester.takeException(), isNull);
  });
}
