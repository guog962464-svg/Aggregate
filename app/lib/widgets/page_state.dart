import 'package:flutter/material.dart';

import 'glass/aggregate_buttons.dart';

class PageState extends StatelessWidget {
  const PageState.loading({super.key})
    : message = '正在加载…',
      icon = Icons.hourglass_empty,
      onRetry = null,
      actions = const [];
  const PageState.empty(this.message, {super.key, this.actions = const []})
    : icon = Icons.inbox_outlined,
      onRetry = null;
  const PageState.error(this.message, {super.key, required this.onRetry})
    : icon = Icons.error_outline,
      actions = const [];

  final String message;
  final IconData icon;
  final VoidCallback? onRetry;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 32),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(
          icon,
          size: 26,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(height: 12),
        Text(message, textAlign: TextAlign.center),
        if (actions.isNotEmpty) ...[
          const SizedBox(height: 20),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
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
    ),
  );
}
