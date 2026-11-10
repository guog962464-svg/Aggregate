import 'dart:async';
import 'dart:io';

import 'package:aggregate/platform/macos/connection_diagnostic.dart';
import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('connection failures identify a repair step without leaking detail', () {
    final cases = <(ConnectionKind, Object, String)>[
      (ConnectionKind.cli, const FileSystemException('not found'), '绝对路径'),
      (
        ConnectionKind.cli,
        const FileSystemException(
          'permission denied',
          '/private/example',
          OSError('Permission denied', 13),
        ),
        '权限',
      ),
      (ConnectionKind.mcpHttp, Exception('HTTP 401 token=secret'), '认证'),
      (ConnectionKind.mcpHttp, Exception('HTTP 403'), '权限'),
      (ConnectionKind.mcpHttp, const SocketException('refused'), '网络'),
      (ConnectionKind.mcpHttp, TimeoutException('slow'), '超时'),
      (
        ConnectionKind.mcpStdio,
        Exception('unsupported protocol version'),
        '协议不兼容',
      ),
    ];
    for (final (kind, cause, expected) in cases) {
      final message = describeConnectionFailure(kind, cause);
      expect(message, contains(expected));
      expect(message, isNot(contains('secret')));
      expect(message, isNot(contains('/private/example')));
    }
  });
}
