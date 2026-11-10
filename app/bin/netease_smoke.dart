// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:aggregate/platform/macos/mac_runtime.dart';
import 'package:aggregate_contracts/aggregate_contracts.dart';

const terminalStates = {
  RunState.succeeded,
  RunState.failed,
  RunState.cancelled,
  RunState.timedOut,
  RunState.outcomeUnknown,
};

/// Manual, opt-in playback check. Playback is stopped in a finally block.
Future<void> main(List<String> args) async {
  final home = Platform.environment['HOME'];
  final checkOnly = args.contains('--check-only');
  final paths = args.where((argument) => argument.startsWith('/'));
  final executable = paths.isNotEmpty
      ? paths.first
      : home == null
      ? null
      : '$home/.local/bin/ncm-cli';
  if (executable == null || !executable.startsWith('/')) {
    throw ArgumentError('请传入 ncm-cli 的绝对路径');
  }
  final data = await Directory.systemTemp.createTemp('aggregate-ncm-smoke-');
  final runtime = await MacRuntime.open(dataDirectory: data);
  try {
    final connection = await runtime.addConnection(
      ConnectionSpec(
        kind: ConnectionKind.cli,
        label: '网易云联调',
        executable: executable,
      ),
    );
    print(
      'connection=${connection.status.name} diagnostic=${connection.diagnostic ?? 'none'}',
    );
    if (connection.status != ConnectionStatus.ready) {
      throw StateError('网易云连接未就绪');
    }
    final capabilities = await runtime.searchCapabilities(
      const SearchQuery(''),
    );
    if (!capabilities.any((item) => item.presentation == 'music.search')) {
      throw StateError('无法确认此程序属于 @music163/ncm-cli');
    }
    if (checkOnly) return;
    Capability action(String role) =>
        capabilities.firstWhere((item) => item.presentation == 'music.$role');
    Future<RunEvent> call(String role, JsonMap arguments) async {
      final handle = await runtime.invoke(
        action(role).id,
        arguments,
        permissionGranted: true,
      );
      final event = await runtime
          .watchRun(handle.id)
          .firstWhere((event) => terminalStates.contains(event.state));
      print(
        '$role=${event.state.name} failure=${event.failure?.code.name ?? 'none'}'
        '${event.failure == null ? '' : ' detail=${event.failure!.message}'}',
      );
      return event;
    }

    Map? payload(RunEvent event) {
      for (final block in event.blocks) {
        var value = block.value;
        if (value is String) {
          try {
            value = jsonDecode(value);
          } on FormatException {
            continue;
          }
        }
        if (value is Map && !value.containsKey('exitCode')) return value;
      }
      return null;
    }

    final search = payload(await call('search', {'keyword': '两只老虎'}));
    final records = (search?['data'] as Map?)?['records'] as List? ?? [];
    final songs = records
        .cast<Map>()
        .where((item) => item['playFlag'] == true && item['vipFlag'] == false)
        .take(2)
        .toList();
    if (songs.length < 2) throw StateError('搜索结果不足两首可播歌曲，无法验证切歌');
    final song = songs.first;
    print('song=${song['name']} originalId=${song['originalId']}');
    try {
      await call('state', {});
      final play = await call('play', {
        'encryptedId': song['id'],
        'originalId': '${song['originalId']}',
      });
      final playResponse = payload(play);
      print('playResponse=${playResponse?['success']}');
      var playing = false;
      for (var attempt = 0; attempt < 7; attempt++) {
        await Future<void>.delayed(const Duration(seconds: 2));
        final state = (payload(await call('state', {}))?['state'] as Map?);
        final status = state?['status'];
        print('observed=$status queue=${state?['queueLength']}');
        if (status == 'playing' && (state?['queueLength'] as int? ?? 0) > 0) {
          playing = true;
          break;
        }
      }
      if (!playing) throw StateError('未确认播放中且队列非空');
      await call('pause', {});
      final paused = (payload(await call('state', {}))?['state'] as Map?);
      print('afterPause=${paused?['status']} queue=${paused?['queueLength']}');
      await call('resume', {});
      final resumed = (payload(await call('state', {}))?['state'] as Map?);
      print(
        'afterResume=${resumed?['status']} queue=${resumed?['queueLength']}',
      );
      if (resumed?['status'] != 'playing') {
        throw StateError('继续播放后未进入 playing');
      }
      final nextSong = songs[1];
      final queued = await call('queueAdd', {
        'encryptedId': nextSong['id'],
        'originalId': '${nextSong['originalId']}',
      });
      final queueResponse = payload(queued);
      if (queued.state != RunState.succeeded ||
          queueResponse?['success'] != true) {
        throw StateError('第二首加入队列失败');
      }
      final beforeNext = (payload(await call('state', {}))?['state'] as Map?);
      print(
        'beforeNext=${beforeNext?['status']} queue=${beforeNext?['queueLength']} index=${beforeNext?['currentIndex']}',
      );
      final length = beforeNext?['queueLength'] as int? ?? 0;
      final index = beforeNext?['currentIndex'] as int? ?? 0;
      if (length < 2 || index >= length - 1) {
        throw StateError('队列中当前歌曲后没有下一首，无法验证切歌');
      }
      for (final role in ['next', 'prev']) {
        final result = await call(role, {});
        if (result.state != RunState.succeeded) {
          throw StateError('$role 命令失败');
        }
        Map? state;
        for (var attempt = 0; attempt < 3; attempt++) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
          state = payload(await call('state', {}))?['state'] as Map?;
          if (state?['currentIndex'] == (role == 'next' ? index + 1 : index) &&
              state?['status'] == 'playing') {
            break;
          }
        }
        print('after$role=${state?['status']} index=${state?['currentIndex']}');
        if (state?['currentIndex'] != (role == 'next' ? index + 1 : index) ||
            state?['status'] != 'playing') {
          throw StateError('$role 命令返回成功，但未确认切换后持续播放');
        }
      }
      final volume = await call('volume', {'value': 50});
      if (volume.state == RunState.failed) {
        throw StateError('音量命令失败');
      }
    } finally {
      await call('stop', {});
    }
  } finally {
    await runtime.dispose();
    await data.delete(recursive: true);
  }
}
