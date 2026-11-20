import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../widgets/glass/aggregate_buttons.dart';
import '../../widgets/glass/glass_action_button.dart';
import '../../widgets/glass/glass_motion.dart';
import '../../widgets/glass/glass_panel_surface.dart';

Future<ExecutionTarget?> showConnectionSetupTargetDialog(
  BuildContext context,
  List<ConnectionSetupTargetOption> options,
) {
  final macDesign =
      defaultTargetPlatform == TargetPlatform.macOS &&
      GlassMotionScope.maybeOf(context) != null;
  return showDialog<ExecutionTarget>(
    context: context,
    barrierColor: macDesign ? const Color(0x3825252B) : null,
    builder: (_) => _ConnectionSetupTargetDialog(options: options),
  );
}

class _ConnectionSetupTargetDialog extends StatelessWidget {
  const _ConnectionSetupTargetDialog({required this.options});

  final List<ConnectionSetupTargetOption> options;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    final macDesign =
        defaultTargetPlatform == TargetPlatform.macOS &&
        GlassMotionScope.maybeOf(context) != null;
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
            shrinkWrap: !compact && !macDesign,
            itemCount: options.length,
            separatorBuilder: (_, _) => macDesign
                ? const SizedBox(height: 10)
                : const Divider(height: 1),
            itemBuilder: (context, index) {
              final option = options[index];
              final isHost = option.target.kind == ExecutionTargetKind.host;
              return Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: macDesign ? 0 : 12,
                  vertical: macDesign ? 0 : 4,
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
                  size: macDesign
                      ? GlassButtonSize.targetOption
                      : GlassButtonSize.secondary,
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

    if (macDesign) return _macDialog(context, list);

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

  Widget _macDialog(BuildContext context, Widget list) => Dialog(
    alignment: const Alignment(0, -0.15),
    backgroundColor: Colors.transparent,
    insetPadding: const EdgeInsets.all(24),
    child: SizedBox(
      width: 585,
      height: 390,
      child: GlassPanelSurface(
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(36),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('先选择执行设备', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 6),
              Text(
                '连接配置会保存到选中的设备。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              Expanded(child: list),
              const SizedBox(height: 12),
              Row(
                children: [
                  AggregateActionButton(
                    label: '取消',
                    icon: Icons.close,
                    style: AggregateActionStyle.quiet,
                    onPressed: () => Navigator.pop(context),
                    size: GlassButtonSize.compactAction,
                  ),
                  const Spacer(),
                  Flexible(
                    child: Text(
                      '选择后进入连接类型步骤',
                      textAlign: TextAlign.right,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
