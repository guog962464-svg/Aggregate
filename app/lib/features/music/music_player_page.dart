import 'dart:async';

import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:flutter/material.dart';

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
    this.onAccountChanged,
  });

  final Connection connection;
  final List<Capability> capabilities;
  final RuntimePort runtime;
  final MusicSession session;
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
      if (!widget.runtime.isPreview &&
          widget.session.accountState != AccountState.signedOut &&
          widget.session.actions.containsKey('music.state')) {
        unawaited(widget.session.execute('state'));
      }
    } catch (cause) {
      if (mounted) setState(() => searchError = '读取音乐连接失败：$cause');
    }
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
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('允许搜索歌曲？'),
          content: Text(
            '搜索词将交给 ${widget.connection.label} 的 CLI 执行。'
            '本次 App 会话中，该连接的后续搜索不再询问。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('允许搜索'),
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
        await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: Text('$action ${song.name}？'),
            content: Text('通过 ${widget.connection.label} 控制播放。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('执行'),
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
    title: widget.connection.label,
    subtitle: '音乐播放器',
    trailing: widget.runtime is ConnectionAccountPort
        ? MusicAccountControl(
            connection: widget.connection,
            runtime: widget.runtime,
            accounts: widget.runtime as ConnectionAccountPort,
            beforeChange: _beforeAccountChange,
            onChanged: _accountChanged,
            onStatus: _accountStatus,
          )
        : null,
    children: [
      LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 700;
          final player = _player(context, compact: compact);
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
              Expanded(flex: 4, child: player),
              const SizedBox(width: 24),
              Expanded(flex: 6, child: library),
            ],
          );
        },
      ),
    ],
  );

  Widget _player(BuildContext context, {required bool compact}) =>
      AnimatedBuilder(
        animation: widget.session,
        builder: (context, _) {
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
                    if (session.actions.containsKey('music.state')) ...[
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
                if (session.actions.containsKey('music.stop') && hasTrack)
                  Center(
                    child: TextButton(
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

  Widget _library(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('找音乐', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 12),
      TextField(
        key: const Key('music-search'),
        controller: query,
        focusNode: queryFocus,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          labelText: '搜索歌曲',
          hintText: '歌曲或歌手',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _semanticIconButton(
            label: '搜索歌曲',
            onPressed: searching || confirmingSearch ? null : search,
            icon: Icons.arrow_forward_rounded,
          ),
        ),
        onSubmitted: (_) => search(),
      ),
      const SizedBox(height: 16),
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
          ),
        ),
    ],
  );

  Widget _semanticIconButton({
    required String label,
    required VoidCallback? onPressed,
    required IconData icon,
    bool filled = false,
  }) => Semantics(
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
          : IconButton(tooltip: label, onPressed: onPressed, icon: Icon(icon)),
    ),
  );
}
