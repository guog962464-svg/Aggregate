import 'dart:convert';

import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:flutter/material.dart';

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
  });

  final List<MusicSearchItem> items;
  final ValueChanged<MusicSearchItem> onPlay;
  final ValueChanged<MusicSearchItem>? onQueue;
  final bool busy;

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
      for (final item in items) ...[
        Row(
          children: [
            const Icon(Icons.music_note_outlined, size: 18),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(
                    item.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (item.playable)
              if (onQueue != null)
                Semantics(
                  container: true,
                  label: '将 ${item.name} 加入下一首',
                  button: true,
                  enabled: !busy,
                  onTap: busy ? null : () => onQueue!(item),
                  child: ExcludeSemantics(
                    child: IconButton(
                      tooltip: '将 ${item.name} 加入下一首',
                      onPressed: busy ? null : () => onQueue!(item),
                      icon: const Icon(Icons.playlist_add),
                    ),
                  ),
                ),
            if (item.playable)
              Semantics(
                container: true,
                label: '播放 ${item.name}',
                button: true,
                enabled: !busy,
                onTap: busy ? null : () => onPlay(item),
                child: ExcludeSemantics(
                  child: IconButton(
                    tooltip: '播放 ${item.name}',
                    onPressed: busy ? null : () => onPlay(item),
                    icon: const Icon(Icons.play_arrow),
                  ),
                ),
              )
            else
              Tooltip(
                message: '当前账号或音源不可播放',
                child: Text(
                  '不可播放',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ),
        const Divider(height: 20),
      ],
    ],
  );
}
