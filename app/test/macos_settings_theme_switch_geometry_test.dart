import 'package:aggregate/app/theme.dart';
import 'package:aggregate/features/settings/settings_page.dart';
import 'package:aggregate/widgets/glass/glass_motion.dart';
import 'package:aggregate/widgets/glass/glass_scene.dart';
import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'macOS settings switch uses reference geometry in wide and compact windows',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final previousPlatform = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      tester.view.devicePixelRatio = 2;

      try {
        for (final logicalSize in [
          const Size(1360, 900),
          const Size(800, 632),
        ]) {
          tester.view.physicalSize = logicalSize * 2;
          await tester.pumpWidget(
            MaterialApp(
              theme: AggregateTheme.forPlatform(
                AggregateTheme.dark,
                TargetPlatform.macOS,
              ),
              home: GlassScene(
                child: GlassMotionScope(
                  child: Scaffold(
                    backgroundColor: Colors.transparent,
                    body: SettingsPage(
                      preferences: const UserPreferences(
                        appearance: AppearancePreference.dark,
                      ),
                      onPreferencesChanged: (_) {},
                      onClearActivity: () async {},
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pump();

          final switchSize = tester.getSize(find.bySemanticsLabel('外观主题'));
          expect(switchSize.width, 480, reason: 'window=$logicalSize');
          expect(switchSize.height, 224, reason: 'window=$logicalSize');
          expect(tester.takeException(), isNull, reason: 'window=$logicalSize');
        }
      } finally {
        semantics.dispose();
        debugDefaultTargetPlatformOverride = previousPlatform;
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      }
    },
  );
}
