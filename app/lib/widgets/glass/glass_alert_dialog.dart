import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'glass_design_tokens.dart';
import 'glass_motion.dart';
import 'glass_panel_surface.dart';

/// Shows a dialog with a neutral macOS scrim while retaining the platform's
/// standard route and barrier-dismiss behavior.
Future<T?> showGlassDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  bool useRootNavigator = true,
}) {
  final motionScope = GlassMotionScope.maybeOf(context);
  final tokens = Theme.of(context).extension<GlassDesignTokens>();
  final glassMacOS =
      defaultTargetPlatform == TargetPlatform.macOS &&
      motionScope != null &&
      tokens != null;
  final barrierColor = glassMacOS
      ? Colors.black.withValues(alpha: tokens.daylight > .5 ? .22 : .38)
      : null;
  return showDialog<T>(
    context: context,
    useRootNavigator: useRootNavigator,
    barrierDismissible: barrierDismissible,
    barrierColor: barrierColor,
    builder: builder,
  );
}

/// Alert-style content on the shared macOS glass surface.
///
/// Other platforms retain Flutter's native Material alert dialog. The macOS
/// surface follows the active scene and remains inside the existing dialog
/// route so keyboard dismissal and navigation results are unchanged.
class GlassAlertDialog extends StatelessWidget {
  const GlassAlertDialog({
    super.key,
    this.icon,
    this.title,
    this.content,
    this.actions = const [],
    this.constraints,
    this.insetPadding = const EdgeInsets.symmetric(
      horizontal: 40,
      vertical: 24,
    ),
    this.scrollable = false,
  });

  final Widget? icon;
  final Widget? title;
  final Widget? content;
  final List<Widget> actions;
  final BoxConstraints? constraints;
  final EdgeInsets insetPadding;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GlassDesignTokens>();
    final glassMacOS =
        defaultTargetPlatform == TargetPlatform.macOS &&
        GlassMotionScope.maybeOf(context) != null &&
        tokens != null;
    if (!glassMacOS) {
      return AlertDialog(
        icon: icon,
        title: title,
        content: content,
        actions: actions,
        constraints: constraints,
        insetPadding: insetPadding,
        scrollable: scrollable,
      );
    }
    final glassTokens = tokens;

    final size = MediaQuery.sizeOf(context);
    final maxWidth = math.min(
      constraints?.maxWidth ?? 560,
      size.width - insetPadding.horizontal,
    );
    final maxHeight = math.min(
      constraints?.maxHeight ?? size.height * .82,
      size.height - insetPadding.vertical,
    );
    final titleStyle = Theme.of(context).textTheme.titleLarge?.copyWith(
      color: glassTokens.text,
      fontSize: 18,
      fontWeight: FontWeight.w600,
    );
    final contentStyle = Theme.of(context).textTheme.bodyMedium
        ?.copyWith(color: glassTokens.text, height: 1.45);

    return Dialog(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      elevation: 0,
      insetPadding: insetPadding,
      child: GlassPanelSurface(
        borderRadius: const BorderRadius.all(Radius.circular(18)),
        blurSigma: 20,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (icon != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
                    child: IconTheme(
                      data: IconThemeData(color: glassTokens.ink, size: 22),
                      child: icon!,
                    ),
                  ),
                if (title != null)
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      24,
                      icon == null ? 22 : 12,
                      24,
                      0,
                    ),
                    child: DefaultTextStyle.merge(
                      style: titleStyle,
                      child: title!,
                    ),
                  ),
                if (content != null)
                  Flexible(
                    fit: FlexFit.loose,
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        24,
                        title == null && icon == null ? 22 : 12,
                        24,
                        0,
                      ),
                      child: DefaultTextStyle.merge(
                        style: contentStyle,
                        child: scrollable
                            ? SingleChildScrollView(child: content!)
                            : content!,
                      ),
                    ),
                  ),
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Divider(
                    height: 1,
                    color: glassTokens.line.withValues(alpha: .72),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.end,
                        children: actions,
                      ),
                    ),
                  ),
                ] else
                  const SizedBox(height: 22),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
