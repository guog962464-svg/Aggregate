import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

class PageFrame extends StatelessWidget {
  const PageFrame({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.contentPadding,
    this.headerContentPadding = EdgeInsets.zero,
    this.titleStyle,
    this.subtitleStyle,
    this.headerSpacing = 24,
    required this.children,
    this.lazyChildren = false,
    this.fillWidth = false,
    this.pinnedHeader = false,
    this.pinnedContentTopOcclusion = 0,
  });
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final EdgeInsets? contentPadding;
  final EdgeInsets headerContentPadding;
  final TextStyle? titleStyle;
  final TextStyle? subtitleStyle;
  final double headerSpacing;
  final List<Widget> children;
  final bool lazyChildren;
  final bool fillWidth;
  final bool pinnedHeader;
  final double pinnedContentTopOcclusion;

  @override
  Widget build(BuildContext context) => DefaultTextStyle.merge(
    style: Theme.of(context).textTheme.bodyMedium,
    child: _buildPageContent(context),
  );

  Widget _buildPageContent(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final heading = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style:
                titleStyle ??
                (defaultTargetPlatform == TargetPlatform.macOS
                    ? Theme.of(context).textTheme.headlineSmall
                    : Theme.of(context).textTheme.headlineMedium),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Text(
              subtitle!,
              style: subtitleStyle ?? Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      );
      final compactHeader = constraints.maxWidth < 560;
      final macOS = defaultTargetPlatform == TargetPlatform.macOS;
      final padding =
          contentPadding ??
          EdgeInsets.fromLTRB(
            macOS
                ? 40
                : constraints.maxWidth < 600
                ? 20
                : 32,
            macOS ? 36 : 28,
            macOS
                ? 52
                : constraints.maxWidth < 600
                ? 20
                : 32,
            40,
          );
      final header = compactHeader
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                heading,
                if (trailing case final action?)
                  Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: action,
                    ),
                  ),
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: heading),
                if (trailing case final action?) ...[
                  const SizedBox(width: 12),
                  action,
                ],
              ],
            );
      final paddedHeader = headerContentPadding == EdgeInsets.zero
          ? header
          : Padding(padding: headerContentPadding, child: header);
      final contentWidth = constraints.maxWidth.isFinite
          ? constraints.maxWidth.clamp(0.0, 1080.0).toDouble()
          : 1080.0;
      if (pinnedHeader) {
        Widget constrainContent(Widget child) => Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: fillWidth ? contentWidth : 0,
              maxWidth: 1080,
            ),
            child: child,
          ),
        );

        final headerPadding = EdgeInsets.fromLTRB(
          padding.left,
          padding.top,
          padding.right,
          0,
        );
        final scrollPadding = EdgeInsets.fromLTRB(
          padding.left,
          headerSpacing,
          padding.right,
          padding.bottom,
        );
        final scrollContent = lazyChildren
            ? CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: scrollPadding,
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => constrainContent(children[index]),
                        childCount: children.length,
                      ),
                    ),
                  ),
                ],
              )
            : SingleChildScrollView(
                padding: scrollPadding,
                child: constrainContent(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: children,
                  ),
                ),
              );
        final clippedScrollContent = pinnedContentTopOcclusion <= 0
            ? scrollContent
            : ClipRect(
                clipper: _PageFrameTopInsetClipper(pinnedContentTopOcclusion),
                child: scrollContent,
              );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: headerPadding,
              child: constrainContent(paddedHeader),
            ),
            Expanded(child: clippedScrollContent),
          ],
        );
      }
      if (!lazyChildren) {
        return SingleChildScrollView(
          padding: padding,
          child: Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: fillWidth ? contentWidth : 0,
                maxWidth: 1080,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  paddedHeader,
                  SizedBox(height: headerSpacing),
                  ...children,
                ],
              ),
            ),
          ),
        );
      }
      return CustomScrollView(
        slivers: [
          SliverPadding(
            padding: padding,
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate((context, index) {
                final child = switch (index) {
                  0 => paddedHeader,
                  1 => SizedBox(height: headerSpacing),
                  _ => children[index - 2],
                };
                return Align(
                  alignment: Alignment.topLeft,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minWidth: fillWidth ? contentWidth : 0,
                      maxWidth: 1080,
                    ),
                    child: child,
                  ),
                );
              }, childCount: children.length + 2),
            ),
          ),
        ],
      );
    },
  );
}

/// Leaves the scene visible beneath a pinned header while scrolling content
/// through the blank header-to-section gutter.
class _PageFrameTopInsetClipper extends CustomClipper<Rect> {
  const _PageFrameTopInsetClipper(this.topInset);

  final double topInset;

  @override
  Rect getClip(Size size) => Rect.fromLTRB(
    0,
    topInset.clamp(0, size.height).toDouble(),
    size.width,
    size.height,
  );

  @override
  bool shouldReclip(covariant _PageFrameTopInsetClipper oldClipper) =>
      oldClipper.topInset != topInset;
}
