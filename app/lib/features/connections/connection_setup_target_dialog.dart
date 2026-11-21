import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../widgets/glass/aggregate_buttons.dart';
import '../../widgets/glass/glass_alert_dialog.dart';
import '../../widgets/glass/glass_action_button.dart';
import '../../widgets/glass/glass_motion.dart';
import '../../widgets/glass/glass_panel_surface.dart';

Future<ExecutionTarget?> showConnectionSetupTargetDialog(
  BuildContext context,
  List<ConnectionSetupTargetOption> options,
) {
  return showGlassDialog<ExecutionTarget>(
    context: context,
    builder: (_) => _ConnectionSetupTargetDialog(options: options),
  );
}

class _ConnectionSetupTargetDialog extends StatefulWidget {
  const _ConnectionSetupTargetDialog({required this.options});

  final List<ConnectionSetupTargetOption> options;

  @override
  State<_ConnectionSetupTargetDialog> createState() =>
      _ConnectionSetupTargetDialogState();
}

class _ConnectionSetupTargetDialogState
    extends State<_ConnectionSetupTargetDialog> {
  ExecutionTarget? selectedTarget;

  @override
  void initState() {
    super.initState();
    selectedTarget = widget.options
        .where((option) => option.selectable)
        .firstOrNull
        ?.target;
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    final macDesign =
        defaultTargetPlatform == TargetPlatform.macOS &&
        GlassMotionScope.maybeOf(context) != null;
    final Widget list = widget.options.isEmpty
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
            itemCount: widget.options.length,
            separatorBuilder: (_, _) => macDesign
                ? const SizedBox(height: 7)
                : const Divider(height: 1),
            itemBuilder: (context, index) {
              final option = widget.options[index];
              final isHost = option.target.kind == ExecutionTargetKind.host;
              final isSelected = selectedTarget == option.target;
              return SizedBox(
                height: macDesign ? 61 : null,
                child: Padding(
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
                    onPressed: !option.selectable
                        ? null
                        : macDesign
                        ? () => setState(() => selectedTarget = option.target)
                        : () => Navigator.pop(context, option.target),
                    enabled: option.selectable,
                    style: macDesign && !isSelected
                        ? AggregateActionStyle.quiet
                        : AggregateActionStyle.secondary,
                    selected: macDesign && isSelected,
                    expand: true,
                    size: macDesign
                        ? GlassButtonSize.targetOption
                        : GlassButtonSize.secondary,
                  ),
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
    // The Flutter view starts below the native macOS title bar. This small
    // upward offset aligns the whole window composition with board 19.
    alignment: const Alignment(0, -.02),
    backgroundColor: Colors.transparent,
    insetPadding: const EdgeInsets.all(24),
    child: SizedBox(
      width: 585,
      height: 390,
      child: GlassPanelSurface(
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(30, 27, 30, 17),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 24,
                child: Text(
                  '选择执行目标',
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontSize: 19, height: 24 / 19),
                ),
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: 14,
                child: Text(
                  '选择此连接实际可用的设备。',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(fontSize: 11, height: 14 / 11),
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(height: 129, child: list),
              const Divider(height: 1),
              const SizedBox(height: 27),
              SizedBox(
                height: 14,
                child: Text(
                  '设备状态与授权说明来自当前运行时。',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(fontSize: 10, height: 14 / 10),
                ),
              ),
              const Spacer(),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  SizedBox(
                    key: const Key('connection-target-cancel'),
                    width: 93,
                    height: 40,
                    child: AggregateActionButton(
                      label: '取消',
                      icon: Icons.close,
                      style: AggregateActionStyle.quiet,
                      onPressed: () => Navigator.pop(context),
                      size: GlassButtonSize.compactAction,
                    ),
                  ),
                  const SizedBox(width: 11),
                  SizedBox(
                    key: const Key('connection-target-choose'),
                    width: 95,
                    height: 46,
                    child: AggregateActionButton(
                      label: '选择',
                      icon: Icons.check,
                      style: AggregateActionStyle.primary,
                      onPressed: selectedTarget == null
                          ? null
                          : () => Navigator.pop(context, selectedTarget),
                      enabled: selectedTarget != null,
                      size: GlassButtonSize.compactAction,
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
