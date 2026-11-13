import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:mobile_scanner/mobile_scanner.dart';

import '../../platform/android/android_host_manager.dart';
import '../../platform/android/android_host_pairing_client.dart';

typedef AndroidHostQrScanner = Future<String?> Function(BuildContext context);

class AndroidHostSettingsPanel extends StatefulWidget {
  const AndroidHostSettingsPanel({
    super.key,
    required this.hostManager,
    this.scanQr,
  });

  final AndroidHostManagerPort hostManager;
  final AndroidHostQrScanner? scanQr;

  @override
  State<AndroidHostSettingsPanel> createState() =>
      _AndroidHostSettingsPanelState();
}

class _AndroidHostSettingsPanelState extends State<AndroidHostSettingsPanel> {
  final _payloadController = TextEditingController();
  final _nameController = TextEditingController(text: '这台手机');
  AndroidHostInvitation? _pendingInvitation;
  AndroidHostPairingReceipt? _receipt;
  String? _error;
  var _busy = false;
  StreamSubscription<AndroidHostStatusChange>? _statusSubscription;

  @override
  void initState() {
    super.initState();
    _statusSubscription = widget.hostManager.statusChanges.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _statusSubscription?.cancel();
    _payloadController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    final scan = widget.scanQr ?? _showScanner;
    final payload = await scan(context);
    if (!mounted || payload == null) return;
    setState(() {
      _payloadController.text = payload;
      _error = null;
    });
  }

  Future<String?> _showScanner(BuildContext context) => Navigator.of(context)
      .push<String>(
        MaterialPageRoute<String>(builder: (_) => const _AndroidHostScanner()),
      );

  Future<void> _pasteInvitation() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (!mounted || text == null || text.isEmpty) return;
    setState(() {
      _payloadController.text = text;
      _error = null;
    });
  }

  Future<void> _requestPairing() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _receipt = null;
      _pendingInvitation = null;
    });
    try {
      final invitation = AndroidHostInvitation.fromQrPayload(
        _payloadController.text.trim(),
      );
      final receipt = await widget.hostManager.requestPairing(
        invitation: invitation,
        displayName: _nameController.text,
      );
      if (!mounted) return;
      setState(() {
        _pendingInvitation = invitation;
        _receipt = receipt;
      });
    } on AndroidHostPairingException catch (error) {
      if (mounted) setState(() => _error = _messageFor(error.failure));
    } on Object {
      if (mounted) setState(() => _error = '配对请求没有完成，请检查 Mac Host 是否运行。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _finishPairing() async {
    final invitation = _pendingInvitation;
    if (invitation == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.hostManager.completePairing(
        invitation: invitation,
        displayName: _nameController.text,
      );
      if (!mounted) return;
      setState(() {
        _pendingInvitation = null;
        _receipt = null;
        _payloadController.clear();
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Mac Host 已配对并连接')));
    } on AndroidHostPairingException catch (error) {
      if (mounted) setState(() => _error = _messageFor(error.failure));
    } on Object {
      if (mounted) setState(() => _error = '连接 Mac Host 失败，请确认两台设备位于同一局域网。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _connect(AndroidPairedHost host) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.hostManager.connect(host.hostId);
      if (mounted) setState(() {});
    } on AndroidHostPairingException catch (error) {
      if (mounted) setState(() => _error = _messageFor(error.failure));
    } on Object {
      if (mounted) setState(() => _error = '连接 Mac Host 失败，请检查局域网和 Host 状态。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnect(AndroidPairedHost host) async {
    try {
      await widget.hostManager.disconnect(host.hostId);
      if (mounted) setState(() {});
    } on Object {
      if (mounted) setState(() => _error = '断开 Mac Host 失败，请重试。');
    }
  }

  Future<void> _remove(AndroidPairedHost host) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('移除此手机上的 Host？'),
        content: Text(
          '将移除“${host.displayName}”的本机配对记录。Mac 上的授权仍需在 Mac Host 设置中撤销。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('移除记录'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.hostManager.remove(host.hostId);
      if (mounted) setState(() {});
    } on Object {
      if (mounted) setState(() => _error = '移除 Host 记录失败，请重试。');
    }
  }

  String _messageFor(AndroidHostPairingFailure failure) => switch (failure) {
    AndroidHostPairingFailure.invalidInvitation =>
      '二维码内容无效或不受支持，请从 Mac Host 设置重新生成。',
    AndroidHostPairingFailure.invitationExpired => '二维码或配对请求已过期，请重新生成二维码。',
    AndroidHostPairingFailure.invalidDisplayName => '设备名称需为 1–80 个字符。',
    AndroidHostPairingFailure.invalidDeviceIdentity =>
      'Android 安全密钥不可用，请重启应用后重试。',
    AndroidHostPairingFailure.tlsPinMismatch =>
      'Mac Host 证书与二维码不匹配，已停止连接。请重新生成二维码。',
    AndroidHostPairingFailure.hostUnavailable =>
      '找不到 Mac Host，请确认两台设备在同一局域网并且 Host 正在运行。',
    AndroidHostPairingFailure.protocolMismatch => 'Mac Host 协议版本不兼容，请升级两端应用。',
    AndroidHostPairingFailure.approvalRequired =>
      '等待 Mac 上批准此设备。批准后再点一次“已批准，连接”。',
    AndroidHostPairingFailure.alreadyPaired => '此设备已在 Mac 上配对；可从下方已保存列表连接。',
    AndroidHostPairingFailure.pairingRejected =>
      'Mac Host 拒绝了配对请求。请检查 Mac 上的配对请求。',
    AndroidHostPairingFailure.responseInvalid =>
      'Mac Host 返回了无法识别的数据，请更新两端应用后重试。',
    AndroidHostPairingFailure.requestTimedOut => 'Mac Host 响应超时，请确认网络后重试。',
    AndroidHostPairingFailure.transportClosed => 'Mac Host 连接已关闭，请重新连接。',
    AndroidHostPairingFailure.storageFailure => '无法保存 Mac Host 配对记录，请检查设备存储空间。',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hosts = widget.hostManager.hosts;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Mac Host', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          '在同一局域网内连接 Mac Host。二维码只包含局域网地址和证书指纹；设备授权需要在 Mac 上确认。',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _nameController,
          maxLength: 80,
          decoration: const InputDecoration(
            labelText: '手机显示名称',
            prefixIcon: Icon(Icons.phone_android),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _payloadController,
          minLines: 2,
          maxLines: 5,
          keyboardType: TextInputType.multiline,
          decoration: const InputDecoration(
            labelText: 'Mac Host 邀请内容',
            hintText: '扫描二维码，或粘贴邀请内容',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: _busy ? null : _scan,
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('扫描二维码'),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _pasteInvitation,
              icon: const Icon(Icons.content_paste),
              label: const Text('粘贴邀请'),
            ),
            FilledButton.icon(
              onPressed: _busy ? null : _requestPairing,
              icon: const Icon(Icons.link),
              label: const Text('请求配对'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text('相机仅在你点击扫描时使用；也可以粘贴二维码内容完成配对。', style: theme.textTheme.bodySmall),
        if (_receipt case final receipt?) ...[
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('在 Mac 上确认配对', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  const Text('请在 Mac Host 设置中找到此设备，并核对下面的验证码。'),
                  const SizedBox(height: 12),
                  Center(
                    child: SelectableText(
                      receipt.confirmationCode,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                        letterSpacing: 6,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('配对请求有效至 ${_formatTime(receipt.expiresAt)}。'),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _busy ? null : _finishPairing,
                    icon: _busy
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check_circle_outline),
                    label: const Text('已批准，连接'),
                  ),
                ],
              ),
            ),
          ),
        ],
        if (_error case final error?) ...[
          const SizedBox(height: 8),
          Semantics(
            liveRegion: true,
            child: Text(
              error,
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
        ],
        const SizedBox(height: 24),
        Text('已保存的 Mac', style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        if (hosts.isEmpty)
          Text('配对完成后会显示在这里。', style: theme.textTheme.bodyMedium)
        else
          ...hosts.map((host) {
            final status = widget.hostManager.statusFor(host.hostId);
            final connected =
                status == AndroidHostStatus.online ||
                widget.hostManager.isConnected(host.hostId);
            return Card(
              child: ListTile(
                leading: Icon(
                  status == AndroidHostStatus.online
                      ? Icons.desktop_mac
                      : Icons.desktop_windows_outlined,
                ),
                title: Text(host.displayName),
                subtitle: Text(
                  '${_hostStatusLabel(status)} · ${host.endpoints.length} 个局域网地址',
                ),
                trailing: PopupMenuButton<String>(
                  tooltip: 'Host 操作',
                  onSelected: (value) {
                    if (value == 'connect') _connect(host);
                    if (value == 'disconnect') _disconnect(host);
                    if (value == 'remove') _remove(host);
                  },
                  itemBuilder: (_) => [
                    if (connected)
                      const PopupMenuItem(
                        value: 'disconnect',
                        child: Text('断开连接'),
                      )
                    else
                      const PopupMenuItem(
                        value: 'connect',
                        child: Text('连接 Mac Host'),
                      ),
                    const PopupMenuItem(
                      value: 'remove',
                      child: Text('移除此手机上的记录'),
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  String _hostStatusLabel(AndroidHostStatus status) => switch (status) {
    AndroidHostStatus.offline => '离线',
    AndroidHostStatus.connecting => '连接中',
    AndroidHostStatus.online => '在线',
    AndroidHostStatus.authenticationInvalid => '认证失效',
    AndroidHostStatus.versionIncompatible => '版本不兼容',
    AndroidHostStatus.permissionDenied => '权限拒绝',
    AndroidHostStatus.timedOut => '请求超时',
    AndroidHostStatus.outcomeUnknown => '执行结果未知',
  };

  String _formatTime(DateTime value) {
    final local = value.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

class _AndroidHostScanner extends StatefulWidget {
  const _AndroidHostScanner();

  @override
  State<_AndroidHostScanner> createState() => _AndroidHostScannerState();
}

class _AndroidHostScannerState extends State<_AndroidHostScanner> {
  final _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
    formats: const [BarcodeFormat.qrCode],
  );
  var _returned = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_returned) return;
    String? value;
    for (final barcode in capture.barcodes) {
      if (barcode.rawValue != null) {
        value = barcode.rawValue;
        break;
      }
    }
    if (value == null) return;
    _returned = true;
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('扫描 Mac Host 二维码'),
      actions: [
        ValueListenableBuilder<MobileScannerState>(
          valueListenable: _controller,
          builder: (context, state, _) => IconButton(
            tooltip: state.torchState == TorchState.on ? '关闭手电筒' : '打开手电筒',
            onPressed: _controller.toggleTorch,
            icon: Icon(
              state.torchState == TorchState.on
                  ? Icons.flash_on
                  : Icons.flash_off,
            ),
          ),
        ),
      ],
    ),
    body: Stack(
      fit: StackFit.expand,
      children: [
        MobileScanner(
          controller: _controller,
          onDetect: _onDetect,
          errorBuilder: (context, error) => ColoredBox(
            color: Theme.of(context).colorScheme.surface,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  '无法打开相机。请允许相机访问，或返回后粘贴二维码内容。\n${error.errorCode.name}',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
          overlayBuilder: (context, constraints) => IgnorePointer(
            child: Center(
              child: Container(
                width: constraints.maxWidth * 0.72,
                height: constraints.maxWidth * 0.72,
                constraints: const BoxConstraints(
                  maxWidth: 320,
                  maxHeight: 320,
                ),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Theme.of(context).colorScheme.primary,
                    width: 3,
                  ),
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 24,
          right: 24,
          bottom: 40,
          child: Card(
            color: Theme.of(context).colorScheme.surface
                .withValues(alpha: 0.92),
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                '将 Mac Host 设置中的二维码放入取景框。扫描结果会先校验邀请内容和证书指纹。',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
