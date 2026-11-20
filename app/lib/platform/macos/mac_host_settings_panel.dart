import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:aggregate_contracts/aggregate_contracts.dart';

import '../../widgets/glass/aggregate_buttons.dart';
import '../../widgets/glass/glass_alert_dialog.dart';
import '../../widgets/glass/glass_action_button.dart' show GlassButtonSize;
import 'host/host_control_port.dart';
import 'host/host_pairing_authority.dart';
import 'host/host_tls_identity.dart';
import 'host/host_wss_transport.dart';

class MacHostSettingsPanel extends StatefulWidget {
  const MacHostSettingsPanel({
    super.key,
    required this.hostControl,
    required this.pairingControl,
    required this.loadConnections,
    this.identityRotation,
  });

  final HostControlPort hostControl;
  final HostPairingControlPort pairingControl;
  final Future<List<Connection>> Function() loadConnections;
  final HostTlsIdentityRotationPort? identityRotation;

  @override
  State<MacHostSettingsPanel> createState() => _MacHostSettingsPanelState();
}

class _MacHostSettingsPanelState extends State<MacHostSettingsPanel> {
  late final HostTlsIdentityRotationPort _identityRotation =
      widget.identityRotation ?? HostTlsIdentityStore();
  late HostStatus _status = widget.hostControl.status;
  StreamSubscription<HostStatus>? _statusSubscription;
  Timer? _refreshTimer;
  List<HostPendingPairing> _pending = const [];
  List<HostDeviceGrant> _paired = const [];
  HostWssPairingInvitation? _invitation;
  String? _error;
  var _busy = false;

  @override
  void initState() {
    super.initState();
    _statusSubscription = widget.hostControl.watchStatus().listen((status) {
      if (!mounted) return;
      setState(() {
        _status = status;
        if (status.phase != HostPhase.running) {
          _pending = const [];
          _invitation = null;
        }
      });
      if (status.phase == HostPhase.running) {
        unawaited(_refreshPairings());
      }
    });
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 4),
      (_) => unawaited(_refreshPairings()),
    );
    if (_status.phase == HostPhase.running) unawaited(_refreshPairings());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    unawaited(_statusSubscription?.cancel());
    super.dispose();
  }

  Future<void> _setRunning(bool running) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (running) {
        await widget.hostControl.start();
      } else {
        await widget.hostControl.stop();
      }
      if (!mounted) return;
      setState(() => _status = widget.hostControl.status);
      if (running) {
        await _refreshPairings(force: true);
      } else {
        setState(() {
          _pending = const [];
          _paired = const [];
          _invitation = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = running
              ? 'Host 启动失败。请检查 Keychain、网络接口和本地网络权限后重试。'
              : 'Host 未能正常关闭，请重试。',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refreshPairings({bool force = false}) async {
    if (!mounted ||
        (_busy && !force) ||
        widget.hostControl.status.phase != HostPhase.running) {
      return;
    }
    try {
      final results = await Future.wait<Object>([
        widget.pairingControl.pendingRequests(),
        widget.pairingControl.pairedDevices(),
      ]);
      if (!mounted) return;
      setState(() {
        _pending = results[0] as List<HostPendingPairing>;
        _paired = results[1] as List<HostDeviceGrant>;
      });
    } catch (_) {
      // Keep the last successfully loaded device list visible during a short
      // discovery or Keychain interruption.
    }
  }

  Future<void> _createInvitation() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final invitation = await widget.pairingControl.createInvitation();
      if (mounted) setState(() => _invitation = invitation);
    } catch (_) {
      if (mounted) setState(() => _error = '无法生成邀请，请先确认 Host 正在运行。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _approve(
    HostPendingPairing request, {
    required Set<HostGrantScope> scopes,
    Map<String, Set<PermissionLevel>> connectionPermissions = const {},
  }) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.pairingControl.approvePending(
        request.deviceId,
        scopes: scopes,
        connectionPermissions: connectionPermissions,
      );
      await _refreshPairings(force: true);
    } catch (_) {
      if (mounted) setState(() => _error = '批准设备失败，请刷新后重试。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _configureApproval(HostPendingPairing request) async {
    if (_busy) return;
    List<Connection> connections;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      connections = await widget.loadConnections();
    } catch (_) {
      if (mounted) setState(() => _error = '无法读取 Mac 连接，暂时不能配置权限。');
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
    final selection = await showGlassDialog<_HostGrantSelection>(
      context: context,
      builder: (context) => _HostGrantDialog(connections: connections),
    );
    if (selection == null || !mounted) return;
    await _approve(
      request,
      scopes: selection.scopes,
      connectionPermissions: selection.connectionPermissions,
    );
  }

  Future<void> _configurePairedGrant(HostDeviceGrant grant) async {
    if (_busy) return;
    List<Connection> connections;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      connections = await widget.loadConnections();
    } catch (_) {
      if (mounted) setState(() => _error = '无法读取 Mac 连接，暂时不能配置权限。');
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
    final selection = await showGlassDialog<_HostGrantSelection>(
      context: context,
      builder: (context) => _HostGrantDialog(
        connections: connections,
        initialScopes: grant.scopes,
        initialConnectionPermissions: grant.connectionPermissions,
        saveLabel: '保存权限',
      ),
    );
    if (selection == null || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.pairingControl.updateDeviceGrant(
        grant.deviceId,
        scopes: selection.scopes,
        connectionPermissions: selection.connectionPermissions,
      );
      await _refreshPairings(force: true);
    } catch (_) {
      if (mounted) setState(() => _error = '保存设备权限失败，请刷新后重试。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject(HostPendingPairing request) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.pairingControl.rejectPending(request.deviceId);
      await _refreshPairings(force: true);
    } catch (_) {
      if (mounted) setState(() => _error = '拒绝配对请求失败，请刷新后重试。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _revoke(HostDeviceGrant grant) async {
    final confirmed = await showGlassDialog<bool>(
      context: context,
      builder: (context) => GlassAlertDialog(
        title: const Text('撤销设备配对？'),
        content: Text('撤销后，${grant.displayName} 的 Host 会话会立即断开，相关向导草稿也会清理。'),
        actions: [
          AggregateActionButton(
            label: '取消',
            icon: Icons.close,
            style: AggregateActionStyle.quiet,
            onPressed: () => Navigator.pop(context, false),
          ),
          AggregateActionButton(
            label: '撤销设备',
            icon: Icons.link_off,
            style: AggregateActionStyle.danger,
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.pairingControl.revokeDevice(grant.deviceId);
      await _refreshPairings(force: true);
    } catch (_) {
      if (mounted) setState(() => _error = '撤销设备失败，请重试。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _rotateHostIdentity() async {
    if (_busy || widget.hostControl.status.phase != HostPhase.running) return;
    final confirmed = await showGlassDialog<bool>(
      context: context,
      builder: (context) => GlassAlertDialog(
        title: const Text('轮换 Mac Host 身份？'),
        content: const Text(
          '此操作会撤销所有已配对设备的授权并断开会话，然后更换 Host ID 和 TLS 证书。Host 会保持停止；请在重新启动后删除手机里保存的旧 Host 并重新配对、审批。',
        ),
        actions: [
          AggregateActionButton(
            label: '取消',
            icon: Icons.close,
            style: AggregateActionStyle.quiet,
            onPressed: () => Navigator.pop(context, false),
          ),
          AggregateActionButton(
            label: '撤销授权并轮换',
            icon: Icons.vpn_key_off_outlined,
            style: AggregateActionStyle.danger,
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    var revokedCount = 0;
    var grantCount = 0;
    var grantsLoaded = false;
    try {
      final grants = await widget.pairingControl.pairedDevices();
      grantsLoaded = true;
      grantCount = grants.length;
      for (final grant in grants) {
        await widget.pairingControl.revokeDevice(grant.deviceId);
        revokedCount++;
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = grantsLoaded
              ? '撤销授权中断，已撤销 $revokedCount/$grantCount 台设备；Host 身份未轮换。请核对设备列表后重试。'
              : '无法读取当前配对授权；Host 身份未轮换，请刷新后重试。';
        });
      }
      await _refreshPairings(force: true);
      _finishIdentityRotation();
      return;
    }

    try {
      await widget.hostControl.stop();
      if (mounted) {
        setState(() {
          _status = widget.hostControl.status;
          _pending = const [];
          _paired = const [];
          _invitation = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error =
              '已撤销 $revokedCount 台设备授权，但 Host 未能确认关闭；身份未轮换。请检查 Host 状态后重试。';
        });
      }
      _finishIdentityRotation();
      return;
    }

    try {
      await _identityRotation.rotate();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Mac Host 身份已轮换。请启动 Host，并让手机重新配对。')),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = '设备授权已撤销，Host 保持停止，但身份轮换未返回有效结果。请重试轮换后再恢复服务。';
        });
      }
    } finally {
      _finishIdentityRotation();
    }
  }

  void _finishIdentityRotation() {
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _copyInvitation() async {
    final invitation = _invitation;
    if (invitation == null) return;
    await Clipboard.setData(ClipboardData(text: invitation.qrPayload));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('配对信息已复制')));
  }

  String _phaseLabel(HostStatus status) => switch (status.phase) {
    HostPhase.stopped => '已关闭',
    HostPhase.starting => '正在启动',
    HostPhase.running => '运行中',
    HostPhase.stopping => '正在关闭',
    HostPhase.unavailable => '暂不可用',
    HostPhase.failed => '启动失败',
  };

  String _scopeLabel(HostGrantScope scope) => switch (scope) {
    HostGrantScope.readConnections => '读取连接',
    HostGrantScope.connectionSetup => '连接向导',
    HostGrantScope.connectionManagement => '连接管理',
    HostGrantScope.account => '账号',
    HostGrantScope.terminal => '终端',
    HostGrantScope.activityClear => '清理活动',
    HostGrantScope.contentTransfer => '内容传输',
  };

  Color _statusColor(ColorScheme scheme) => switch (_status.phase) {
    HostPhase.running => scheme.primary,
    HostPhase.failed => scheme.error,
    HostPhase.unavailable => scheme.tertiary,
    _ => scheme.onSurfaceVariant,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final running = _status.phase == HostPhase.running;
    final invitation = _invitation;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final heading = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Mac Host', style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text('让已配对设备安全连接到这台 Mac。', style: theme.textTheme.bodySmall),
              ],
            );
            final status = Semantics(
              liveRegion: true,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _statusColor(theme.colorScheme),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(_phaseLabel(_status)),
                ],
              ),
            );
            final helper = Text(
              running ? '轮换身份会撤销全部配对授权并停止 Host。' : '请先启动 Host，才能读取并撤销设备授权。',
              style: theme.textTheme.bodySmall,
            );
            final startStopAction = AggregateActionButton(
              label: running ? '停止 Host' : '启动 Host',
              icon: running
                  ? Icons.stop_circle_outlined
                  : Icons.play_circle_outline,
              busyLabel: running ? '正在停止…' : '正在启动…',
              style: running
                  ? AggregateActionStyle.danger
                  : AggregateActionStyle.primary,
              onPressed: _busy ? null : () => _setRunning(!running),
              enabled: !_busy,
              busy: _busy,
              size: GlassButtonSize.compactAction,
              expand: true,
            );
            final rotateAction = AggregateActionButton(
              label: '轮换 Mac Host 身份',
              icon: Icons.vpn_key_outlined,
              style: AggregateActionStyle.danger,
              onPressed: _busy || !running ? null : _rotateHostIdentity,
              enabled: !_busy && running,
              size: GlassButtonSize.compactAction,
              expand: true,
            );

            if (constraints.maxWidth >= 720) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        heading,
                        const SizedBox(height: 12),
                        status,
                        const SizedBox(height: 16),
                        helper,
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const SizedBox(height: 29),
                      SizedBox(width: 120, height: 40, child: startStopAction),
                      const SizedBox(height: 12),
                      SizedBox(width: 180, height: 40, child: rotateAction),
                    ],
                  ),
                ],
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                heading,
                const SizedBox(height: 12),
                status,
                const SizedBox(height: 8),
                helper,
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [startStopAction, rotateAction],
                ),
              ],
            );
          },
        ),
        if (_status.phase == HostPhase.unavailable)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('配对认证组件尚未就绪，Host 未开放网络监听。'),
          ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Semantics(
            liveRegion: true,
            child: Text(
              _error!,
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
        ],
        if (running) ...[
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 9),
          LayoutBuilder(
            builder: (context, constraints) {
              final description = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('配对邀请', style: theme.textTheme.titleSmall),
                  Text(
                    '二维码只包含短时邀请和 Host 地址，不含长期设备密钥。',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              );
              final action = AggregateActionButton(
                label: '生成新邀请',
                icon: Icons.add,
                onPressed: _busy ? null : _createInvitation,
                enabled: !_busy,
                size: GlassButtonSize.compactAction,
                expand: true,
              );
              if (constraints.maxWidth >= 720) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 9),
                        child: description,
                      ),
                    ),
                    SizedBox(width: 141, height: 40, child: action),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  description,
                  const SizedBox(height: 8),
                  Align(alignment: Alignment.centerRight, child: action),
                ],
              );
            },
          ),
          if (invitation != null) ...[
            LayoutBuilder(
              builder: (context, constraints) {
                final qrSize = constraints.maxWidth < 520 ? 128.0 : 160.0;
                final qr = Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: QrImageView(
                    data: invitation.qrPayload,
                    size: qrSize,
                    backgroundColor: Colors.white,
                    semanticsLabel: 'Aggregate Mac Host 配对二维码',
                  ),
                );
                final details = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '邀请于 ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(invitation.invitation.expiresAt.toLocal()))} 到期',
                    ),
                    const SizedBox(height: 8),
                    Text('${invitation.endpoints.length} 个本机网络地址'),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: 138,
                      height: 40,
                      child: AggregateActionButton(
                        label: '复制配对信息',
                        icon: Icons.copy_outlined,
                        style: AggregateActionStyle.quiet,
                        onPressed: _copyInvitation,
                        size: GlassButtonSize.compactAction,
                        expand: true,
                      ),
                    ),
                  ],
                );
                if (constraints.maxWidth < 520) {
                  return Container(
                    key: const Key('host-invitation-card'),
                    padding: const EdgeInsets.all(12),
                    decoration: _hostPanelDecoration(theme),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [qr, const SizedBox(height: 12), details],
                    ),
                  );
                }
                return Container(
                  key: const Key('host-invitation-card'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 12,
                  ),
                  decoration: _hostPanelDecoration(theme),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      qr,
                      const SizedBox(width: 24),
                      Expanded(
                        child: SizedBox(
                          height: 176,
                          child: Align(
                            alignment: Alignment.topLeft,
                            child: details,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
          SizedBox(height: invitation == null ? 16 : 33),
          const Divider(),
          if (invitation == null) const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Transform.translate(
                  offset: const Offset(0, 11),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('待处理设备', style: theme.textTheme.titleSmall),
                      const SizedBox(height: 4),
                      Text('核对设备与确认码后再审批', style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
              ),
              AggregateIconButton(
                tooltip: '刷新配对设备',
                icon: Icons.refresh,
                onPressed: _busy ? null : _refreshPairings,
                enabled: !_busy,
              ),
            ],
          ),
          if (_pending.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text('暂时没有待批准的设备。', style: theme.textTheme.bodySmall),
            )
          else
            for (final request in _pending) _pendingCard(request, theme),
          if (_paired.isNotEmpty) ...[
            const SizedBox(height: 23),
            Text('已配对设备', style: theme.textTheme.titleSmall),
            Text('权限可随时编辑或撤销', style: theme.textTheme.bodySmall),
            for (final grant in _paired) _pairedCard(grant, theme),
          ],
        ],
      ],
    );
  }

  BoxDecoration _hostPanelDecoration(ThemeData theme) => BoxDecoration(
    color: theme.colorScheme.surfaceContainerLow.withValues(alpha: .42),
    borderRadius: BorderRadius.circular(12),
    border: Border.all(
      color: theme.colorScheme.outlineVariant.withValues(alpha: .58),
    ),
  );

  Widget _pendingCard(HostPendingPairing request, ThemeData theme) {
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(request.displayName, style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          '${request.platform} · 确认码 ${request.confirmationCode}',
          style: theme.textTheme.bodySmall,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
    final actions =
        <
          ({
            String label,
            IconData icon,
            AggregateActionStyle style,
            double width,
            VoidCallback onPressed,
          })
        >[
          (
            label: '拒绝',
            icon: Icons.close,
            style: AggregateActionStyle.danger,
            width: 84,
            onPressed: () => _reject(request),
          ),
          (
            label: '批准只读',
            icon: Icons.visibility_outlined,
            style: AggregateActionStyle.secondary,
            width: 107,
            onPressed: () => _approve(
              request,
              scopes: const {HostGrantScope.readConnections},
            ),
          ),
          (
            label: '允许连接向导',
            icon: Icons.settings_outlined,
            style: AggregateActionStyle.primary,
            width: 143,
            onPressed: () => _approve(
              request,
              scopes: const {
                HostGrantScope.readConnections,
                HostGrantScope.connectionSetup,
              },
            ),
          ),
          (
            label: '自定义权限',
            icon: Icons.tune,
            style: AggregateActionStyle.secondary,
            width: 125,
            onPressed: () => _configureApproval(request),
          ),
        ];

    Widget buildAction(
      ({
        String label,
        IconData icon,
        AggregateActionStyle style,
        double width,
        VoidCallback onPressed,
      })
      action, {
      required bool fixedWidth,
    }) {
      final button = AggregateActionButton(
        label: action.label,
        icon: action.icon,
        style: action.style,
        onPressed: _busy ? null : action.onPressed,
        enabled: !_busy,
        size: GlassButtonSize.compactAction,
        expand: fixedWidth,
      );
      return fixedWidth
          ? SizedBox(width: action.width, height: 40, child: button)
          : button;
    }

    return Container(
      key: Key('host-pending-card-${request.deviceId}'),
      decoration: _hostPanelDecoration(theme),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 720;
          return Padding(
            padding: EdgeInsets.symmetric(
              horizontal: 12,
              vertical: wide ? 14 : 10,
            ),
            child: wide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      SizedBox(width: 194, child: details),
                      const SizedBox(width: 16),
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final action in actions)
                            buildAction(action, fixedWidth: true),
                        ],
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      details,
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final action in actions)
                            buildAction(action, fixedWidth: false),
                        ],
                      ),
                    ],
                  ),
          );
        },
      ),
    );
  }

  Widget _pairedCard(HostDeviceGrant grant, ThemeData theme) => Container(
    key: Key('host-paired-card-${grant.deviceId}'),
    decoration: _hostPanelDecoration(theme),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final actions = Wrap(
          spacing: 6,
          children: [
            SizedBox(
              width: 112,
              height: 40,
              child: AggregateActionButton(
                label: '修改权限',
                icon: Icons.tune,
                onPressed: _busy ? null : () => _configurePairedGrant(grant),
                enabled: !_busy,
                size: GlassButtonSize.compactAction,
                expand: true,
              ),
            ),
            SizedBox(
              width: 111,
              height: 40,
              child: AggregateActionButton(
                label: '撤销',
                icon: Icons.link_off,
                style: AggregateActionStyle.danger,
                onPressed: _busy ? null : () => _revoke(grant),
                enabled: !_busy,
                size: GlassButtonSize.compactAction,
                expand: true,
              ),
            ),
          ],
        );
        final details = Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              grant.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              grant.scopes.map(_scopeLabel).join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(fontSize: 10),
            ),
          ],
        );
        if (constraints.maxWidth >= 720) {
          return SizedBox(
            height: 64,
            child: Padding(
              padding: const EdgeInsets.only(left: 14),
              child: Row(
                children: [
                  Expanded(child: details),
                  actions,
                ],
              ),
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [details, const SizedBox(height: 10), actions],
          ),
        );
      },
    ),
  );
}

final class _HostGrantSelection {
  const _HostGrantSelection({
    required this.scopes,
    required this.connectionPermissions,
  });

  final Set<HostGrantScope> scopes;
  final Map<String, Set<PermissionLevel>> connectionPermissions;
}

class _HostGrantDialog extends StatefulWidget {
  const _HostGrantDialog({
    required this.connections,
    this.initialScopes = const {HostGrantScope.readConnections},
    this.initialConnectionPermissions = const {},
    this.saveLabel = '批准所选权限',
  });

  final List<Connection> connections;
  final Set<HostGrantScope> initialScopes;
  final Map<String, Set<PermissionLevel>> initialConnectionPermissions;
  final String saveLabel;

  @override
  State<_HostGrantDialog> createState() => _HostGrantDialogState();
}

class _HostGrantDialogState extends State<_HostGrantDialog> {
  final Set<HostGrantScope> _scopes = {};
  final Set<HostGrantScope> _preservedUnavailableScopes = {};
  final Map<String, Set<PermissionLevel>> _connectionPermissions = {};

  @override
  void initState() {
    super.initState();
    _preservedUnavailableScopes.addAll(
      widget.initialScopes.difference({
        HostGrantScope.readConnections,
        HostGrantScope.connectionSetup,
        HostGrantScope.connectionManagement,
        HostGrantScope.account,
        HostGrantScope.terminal,
        HostGrantScope.activityClear,
      }),
    );
    _scopes.addAll(
      widget.initialScopes.difference(_preservedUnavailableScopes),
    );
    final availableConnectionIds = widget.connections
        .map((connection) => connection.id.value)
        .toSet();
    for (final entry in widget.initialConnectionPermissions.entries) {
      if (availableConnectionIds.contains(entry.key)) {
        _connectionPermissions[entry.key] = {...entry.value};
      }
    }
  }

  bool get _needsConnectionSelection =>
      _scopes.contains(HostGrantScope.connectionManagement) ||
      _scopes.contains(HostGrantScope.account) ||
      _scopes.contains(HostGrantScope.terminal);

  void _togglePermission(Connection connection, PermissionLevel permission) {
    setState(() {
      final levels = _connectionPermissions.putIfAbsent(
        connection.id.value,
        () => <PermissionLevel>{},
      );
      if (levels.contains(permission)) {
        if (permission == PermissionLevel.read &&
            (levels.contains(PermissionLevel.localControl) ||
                levels.contains(PermissionLevel.externalWrite))) {
          return;
        }
        levels.remove(permission);
        if (levels.isEmpty) _connectionPermissions.remove(connection.id.value);
      } else {
        levels.add(permission);
        if (permission != PermissionLevel.read) {
          levels.add(PermissionLevel.read);
        }
      }
    });
  }

  void _finish() {
    final scopes = Set<HostGrantScope>.unmodifiable({
      ..._scopes,
      ..._preservedUnavailableScopes,
    });
    final permissions = Map<String, Set<PermissionLevel>>.unmodifiable({
      for (final entry in _connectionPermissions.entries)
        entry.key: Set<PermissionLevel>.unmodifiable(entry.value),
    });
    Navigator.of(context).pop(
      _HostGrantSelection(scopes: scopes, connectionPermissions: permissions),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canApprove =
        !_needsConnectionSelection || _connectionPermissions.isNotEmpty;
    return GlassAlertDialog(
      title: const Text('配置设备权限'),
      constraints: const BoxConstraints(maxWidth: 720),
      content: SizedBox(
        width: 640,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.65,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.visibility_outlined),
                  title: Text('读取连接'),
                  subtitle: Text('必需权限；未设置单连接规则时可读取所有连接。'),
                ),
                for (final scope in const [
                  HostGrantScope.connectionSetup,
                  HostGrantScope.connectionManagement,
                  HostGrantScope.account,
                  HostGrantScope.terminal,
                  HostGrantScope.activityClear,
                ])
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _scopes.contains(scope),
                    title: Text(_scopeLabel(scope)),
                    subtitle: Text(_scopeDescription(scope)),
                    onChanged: (selected) => setState(() {
                      if (selected == true) {
                        _scopes.add(scope);
                      } else {
                        _scopes.remove(scope);
                      }
                    }),
                  ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  enabled: false,
                  leading: const Icon(Icons.lock_outline),
                  title: const Text('内容传输'),
                  subtitle: Text(
                    _preservedUnavailableScopes.contains(
                          HostGrantScope.contentTransfer,
                        )
                        ? '已有授权会保留；相关接口尚未开放。'
                        : '尚未开放',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                const Divider(),
                Text('逐连接权限', style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(
                  '设置任一连接后，仅列出的连接可读取。控制或外部写入会同时包含读取权限。',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                if (widget.connections.isEmpty)
                  Text('Mac 尚无已登记连接。', style: theme.textTheme.bodySmall)
                else
                  for (final connection in widget.connections)
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: Text(connection.label),
                      subtitle: Text(connection.kind.name),
                      childrenPadding: const EdgeInsets.only(bottom: 8),
                      children: [
                        Wrap(
                          spacing: 8,
                          children: [
                            _permissionChip(
                              connection,
                              PermissionLevel.read,
                              '读取',
                            ),
                            _permissionChip(
                              connection,
                              PermissionLevel.localControl,
                              '本机控制',
                            ),
                            _permissionChip(
                              connection,
                              PermissionLevel.externalWrite,
                              '外部写入',
                            ),
                          ],
                        ),
                      ],
                    ),
                if (_needsConnectionSelection && _connectionPermissions.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '所选权限需要至少一个逐连接授权。',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        AggregateActionButton(
          label: '取消',
          icon: Icons.close,
          style: AggregateActionStyle.quiet,
          onPressed: () => Navigator.of(context).pop(),
        ),
        AggregateActionButton(
          label: widget.saveLabel,
          icon: Icons.save_outlined,
          style: AggregateActionStyle.primary,
          onPressed: canApprove ? _finish : null,
          enabled: canApprove,
        ),
      ],
    );
  }

  Widget _permissionChip(
    Connection connection,
    PermissionLevel permission,
    String label,
  ) {
    final selected =
        _connectionPermissions[connection.id.value]?.contains(permission) ??
        false;
    final icon = switch (permission) {
      PermissionLevel.read => Icons.visibility_outlined,
      PermissionLevel.localControl => Icons.desktop_windows_outlined,
      PermissionLevel.externalWrite => Icons.edit_outlined,
      PermissionLevel.unknown => Icons.help_outline,
    };
    return AggregateActionButton(
      label: label,
      icon: icon,
      style: AggregateActionStyle.secondary,
      selected: selected,
      semanticsLabel: '$label权限${selected ? '已选择' : '未选择'}',
      onPressed: () => _togglePermission(connection, permission),
    );
  }

  String _scopeLabel(HostGrantScope scope) => switch (scope) {
    HostGrantScope.readConnections => '读取连接',
    HostGrantScope.connectionSetup => '连接向导',
    HostGrantScope.connectionManagement => '连接管理',
    HostGrantScope.account => '账号',
    HostGrantScope.terminal => '终端',
    HostGrantScope.activityClear => '清理活动',
    HostGrantScope.contentTransfer => '内容传输',
  };

  String _scopeDescription(HostGrantScope scope) => switch (scope) {
    HostGrantScope.readConnections => '读取连接',
    HostGrantScope.connectionSetup => '检测、测试和保存 Mac 连接',
    HostGrantScope.connectionManagement => '删除或排序连接；保存动作清单还需该连接的外部写入权限',
    HostGrantScope.account => '查看账号状态、登录或退出',
    HostGrantScope.terminal => '打开并交互操作 Mac CLI 终端',
    HostGrantScope.activityClear => '清除 Mac 上的运行活动记录',
    HostGrantScope.contentTransfer => '传输文件内容',
  };
}
