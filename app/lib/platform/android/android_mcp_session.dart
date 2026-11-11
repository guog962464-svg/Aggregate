import 'dart:async';

import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:aggregate_domain/aggregate_domain.dart';
import 'package:mcp_dart/mcp_dart.dart' as mcp;

final class AndroidMcpSession {
  AndroidMcpSession._(this.client, this.capabilities);

  final mcp.McpClient client;
  final List<Capability> capabilities;

  String? get protocolVersion => client.getServerVersion()?.version;

  static Future<AndroidMcpSession> connect(
    String id,
    Uri endpoint,
    String? token,
  ) async {
    final client = mcp.McpClient(
      const mcp.Implementation(name: 'aggregate-android', version: '0.3.0'),
    );
    try {
      final transport = mcp.StreamableHttpClientTransport(
        endpoint,
        opts: token == null
            ? null
            : mcp.StreamableHttpClientTransportOptions(
                requestInit: {
                  'headers': {'Authorization': 'Bearer $token'},
                },
              ),
      );
      await client.connect(transport).timeout(const Duration(seconds: 12));
      final capabilities = await _discover(id, client);
      return AndroidMcpSession._(client, capabilities);
    } catch (_) {
      await client.close();
      rethrow;
    }
  }

  static Future<List<Capability>> _discover(
    String id,
    mcp.McpClient client,
  ) async {
    final capabilities = <Capability>[];
    String? cursor;
    final seen = <String>{};
    if (client.getServerCapabilities()?.tools != null) {
      do {
        final page = await client
            .listTools(
              params: cursor == null
                  ? null
                  : mcp.ListToolsRequest(cursor: cursor),
            )
            .timeout(const Duration(seconds: 10));
        for (final tool in page.tools) {
          capabilities.add(
            Capability(
              id: CapabilityId(
                ConnectionId(id),
                CapabilityKind.mcpTool,
                tool.name,
              ),
              title: tool.title ?? tool.name,
              description: tool.description ?? 'MCP 工具',
              permission: PermissionLevel.unknown,
              inputSchema: Map<String, Object?>.from(tool.inputSchema.toJson()),
            ),
          );
        }
        cursor = page.nextCursor;
      } while (cursor != null && seen.add(cursor) && seen.length < 100);
    }

    cursor = null;
    seen.clear();
    if (client.getServerCapabilities()?.resources != null) {
      do {
        final page = await client
            .listResources(
              params: cursor == null
                  ? null
                  : mcp.ListResourcesRequest(cursor: cursor),
            )
            .timeout(const Duration(seconds: 10));
        for (final resource in page.resources) {
          capabilities.add(
            Capability(
              id: CapabilityId(
                ConnectionId(id),
                CapabilityKind.mcpResource,
                resource.uri,
              ),
              title: resource.title ?? resource.name,
              description: resource.description ?? resource.uri,
              permission: PermissionLevel.read,
            ),
          );
        }
        cursor = page.nextCursor;
      } while (cursor != null && seen.add(cursor) && seen.length < 100);
    }

    cursor = null;
    seen.clear();
    if (client.getServerCapabilities()?.prompts != null) {
      do {
        final page = await client
            .listPrompts(
              params: cursor == null
                  ? null
                  : mcp.ListPromptsRequest(cursor: cursor),
            )
            .timeout(const Duration(seconds: 10));
        for (final prompt in page.prompts) {
          final properties = <String, Object?>{};
          final required = <String>[];
          for (final argument in prompt.arguments ?? <mcp.PromptArgument>[]) {
            properties[argument.name] = {
              'type': 'string',
              'title': argument.title ?? argument.name,
            };
            if (argument.required == true) required.add(argument.name);
          }
          capabilities.add(
            Capability(
              id: CapabilityId(
                ConnectionId(id),
                CapabilityKind.mcpPrompt,
                prompt.name,
              ),
              title: prompt.title ?? prompt.name,
              description: prompt.description ?? 'MCP 提示',
              permission: PermissionLevel.read,
              inputSchema: {
                'type': 'object',
                'properties': properties,
                'required': required,
              },
            ),
          );
        }
        cursor = page.nextCursor;
      } while (cursor != null && seen.add(cursor) && seen.length < 100);
    }
    return capabilities;
  }

  Future<({List<ResultBlock> blocks, bool isError})> call(
    String name,
    JsonMap arguments,
  ) async {
    final result = await client
        .callTool(mcp.CallToolRequest(name: name, arguments: arguments))
        .timeout(const Duration(seconds: 30));
    return (
      blocks: ResultNormalizer.fromMcp(
        Map<String, Object?>.from(result.toJson()),
      ),
      isError: result.isError == true,
    );
  }

  Future<List<ResultBlock>> readResource(Uri uri) async {
    final result = await client
        .readResource(mcp.ReadResourceRequest(uri: uri.toString()))
        .timeout(const Duration(seconds: 30));
    return [
      for (final content in result.toJson()['contents'] as List? ?? const [])
        ResultBlock(ResultKind.json, content),
    ];
  }

  Future<List<ResultBlock>> getPrompt(String name, JsonMap arguments) async {
    final result = await client
        .getPrompt(
          mcp.GetPromptRequest(
            name: name,
            arguments: arguments.map((key, value) => MapEntry(key, '$value')),
          ),
        )
        .timeout(const Duration(seconds: 30));
    return [
      for (final message in result.toJson()['messages'] as List? ?? const [])
        ResultBlock(ResultKind.json, message),
    ];
  }

  Future<void> close() => client.close();
}
