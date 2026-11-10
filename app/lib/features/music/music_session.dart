import 'dart:convert';
import 'dart:async';

import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:flutter/foundation.dart';

/// Keeps the optional music presentation in sync with generic RuntimePort runs.
/// No process or player API is called from the UI layer.
final class MusicSession extends ChangeNotifier {
  MusicSession(this.runtime);

  final RuntimePort runtime;
  final actions = <String, Capability>{};
  ConnectionId? connection;
  String source = '音乐';
  String title = '播放状态待读取';
  String? artist;
  String detail = '';
  bool visible = false;
  bool busy = false;
  bool searchAuthorized = false;
  bool controlsAuthorized = false;
  AccountState? accountState;
  bool? playing;
  String playbackStatus = '状态未知';
  int queueLength = 0;
  int currentIndex = 0;
  bool get canNext => queueLength > 1 && currentIndex < queueLength - 1;
  bool get canPrev => queueLength > 1 && currentIndex > 0;
  bool _disposed = false;
  int _verification = 0;
  int _attachment = 0;
  int _accountGeneration = 0;
  String? _playbackCommandIssue;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _verification++;
    _attachment++;
    super.dispose();
  }

  Future<void> attach(Capability capability) async {
    if (capability.presentation?.startsWith('music.') != true) return;
    final target = capability.id.connection;
    final attachment = ++_attachment;
    if (connection?.value != capability.id.connection.value) {
      _verification++;
      title = '播放状态待读取';
      artist = null;
      detail = '';
      visible = false;
      playing = null;
      playbackStatus = '状态未知';
      queueLength = 0;
      currentIndex = 0;
      searchAuthorized = false;
      controlsAuthorized = false;
      accountState = null;
    }
    connection = target;
    final catalog = await runtime.searchCapabilities(const SearchQuery(''));
    if (_disposed || attachment != _attachment) return;
    actions
      ..clear()
      ..addEntries(
        catalog
            .where(
              (item) =>
                  item.id.connection.value == target.value &&
                  item.presentation?.startsWith('music.') == true,
            )
            .map((item) => MapEntry(item.presentation!, item)),
      );
    final connections = await runtime.listConnections();
    if (_disposed || attachment != _attachment) return;
    for (final item in connections) {
      if (item.id.value == target.value) source = item.label;
    }
    _notify();
  }

  void observe(Capability capability, RunEvent event) {
    final role = capability.presentation;
    if (role == null || !role.startsWith('music.')) return;
    if (event.state == RunState.outcomeUnknown && role == 'music.play') {
      visible = true;
      playing = null;
      playbackStatus = '正在确认';
      _playbackCommandIssue = event.failure?.message ?? '播放命令未获确认';
      detail = '播放服务暂未确认命令，正在读取状态';
      if (!runtime.isPreview) unawaited(_verifyPlayback(++_verification));
      _notify();
      return;
    }
    if (event.state == RunState.failed || event.state == RunState.timedOut) {
      detail = event.failure?.message ?? '命令失败';
      if (role == 'music.state') {
        playing = null;
        playbackStatus = '状态读取失败';
      } else if (role == 'music.play') {
        visible = true;
        playing = null;
        playbackStatus = '正在确认';
        _playbackCommandIssue = detail;
        if (!runtime.isPreview) unawaited(_verifyPlayback(++_verification));
      }
      _notify();
      return;
    }
    if (event.state != RunState.succeeded) return;
    if (role == 'music.search') return;
    visible = true;
    if (role == 'music.state') {
      _readState(event.blocks);
    } else if (role == 'music.play') {
      _playbackCommandIssue = null;
      final response = _response(event.blocks);
      if (response?['success'] == false) {
        playing = false;
        playbackStatus = '播放失败';
        detail = '${response?['message'] ?? '播放器拒绝了播放命令'}';
        _notify();
        return;
      }
      playing = null;
      playbackStatus = '正在启动';
      detail = '正在确认播放状态';
      if (!runtime.isPreview) unawaited(_verifyPlayback(++_verification));
    } else {
      _verification++;
      detail = '${capability.title}已发送 · 正在读取状态';
      playing = null;
      playbackStatus = '正在确认';
      if (!runtime.isPreview) {
        if (role == 'music.next' || role == 'music.prev') {
          unawaited(_verifyTrackSwitch(role, currentIndex, _verification));
        } else {
          unawaited(_refreshAfterControl());
        }
      }
    }
    _notify();
  }

  void _readState(List<ResultBlock> blocks) {
    final meaningful = blocks.where((block) {
      final value = block.value;
      return value is! Map || !value.containsKey('exitCode');
    }).toList();
    if (meaningful.isEmpty) {
      detail = '状态命令未返回内容';
      playing = null;
      playbackStatus = '状态读取失败';
      return;
    }
    Object? value = meaningful.first.value;
    if (value is String) {
      final raw = value;
      try {
        value = jsonDecode(value);
      } on FormatException {
        detail = raw.trim();
        return;
      }
    }
    if (value is Map) {
      if (value['success'] == false) {
        detail = '${value['message'] ?? '读取状态失败'}';
        playing = null;
        playbackStatus = '状态读取失败';
        return;
      }
      final state = value['state'] is Map ? value['state'] as Map : value;
      final track = state['song'] is Map ? state['song'] as Map : state;
      final reportedTitle = track['title'] ?? track['name'];
      if (reportedTitle is String && reportedTitle.isNotEmpty) {
        title = reportedTitle;
      }
      artist = track['artist']?.toString();
      // A new status response must not inherit an earlier queue. Some CLI
      // responses omit these fields even after reporting a playback state.
      final length = state['queueLength'];
      queueLength = length is int && length > 0 ? length : 0;
      final index = state['currentIndex'];
      currentIndex = index is int && index >= 0 ? index : 0;
      final status = state['status']?.toString();
      if (status == 'playing') {
        if (queueLength > 0) {
          playing = true;
          playbackStatus = '播放中';
        } else {
          playing = null;
          playbackStatus = '正在确认';
          detail = '状态报告播放中，但队列为空；正在继续确认';
          return;
        }
      } else if (status == 'stopped') {
        playing = false;
        playbackStatus = queueLength > 0 ? '未播放' : '已停止';
      } else {
        if (state['playing'] is bool) playing = state['playing'] as bool;
        if (state['paused'] is bool) playing = !(state['paused'] as bool);
        if (playing == true && queueLength == 0) {
          playing = null;
          playbackStatus = '正在确认';
          detail = '状态报告播放中，但队列为空；正在继续确认';
          return;
        }
        playbackStatus = playing == true ? '播放中' : '状态未知';
      }
      detail = state['progress']?.toString() ?? playbackStatus;
    } else {
      detail = '$value';
    }
  }

  Map? _response(List<ResultBlock> blocks) {
    for (final block in blocks) {
      Object? value = block.value;
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

  void prepareTrack(String name, String artistName) {
    _playbackCommandIssue = null;
    title = name;
    artist = artistName;
    detail = '正在发送播放命令';
    playbackStatus = '正在启动';
    playing = null;
    visible = true;
    _notify();
  }

  void authorizeControls() {
    controlsAuthorized = true;
    _notify();
  }

  void authorizeSearch() {
    searchAuthorized = true;
    _notify();
  }

  void resetForAccountChange(AccountState state) {
    _accountGeneration++;
    _verification++;
    title = '播放状态待读取';
    artist = null;
    detail = '';
    visible = false;
    busy = false;
    playing = null;
    playbackStatus = '状态未知';
    queueLength = 0;
    currentIndex = 0;
    searchAuthorized = false;
    controlsAuthorized = false;
    accountState = state;
    _playbackCommandIssue = null;
    _notify();
  }

  Future<void> _refreshAfterControl() async {
    final accountGeneration = _accountGeneration;
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (!_disposed && accountGeneration == _accountGeneration) {
      await execute('state');
    }
  }

  Future<void> _verifyTrackSwitch(
    String role,
    int previousIndex,
    int verification,
  ) async {
    for (final delay in [350, 800, 1200]) {
      await Future<void>.delayed(Duration(milliseconds: delay));
      if (_disposed || verification != _verification) return;
      await execute('state');
      if (_disposed || verification != _verification) return;
      if (playing == true &&
          (role == 'music.next' && currentIndex > previousIndex ||
              role == 'music.prev' && currentIndex < previousIndex)) {
        return;
      }
    }
    if (_disposed || verification != _verification) return;
    detail = '${role == 'music.next' ? '下一首' : '上一首'}命令已发送，但未确认切换后持续播放';
    _notify();
  }

  Future<void> _verifyPlayback(int verification) async {
    for (final delay in [1, 2, 2, 2, 2]) {
      await Future<void>.delayed(Duration(seconds: delay));
      if (_disposed || verification != _verification) return;
      await execute('state');
      if (playing == true && queueLength > 0) return;
    }
    if (_disposed || verification != _verification) return;
    final stateReadFailed = playbackStatus == '状态读取失败';
    playbackStatus = '未能播放';
    detail = [
      ?_playbackCommandIssue,
      if (stateReadFailed)
        '状态读取失败，无法确认播放。请检查连接诊断。'
      else if (queueLength > 0)
        '歌曲已加入队列，但未确认播放器开始播放。请检查连接诊断。'
      else
        '播放队列为空，未确认开始播放。请检查歌曲权限或连接诊断。',
    ].join('；');
    _notify();
  }

  Future<void> execute(String role, [JsonMap arguments = const {}]) async {
    final capability = actions['music.$role'];
    if (capability == null || busy) return;
    final accountGeneration = _accountGeneration;
    busy = true;
    _notify();
    try {
      final handle = await runtime.invoke(
        capability.id,
        arguments,
        permissionGranted: true,
      );
      if (accountGeneration != _accountGeneration) {
        await runtime.cancel(handle.id);
        return;
      }
      await for (final event in runtime.watchRun(handle.id)) {
        if (accountGeneration != _accountGeneration) break;
        if ({
          RunState.succeeded,
          RunState.failed,
          RunState.cancelled,
          RunState.timedOut,
          RunState.outcomeUnknown,
        }.contains(event.state)) {
          observe(capability, event);
          break;
        }
      }
    } catch (cause) {
      if (accountGeneration == _accountGeneration) detail = '$cause';
    } finally {
      if (accountGeneration == _accountGeneration) {
        busy = false;
        _notify();
      }
    }
  }

  void dismiss() {
    visible = false;
    _notify();
  }
}
