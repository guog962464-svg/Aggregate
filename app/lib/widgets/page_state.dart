import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'glass/aggregate_buttons.dart';
import 'glass/glass_glyph.dart';

class PageState extends StatelessWidget {
  const PageState.loading({
    super.key,
    this.message = '正在加载…',
    this.actions = const [],
    this.glyph = GlassGlyph.hourglass,
  }) : icon = Icons.hourglass_empty,
       onRetry = null;
  const PageState.empty(
    this.message, {
    super.key,
    this.actions = const [],
    this.glyph = GlassGlyph.inbox,
  }) : icon = Icons.inbox_outlined,
       onRetry = null;
  const PageState.error(
    this.message, {
    super.key,
    required this.onRetry,
    this.glyph = GlassGlyph.error,
  }) : icon = Icons.error_outline,
       actions = const [];

  final String message;
  final IconData icon;
  final GlassGlyph glyph;
  final VoidCallback? onRetry;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 480;
      final body = Column(
        crossAxisAlignment: compact
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start,
        children: [
          Text(
            message,
            textAlign: compact ? TextAlign.center : TextAlign.start,
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: compact ? WrapAlignment.center : WrapAlignment.start,
              children: actions,
            ),
          ],
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            AggregateActionButton(
              label: '重试',
              icon: Icons.refresh_rounded,
              onPressed: onRetry,
            ),
          ],
        ],
      );
      final iconColor = Theme.of(context).colorScheme.onSurfaceVariant;
      final iconWidget = defaultTargetPlatform == TargetPlatform.macOS
          ? GlassGlyphMark(glyph: glyph, size: 26, color: iconColor)
          : Icon(icon, size: 26, color: iconColor);

      return Padding(
        padding: EdgeInsets.symmetric(
          vertical: 32,
          horizontal: compact ? 12 : 8,
        ),
        child: compact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [iconWidget, const SizedBox(height: 12), body],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  iconWidget,
                  const SizedBox(width: 16),
                  Expanded(child: body),
                ],
              ),
      );
    },
  );
}
