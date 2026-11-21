import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'glass/glass_action_button.dart';
import 'glass/glass_design_tokens.dart';
import 'glass/glass_glyph.dart';
import 'glass/glass_motion.dart';

class CapabilityRow extends StatelessWidget {
  const CapabilityRow({
    super.key,
    required this.capability,
    required this.source,
    required this.onOpen,
    this.isFavorite = false,
    this.onFavoriteChanged,
    this.selected = false,
    this.compactDirectory = false,
    this.directorySubtitle,
  });
  final Capability capability;
  final String source;
  final VoidCallback onOpen;
  final bool isFavorite;
  final ValueChanged<bool>? onFavoriteChanged;
  final bool selected;
  final bool compactDirectory;
  final String? directorySubtitle;

  @override
  Widget build(BuildContext context) {
    final icon = _icon(capability);
    final description = compactDirectory
        ? directorySubtitle ?? _directoryDescription(capability)
        : capability.description;
    if (defaultTargetPlatform == TargetPlatform.macOS &&
        GlassMotionScope.maybeOf(context) != null) {
      return _buildMacDirectoryRow(
        context,
        icon: icon,
        description: description,
      );
    }
    return Material(
      type: MaterialType.transparency,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        leading: Icon(icon, size: 19),
        title: Tooltip(
          message: capability.title,
          child: Text(
            capability.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        subtitle: compactDirectory
            ? Text(description, maxLines: 1, overflow: TextOverflow.ellipsis)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    capability.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(source, maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
        trailing: onFavoriteChanged == null
            ? const Icon(Icons.chevron_right)
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: isFavorite
                        ? '取消收藏 ${capability.title}'
                        : '收藏 ${capability.title}',
                    onPressed: () => onFavoriteChanged!(!isFavorite),
                    icon: Icon(
                      isFavorite
                          ? Icons.star_rounded
                          : Icons.star_border_rounded,
                      size: 20,
                    ),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
        onTap: onOpen,
        selected: selected,
      ),
    );
  }

  Widget _buildMacDirectoryRow(
    BuildContext context, {
    required IconData icon,
    required String description,
  }) {
    final tokens =
        Theme.of(context).extension<GlassDesignTokens>() ??
        GlassDesignTokens.forBrightness(Theme.of(context).brightness);
    const rowHeight = 56.0;
    const rowRadius = 11.0;
    final selectedDecoration = selected
        ? BoxDecoration(
            borderRadius: BorderRadius.circular(rowRadius),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                tokens.glassTop.withValues(alpha: .56),
                tokens.glassBottom.withValues(alpha: .36),
              ],
            ),
            border: Border.all(
              color: tokens.line.withValues(alpha: .42),
              width: .7,
            ),
            boxShadow: [
              BoxShadow(
                color: tokens.shadow.withValues(alpha: .11),
                blurRadius: 5,
                offset: const Offset(0, 2),
              ),
            ],
          )
        : null;
    final mainAction = GlassActionButton(
      glyph: GlassGlyphCatalog.fromMaterialIcon(icon),
      label: capability.title,
      description: description,
      source: compactDirectory ? null : source,
      semanticsLabel:
          '${capability.title}；${capability.description}；来源：$source',
      onPressed: onOpen,
      kind: GlassButtonKind.directoryRow,
      size: GlassButtonSize.directory,
      selected: selected,
      surfaceSelected: false,
      expand: true,
    );
    final favoriteLabel = isFavorite
        ? '取消收藏 ${capability.title}'
        : '收藏 ${capability.title}';
    final favoriteAction = onFavoriteChanged == null
        ? null
        : Tooltip(
            message: favoriteLabel,
            excludeFromSemantics: true,
            child: GlassActionButton(
              glyph: GlassGlyphCatalog.fromMaterialIcon(
                isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
              ),
              semanticsLabel: favoriteLabel,
              onPressed: () => onFavoriteChanged!(!isFavorite),
              kind: GlassButtonKind.directoryRow,
              size: GlassButtonSize.navigation,
              iconOnly: true,
            ),
          );

    return SizedBox(
      height: rowHeight,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (selectedDecoration != null)
            DecoratedBox(decoration: selectedDecoration),
          if (selected)
            Positioned(
              left: 0,
              top: 8,
              bottom: 8,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: tokens.warm.withValues(alpha: .88),
                  borderRadius: BorderRadius.circular(1),
                ),
                child: const SizedBox(width: 1.5),
              ),
            ),
          Row(
            children: [
              Expanded(child: mainAction),
              if (favoriteAction != null)
                SizedBox(
                  width: 38,
                  height: rowHeight,
                  child: Center(child: favoriteAction),
                ),
            ],
          ),
          if (!selected)
            Positioned(
              left: 2,
              right: 2,
              bottom: 0,
              child: Container(
                height: 1,
                color: tokens.line.withValues(alpha: .62),
              ),
            ),
        ],
      ),
    );
  }
}

String _directoryDescription(Capability capability) =>
    switch (capability.id.kind) {
      CapabilityKind.mcpTool => switch (capability.permission) {
        PermissionLevel.read => '只读工具',
        PermissionLevel.localControl => '运行端控制',
        PermissionLevel.externalWrite => '外部写入',
        PermissionLevel.unknown => '权限待确认',
      },
      CapabilityKind.mcpResource => '只读资源',
      CapabilityKind.mcpPrompt => '内容预览',
      CapabilityKind.cliCommand => 'CLI 命令',
      CapabilityKind.cliAction => 'CLI 动作',
    };

IconData _icon(Capability capability) => switch (capability.presentation) {
  'music.prev' => Icons.skip_previous_rounded,
  'music.next' => Icons.skip_next_rounded,
  'music.pause' => Icons.pause_rounded,
  'music.resume' || 'music.play' => Icons.play_arrow_rounded,
  'music.stop' => Icons.stop,
  'music.search' || 'music.state' => Icons.music_note_rounded,
  'music.queueAdd' => Icons.playlist_add,
  _ => switch (capability.id.kind) {
    CapabilityKind.cliCommand => Icons.terminal_outlined,
    CapabilityKind.cliAction => Icons.play_circle_outline,
    CapabilityKind.mcpTool => Icons.build_outlined,
    CapabilityKind.mcpResource => Icons.description_outlined,
    CapabilityKind.mcpPrompt => Icons.chat_bubble_outline,
  },
};
