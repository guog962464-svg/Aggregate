import 'package:flutter/material.dart';

class PageFrame extends StatelessWidget {
  const PageFrame({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    required this.children,
    this.lazyChildren = false,
  });
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final List<Widget> children;
  final bool lazyChildren;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final heading = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.headlineMedium),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      );
      final compactHeader = constraints.maxWidth < 560;
      final padding = EdgeInsets.fromLTRB(
        constraints.maxWidth < 600 ? 20 : 32,
        28,
        constraints.maxWidth < 600 ? 20 : 32,
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
                children: [header, const SizedBox(height: 24), ...children],
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
                  1 => const SizedBox(height: 24),
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
