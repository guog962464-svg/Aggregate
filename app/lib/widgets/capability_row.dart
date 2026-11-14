import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'glass/glass_action_button.dart';
import 'glass/aggregate_buttons.dart';
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
  });
  final Capability capability;
  final String source;
  final VoidCallback onOpen;
  final bool isFavorite;
  final ValueChanged<bool>? onFavoriteChanged;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final icon = _icon(capability.id.kind);
    if (defaultTargetPlatform == TargetPlatform.macOS &&
        GlassMotionScope.maybeOf(context) != null) {
      return Row(
        children: [
          Expanded(
            child: GlassActionButton(
              glyph: GlassGlyphCatalog.fromMaterialIcon(icon),
              label: capability.title,
              description: capability.description,
              source: source,
              semanticsLabel:
                  '${capability.title}；${capability.description}；来源：$source',
              onPressed: onOpen,
              kind: GlassButtonKind.navigation,
              size: GlassButtonSize.secondary,
              selected: selected,
              expand: true,
            ),
          ),
          if (onFavoriteChanged != null)
            AggregateIconButton(
              tooltip: isFavorite
                  ? '取消收藏 ${capability.title}'
                  : '收藏 ${capability.title}',
              icon: isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
              selected: isFavorite,
              onPressed: () => onFavoriteChanged!(!isFavorite),
            ),
        ],
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
        subtitle: Column(
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
}

IconData _icon(CapabilityKind kind) => switch (kind) {
  CapabilityKind.cliCommand => Icons.terminal_outlined,
  CapabilityKind.cliAction => Icons.play_circle_outline,
  CapabilityKind.mcpTool => Icons.build_outlined,
  CapabilityKind.mcpResource => Icons.description_outlined,
  CapabilityKind.mcpPrompt => Icons.chat_bubble_outline,
};
