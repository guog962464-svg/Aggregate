// ignore_for_file: avoid_print

import 'dart:io';

import 'package:aggregate/platform/macos/mac_runtime.dart';
import 'package:aggregate_contracts/aggregate_contracts.dart';

/// Adds the optional ncm-cli example to the current user's Aggregate data.
Future<void> main(List<String> arguments) async {
  final home = Platform.environment['HOME'];
  final executable = arguments.isNotEmpty
      ? arguments.first
      : home == null
      ? ''
      : '$home/.local/bin/ncm-cli';
  if (!executable.startsWith('/') || !await File(executable).exists()) {
    throw ArgumentError('请传入已安装 ncm-cli 的绝对路径');
  }
  final runtime = await MacRuntime.open();
  try {
    final matching = (await runtime.listConnections()).where(
      (item) => item.kind == ConnectionKind.cli && item.location == executable,
    );
    final connection = matching.isEmpty
        ? await runtime.addConnection(
            ConnectionSpec(
              kind: ConnectionKind.cli,
              label: '网易云音乐',
              executable: executable,
            ),
          )
        : await runtime.refreshConnection(matching.first.id);
    print('connection=${connection.status.name}');
    if (connection.diagnostic != null) {
      print('diagnostic=${connection.diagnostic}');
    }
  } finally {
    await runtime.dispose();
  }
}
