import 'dart:async';

import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:flutter/material.dart';
import 'package:terminal_view/terminal_view.dart';

/// A small account entry in the player heading. Provider work stays in the
/// optional account port; other CLI and MCP connections never show it.
class MusicAccountControl extends StatefulWidget {
  const MusicAccountControl({
    super.key,
    required this.connection,
    required this.runtime,
    required this.accounts,
    required this.beforeChange,
    required this.onChanged,
    required this.onStatus,
  });

  final Connection connection;
  final RuntimePort runtime;
  final ConnectionAccountPort accounts;
  final Future<void> Function() beforeChange;
  final ValueChanged<AccountSnapshot> onChanged;
  final ValueChanged<AccountSnapshot> onStatus;

  @override
  State<MusicAccountControl> createState() => _MusicAccountControlState();
}

class _MusicAccountControlState extends State<MusicAccountControl> {
  AccountSnapshot? snapshot;
  int generation = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  @override
  void didUpdateWidget(covariant MusicAccountControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.connection.id.value != widget.connection.id.value) {
      snapshot = null;
      unawaited(_refresh());
    }
  }

  Future<void> _refresh() async {
    final current = ++generation;
    try {
      final result = await widget.accounts.readAccount(widget.connection.id);
      if (mounted && current == generation) {
        setState(() => snapshot = result);
        if (result != null) widget.onStatus(result);
      }
    } catch (_) {
      if (mounted && current == generation) {
        setState(
          () => snapshot = const AccountSnapshot(
            AccountState.unknown,
            message: '账号状态检查失败，请重试。',
          ),
        );
      }
    }
  }

  Future<void> _open() async {
    final current = snapshot;
    if (current == null) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _AccountDialog(
        connection: widget.connection,
        runtime: widget.runtime,
        accounts: widget.accounts,
        initial: current,
        beforeChange: widget.beforeChange,
        onChanged: widget.onChanged,
      ),
    );
    if (mounted) unawaited(_refresh());
  }

  @override
  Widget build(BuildContext context) {
    final current = snapshot;
    if (current == null) return const SizedBox.shrink();
    final label = switch (current.state) {
      AccountState.signedIn => current.nickname ?? '已登录',
      AccountState.signedOut => '登录账号',
      AccountState.unknown => '账号状态待确认',
    };
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 190),
      child: Tooltip(
        message: '管理网易云音乐账号',
        child: Semantics(
          label: '管理网易云音乐账号，$label',
          button: true,
          child: TextButton.icon(
            key: const Key('music-account'),
            onPressed: _open,
            icon: const Icon(Icons.account_circle_outlined),
            label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
          ),
        ),
      ),
    );
  }
}

enum _AccountPhase { idle, starting, scanning, verifying, signingOut }

class _AccountDialog extends StatefulWidget {
  const _AccountDialog({
    required this.connection,
    required this.runtime,
    required this.accounts,
    required this.initial,
    required this.beforeChange,
    required this.onChanged,
  });

  final Connection connection;
  final RuntimePort runtime;
  final ConnectionAccountPort accounts;
  final AccountSnapshot initial;
  final Future<void> Function() beforeChange;
  final ValueChanged<AccountSnapshot> onChanged;

  @override
  State<_AccountDialog> createState() => _AccountDialogState();
}

class _AccountDialogState extends State<_AccountDialog> {
  late AccountSnapshot snapshot = widget.initial;
  _AccountPhase phase = _AccountPhase.idle;
  String? notice;
  bool noticeIsError = false;
  Terminal terminal = Terminal(maxLines: 800);
  TerminalSession? loginSession;
  StreamSubscription<String>? outputSubscription;
  Timer? loginTimeout;
  int operation = 0;

  @override
  void dispose() {
    operation++;
    loginTimeout?.cancel();
    final session = loginSession;
    if (session != null) unawaited(widget.runtime.closeTerminal(session));
    unawaited(outputSubscription?.cancel());
    super.dispose();
  }

  bool get busy => phase != _AccountPhase.idle;

  Future<void> _refresh() async {
    if (busy) return;
    setState(() {
      notice = null;
      noticeIsError = false;
    });
    try {
      final result = await widget.accounts.readAccount(widget.connection.id);
      if (mounted) {
        setState(() {
          snapshot =
              result ??
              const AccountSnapshot(
                AccountState.unknown,
                message: '此连接不支持账号管理。',
              );
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          notice = '账号状态读取失败，请重试。';
          noticeIsError = true;
        });
      }
    }
  }

  Future<bool> _confirm(String title, String detail, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(title),
          content: Text(detail),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _logout({required bool switchAccount}) async {
    if (busy || snapshot.state != AccountState.signedIn) return;
    final confirmed = await _confirm(
      switchAccount ? '切换账号？' : '退出登录？',
      switchAccount
          ? '将先退出当前账号，再用网易云音乐 App 扫码登录新账号。若中途取消，当前连接会保持未登录。'
          : '将退出此设备上 ncm-cli 的当前网易云音乐账号。',
      switchAccount ? '退出并切换' : '退出登录',
    );
    if (!confirmed || !mounted) return;
    setState(() {
      phase = _AccountPhase.signingOut;
      notice = null;
      noticeIsError = false;
    });
    try {
      await widget.beforeChange();
      final result = await widget.accounts.logoutAccount(
        widget.connection.id,
        confirmed: true,
      );
      if (!mounted) return;
      widget.onChanged(result);
      setState(() {
        snapshot = result;
        phase = _AccountPhase.idle;
        notice = switchAccount ? null : '已退出登录';
        noticeIsError = false;
      });
      if (switchAccount) unawaited(_startLogin());
    } catch (cause) {
      if (!mounted) return;
      AccountSnapshot? result;
      try {
        result = await widget.accounts.readAccount(widget.connection.id);
      } catch (_) {
        result = const AccountSnapshot(AccountState.unknown);
      }
      if (!mounted) return;
      widget.onChanged(result ?? const AccountSnapshot(AccountState.unknown));
      setState(() {
        snapshot = result ?? const AccountSnapshot(AccountState.unknown);
        phase = _AccountPhase.idle;
        notice = _safeError(cause);
        noticeIsError = true;
      });
    }
  }

  Future<void> _startLogin() async {
    if (busy) return;
    final current = ++operation;
    setState(() {
      phase = _AccountPhase.starting;
      notice = null;
      noticeIsError = false;
      terminal = Terminal(maxLines: 800);
    });
    try {
      final session = await widget.accounts.beginAccountLogin(
        widget.connection.id,
      );
      if (!mounted || current != operation) {
        await widget.runtime.closeTerminal(session);
        return;
      }
      loginSession = session;
      terminal.onOutput = (text) {
        if (loginSession?.id == session.id) {
          unawaited(widget.runtime.writeTerminal(session, text));
        }
      };
      terminal.onResize = (columns, rows, _, _) {
        if (loginSession?.id == session.id) {
          unawaited(widget.runtime.resizeTerminal(session, columns, rows));
        }
      };
      outputSubscription = widget.runtime
          .watchTerminal(session)
          .listen(terminal.write);
      setState(() => phase = _AccountPhase.scanning);
      loginTimeout = Timer(const Duration(minutes: 3), () {
        if (mounted && current == operation) {
          unawaited(_cancelLogin(message: '二维码等待超时，请重新扫码。'));
        }
      });
      unawaited(_finishLogin(session, current));
    } catch (cause) {
      if (!mounted || current != operation) return;
      setState(() {
        phase = _AccountPhase.idle;
        notice = _safeError(cause);
        noticeIsError = true;
      });
    }
  }

  Future<void> _finishLogin(TerminalSession session, int current) async {
    try {
      final exit = await widget.accounts.waitAccountLogin(session);
      if (!mounted || current != operation) return;
      loginTimeout?.cancel();
      setState(() => phase = _AccountPhase.verifying);
      final result = await widget.accounts.readAccount(widget.connection.id);
      if (!mounted || current != operation) return;
      await _releaseLogin();
      if (!mounted || current != operation) return;
      setState(() {
        snapshot = result ?? const AccountSnapshot(AccountState.unknown);
        phase = _AccountPhase.idle;
        notice = result?.state == AccountState.signedIn
            ? '登录成功'
            : exit == 0
            ? '登录命令已结束，但未确认新账号。请重试。'
            : '登录未完成，请重新扫码。';
        noticeIsError = result?.state != AccountState.signedIn;
      });
      if (result?.state == AccountState.signedIn) widget.onChanged(result!);
    } catch (_) {
      if (!mounted || current != operation) return;
      await _releaseLogin();
      if (mounted && current == operation) {
        setState(() {
          phase = _AccountPhase.idle;
          notice = '登录会话中断，请重新扫码。';
          noticeIsError = true;
        });
      }
    }
  }

  Future<void> _releaseLogin() async {
    loginTimeout?.cancel();
    final session = loginSession;
    loginSession = null;
    final cancellation = outputSubscription?.cancel();
    outputSubscription = null;
    if (session != null) await widget.runtime.closeTerminal(session);
    if (cancellation != null) unawaited(cancellation);
  }

  Future<void> _cancelLogin({String message = '已取消登录'}) async {
    operation++;
    if (mounted) {
      setState(() {
        phase = _AccountPhase.idle;
        notice = message;
        noticeIsError = message != '已取消登录';
      });
    }
    await _releaseLogin();
  }

  String _safeError(Object cause) => cause is StateError
      ? cause.message.toString()
      : cause is TimeoutException
      ? '账号操作超时，请检查网络后重试。'
      : '账号操作失败，请检查连接后重试。';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scanning = phase == _AccountPhase.scanning;
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 600),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(Icons.account_circle_outlined),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text('网易云音乐账号', style: theme.textTheme.titleLarge),
                  ),
                  IconButton(
                    tooltip: '关闭账号面板',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(switch (snapshot.state) {
                AccountState.signedIn =>
                  '已登录 · ${snapshot.nickname ?? '网易云音乐账号'}',
                AccountState.signedOut => '当前未登录',
                AccountState.unknown => snapshot.message ?? '账号状态待确认',
              }),
              if (notice case final message?) ...[
                const SizedBox(height: 8),
                Text(
                  message,
                  style: noticeIsError
                      ? TextStyle(color: theme.colorScheme.error)
                      : theme.textTheme.bodyMedium,
                ),
              ],
              const SizedBox(height: 16),
              if (phase == _AccountPhase.starting ||
                  phase == _AccountPhase.verifying ||
                  phase == _AccountPhase.signingOut) ...[
                const LinearProgressIndicator(),
                const SizedBox(height: 12),
                Text(switch (phase) {
                  _AccountPhase.starting => '正在生成登录二维码…',
                  _AccountPhase.verifying => '正在确认新账号…',
                  _ => '正在退出登录…',
                }),
              ],
              if (scanning) ...[
                const Text('使用网易云音乐 App 扫描下方二维码并在手机上确认。'),
                const SizedBox(height: 8),
                SizedBox(
                  height: 320,
                  width: double.infinity,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: TerminalView(
                      terminal,
                      autofocus: true,
                      textStyle: const TerminalStyle(fontSize: 7),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (scanning)
                    TextButton(
                      onPressed: _cancelLogin,
                      child: const Text('取消扫码'),
                    )
                  else ...[
                    TextButton(
                      onPressed: busy ? null : _refresh,
                      child: const Text('刷新状态'),
                    ),
                    if (snapshot.state == AccountState.signedIn) ...[
                      TextButton(
                        onPressed: busy
                            ? null
                            : () => _logout(switchAccount: false),
                        child: const Text('退出登录'),
                      ),
                      FilledButton(
                        onPressed: busy
                            ? null
                            : () => _logout(switchAccount: true),
                        child: const Text('切换账号'),
                      ),
                    ] else
                      FilledButton(
                        onPressed: busy ? null : _startLogin,
                        child: const Text('扫码登录'),
                      ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
