import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:aggregate_runtime/aggregate_runtime.dart';

/// Stage 1 macOS entry point. The backend is a clearly labeled preview fixture.
/// Stage 2 replaces it with real CLI/MCP adapters without changing the UI port.
final class LocalRuntimePort implements RuntimePort {
  LocalRuntimePort.preview()
    : _delegate = PreviewRuntime(
        connections: const [
          Connection(
            id: ConnectionId('example-git'),
            kind: ConnectionKind.cli,
            label: '示例 Git CLI',
            location: '/usr/bin/git · 预览',
          ),
          Connection(
            id: ConnectionId('example-mcp'),
            kind: ConnectionKind.mcpHttp,
            label: '示例 MCP',
            location: 'mcp://preview · 预览',
            protocolVersion: '2026-07-28',
          ),
        ],
        capabilities: const [
          Capability(
            id: CapabilityId(
              ConnectionId('example-git'),
              CapabilityKind.cliAction,
              'status',
            ),
            title: '查看 Git 状态',
            description: '以预览结果演示 CLI 动作',
            permission: PermissionLevel.read,
          ),
          Capability(
            id: CapabilityId(
              ConnectionId('example-mcp'),
              CapabilityKind.mcpTool,
              'add',
            ),
            title: '两个整数相加',
            description: '以预览结果演示 MCP 工具与结构化输出',
            permission: PermissionLevel.read,
            inputSchema: {
              'type': 'object',
              'properties': {
                'a': {'type': 'integer', 'title': '第一个整数'},
                'b': {'type': 'integer', 'title': '第二个整数'},
              },
              'required': ['a', 'b'],
            },
          ),
          Capability(
            id: CapabilityId(
              ConnectionId('example-mcp'),
              CapabilityKind.mcpResource,
              'readme',
            ),
            title: '读取项目说明',
            description: '资源阅读器的预览样本',
            permission: PermissionLevel.read,
          ),
          Capability(
            id: CapabilityId(
              ConnectionId('example-mcp'),
              CapabilityKind.mcpPrompt,
              'summary',
            ),
            title: '生成摘要提示',
            description: '提示预览的样本',
            permission: PermissionLevel.read,
            inputSchema: {
              'type': 'object',
              'properties': {
                'topic': {'type': 'string', 'title': '主题'},
              },
              'required': ['topic'],
            },
          ),
        ],
      );

  final PreviewRuntime _delegate;

  @override
  Future<List<Connection>> listConnections() => _delegate.listConnections();
  @override
  Future<List<Capability>> searchCapabilities(SearchQuery query) =>
      _delegate.searchCapabilities(query);
  @override
  Future<RunHandle> invoke(CapabilityId id, JsonMap arguments) =>
      _delegate.invoke(id, arguments);
  @override
  Stream<RunEvent> watchRun(RunId id) => _delegate.watchRun(id);
  @override
  Future<List<RunSummary>> listRecentRuns() => _delegate.listRecentRuns();
  @override
  Future<void> cancel(RunId id) => _delegate.cancel(id);
  @override
  Future<List<ResultBlock>> readResource(ResourceRef ref) =>
      _delegate.readResource(ref);
  @override
  Future<List<ResultBlock>> getPrompt(PromptRef ref, JsonMap arguments) =>
      _delegate.getPrompt(ref, arguments);
  @override
  Future<TerminalSession> openTerminal(CliCommand command) =>
      _delegate.openTerminal(command);
}
