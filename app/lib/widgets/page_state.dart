import 'package:flutter/material.dart';

class PageState extends StatelessWidget {
  const PageState.loading({super.key})
    : message = '正在加载…',
      icon = Icons.hourglass_empty,
      onRetry = null;
  const PageState.empty(this.message, {super.key})
    : icon = Icons.inbox_outlined,
      onRetry = null;
  const PageState.error(this.message, {super.key, required this.onRetry})
    : icon = Icons.error_outline;

  final String message;
  final IconData icon;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 32),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(height: 12),
        Text(message),
        if (onRetry != null) ...[
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ],
    ),
  );
}
