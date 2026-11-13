import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:flutter/material.dart';

Future<ExecutionTarget?> showConnectionSetupTargetDialog(
  BuildContext context,
  List<ConnectionSetupTargetOption> options,
) => showDialog<ExecutionTarget>(
  context: context,
  builder: (_) => _ConnectionSetupTargetDialog(options: options),
);

class _ConnectionSetupTargetDialog extends StatelessWidget {
  const _ConnectionSetupTargetDialog({required this.options});

  final List<ConnectionSetupTargetOption> options;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    final list = ListView.separated(
      shrinkWrap: !compact,
      itemCount: options.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final option = options[index];
        final isHost = option.target.kind == ExecutionTargetKind.host;
        return ListTile(
          enabled: option.selectable,
          minVerticalPadding: 12,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20),
          leading: Icon(
            isHost ? Icons.desktop_mac_outlined : Icons.phone_android_outlined,
          ),
          title: Text(option.label),
          subtitle: Text(option.detail),
          trailing: option.selectable
              ? const Icon(Icons.chevron_right)
              : const Icon(Icons.lock_outline),
          onTap: option.selectable
              ? () => Navigator.pop(context, option.target)
              : null,
        );
      },
    );

    if (compact) {
      return Dialog.fullscreen(
        child: Scaffold(
          appBar: AppBar(
            title: const Text('选择执行设备'),
            leading: IconButton(
              tooltip: '关闭选择执行设备',
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close),
            ),
          ),
          body: SafeArea(child: list),
        ),
      );
    }

    return AlertDialog(
      title: const Text('先选择执行设备'),
      content: SizedBox(width: 440, child: list),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ],
    );
  }
}
