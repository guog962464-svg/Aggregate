import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aggregate/widgets/glass/glass_design_tokens.dart';
import 'package:aggregate/widgets/glass/glass_glyph.dart';

void main() {
  for (final ratio in [1.0, 2.0]) {
    for (final brightness in [Brightness.light, Brightness.dark]) {
      final scaleName = ratio == 1 ? '1x' : '2x';
      testWidgets(
        'all glyphs stay distinct at $scaleName ${brightness.name} scale',
        (tester) async {
          addTearDown(() {
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
          });
          tester.view.devicePixelRatio = ratio;
          tester.view.physicalSize = Size(800 * ratio, 600 * ratio);
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(brightness: brightness).copyWith(
                extensions: [GlassDesignTokens.forBrightness(brightness)],
              ),
              home: Scaffold(
                backgroundColor: GlassDesignTokens.forBrightness(brightness)
                    .surface,
                body: Center(
                  child: SizedBox(
                    key: const ValueKey('glyph-board'),
                    width: 760,
                    height: 280,
                    child: Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (final glyph in GlassGlyph.values)
                          GlassGlyphMark(glyph: glyph, size: 20),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );

          await expectLater(
            find.byKey(const ValueKey('glyph-board')),
            matchesGoldenFile('goldens/glass_glyph_${brightness.name}.png'),
          );
        },
      );
    }
  }
}
