import 'package:flutter/material.dart';

import '../../features/settings/glass_theme_switch.dart';
import 'glass_design_tokens.dart';

/// Standalone native preview for comparing the original switch with the
/// target heights of the upcoming glass buttons.
class GlassMaterialFixturePage extends StatelessWidget {
  const GlassMaterialFixturePage({
    super.key,
    required this.light,
    required this.onLightChanged,
  });

  final bool light;
  final ValueChanged<bool> onLightChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GlassDesignTokens>()!;
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(32, 16, 32, 12),
              sliver: SliverToBoxAdapter(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '玻璃材质样本',
                            style: textTheme.headlineSmall?.copyWith(
                              color: tokens.text,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            '原主题开关与新按钮目标高度 · 可拖动切换明暗',
                            style: textTheme.bodyMedium?.copyWith(
                              color: tokens.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      'UI-1 / FIXTURE',
                      style: textTheme.labelMedium?.copyWith(
                        color: tokens.muted,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              sliver: SliverToBoxAdapter(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(
                        color: tokens.line.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                  padding: const EdgeInsets.only(top: 18),
                  child: Text(
                    '原主题控件',
                    style: textTheme.titleMedium?.copyWith(
                      color: tokens.text,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(32, 0, 32, 10),
              sliver: SliverToBoxAdapter(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 320),
                    child: GlassThemeSwitch(
                      light: light,
                      onChanged: onLightChanged,
                    ),
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(32, 0, 32, 16),
              sliver: SliverToBoxAdapter(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(
                        color: tokens.line.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                  padding: const EdgeInsets.only(top: 14),
                  child: Text(
                    '新按钮目标高度',
                    style: textTheme.titleMedium?.copyWith(
                      color: tokens.text,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(32, 0, 32, 12),
              sliver: SliverToBoxAdapter(
                child: Wrap(
                  spacing: 20,
                  runSpacing: 20,
                  crossAxisAlignment: WrapCrossAlignment.end,
                  alignment: WrapAlignment.spaceBetween,
                  children: [
                    for (final sample in const [
                      (label: '主按钮', height: GlassDesignTokens.primaryHeight),
                      (
                        label: '次级按钮',
                        height: GlassDesignTokens.secondaryHeight,
                      ),
                      (
                        label: '放大参照',
                        height: GlassDesignTokens.referenceHeight,
                      ),
                    ])
                      _GlassHeightSample(
                        label: sample.label,
                        height: sample.height,
                        tokens: tokens,
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GlassHeightSample extends StatelessWidget {
  const _GlassHeightSample({
    required this.label,
    required this.height,
    required this.tokens,
  });

  final String label;
  final double height;
  final GlassDesignTokens tokens;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return SizedBox(
      width: 180,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [tokens.glassTop, tokens.glassBottom],
              ),
              border: Border.all(color: tokens.highlight, width: 1),
              boxShadow: [
                BoxShadow(
                  color: tokens.shadow,
                  blurRadius: 18,
                  offset: const Offset(0, 7),
                ),
                BoxShadow(
                  color: tokens.highlight.withValues(alpha: 0.22),
                  blurRadius: 2,
                  offset: const Offset(0, 1),
                  spreadRadius: -1,
                ),
              ],
            ),
            child: SizedBox(
              width: 180,
              height: height,
              child: Center(
                child: Text(
                  '${height.round()} px',
                  style: textTheme.labelMedium?.copyWith(
                    color: tokens.muted,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 9),
          Text(label, style: textTheme.bodySmall?.copyWith(color: tokens.text)),
        ],
      ),
    );
  }
}
