import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

class PageFrame extends StatelessWidget {
  const PageFrame({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.contentPadding,
    this.titleStyle,
    this.headerSpacing = 24,
    required this.children,
    this.lazyChildren = false,
  });
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final EdgeInsets? contentPadding;
  final TextStyle? titleStyle;
  final double headerSpacing;
  final List<Widget> children;
  final bool lazyChildren;

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
            Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      );
      final compactHeader = constraints.maxWidth < 560;
      final macOS = defaultTargetPlatform == TargetPlatform.macOS;
      final padding =
          contentPadding ??
          EdgeInsets.fromLTRB(
            macOS
                ? 30
                : constraints.maxWidth < 600
                ? 20
                : 32,
            28,
            macOS
                ? 30
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
      if (!lazyChildren) {
        return SingleChildScrollView(
          padding: padding,
          child: Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1080),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  header,
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
                  0 => header,
                  1 => SizedBox(height: headerSpacing),
                  _ => children[index - 2],
                };
                return Align(
                  alignment: Alignment.topLeft,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1080),
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
