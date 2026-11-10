import 'package:flutter/material.dart';

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
    );
    if (confirmed != true) return;
    session.authorizeControls();
  }
  await session.execute(role);
}

class MusicMiniPlayer extends StatelessWidget {
  const MusicMiniPlayer({super.key, required this.session});

  final MusicSession session;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: session,
    builder: (context, _) {
      if (!session.visible) return const SizedBox.shrink();
      final scheme = Theme.of(context).colorScheme;
      final canToggle = session.playing == true
          ? session.actions.containsKey('music.pause')
          : session.queueLength > 0 &&
                session.actions.containsKey('music.resume');
      return Material(
        color: scheme.surface,
        child: SafeArea(
          top: false,
          child: Container(
            constraints: const BoxConstraints(minHeight: 68),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: Theme.of(context).dividerColor),
              ),
            ),
            child: Row(
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
                      Text(
                        [
                          session.source,
                          ?session.artist,
                          session.detail,
                        ].where((part) => part.isNotEmpty).join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (session.actions.containsKey('music.prev') &&
                    session.canPrev)
                  IconButton(
                    tooltip: '上一首',
                    onPressed: session.busy
                        ? null
                        : () => confirmMusicControl(
                            context,
                            session,
                            'prev',
                            '上一首',
                          ),
                    icon: const Icon(Icons.skip_previous),
                  ),
                IconButton(
                  tooltip: session.playing == true ? '暂停' : '继续播放',
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
                  icon: Icon(
                    session.playing == true ? Icons.pause : Icons.play_arrow,
                  ),
                ),
                if (session.actions.containsKey('music.next') &&
                    session.canNext)
                  IconButton(
                    tooltip: '下一首',
                    onPressed: session.busy
                        ? null
                        : () => confirmMusicControl(
                            context,
                            session,
                            'next',
                            '下一首',
                          ),
                    icon: const Icon(Icons.skip_next),
                  ),
                if (session.actions.containsKey('music.stop'))
                  IconButton(
                    tooltip: '停止播放',
                    onPressed: session.busy
                        ? null
                        : () => confirmMusicControl(
                            context,
                            session,
                            'stop',
                            '停止播放',
                          ),
                    icon: const Icon(Icons.stop),
                  ),
                if (session.actions.containsKey('music.state'))
                  IconButton(
                    tooltip: '刷新播放状态',
                    onPressed: session.busy
                        ? null
                        : () => confirmMusicControl(
                            context,
                            session,
                            'state',
                            '刷新状态',
                          ),
                    icon: const Icon(Icons.refresh),
                  ),
                IconButton(
                  tooltip: '收起迷你播放器',
                  onPressed: session.dismiss,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
        ),
      );
    },
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
                          OutlinedButton.icon(
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
