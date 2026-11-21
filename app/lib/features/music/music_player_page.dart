import 'dart:async';

import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../widgets/glass/aggregate_buttons.dart';
import '../../widgets/glass/glass_alert_dialog.dart';
import '../../widgets/glass/glass_action_button.dart';
import '../../widgets/glass/glass_design_tokens.dart';
import '../../widgets/glass/glass_glyph.dart';
import '../../widgets/glass/glass_motion.dart';
import '../../widgets/glass/glass_panel_surface.dart';
import '../../widgets/page_frame.dart';
import 'music_mini_player.dart';
import 'music_search_results.dart';
import 'music_session.dart';
import 'music_account_control.dart';

/// A connection home selected by music presentation metadata. All commands
/// still run through RuntimePort; this widget owns only search and layout.
class MusicPlayerPage extends StatefulWidget {
  const MusicPlayerPage({
    super.key,
    required this.connection,
    required this.capabilities,
    required this.runtime,
    required this.session,
    this.showPreviewSample = false,
    this.onAccountChanged,
  });

  final Connection connection;
  final List<Capability> capabilities;
  final RuntimePort runtime;
  final MusicSession session;
  final bool showPreviewSample;
  final VoidCallback? onAccountChanged;

  @override
  State<MusicPlayerPage> createState() => _MusicPlayerPageState();
}

class _MusicPlayerPageState extends State<MusicPlayerPage> {
  final query = TextEditingController();
  final queryFocus = FocusNode();
  List<MusicSearchItem> songs = const [];
  String? searchError;
  bool searching = false;
  bool confirmingSearch = false;
  bool searched = false;
  RunId? searchRun;
  StreamSubscription<RunEvent>? searchSubscription;
  int searchGeneration = 0;
  bool previewSampleLoaded = false;

  bool _usesGlassButtons(BuildContext context) =>
      defaultTargetPlatform == TargetPlatform.macOS &&
      GlassMotionScope.maybeOf(context) != null;

  Capability? get searchAction {
    for (final item in widget.capabilities) {
      if (item.presentation == 'music.search') return item;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    unawaited(_attach());
  }

  Future<void> _attach() async {
    final action = searchAction;
    if (action == null) return;
    try {
      await widget.session.attach(action);
      if (!mounted ||
          widget.session.connection?.value != widget.connection.id.value) {
        return;
      }
      if (widget.showPreviewSample) {
        _loadPreviewSample();
      } else if (!widget.runtime.isPreview &&
          widget.session.accountState != AccountState.signedOut &&
          widget.session.actions.containsKey('music.state')) {
        unawaited(widget.session.execute('state'));
      }
    } catch (cause) {
      if (mounted) setState(() => searchError = '读取音乐连接失败：$cause');
    }
  }

  void _loadPreviewSample() {
    if (previewSampleLoaded) return;
    previewSampleLoaded = true;
    widget.session.showPreviewSample();
    setState(() {
      searched = true;
      songs = const [
        MusicSearchItem(
          id: 'PREVIEW00000000000000000000000001',
          originalId: '123',
          name: '示例歌曲',
          artist: '示例歌手',
          playable: true,
        ),
        MusicSearchItem(
          id: 'PREVIEW00000000000000000000000002',
          originalId: '124',
          name: '暂不可播放的歌曲',
          artist: '示例歌手',
          playable: false,
        ),
      ];
    });
  }

  @override
  void didUpdateWidget(covariant MusicPlayerPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.capabilities != widget.capabilities ||
        oldWidget.connection.id.value != widget.connection.id.value) {
      unawaited(_attach());
    }
  }

  @override
  void dispose() {
    searchGeneration++;
    final run = searchRun;
    if (run != null) unawaited(widget.runtime.cancel(run));
    unawaited(searchSubscription?.cancel());
    query.dispose();
    queryFocus.dispose();
    super.dispose();
  }

  Future<void> search() async {
    final keyword = query.text.trim();
    final action = searchAction;
    if (keyword.isEmpty) {
      queryFocus.requestFocus();
      return;
    }
    if (widget.session.accountState == AccountState.signedOut) {
      setState(() => searchError = '请先登录网易云音乐账号。');
      return;
    }
    if (action == null || searching || confirmingSearch) return;
    if (!await _confirmSearch(action) || !mounted) return;
    final current = ++searchGeneration;
    setState(() {
      searching = true;
      searched = true;
      searchError = null;
      songs = const [];
    });
    try {
      final handle = await widget.runtime.invoke(action.id, {
        'keyword': keyword,
      }, permissionGranted: widget.session.searchAuthorized);
      if (!mounted || current != searchGeneration) {
        await widget.runtime.cancel(handle.id);
        return;
      }
      searchRun = handle.id;
      searchSubscription = widget.runtime
          .watchRun(handle.id)
          .listen(
            (event) {
              if (!mounted || current != searchGeneration) return;
              if (event.state == RunState.succeeded) {
                setState(() {
                  songs = parseMusicSearchResults(event.blocks);
                  searching = false;
                  searchRun = null;
                });
              } else if ({
                RunState.failed,
                RunState.cancelled,
                RunState.timedOut,
                RunState.outcomeUnknown,
              }.contains(event.state)) {
                setState(() {
                  searchError = event.failure?.message ?? '搜索未完成';
                  searching = false;
                  searchRun = null;
                });
              } else {
                return;
              }
              unawaited(searchSubscription?.cancel());
              searchSubscription = null;
            },
            onError: (Object cause) {
              if (!mounted || current != searchGeneration) return;
              setState(() {
                searchError = '搜索失败：$cause';
                searching = false;
                searchRun = null;
              });
            },
          );
    } catch (cause) {
      if (mounted && current == searchGeneration) {
        setState(() {
          searchError = '搜索失败：$cause';
          searching = false;
          searchRun = null;
        });
      }
    }
  }

  Future<bool> _confirmSearch(Capability action) async {
    if (widget.runtime.isPreview ||
        action.permission == PermissionLevel.read ||
        widget.session.searchAuthorized) {
      return true;
    }
    final connectionId = widget.connection.id.value;
    setState(() => confirmingSearch = true);
    try {
      final confirmed = await showGlassDialog<bool>(
        context: context,
        builder: (_) => GlassAlertDialog(
          title: const Text('允许搜索歌曲？'),
          content: Text(
            '搜索词将交给 ${widget.connection.label} 的 CLI 执行。'
            '本次 App 会话中，该连接的后续搜索不再询问。',
          ),
          actions: [
            AggregateActionButton(
              label: '取消',
              icon: Icons.close,
              style: AggregateActionStyle.quiet,
              onPressed: () => Navigator.pop(context, false),
            ),
            AggregateActionButton(
              label: '允许搜索',
              icon: Icons.search,
              style: AggregateActionStyle.primary,
              onPressed: () => Navigator.pop(context, true),
            ),
          ],
        ),
      );
      if (!mounted || widget.connection.id.value != connectionId) return false;
      if (confirmed != true) return false;
      widget.session.authorizeSearch();
      return true;
    } finally {
      if (mounted) setState(() => confirmingSearch = false);
    }
  }

  Future<bool> _confirmSong(MusicSearchItem song, String action) async {
    if (widget.runtime.isPreview || widget.session.controlsAuthorized) {
      return true;
    }
    final confirmed =
        await showGlassDialog<bool>(
          context: context,
          builder: (_) => GlassAlertDialog(
            title: Text('$action ${song.name}？'),
            content: Text('通过 ${widget.connection.label} 控制播放。'),
            actions: [
              AggregateActionButton(
                label: '取消',
                icon: Icons.close,
                style: AggregateActionStyle.quiet,
                onPressed: () => Navigator.pop(context, false),
              ),
              AggregateActionButton(
                label: '执行',
                icon: Icons.play_arrow,
                style: AggregateActionStyle.primary,
                onPressed: () => Navigator.pop(context, true),
              ),
            ],
          ),
        ) ??
        false;
    if (confirmed) widget.session.authorizeControls();
    return confirmed;
  }

  Future<void> _play(MusicSearchItem song) async {
    if (!await _confirmSong(song, '播放') || !mounted) return;
    if (widget.session.busy) return;
    widget.session.prepareTrack(song.name, song.artist);
    await widget.session.execute('play', {
      'encryptedId': song.id,
      'originalId': song.originalId,
    });
  }

  Future<void> _queue(MusicSearchItem song) async {
    if (!await _confirmSong(song, '加入下一首') || !mounted) return;
    if (widget.session.busy) return;
    await widget.session.execute('queueAdd', {
      'encryptedId': song.id,
      'originalId': song.originalId,
    });
  }

  Future<void> _beforeAccountChange() async {
    if (widget.session.visible &&
        widget.session.playing != false &&
        widget.session.actions.containsKey('music.stop')) {
      try {
        await widget.session
            .execute('stop')
            .timeout(const Duration(seconds: 5));
      } on TimeoutException {
        // Account changes must not wait indefinitely for a player daemon.
      }
    }
  }

  void _accountStatus(AccountSnapshot snapshot) {
    if (!mounted) return;
    if (snapshot.state == AccountState.signedOut &&
        widget.session.accountState != AccountState.signedOut) {
      _accountChanged(snapshot);
      return;
    }
    widget.session.accountState = snapshot.state;
  }

  void _accountChanged(AccountSnapshot snapshot) {
    if (!mounted) return;
    searchGeneration++;
    if (searchRun case final run?) unawaited(widget.runtime.cancel(run));
    unawaited(searchSubscription?.cancel());
    searchSubscription = null;
    searchRun = null;
    query.clear();
    widget.session.resetForAccountChange(snapshot.state);
    setState(() {
      songs = const [];
      searched = false;
      searching = false;
      searchError = null;
    });
    widget.onAccountChanged?.call();
  }

  @override
  Widget build(BuildContext context) => PageFrame(
    title: defaultTargetPlatform == TargetPlatform.macOS
        ? widget.connection.label
        : '音乐播放器',
    subtitle: widget.connection.executionTarget.kind == ExecutionTargetKind.host
        ? '音乐播放器 · 声音由配对 Mac 输出'
        : '播放、搜索和账号状态来自同一音乐会话',
    trailing:
        defaultTargetPlatform != TargetPlatform.macOS &&
            widget.runtime is ConnectionAccountPort
        ? MusicAccountControl(
            connection: widget.connection,
            runtime: widget.runtime,
            accounts: widget.runtime as ConnectionAccountPort,
            beforeChange: _beforeAccountChange,
            onChanged: _accountChanged,
            onStatus: _accountStatus,
          )
        : null,
    headerSpacing: 23,
    children: [
      LayoutBuilder(
        builder: (context, constraints) {
          // The two-column macOS player needs enough room for its artwork,
          // details, and account actions. Switch to the compact arrangement
          // before the player card becomes too narrow for the account row.
          final compact = constraints.maxWidth < 820;
          final accountControl =
              defaultTargetPlatform == TargetPlatform.macOS &&
                  widget.runtime is ConnectionAccountPort
              ? MusicAccountControl(
                  connection: widget.connection,
                  runtime: widget.runtime,
                  accounts: widget.runtime as ConnectionAccountPort,
                  beforeChange: _beforeAccountChange,
                  onChanged: _accountChanged,
                  onStatus: _accountStatus,
                )
              : null;
          final player = _player(
            context,
            compact: compact,
            accountControl: accountControl,
          );
          final library = _library(context);
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [player, const SizedBox(height: 20), library],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 468, child: player),
              const SizedBox(width: 38),
              Expanded(
                flex: 522,
                child: Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: library,
                ),
              ),
            ],
          );
        },
      ),
    ],
  );

  Widget _player(
    BuildContext context, {
    required bool compact,
    required Widget? accountControl,
  }) => AnimatedBuilder(
    animation: widget.session,
    builder: (context, _) {
      if (!compact && defaultTargetPlatform == TargetPlatform.macOS) {
        return _widePlayer(
          context,
          widget.session,
          accountControl: accountControl,
        );
      }
      final session = widget.session;
      final scheme = Theme.of(context).colorScheme;
      final hasTrack = session.visible && session.title != '播放状态待读取';
      final canToggle = session.playing == true
          ? session.actions.containsKey('music.pause')
          : session.queueLength > 0 &&
                session.actions.containsKey('music.resume');
      final artwork = ExcludeSemantics(
        child: Container(
          width: compact ? 88 : 150,
          height: compact ? 88 : 150,
          decoration: BoxDecoration(
            color: scheme.primaryContainer,
            borderRadius: BorderRadius.circular(compact ? 14 : 20),
          ),
          child: Icon(
            Icons.music_note_rounded,
            size: compact ? 40 : 64,
            color: scheme.onPrimaryContainer,
          ),
        ),
      );
      final trackDetails = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            hasTrack ? session.title : '从搜索开始播放',
            maxLines: compact ? 1 : 2,
            overflow: TextOverflow.ellipsis,
            style: compact
                ? Theme.of(context).textTheme.titleMedium
                : Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 4),
          Text(
            hasTrack
                ? (session.artist ?? widget.connection.label)
                : widget.connection.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          Text(
            session.detail.isEmpty ? '搜索歌曲，选择一首开始播放。' : session.detail,
            maxLines: compact ? 2 : 3,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      );
      return Container(
        padding: EdgeInsets.all(compact ? 18 : 24),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('播放器', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                Text(
                  session.visible ? session.playbackStatus : '尚未播放',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            SizedBox(height: compact ? 16 : 24),
            if (compact)
              Row(
                children: [
                  artwork,
                  const SizedBox(width: 16),
                  Expanded(child: trackDetails),
                ],
              )
            else ...[
              Center(child: artwork),
              const SizedBox(height: 24),
              trackDetails,
            ],
            SizedBox(height: compact ? 12 : 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (session.actions.containsKey('music.prev'))
                  _semanticIconButton(
                    label: '上一首',
                    onPressed: session.busy || !session.canPrev
                        ? null
                        : () => confirmMusicControl(
                            context,
                            session,
                            'prev',
                            '上一首',
                          ),
                    icon: Icons.skip_previous_rounded,
                  ),
                const SizedBox(width: 8),
                _semanticIconButton(
                  label: session.playing == true ? '暂停' : '继续播放',
                  filled: true,
                  onPressed:
                      session.busy ||
                          session.playbackStatus == '正在确认' ||
                          !canToggle
                      ? null
                      : () => confirmMusicControl(
                          context,
                          session,
                          session.playing == true ? 'pause' : 'resume',
                          session.playing == true ? '暂停' : '继续播放',
                        ),
                  icon: session.playing == true
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                ),
                const SizedBox(width: 8),
                if (session.actions.containsKey('music.next'))
                  _semanticIconButton(
                    label: '下一首',
                    onPressed: session.busy || !session.canNext
                        ? null
                        : () => confirmMusicControl(
                            context,
                            session,
                            'next',
                            '下一首',
                          ),
                    icon: Icons.skip_next_rounded,
                  ),
                if (session.actions.containsKey('music.state') &&
                    !(defaultTargetPlatform == TargetPlatform.macOS &&
                        accountControl != null)) ...[
                  const SizedBox(width: 8),
                  _semanticIconButton(
                    label: '刷新播放状态',
                    onPressed: session.busy
                        ? null
                        : () => session.execute('state'),
                    icon: Icons.refresh_rounded,
                  ),
                ],
              ],
            ),
            if (defaultTargetPlatform == TargetPlatform.macOS &&
                accountControl != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  if (session.actions.containsKey('music.state'))
                    SizedBox(
                      width: 132,
                      height: 40,
                      child: AggregateActionButton(
                        key: const Key('music-refresh-status'),
                        label: '刷新状态',
                        icon: Icons.refresh_rounded,
                        onPressed: session.busy
                            ? null
                            : () => session.execute('state'),
                        enabled: !session.busy,
                        style: AggregateActionStyle.secondary,
                        size: GlassButtonSize.compactAction,
                        expand: true,
                      ),
                    ),
                  if (session.actions.containsKey('music.state'))
                    const SizedBox(width: 12),
                  SizedBox(width: 132, height: 40, child: accountControl),
                ],
              ),
            ],
            if (session.actions.containsKey('music.stop') && hasTrack)
              Center(
                child: _usesGlassButtons(context)
                    ? AggregateActionButton(
                        label: '停止播放',
                        icon: Icons.stop_circle_outlined,
                        style: AggregateActionStyle.quiet,
                        onPressed: session.busy
                            ? null
                            : () => confirmMusicControl(
                                context,
                                session,
                                'stop',
                                '停止播放',
                              ),
                        enabled: !session.busy,
                      )
                    : TextButton(
                        onPressed: session.busy
                            ? null
                            : () => confirmMusicControl(
                                context,
                                session,
                                'stop',
                                '停止播放',
                              ),
                        child: const Text('停止播放'),
                      ),
              ),
          ],
        ),
      );
    },
  );

  Widget _widePlayer(
    BuildContext context,
    MusicSession session, {
    required Widget? accountControl,
  }) {
    final theme = Theme.of(context);
    final tokens =
        theme.extension<GlassDesignTokens>() ??
        GlassDesignTokens.forBrightness(theme.brightness);
    final hasTrack = session.visible && session.title != '播放状态待读取';
    final playbackLabel = session.playing == true ? '暂停' : '继续播放';
    final canToggle = session.playing == true
        ? session.actions.containsKey('music.pause')
        : session.queueLength > 0 &&
              session.actions.containsKey('music.resume');
    final controls = <Widget>[];
    if (session.actions.containsKey('music.prev')) {
      controls.add(
        _semanticIconButton(
          label: '上一首',
          playbackControl: true,
          onPressed: session.busy || !session.canPrev
              ? null
              : () => confirmMusicControl(context, session, 'prev', '上一首'),
          icon: Icons.skip_previous_rounded,
        ),
      );
    }
    controls.add(
      _semanticIconButton(
        label: playbackLabel,
        filled: true,
        playbackControl: true,
        onPressed:
            session.busy || session.playbackStatus == '正在确认' || !canToggle
            ? null
            : () => confirmMusicControl(
                context,
                session,
                session.playing == true ? 'pause' : 'resume',
                playbackLabel,
              ),
        icon: session.playing == true
            ? Icons.pause_rounded
            : Icons.play_arrow_rounded,
      ),
    );
    if (session.actions.containsKey('music.next')) {
      controls.add(
        _semanticIconButton(
          label: '下一首',
          playbackControl: true,
          onPressed: session.busy || !session.canNext
              ? null
              : () => confirmMusicControl(context, session, 'next', '下一首'),
          icon: Icons.skip_next_rounded,
        ),
      );
    }
    if (session.actions.containsKey('music.stop') && hasTrack) {
      controls.add(
        _semanticIconButton(
          label: '停止播放',
          playbackControl: true,
          onPressed: session.busy
              ? null
              : () => confirmMusicControl(context, session, 'stop', '停止播放'),
          icon: Icons.stop_circle_outlined,
        ),
      );
    }

    return GlassPanelSurface(
      key: const Key('music-player-section'),
      borderRadius: const BorderRadius.all(Radius.circular(19)),
      shadowOpacity: .035,
      shadowBlurRadius: 7,
      shadowOffset: const Offset(0, 1),
      child: SizedBox(
        key: const Key('music-player-card'),
        height: 530,
        width: double.infinity,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(30, 24, 30, 65),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 20,
                child: Row(
                  children: [
                    Text('播放器', style: theme.textTheme.titleMedium),
                    const Spacer(),
                    if (session.visible) ...[
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: tokens.status,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 7),
                    ],
                    Text(
                      session.visible ? session.playbackStatus : '尚未播放',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: session.visible ? tokens.status : tokens.muted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    key: const Key('music-player-artwork'),
                    width: 150,
                    height: 150,
                    decoration: BoxDecoration(
                      color: tokens.inset,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: tokens.line.withValues(alpha: .82),
                      ),
                    ),
                    child: Center(
                      child: GlassGlyphMark(
                        glyph: GlassGlyph.music,
                        size: 56,
                        color: tokens.ink,
                      ),
                    ),
                  ),
                  const SizedBox(width: 22),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          hasTrack ? session.title : '从搜索开始播放',
                          key: const Key('music-player-title'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontSize: 18,
                            height: 24 / 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          hasTrack
                              ? (session.artist ?? widget.connection.label)
                              : widget.connection.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          session.detail.isEmpty
                              ? '搜索歌曲，选择一首开始播放。'
                              : session.detail,
                          key: const Key('music-player-progress'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 34),
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Row(
                  children: [
                    for (var index = 0; index < controls.length; index++) ...[
                      if (index > 0) const SizedBox(width: 14),
                      controls[index],
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 32),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '播放信息',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: tokens.muted,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${widget.connection.label} · ${session.outputLocation}',
                    key: const Key('music-playback-information'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: tokens.text,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 47),
              if (session.actions.containsKey('music.state') ||
                  accountControl != null)
                Row(
                  children: [
                    if (session.actions.containsKey('music.state'))
                      SizedBox(
                        key: const Key('music-refresh-status-frame'),
                        width: 132,
                        height: 40,
                        child: AggregateActionButton(
                          key: const Key('music-refresh-status'),
                          label: '刷新状态',
                          icon: Icons.refresh_rounded,
                          onPressed: session.busy
                              ? null
                              : () => session.execute('state'),
                          enabled: !session.busy,
                          style: AggregateActionStyle.secondary,
                          size: GlassButtonSize.compactAction,
                          expand: true,
                        ),
                      ),
                    if (session.actions.containsKey('music.state') &&
                        accountControl != null)
                      const SizedBox(width: 12),
                    if (accountControl != null)
                      SizedBox(
                        key: const Key('music-account-frame'),
                        width: 132,
                        height: 40,
                        child: accountControl,
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _library(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        '找音乐',
        style: Theme.of(context).textTheme.titleMedium
            ?.copyWith(height: 20 / 16),
      ),
      const SizedBox(height: 4),
      Text(
        '搜索歌曲并查看结果',
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(fontSize: 11, height: 14 / 11),
      ),
      const SizedBox(height: 4),
      LayoutBuilder(
        builder: (context, constraints) {
          final wideMac =
              defaultTargetPlatform == TargetPlatform.macOS &&
              constraints.maxWidth >= 420;
          final input = SizedBox(
            height: wideMac ? 44 : null,
            child: TextField(
              key: const Key('music-search'),
              controller: query,
              focusNode: queryFocus,
              style: wideMac
                  ? Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(fontSize: 13, fontWeight: FontWeight.w400)
                  : null,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                constraints: wideMac
                    ? const BoxConstraints.tightFor(height: 44)
                    : null,
                isDense: wideMac,
                contentPadding: wideMac
                    ? const EdgeInsets.symmetric(horizontal: 14, vertical: 10)
                    : null,
                labelText: wideMac ? null : '搜索歌曲',
                hintText: wideMac ? '搜索歌曲' : '歌曲或歌手',
                hintStyle: wideMac
                    ? Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        color: Theme.of(context)
                            .extension<GlassDesignTokens>()
                            ?.muted,
                      )
                    : null,
                prefixIcon: wideMac
                    ? ExcludeSemantics(
                        child: Padding(
                          padding: const EdgeInsets.only(left: 13, right: 10),
                          child: GlassGlyphMark(
                            glyph: GlassGlyph.search,
                            size: 18,
                            color: Theme.of(context)
                                .extension<GlassDesignTokens>()
                                ?.muted,
                          ),
                        ),
                      )
                    : const Icon(Icons.search, size: 18),
                prefixIconConstraints: wideMac
                    ? const BoxConstraints(minWidth: 42, maxWidth: 42)
                    : null,
                suffixIconConstraints: wideMac
                    ? const BoxConstraints(minWidth: 46, maxWidth: 46)
                    : null,
                suffixIcon: wideMac
                    ? null
                    : _semanticIconButton(
                        label: '搜索歌曲',
                        onPressed: searching || confirmingSearch
                            ? null
                            : search,
                        icon: Icons.search,
                      ),
              ),
              onSubmitted: (_) => search(),
            ),
          );
          if (!wideMac) return input;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              input,
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: SizedBox(
                  width: 134,
                  height: 46,
                  child: AggregateActionButton(
                    key: const Key('music-search-submit'),
                    label: '搜索',
                    icon: Icons.search,
                    onPressed: searching || confirmingSearch ? null : search,
                    enabled: !searching && !confirmingSearch,
                    style: AggregateActionStyle.primary,
                    size: GlassButtonSize.primary,
                    expand: true,
                  ),
                ),
              ),
            ],
          );
        },
      ),
      const SizedBox(height: 12),
      if (searching) const LinearProgressIndicator(),
      if (searchError case final message?) ...[
        Text(
          message,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
        const SizedBox(height: 12),
      ],
      if (!searched)
        Text('搜索结果会显示在这里。', style: Theme.of(context).textTheme.bodySmall)
      else if (!searching && searchError == null && songs.isEmpty)
        const Text('没有找到歌曲，换个歌名或歌手再试。')
      else if (songs.isNotEmpty)
        AnimatedBuilder(
          animation: widget.session,
          builder: (context, _) => MusicSearchResults(
            items: songs,
            onPlay: (song) => unawaited(_play(song)),
            onQueue:
                widget.session.queueLength > 0 &&
                    widget.session.actions.containsKey('music.queueAdd')
                ? (song) => unawaited(_queue(song))
                : null,
            busy: widget.session.busy || searching,
            boardRowStyle: true,
          ),
        ),
    ],
  );

  Widget _semanticIconButton({
    required String label,
    required VoidCallback? onPressed,
    required IconData icon,
    bool filled = false,
    bool playbackControl = false,
  }) {
    if (_usesGlassButtons(context)) {
      return AggregateIconButton(
        tooltip: label,
        icon: icon,
        onPressed: onPressed,
        enabled: onPressed != null,
        selected: filled && label == '暂停',
        kind: playbackControl
            ? GlassButtonKind.musicControl
            : filled
            ? GlassButtonKind.primary
            : GlassButtonKind.icon,
        size: playbackControl
            ? GlassButtonSize.musicControl
            : filled
            ? GlassButtonSize.playback
            : GlassButtonSize.icon,
      );
    }
    return Semantics(
      container: true,
      label: label,
      button: true,
      enabled: onPressed != null,
      onTap: onPressed,
      child: ExcludeSemantics(
        child: filled
            ? IconButton.filled(
                tooltip: label,
                onPressed: onPressed,
                icon: Icon(icon),
              )
            : IconButton(
                tooltip: label,
                onPressed: onPressed,
                icon: Icon(icon),
              ),
      ),
    );
  }
}
