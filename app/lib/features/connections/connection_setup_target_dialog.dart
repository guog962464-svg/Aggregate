import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:flutter/material.dart';

import '../../widgets/glass/aggregate_buttons.dart';

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
    final Widget list = options.isEmpty
        ? const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.devices_outlined, size: 32),
                  SizedBox(height: 12),
                  Text('当前没有可用的执行设备。'),
                  SizedBox(height: 4),
                  Text('请检查本机运行端或先连接 Mac Host。'),
                ],
              ),
            ),
          )
        : ListView.separated(
            shrinkWrap: !compact,
            itemCount: options.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final option = options[index];
              final isHost = option.target.kind == ExecutionTargetKind.host;
              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                child: AggregateActionButton(
                  label: option.label,
                  description: option.detail,
                  semanticsLabel: '${option.label}，${option.detail}',
                  icon: isHost
                      ? Icons.desktop_mac_outlined
                      : Icons.phone_android_outlined,
                  onPressed: option.selectable
                      ? () => Navigator.pop(context, option.target)
                      : null,
                  enabled: option.selectable,
                  expand: true,
                ),
              );
            },
          );

    if (compact) {
      return Dialog.fullscreen(
        child: Scaffold(
          appBar: AppBar(
            title: const Text('第 1 步 · 选择执行设备'),
            leading: AggregateIconButton(
              tooltip: '关闭选择执行设备',
              icon: Icons.close,
              onPressed: () => Navigator.pop(context),
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
        AggregateActionButton(
          label: '取消',
          icon: Icons.close,
          style: AggregateActionStyle.quiet,
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }
}
