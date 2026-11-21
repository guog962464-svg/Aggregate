import 'dart:convert';

import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../widgets/glass/aggregate_buttons.dart';
import '../../widgets/glass/glass_design_tokens.dart';
import '../../widgets/glass/glass_glyph.dart';
import '../../widgets/glass/glass_motion.dart';

const _lazyResultsThreshold = 40;

final class MusicSearchItem {
  const MusicSearchItem({
    required this.id,
    required this.originalId,
    required this.name,
    required this.artist,
    required this.playable,
  });

  final String id;
  final String originalId;
  final String name;
  final String artist;
  final bool playable;
}

List<MusicSearchItem> parseMusicSearchResults(List<ResultBlock> blocks) {
  for (final block in blocks) {
    Object? value = block.value;
    if (value is String) {
      try {
        value = jsonDecode(value);
      } on FormatException {
        continue;
      }
    }
    if (value is! Map || value['data'] is! Map) continue;
    final data = value['data'] as Map;
    final records = data['records'];
    if (records is! List) continue;
    return [
      for (final record in records)
        if (record is Map &&
            record['id'] is String &&
            record['originalId'] != null &&
            record['name'] is String)
          MusicSearchItem(
            id: record['id'] as String,
            originalId: '${record['originalId']}',
            name: record['name'] as String,
            artist: _artists(record),
            playable: record['playFlag'] == true,
          ),
    ];
  }
  return const [];
}

String _artists(Map record) {
  final artists =
      record['artists'] is List && (record['artists'] as List).isNotEmpty
      ? record['artists'] as List
      : record['fullArtists'] is List
      ? record['fullArtists'] as List
      : const [];
  final names = [
    for (final artist in artists)
      if (artist is Map && artist['name'] is String) artist['name'] as String,
  ];
  return names.isEmpty ? '未知歌手' : names.join('、');
}

class MusicSearchResults extends StatelessWidget {
  const MusicSearchResults({
    super.key,
    required this.items,
    required this.onPlay,
    this.onQueue,
    required this.busy,
    this.boardRowStyle = false,
  });

  final List<MusicSearchItem> items;
  final ValueChanged<MusicSearchItem> onPlay;
  final ValueChanged<MusicSearchItem>? onQueue;
  final bool busy;
  final bool boardRowStyle;

  bool _usesGlassButtons(BuildContext context) =>
      defaultTargetPlatform == TargetPlatform.macOS &&
      GlassMotionScope.maybeOf(context) != null;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              '歌曲 · ${items.length} 首',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          Text('由当前连接提供', style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
      const SizedBox(height: 12),
      if (items.length < _lazyResultsThreshold)
        for (final item in items) ...[
          _songRow(context, item),
          const Divider(height: 20),
        ]
      else
        SizedBox(
          key: const Key('music-search-results-list'),
          height: 420,
          child: ListView.separated(
            primary: false,
            padding: EdgeInsets.zero,
            itemCount: items.length,
            itemBuilder: (context, index) => KeyedSubtree(
              key: ValueKey('music-search-result-${items[index].id}'),
              child: _songRow(context, items[index]),
            ),
            separatorBuilder: (context, index) => const Divider(height: 20),
          ),
        ),
    ],
  );

  Widget _songRow(BuildContext context, MusicSearchItem item) {
    final theme = Theme.of(context);
    final tokens =
        theme.extension<GlassDesignTokens>() ??
        GlassDesignTokens.forBrightness(theme.brightness);
    final useBoardStyle =
        boardRowStyle && defaultTargetPlatform == TargetPlatform.macOS;
    final playAction = useBoardStyle
        ? _boardTextAction(
            context,
            label: '播放 ${item.name}',
            onPressed: busy ? null : () => onPlay(item),
          )
        : _resultActionButton(
            context,
            label: '播放 ${item.name}',
            icon: Icons.play_arrow,
            onPressed: busy ? null : () => onPlay(item),
          );
    final unavailable = useBoardStyle
        ? Text(
            '不可播放',
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 10,
              color: tokens.muted,
            ),
          )
        : Tooltip(
            message: '当前账号或音源不可播放',
            child: Text('不可播放', style: theme.textTheme.bodySmall),
          );

    return Padding(
      key: ValueKey('music-search-result-row-${item.id}'),
      padding: EdgeInsets.only(
        left: useBoardStyle ? 13 : 0,
        right: useBoardStyle ? 12 : 0,
      ),
      child: Row(
        children: [
          if (useBoardStyle)
            ExcludeSemantics(
              child: GlassGlyphMark(glyph: GlassGlyph.music, size: 18),
            )
          else
            const Icon(Icons.music_note_outlined, size: 18),
          SizedBox(width: useBoardStyle ? 11 : 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  key: ValueKey('music-search-result-title-${item.id}'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: useBoardStyle
                      ? theme.textTheme.bodyMedium?.copyWith(
                          fontSize: 13,
                          height: 17 / 13,
                        )
                      : null,
                ),
                Text(
                  useBoardStyle
                      ? '${item.artist} · ${item.playable ? '可播放' : '当前音源不可播放'}'
                      : item.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: useBoardStyle ? 10 : null,
                    color: useBoardStyle ? tokens.muted : null,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (item.playable) ...[
            if (onQueue != null)
              _resultActionButton(
                context,
                label: '将 ${item.name} 加入下一首',
                icon: Icons.playlist_add,
                onPressed: busy ? null : () => onQueue!(item),
              ),
            playAction,
          ] else
            unavailable,
        ],
      ),
    );
  }

  Widget _boardTextAction(
    BuildContext context, {
    required String label,
    required VoidCallback? onPressed,
  }) {
    final theme = Theme.of(context);
    final tokens =
        theme.extension<GlassDesignTokens>() ??
        GlassDesignTokens.forBrightness(theme.brightness);
    return Semantics(
      label: label,
      button: true,
      enabled: onPressed != null,
      onTap: onPressed,
      child: ExcludeSemantics(
        child: TextButton(
          key: ValueKey('music-search-result-action-$label'),
          onPressed: onPressed,
          style: TextButton.styleFrom(
            foregroundColor: tokens.muted,
            padding: EdgeInsets.zero,
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
          child: Text(
            '播放',
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  Widget _resultActionButton(
    BuildContext context, {
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    if (_usesGlassButtons(context)) {
      return AggregateIconButton(
        tooltip: label,
        icon: icon,
        onPressed: onPressed,
        enabled: onPressed != null,
      );
    }
    return Semantics(
      container: true,
      label: label,
      button: true,
      enabled: onPressed != null,
      onTap: onPressed,
      child: ExcludeSemantics(
        child: IconButton(
          tooltip: label,
          onPressed: onPressed,
          icon: Icon(icon),
        ),
      ),
    );
  }
}
