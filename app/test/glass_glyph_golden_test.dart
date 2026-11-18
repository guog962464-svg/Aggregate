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

  for (final brightness in [Brightness.light, Brightness.dark]) {
    testWidgets(
      'primary run refresh and search silhouettes at 32 dp in ${brightness.name}',
      (tester) async {
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });
        tester.view.devicePixelRatio = 2;
        tester.view.physicalSize = const Size(600, 180);
        final tokens = GlassDesignTokens.forBrightness(brightness);
        const samples = [
          GlassGlyph.play,
          GlassGlyph.refresh,
          GlassGlyph.search,
        ];
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness)
                .copyWith(extensions: [tokens]),
            home: Scaffold(
              backgroundColor: tokens.surface,
              body: Center(
                child: SizedBox(
                  key: const ValueKey('primary-glyph-board'),
                  width: 300,
                  height: 90,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      for (final glyph in samples)
                        GlassGlyphMark(glyph: glyph, size: 32),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );

        await expectLater(
          find.byKey(const ValueKey('primary-glyph-board')),
          matchesGoldenFile(
            'goldens/glass_primary_glyphs_${brightness.name}.png',
          ),
        );
      },
    );
  }
}
