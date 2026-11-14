import 'package:aggregate/features/music/music_search_results.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _macOS = TargetPlatformVariant({TargetPlatform.macOS});

void main() {
  testWidgets('desktop music results lazily reach and play the last song', (
    tester,
  ) async {
    await _verifyLongResults(tester, const Size(1024, 768));
  }, variant: _macOS);

  testWidgets('compact music results lazily reach and play the last song', (
    tester,
  ) async {
    await _verifyLongResults(tester, const Size(700, 768));
  }, variant: _macOS);
}

Future<void> _verifyLongResults(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final songs = [
    for (var index = 0; index < 90; index++)
      MusicSearchItem(
        id: 'song-$index',
        originalId: 'original-$index',
        name: '歌曲 $index',
        artist: '歌手 $index',
        playable: true,
      ),
  ];
  MusicSearchItem? played;

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: MusicSearchResults(
          items: songs,
          onPlay: (song) => played = song,
          busy: false,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  final lastSong = const ValueKey('music-search-result-song-89');
  expect(find.byKey(lastSong), findsNothing);
  final scrollable = find.descendant(
    of: find.byKey(const Key('music-search-results-list')),
    matching: find.byType(Scrollable),
  );
  await tester.scrollUntilVisible(
    find.byKey(lastSong),
    240,
    scrollable: scrollable,
  );

  expect(find.byKey(lastSong), findsOneWidget);
  await tester.tap(find.byTooltip('播放 歌曲 89'));
  expect(played?.id, 'song-89');
  expect(tester.takeException(), isNull);
}
