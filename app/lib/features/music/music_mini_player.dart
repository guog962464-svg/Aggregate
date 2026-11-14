import 'dart:async';

import 'package:flutter/material.dart';

import '../../widgets/glass/aggregate_buttons.dart';
import '../../widgets/glass/glass_action_button.dart';
import '../../widgets/glass/glass_motion.dart';
import 'music_session.dart';

Future<void> confirmMusicControl(
  BuildContext context,
  MusicSession session,
  String role,
  String label,
) async {
  if (role != 'state' && !session.controlsAuthorized) {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('$label？'),
        content: Text('通过 ${session.source} 执行播放控制。'),
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
    );
    if (confirmed != true) return;
    session.authorizeControls();
  }
  await session.execute(role);
}

class MusicMiniPlayer extends StatelessWidget {
  const MusicMiniPlayer({
    super.key,
    required this.session,
    this.includeBottomSafeArea = true,
    this.onOpen,
  });

  final MusicSession session;
  final bool includeBottomSafeArea;
  final VoidCallback? onOpen;

  bool _usesGlassButtons(BuildContext context) =>
      GlassMotionScope.maybeOf(context) != null;

  Widget _iconButton(
    BuildContext context, {
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
    bool primary = false,
    bool selected = false,
  }) {
    if (_usesGlassButtons(context)) {
      return AggregateIconButton(
        tooltip: label,
        icon: icon,
        onPressed: onPressed,
        enabled: onPressed != null,
        selected: selected,
        kind: primary ? GlassButtonKind.primary : GlassButtonKind.icon,
        size: primary ? GlassButtonSize.playback : GlassButtonSize.icon,
      );
    }
    return primary
        ? IconButton.filled(
            tooltip: label,
            onPressed: onPressed,
            icon: Icon(icon),
          )
        : IconButton(tooltip: label, onPressed: onPressed, icon: Icon(icon));
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: session,
    builder: (context, _) => LayoutBuilder(
      builder: (context, constraints) {
        if (!session.visible || MediaQuery.viewInsetsOf(context).bottom > 0) {
          return const SizedBox.shrink();
        }
        final compact = constraints.maxWidth < 600;
        final canToggle = session.playing == true
            ? session.actions.containsKey('music.pause')
            : session.queueLength > 0 &&
                  session.actions.containsKey('music.resume');
        return Material(
          color: Theme.of(context).colorScheme.surface,
          child: SafeArea(
            top: false,
            bottom: includeBottomSafeArea,
            child: Container(
              constraints: const BoxConstraints(minHeight: 68),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: Theme.of(context).dividerColor),
                ),
              ),
              child: compact
                  ? _compactControls(context, canToggle: canToggle)
                  : _wideControls(context, canToggle: canToggle),
            ),
          ),
        );
      },
    ),
  );

  Widget _trackSummary(BuildContext context, {required bool compact}) {
    final displayOutputLocation = compact
        ? switch (session.outputLocation) {
            '声音由配对 Mac 输出' => 'Mac 输出',
            '声音由此设备输出' => '此设备输出',
            '输出位置待确认' => '确认输出位置中',
            '执行端未知' => '输出位置未知',
            _ => session.outputLocation,
          }
        : session.outputLocation;
    return Row(
      children: [
        const Icon(Icons.music_note_outlined),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                session.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: displayOutputLocation,
                      semanticsLabel: session.outputLocation,
                    ),
                    if (session.source.isNotEmpty)
                      TextSpan(text: ' · ${session.source}'),
                    if (session.artist case final artist?
                        when artist.isNotEmpty)
                      TextSpan(text: ' · $artist'),
                    if (session.detail.isNotEmpty)
                      TextSpan(text: ' · ${session.detail}'),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _compactControls(
    BuildContext context, {
    required bool canToggle,
  }) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Row(
        children: [
          Expanded(child: _trackSummary(context, compact: true)),
          if (onOpen != null)
            _iconButton(
              context,
              label: '打开播放器',
              icon: Icons.open_in_full,
              onPressed: onOpen,
            ),
          if (session.actions.containsKey('music.stop') ||
              session.actions.containsKey('music.state'))
            PopupMenuButton<String>(
              tooltip: '更多播放操作',
              onSelected: (action) {
                final label = action == 'stop' ? '停止播放' : '刷新播放状态';
                unawaited(confirmMusicControl(context, session, action, label));
              },
              itemBuilder: (context) => [
                if (session.actions.containsKey('music.stop'))
                  const PopupMenuItem(value: 'stop', child: Text('停止播放')),
                if (session.actions.containsKey('music.state'))
                  const PopupMenuItem(value: 'state', child: Text('刷新播放状态')),
              ],
              enabled: !session.busy,
            ),
          _iconButton(
            context,
            label: '收起迷你播放器',
            icon: Icons.close,
            onPressed: session.dismiss,
          ),
        ],
      ),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (session.actions.containsKey('music.prev') && session.canPrev)
            _iconButton(
              context,
              label: '上一首',
              icon: Icons.skip_previous_rounded,
              onPressed: session.busy
                  ? null
                  : () => confirmMusicControl(context, session, 'prev', '上一首'),
            ),
          _iconButton(
            context,
            label: session.playing == true ? '暂停' : '继续播放',
            icon: session.playing == true
                ? Icons.pause_rounded
                : Icons.play_arrow_rounded,
            onPressed:
                session.busy || session.playbackStatus == '正在确认' || !canToggle
                ? null
                : () => confirmMusicControl(
                    context,
                    session,
                    session.playing == true ? 'pause' : 'resume',
                    session.playing == true ? '暂停' : '继续播放',
                  ),
            primary: true,
            selected: session.playing == true,
          ),
          if (session.actions.containsKey('music.next') && session.canNext)
            _iconButton(
              context,
              label: '下一首',
              icon: Icons.skip_next_rounded,
              onPressed: session.busy
                  ? null
                  : () => confirmMusicControl(context, session, 'next', '下一首'),
            ),
        ],
      ),
    ],
  );

  Widget _wideControls(BuildContext context, {required bool canToggle}) => Row(
    children: [
      Expanded(child: _trackSummary(context, compact: false)),
      if (session.actions.containsKey('music.prev') && session.canPrev)
        _iconButton(
          context,
          label: '上一首',
          icon: Icons.skip_previous_rounded,
          onPressed: session.busy
              ? null
              : () => confirmMusicControl(context, session, 'prev', '上一首'),
        ),
      _iconButton(
        context,
        label: session.playing == true ? '暂停' : '继续播放',
        icon: session.playing == true
            ? Icons.pause_rounded
            : Icons.play_arrow_rounded,
        onPressed:
            session.busy || session.playbackStatus == '正在确认' || !canToggle
            ? null
            : () => confirmMusicControl(
                context,
                session,
                session.playing == true ? 'pause' : 'resume',
                session.playing == true ? '暂停' : '继续播放',
              ),
        primary: true,
        selected: session.playing == true,
      ),
      if (session.actions.containsKey('music.next') && session.canNext)
        _iconButton(
          context,
          label: '下一首',
          icon: Icons.skip_next_rounded,
          onPressed: session.busy
              ? null
              : () => confirmMusicControl(context, session, 'next', '下一首'),
        ),
      if (session.actions.containsKey('music.stop'))
        _iconButton(
          context,
          label: '停止播放',
          icon: Icons.stop_circle_outlined,
          onPressed: session.busy
              ? null
              : () => confirmMusicControl(context, session, 'stop', '停止播放'),
        ),
      if (session.actions.containsKey('music.state'))
        _iconButton(
          context,
          label: '刷新播放状态',
          icon: Icons.refresh_rounded,
          onPressed: session.busy
              ? null
              : () => confirmMusicControl(context, session, 'state', '刷新播放状态'),
        ),
      if (onOpen != null)
        _iconButton(
          context,
          label: '打开播放器',
          icon: Icons.open_in_full,
          onPressed: onOpen,
        ),
      _iconButton(
        context,
        label: '收起迷你播放器',
        icon: Icons.close,
        onPressed: session.dismiss,
      ),
    ],
  );
}

class MusicRunPanel extends StatelessWidget {
  const MusicRunPanel({super.key, required this.session});

  final MusicSession session;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: session,
    builder: (context, _) => !session.visible
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.music_note_outlined, size: 22),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          session.source,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      Text(
                        session.playbackStatus,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    session.visible ? session.title : '尚未读取播放状态',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (session.detail.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      session.detail,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final action in [
                        ('prev', '上一首', Icons.skip_previous),
                        if (session.playing == true || session.queueLength > 0)
                          (
                            session.playing == true ? 'pause' : 'resume',
                            session.playing == true ? '暂停' : '继续播放',
                            session.playing == true
                                ? Icons.pause
                                : Icons.play_arrow,
                          ),
                        ('next', '下一首', Icons.skip_next),
                        ('stop', '停止播放', Icons.stop),
                        ('state', '刷新状态', Icons.refresh),
                      ])
                        if (session.actions.containsKey('music.${action.$1}') &&
                            (action.$1 != 'next' || session.canNext) &&
                            (action.$1 != 'prev' || session.canPrev))
                          GlassMotionScope.maybeOf(context) != null
                              ? AggregateActionButton(
                                  label: action.$2,
                                  icon: action.$3,
                                  onPressed: session.busy
                                      ? null
                                      : () => confirmMusicControl(
                                          context,
                                          session,
                                          action.$1,
                                          action.$2,
                                        ),
                                  enabled: !session.busy,
                                )
                              : OutlinedButton.icon(
                                  onPressed: session.busy
                                      ? null
                                      : () => confirmMusicControl(
                                          context,
                                          session,
                                          action.$1,
                                          action.$2,
                                        ),
                                  icon: Icon(action.$3, size: 18),
                                  label: Text(action.$2),
                                ),
                    ],
                  ),
                ],
              ),
            ),
          ),
  );
}
