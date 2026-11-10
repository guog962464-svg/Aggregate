import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:aggregate_runtime/aggregate_runtime.dart';

/// Platform-independent sample data for UI development and review.
PreviewRuntime createPreviewRuntime() => PreviewRuntime(
  connections: const [
    Connection(
      id: ConnectionId('example-git'),
      kind: ConnectionKind.cli,
      label: '示例 Git CLI',
      location: 'git · 预览',
    ),
    Connection(
      id: ConnectionId('example-mcp'),
      kind: ConnectionKind.mcpHttp,
      label: '示例 MCP',
      location: 'mcp://preview · 预览',
      protocolVersion: '2026-07-28',
    ),
    Connection(
      id: ConnectionId('example-music'),
      kind: ConnectionKind.cli,
      label: '示例网易云音乐',
      location: 'ncm-cli · 预览',
    ),
  ],
  capabilities: [
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
        ConnectionId('example-music'),
        CapabilityKind.cliAction,
        'search',
      ),
      title: '搜索歌曲',
      description: '预览音乐连接器的搜索结果',
      permission: PermissionLevel.read,
      presentation: 'music.search',
      inputSchema: {
        'type': 'object',
        'properties': {
          'keyword': {'type': 'string', 'title': '关键词'},
        },
        'required': ['keyword'],
      },
    ),
    Capability(
      id: CapabilityId(
        ConnectionId('example-music'),
        CapabilityKind.cliAction,
        'play',
      ),
      title: '播放歌曲',
      description: '预览由公共调用结果驱动的迷你播放器',
      permission: PermissionLevel.read,
      presentation: 'music.play',
      inputSchema: {
        'type': 'object',
        'properties': {
          'encryptedId': {'type': 'string', 'title': '加密 ID'},
          'originalId': {'type': 'string', 'title': '原始 ID'},
        },
        'required': ['encryptedId', 'originalId'],
      },
    ),
    for (final role in ['pause', 'resume', 'stop', 'next', 'prev', 'state'])
      Capability(
        id: CapabilityId(
          ConnectionId('example-music'),
          CapabilityKind.cliAction,
          role,
        ),
        title: switch (role) {
          'pause' => '暂停播放',
          'resume' => '继续播放',
          'stop' => '停止播放',
          'next' => '下一首',
          'prev' => '上一首',
          _ => '播放状态',
        },
        description: '预览音乐播放控制',
        permission: PermissionLevel.read,
        presentation: 'music.$role',
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
