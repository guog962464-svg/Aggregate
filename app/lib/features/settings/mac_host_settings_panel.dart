import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../platform/macos/host/host_control_port.dart';
import '../../platform/macos/host/host_pairing_authority.dart';
import '../../platform/macos/host/host_wss_transport.dart';

class MacHostSettingsPanel extends StatefulWidget {
  const MacHostSettingsPanel({
    super.key,
    required this.hostControl,
    required this.pairingControl,
  });

  final HostControlPort hostControl;
  final HostPairingControlPort pairingControl;

  @override
  State<MacHostSettingsPanel> createState() => _MacHostSettingsPanelState();
}

class _MacHostSettingsPanelState extends State<MacHostSettingsPanel> {
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
    required bool setup,
  }) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.pairingControl.approvePending(
        request.deviceId,
        scopes: {
          HostGrantScope.readConnections,
          if (setup) HostGrantScope.connectionSetup,
        },
      );
      await _refreshPairings(force: true);
    } catch (_) {
      if (mounted) setState(() => _error = '批准设备失败，请刷新后重试。');
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('撤销设备配对？'),
        content: Text('撤销后，${grant.displayName} 的 Host 会话会立即断开，相关向导草稿也会清理。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('撤销设备'),
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
    return Card.outlined(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.lan_outlined,
                  color: _statusColor(theme.colorScheme),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Mac Host', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text(
                        '允许已批准的 Android 设备使用这台 Mac 上登记的连接。关闭应用或停止 Host 后，手机显示离线。',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                FilledButton.icon(
                  onPressed: _busy ? null : () => _setRunning(!running),
                  icon: _busy
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          running
                              ? Icons.stop_circle_outlined
                              : Icons.play_circle_outline,
                        ),
                  label: Text(running ? '停止 Host' : '启动 Host'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Semantics(
              liveRegion: true,
              child: Row(
                children: [
                  Icon(
                    running ? Icons.check_circle_outline : Icons.info_outline,
                    size: 18,
                    color: _statusColor(theme.colorScheme),
                  ),
                  const SizedBox(width: 8),
                  Text('状态：${_phaseLabel(_status)}'),
                ],
              ),
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
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 12,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('配对邀请', style: theme.textTheme.titleSmall),
                      const SizedBox(height: 4),
                      Text(
                        '二维码只包含短时邀请和 Host 地址，不含长期设备密钥。',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _createInvitation,
                    icon: const Icon(Icons.qr_code_2),
                    label: const Text('生成新邀请'),
                  ),
                ],
              ),
              if (invitation != null) ...[
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final qr = Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: QrImageView(
                        data: invitation.qrPayload,
                        size: 220,
                        backgroundColor: Colors.white,
                        semanticsLabel: 'Aggregate Mac Host 配对二维码',
                      ),
                    );
                    final details = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '有效期至 ${invitation.invitation.expiresAt.toLocal()}',
                        ),
                        const SizedBox(height: 8),
                        Text('${invitation.endpoints.length} 个本机网络地址'),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _copyInvitation,
                          icon: const Icon(Icons.copy_outlined),
                          label: const Text('复制配对信息'),
                        ),
                      ],
                    );
                    if (constraints.maxWidth < 520) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [qr, const SizedBox(height: 12), details],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        qr,
                        const SizedBox(width: 20),
                        Expanded(child: details),
                      ],
                    );
                  },
                ),
              ],
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Text('待处理设备', style: theme.textTheme.titleSmall),
                  ),
                  IconButton(
                    tooltip: '刷新配对设备',
                    onPressed: _busy ? null : _refreshPairings,
                    icon: const Icon(Icons.refresh),
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
                const SizedBox(height: 16),
                Text('已配对设备', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                for (final grant in _paired) _pairedCard(grant, theme),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _pendingCard(HostPendingPairing request, ThemeData theme) => Card(
    color: theme.colorScheme.surfaceContainerLow,
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(request.displayName, style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            '${request.platform} · 确认码 ${request.confirmationCode}',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: _busy ? null : () => _reject(request),
                child: const Text('拒绝'),
              ),
              OutlinedButton(
                onPressed: _busy ? null : () => _approve(request, setup: false),
                child: const Text('批准只读'),
              ),
              FilledButton(
                onPressed: _busy ? null : () => _approve(request, setup: true),
                child: const Text('允许连接向导'),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _pairedCard(HostDeviceGrant grant, ThemeData theme) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
    leading: const Icon(Icons.devices_outlined),
    title: Text(grant.displayName),
    subtitle: Text(
      grant.scopes.map(_scopeLabel).join(' · '),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    ),
    trailing: TextButton(
      onPressed: _busy ? null : () => _revoke(grant),
      child: const Text('撤销'),
    ),
  );
}
