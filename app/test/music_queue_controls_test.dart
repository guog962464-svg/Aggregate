import 'package:aggregate/features/music/music_session.dart';
import 'package:aggregate/features/music/music_search_results.dart';
import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:aggregate_runtime/aggregate_runtime.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('music controls follow the reported queue position', () {
    final runtime = PreviewRuntime(
      connections: const [],
      capabilities: const [],
    );
    final session = MusicSession(runtime);
    addTearDown(() async {
      session.dispose();
      await runtime.dispose();
    });
    const capability = Capability(
      id: CapabilityId(
        ConnectionId('music'),
        CapabilityKind.cliAction,
        'state',
      ),
      title: '播放状态',
      description: '',
      permission: PermissionLevel.read,
      presentation: 'music.state',
    );
    void report(int length, int index) {
      session.observe(
        capability,
        RunEvent(
          runId: const RunId('state'),
          sequence: 1,
          state: RunState.succeeded,
          occurredAt: DateTime.utc(2026, 11, 9),
          blocks: [
            ResultBlock(ResultKind.json, {
              'success': true,
              'state': {
                'status': 'playing',
                'queueLength': length,
                'currentIndex': index,
              },
            }),
          ],
        ),
      );
    }

    report(0, 0);
    expect(session.playing, isNull);
    expect(session.playbackStatus, '正在确认');
    report(1, 0);
    expect(session.canPrev, isFalse);
    expect(session.canNext, isFalse);
    report(3, 0);
    expect(session.canPrev, isFalse);
    expect(session.canNext, isTrue);
    report(3, 1);
    expect(session.canPrev, isTrue);
    expect(session.canNext, isTrue);
    report(3, 2);
    expect(session.canPrev, isTrue);
    expect(session.canNext, isFalse);

    // A later incomplete response cannot reuse the previously confirmed queue.
    session.observe(
      capability,
      RunEvent(
        runId: const RunId('state'),
        sequence: 2,
        state: RunState.succeeded,
        occurredAt: DateTime.utc(2026, 11, 9),
        blocks: [
          ResultBlock(ResultKind.json, {
            'success': true,
            'state': {'playing': true},
          }),
        ],
      ),
    );
    expect(session.queueLength, 0);
    expect(session.playing, isNull);
    expect(session.playbackStatus, '正在确认');
    expect(session.canPrev, isFalse);
    expect(session.canNext, isFalse);

    session.observe(
      const Capability(
        id: CapabilityId(
          ConnectionId('music'),
          CapabilityKind.cliAction,
          'pause',
        ),
        title: '暂停播放',
        description: '',
        permission: PermissionLevel.localControl,
        presentation: 'music.pause',
      ),
      RunEvent(
        runId: const RunId('pause'),
        sequence: 1,
        state: RunState.succeeded,
        occurredAt: DateTime.utc(2026, 11, 9),
      ),
    );
    expect(session.playing, isNull);
    expect(session.playbackStatus, '正在确认');

    session.observe(
      capability,
      RunEvent(
        runId: const RunId('state'),
        sequence: 2,
        state: RunState.failed,
        occurredAt: DateTime.utc(2026, 11, 9),
      ),
    );
    expect(session.playing, isNull);
    expect(session.playbackStatus, '状态读取失败');
  });

  testWidgets('search result can add a playable song to the next slot', (
    tester,
  ) async {
    MusicSearchItem? queued;
    const item = MusicSearchItem(
      id: 'encrypted',
      originalId: '123',
      name: '示例歌曲',
      artist: '示例歌手',
      playable: true,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MusicSearchResults(
            items: const [item],
            onPlay: (_) {},
            onQueue: (value) => queued = value,
            busy: false,
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('将 示例歌曲 加入下一首'));
    expect(queued, same(item));
  });
}
