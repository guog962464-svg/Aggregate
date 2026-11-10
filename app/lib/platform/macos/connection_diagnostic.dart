import 'dart:async';
import 'dart:io';

import 'package:aggregate_contracts/aggregate_contracts.dart';

/// Maps transport failures to repair steps without showing server replies,
/// URLs, headers, or credentials in the connection details.
String describeConnectionFailure(ConnectionKind kind, Object cause) {
  final description = '$cause'.toLowerCase();
  if (kind == ConnectionKind.cli || kind == ConnectionKind.mcpStdio) {
    if (cause is FileSystemException || cause is ProcessException) {
      if (description.contains('permission denied') ||
          description.contains('operation not permitted') ||
          description.contains('eacces')) {
        return '没有执行程序或工作目录的权限。请检查文件权限后重试。';
      }
      return '找不到程序或工作目录。请检查绝对路径，并确认程序可执行。';
    }
  }
  if (description.contains('连接凭证缺失')) {
    return 'MCP 凭证已丢失。请删除此连接并重新添加 Bearer Token。';
  }
  if (_hasAny(description, const [
    '401',
    'unauthorized',
    'invalid_token',
    'token expired',
    'authentication required',
  ])) {
    return 'MCP 认证已失效。请重新添加连接并更新 Bearer Token。';
  }
  if (_hasAny(description, const [
    '403',
    'forbidden',
    'permission denied',
    'insufficient scope',
  ])) {
    return 'MCP 服务拒绝访问。请检查该账号的服务权限。';
  }
  if (cause is TimeoutException) {
    return '连接超时。请检查服务是否运行、网络或代理设置，然后重试。';
  }
  if (cause is SocketException ||
      cause is HttpException ||
      _hasAny(description, const [
        'socketexception',
        'connection refused',
        'connection reset',
        'failed host lookup',
        'network is unreachable',
        'connection closed',
      ])) {
    return '网络或服务连接中断。请检查地址、网络和服务进程，然后重试。';
  }
  if (_hasAny(description, const [
    'unsupported protocol',
    'protocol version',
    'invalid jsonrpc',
    'invalid mcp',
    'method not found',
    'handshake',
    'content-type',
    'content type',
    'invalid response',
    'unexpected response',
  ])) {
    return 'MCP 协议不兼容。请更新服务端，并确认其支持当前 MCP 初始化与能力发现。';
  }
  if (cause is FormatException && kind == ConnectionKind.cli) {
    if (description.contains('schemaversion')) {
      return '动作清单版本不受支持。请将 schemaVersion 改为 1 后重新导入。';
    }
    return 'CLI 动作清单格式无效。请检查 JSON、程序路径和平台字段。';
  }
  return kind == ConnectionKind.cli
      ? 'CLI 连接检查失败。请检查程序路径、权限和动作清单。'
      : 'MCP 连接检查失败。请检查服务状态、协议版本和认证信息。';
}

bool _hasAny(String source, List<String> terms) => terms.any(source.contains);
