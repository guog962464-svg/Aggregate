import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'glass_action_button.dart';
import 'glass_glyph.dart';
import 'glass_motion.dart';

enum AggregateActionStyle { primary, secondary, quiet, danger }

/// A platform-aware action button. macOS uses the shared glass-dot system;
/// other platforms retain their existing Material button behavior.
class AggregateActionButton extends StatelessWidget {
  const AggregateActionButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.description,
    this.source,
    this.busyLabel,
    this.semanticsLabel,
    this.style = AggregateActionStyle.secondary,
    this.enabled = true,
    this.busy = false,
    this.selected = false,
    this.size = GlassButtonSize.secondary,
    this.focusNode,
    this.autofocus = false,
    this.expand = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final String? description;
  final String? source;
  final String? busyLabel;
  final String? semanticsLabel;
  final AggregateActionStyle style;
  final bool enabled;
  final bool busy;
  final bool selected;
  final GlassButtonSize size;
  final FocusNode? focusNode;
  final bool autofocus;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final action = enabled && !busy ? onPressed : null;
    final scope = GlassMotionScope.maybeOf(context);
    if (defaultTargetPlatform == TargetPlatform.macOS && scope != null) {
      return GlassActionButton(
        glyph: GlassGlyphCatalog.fromMaterialIcon(icon),
        label: label,
        busyLabel: busyLabel,
        description: description,
        source: source,
        semanticsLabel: semanticsLabel,
        onPressed: action,
        enabled: enabled,
        busy: busy,
        selected: selected,
        kind: switch (style) {
          AggregateActionStyle.primary => GlassButtonKind.primary,
          AggregateActionStyle.secondary => GlassButtonKind.secondary,
          AggregateActionStyle.quiet => GlassButtonKind.navigation,
          AggregateActionStyle.danger => GlassButtonKind.danger,
        },
        size: size,
        focusNode: focusNode,
        autofocus: autofocus,
        expand: expand,
      );
    }

    final child = Text(busy ? busyLabel ?? '$label中' : label);
    final button = switch (style) {
      AggregateActionStyle.primary => FilledButton.icon(
        onPressed: action,
        focusNode: focusNode,
        autofocus: autofocus,
        icon: Icon(icon),
        label: child,
      ),
      AggregateActionStyle.secondary => OutlinedButton.icon(
        onPressed: action,
        focusNode: focusNode,
        autofocus: autofocus,
        icon: Icon(icon),
        label: child,
      ),
      AggregateActionStyle.quiet => TextButton.icon(
        onPressed: action,
        focusNode: focusNode,
        autofocus: autofocus,
        icon: Icon(icon),
        label: child,
      ),
      AggregateActionStyle.danger => TextButton.icon(
        onPressed: action,
        focusNode: focusNode,
        autofocus: autofocus,
        style: TextButton.styleFrom(
          foregroundColor: Theme.of(context).colorScheme.error,
        ),
        icon: Icon(icon),
        label: child,
      ),
    };
    if (semanticsLabel == null) return button;
    return Semantics(
      label: semanticsLabel,
      button: true,
      enabled: action != null,
      selected: selected,
      onTap: action,
      child: ExcludeSemantics(child: button),
    );
  }
}

/// A platform-aware icon action with a visible tooltip and accessible name.
class AggregateIconButton extends StatelessWidget {
  const AggregateIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.enabled = true,
    this.busy = false,
    this.selected = false,
    this.kind = GlassButtonKind.icon,
    this.size = GlassButtonSize.icon,
    this.focusNode,
    this.autofocus = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool enabled;
  final bool busy;
  final bool selected;
  final GlassButtonKind kind;
  final GlassButtonSize size;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final action = enabled && !busy ? onPressed : null;
    final scope = GlassMotionScope.maybeOf(context);
    if (defaultTargetPlatform == TargetPlatform.macOS && scope != null) {
      return Tooltip(
        message: tooltip,
        excludeFromSemantics: true,
        child: GlassActionButton(
          glyph: GlassGlyphCatalog.fromMaterialIcon(icon),
          semanticsLabel: tooltip,
          onPressed: action,
          enabled: enabled,
          busy: busy,
          selected: selected,
          iconOnly: true,
          kind: kind,
          size: size,
          focusNode: focusNode,
          autofocus: autofocus,
        ),
      );
    }

    return Semantics(
      selected: selected,
      child: IconButton(
        tooltip: tooltip,
        onPressed: action,
        focusNode: focusNode,
        autofocus: autofocus,
        icon: Icon(icon),
      ),
    );
  }
}
