import 'package:flutter/material.dart';

import '../../features/settings/glass_theme_switch.dart';
import 'glass_action_button.dart';
import 'glass_design_tokens.dart';
import 'glass_glyph.dart';

/// Native motion board for reviewing UI-3 buttons without connecting
/// decorative controls to product actions.
class GlassButtonsFixturePage extends StatelessWidget {
  const GlassButtonsFixturePage({
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
    const referenceSamples = <_ReferenceGlyphSample>[
      _ReferenceGlyphSample(
        '运行',
        GlassGlyph.play,
        kind: GlassButtonKind.primary,
      ),
      _ReferenceGlyphSample('暂停', GlassGlyph.pause),
      _ReferenceGlyphSample('添加连接', GlassGlyph.plus),
      _ReferenceGlyphSample('刷新', GlassGlyph.refresh),
      _ReferenceGlyphSample('复制', GlassGlyph.copy),
      _ReferenceGlyphSample('保存', GlassGlyph.save),
      _ReferenceGlyphSample('搜索', GlassGlyph.search),
      _ReferenceGlyphSample('打开', GlassGlyph.externalLink),
      _ReferenceGlyphSample('停止', GlassGlyph.stop),
      _ReferenceGlyphSample(
        '移除',
        GlassGlyph.trash,
        kind: GlassButtonKind.danger,
      ),
      _ReferenceGlyphSample('连接', GlassGlyph.network),
      _ReferenceGlyphSample('允许访问', GlassGlyph.shield),
    ];
    final samples = <_ButtonSample>[
      _ButtonSample(
        title: '主操作',
        label: '运行',
        glyph: GlassGlyph.play,
        kind: GlassButtonKind.primary,
        size: GlassButtonSize.primary,
      ),
      _ButtonSample(
        title: '次级操作',
        label: '刷新状态',
        glyph: GlassGlyph.refresh,
        kind: GlassButtonKind.secondary,
      ),
      _ButtonSample(
        title: '动作编辑器 · 导出',
        label: '导出',
        glyph: GlassGlyph.save,
        kind: GlassButtonKind.navigation,
        size: GlassButtonSize.secondary,
      ),
      _ButtonSample(
        title: '图标按钮',
        label: '搜索',
        glyph: GlassGlyph.search,
        kind: GlassButtonKind.icon,
        size: GlassButtonSize.icon,
        iconOnly: true,
      ),
      _ButtonSample(
        title: '播控 · 上一首',
        label: '上一首',
        glyph: GlassGlyph.previous,
        kind: GlassButtonKind.playback,
        size: GlassButtonSize.playback,
      ),
      _ButtonSample(
        title: '播控 · 播放',
        label: '播放',
        glyph: GlassGlyph.play,
        kind: GlassButtonKind.playback,
        size: GlassButtonSize.playback,
      ),
      _ButtonSample(
        title: '播控 · 下一首',
        label: '下一首',
        glyph: GlassGlyph.next,
        kind: GlassButtonKind.playback,
        size: GlassButtonSize.playback,
      ),
      _ButtonSample(
        title: '导航',
        label: '返回',
        glyph: GlassGlyph.arrowBack,
        kind: GlassButtonKind.navigation,
      ),
      _ButtonSample(
        title: '分段 · 已选',
        label: '全部',
        glyph: GlassGlyph.grid,
        kind: GlassButtonKind.segmented,
        selected: true,
      ),
      _ButtonSample(
        title: '分段 · 未选',
        label: '收藏',
        glyph: GlassGlyph.star,
        kind: GlassButtonKind.segmented,
      ),
      _ButtonSample(
        title: '危险操作',
        label: '删除',
        glyph: GlassGlyph.trash,
        kind: GlassButtonKind.danger,
      ),
      _ButtonSample(
        title: '忙碌',
        label: '保存',
        glyph: GlassGlyph.save,
        kind: GlassButtonKind.secondary,
        busy: true,
      ),
      _ButtonSample(
        title: '禁用',
        label: '复制结果',
        glyph: GlassGlyph.copy,
        kind: GlassButtonKind.secondary,
        enabled: false,
      ),
    ];

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(32, 18, 32, 16),
              sliver: SliverToBoxAdapter(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '统一玻璃按钮',
                            style: textTheme.headlineSmall?.copyWith(
                              color: tokens.text,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            '13 个静置/点击样本 · 同一圆角点阵工厂 · 无业务回调',
                            style: textTheme.bodyMedium?.copyWith(
                              color: tokens.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      width: 250,
                      child: GlassThemeSwitch(
                        light: light,
                        onChanged: onLightChanged,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Text(
                      'UI-3 / FIXTURE',
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
                child: _FixtureSectionHeading(
                  title: '设计尺寸图案对照',
                  detail: '96 dp 原生控件 · 与 revision 5 点阵图案同尺寸核对',
                  tokens: tokens,
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(32, 16, 32, 26),
              sliver: SliverToBoxAdapter(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = constraints.maxWidth >= 900
                        ? 4
                        : constraints.maxWidth >= 600
                        ? 3
                        : 2;
                    const spacing = 18.0;
                    final width =
                        (constraints.maxWidth - spacing * (columns - 1)) /
                        columns;
                    return Wrap(
                      spacing: spacing,
                      runSpacing: 20,
                      children: [
                        for (final sample in referenceSamples)
                          SizedBox(
                            width: width,
                            child: _ReferenceGlyphTile(
                              sample: sample,
                              tokens: tokens,
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              sliver: SliverToBoxAdapter(
                child: _FixtureSectionHeading(
                  title: '动作与状态样本',
                  detail: '正常、选中、危险、忙碌与禁用复用同一材质层',
                  tokens: tokens,
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(32, 16, 32, 26),
              sliver: SliverToBoxAdapter(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = constraints.maxWidth >= 1080
                        ? 4
                        : constraints.maxWidth >= 760
                        ? 3
                        : 2;
                    final spacing = 18.0;
                    final width =
                        (constraints.maxWidth - spacing * (columns - 1)) /
                        columns;
                    return Wrap(
                      spacing: spacing,
                      runSpacing: 18,
                      children: [
                        for (final sample in samples)
                          SizedBox(
                            width: width,
                            child: _ButtonSampleTile(
                              sample: sample,
                              tokens: tokens,
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              sliver: SliverToBoxAdapter(
                child: _FixtureSectionHeading(
                  title: '60 种点阵独立动效',
                  detail: '每个 glyph 均可直接点击，逐项检查静置与点击光效',
                  tokens: tokens,
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(32, 16, 32, 36),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 112,
                  mainAxisExtent: 122,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                ),
                delegate: SliverChildBuilderDelegate((context, index) {
                  final glyph = GlassGlyph.values[index];
                  return _GlyphSample(glyph: glyph, tokens: tokens);
                }, childCount: GlassGlyph.values.length),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReferenceGlyphSample {
  const _ReferenceGlyphSample(
    this.label,
    this.glyph, {
    this.kind = GlassButtonKind.secondary,
  });

  final String label;
  final GlassGlyph glyph;
  final GlassButtonKind kind;
}

class _ReferenceGlyphTile extends StatelessWidget {
  const _ReferenceGlyphTile({required this.sample, required this.tokens});

  final _ReferenceGlyphSample sample;
  final GlassDesignTokens tokens;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      GlassActionButton(
        label: sample.label,
        semanticsLabel: sample.label,
        glyph: sample.glyph,
        kind: sample.kind,
        size: GlassButtonSize.reference,
        iconOnly: true,
        onPressed: () {},
      ),
      const SizedBox(height: 8),
      Text(
        sample.label,
        style: TextStyle(color: tokens.text, fontWeight: FontWeight.w500),
      ),
    ],
  );
}

class _ButtonSample {
  const _ButtonSample({
    required this.title,
    required this.label,
    required this.glyph,
    required this.kind,
    this.size = GlassButtonSize.secondary,
    this.busy = false,
    this.enabled = true,
    this.selected = false,
    this.iconOnly = false,
  });

  final String title;
  final String label;
  final GlassGlyph glyph;
  final GlassButtonKind kind;
  final GlassButtonSize size;
  final bool busy;
  final bool enabled;
  final bool selected;
  final bool iconOnly;
}

class _ButtonSampleTile extends StatelessWidget {
  const _ButtonSampleTile({required this.sample, required this.tokens});

  final _ButtonSample sample;
  final GlassDesignTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(sample.title, style: TextStyle(color: tokens.muted, fontSize: 12)),
        const SizedBox(height: 8),
        GlassActionButton(
          label: sample.label,
          semanticsLabel: sample.label,
          glyph: sample.glyph,
          kind: sample.kind,
          size: sample.size,
          busy: sample.busy,
          enabled: sample.enabled,
          selected: sample.selected,
          iconOnly: sample.iconOnly,
          onPressed: sample.enabled && !sample.busy ? () {} : null,
        ),
      ],
    );
  }
}

class _GlyphSample extends StatelessWidget {
  const _GlyphSample({required this.glyph, required this.tokens});

  final GlassGlyph glyph;
  final GlassDesignTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GlassActionButton(
          label: glyph.name,
          semanticsLabel: glyph.name,
          glyph: glyph,
          kind: GlassButtonKind.secondary,
          size: GlassButtonSize.reference,
          iconOnly: true,
          onPressed: () {},
        ),
        const SizedBox(height: 4),
        Text(
          glyph.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: tokens.muted, fontSize: 10),
        ),
      ],
    );
  }
}

class _FixtureSectionHeading extends StatelessWidget {
  const _FixtureSectionHeading({
    required this.title,
    required this.detail,
    required this.tokens,
  });

  final String title;
  final String detail;
  final GlassDesignTokens tokens;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: tokens.line.withValues(alpha: .7)),
        ),
      ),
      padding: const EdgeInsets.only(top: 14),
      child: Row(
        children: [
          Text(
            title,
            style: textTheme.titleMedium?.copyWith(
              color: tokens.text,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              detail,
              style: textTheme.bodySmall?.copyWith(color: tokens.muted),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
