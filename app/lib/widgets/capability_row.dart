import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:flutter/material.dart';

class CapabilityRow extends StatelessWidget {
  const CapabilityRow({
    super.key,
    required this.capability,
    required this.source,
    required this.onOpen,
  });
  final Capability capability;
  final String source;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Tooltip(
      message: capability.title,
      child: Text(
        capability.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    ),
    subtitle: Text(
      '${capability.description} · $source',
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    ),
    trailing: const Icon(Icons.chevron_right),
    onTap: onOpen,
  );
}
