import 'dart:async';

import 'dart:convert';

import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:aggregate_domain/aggregate_domain.dart';
import 'package:mcp_dart/mcp_dart.dart' as mcp;

import 'android_mcp_http_client.dart';

const _maxMcpPagesPerList = 20;
const _maxMcpCapabilities = 1000;
const _maxMcpCatalogBytes = 4 * 1024 * 1024;
const _maxMcpSchemaBytes = 256 * 1024;
const _maxMcpFieldBytes = 16 * 1024;
const _maxMcpCursorBytes = 4096;
const _maxMcpPromptArguments = 64;

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
        opts: mcp.StreamableHttpClientTransportOptions(
          requestInit: token == null
              ? null
              : {
                  'headers': {'Authorization': 'Bearer $token'},
                },
          httpClient: AndroidMcpHttpClient(),
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
    var catalogBytes = 0;
    void appendCapability(
      Capability capability,
      Iterable<String> fields, {
      int schemaBytes = 0,
    }) {
      var recordBytes = schemaBytes;
      if (schemaBytes > _maxMcpSchemaBytes) {
        throw const FormatException('MCP 功能参数结构超过 Android 限制');
      }
      for (final field in fields) {
        final fieldBytes = utf8.encode(field).length;
        if (fieldBytes > _maxMcpFieldBytes) {
          throw const FormatException('MCP 功能说明超过 Android 限制');
        }
        recordBytes += fieldBytes;
      }
      if (capabilities.length >= _maxMcpCapabilities ||
          recordBytes > _maxMcpCatalogBytes - catalogBytes) {
        throw const FormatException('MCP 功能目录超过 Android 限制');
      }
      catalogBytes += recordBytes;
      capabilities.add(capability);
    }

    String? cursor;
    final seen = <String>{};
    if (client.getServerCapabilities()?.tools != null) {
      var pageCount = 0;
      do {
        if (++pageCount > _maxMcpPagesPerList) {
          throw const FormatException('MCP 工具目录页数超过 Android 限制');
        }
        final page = await client
            .listTools(
              params: cursor == null
                  ? null
                  : mcp.ListToolsRequest(cursor: cursor),
            )
            .timeout(const Duration(seconds: 10));
        for (final tool in page.tools) {
          final title = tool.title ?? tool.name;
          final description = tool.description ?? 'MCP 工具';
          final inputSchema = Map<String, Object?>.from(
            tool.inputSchema.toJson(),
          );
          final schemaBytes = utf8.encode(jsonEncode(inputSchema)).length;
          appendCapability(
            Capability(
              id: CapabilityId(
                ConnectionId(id),
                CapabilityKind.mcpTool,
                tool.name,
              ),
              title: title,
              description: description,
              permission: PermissionLevel.unknown,
              inputSchema: inputSchema,
            ),
            [tool.name, title, description],
            schemaBytes: schemaBytes,
          );
        }
        cursor = page.nextCursor;
        _validateNextCursor(cursor, seen, pageCount);
      } while (cursor != null);
    }

    cursor = null;
    seen.clear();
    if (client.getServerCapabilities()?.resources != null) {
      var pageCount = 0;
      do {
        if (++pageCount > _maxMcpPagesPerList) {
          throw const FormatException('MCP 资源目录页数超过 Android 限制');
        }
        final page = await client
            .listResources(
              params: cursor == null
                  ? null
                  : mcp.ListResourcesRequest(cursor: cursor),
            )
            .timeout(const Duration(seconds: 10));
        for (final resource in page.resources) {
          final title = resource.title ?? resource.name;
          final description = resource.description ?? resource.uri;
          appendCapability(
            Capability(
              id: CapabilityId(
                ConnectionId(id),
                CapabilityKind.mcpResource,
                resource.uri,
              ),
              title: title,
              description: description,
              permission: PermissionLevel.read,
            ),
            [resource.name, resource.uri, title, description],
          );
        }
        cursor = page.nextCursor;
        _validateNextCursor(cursor, seen, pageCount);
      } while (cursor != null);
    }

    cursor = null;
    seen.clear();
    if (client.getServerCapabilities()?.prompts != null) {
      var pageCount = 0;
      do {
        if (++pageCount > _maxMcpPagesPerList) {
          throw const FormatException('MCP 提示目录页数超过 Android 限制');
        }
        final page = await client
            .listPrompts(
              params: cursor == null
                  ? null
                  : mcp.ListPromptsRequest(cursor: cursor),
            )
            .timeout(const Duration(seconds: 10));
        for (final prompt in page.prompts) {
          final promptArguments = prompt.arguments ?? <mcp.PromptArgument>[];
          if (promptArguments.length > _maxMcpPromptArguments) {
            throw const FormatException('MCP 提示参数数量超过 Android 限制');
          }
          final properties = <String, Object?>{};
          final required = <String>[];
          for (final argument in promptArguments) {
            properties[argument.name] = {
              'type': 'string',
              'title': argument.title ?? argument.name,
            };
            if (argument.required == true) required.add(argument.name);
          }
          final title = prompt.title ?? prompt.name;
          final description = prompt.description ?? 'MCP 提示';
          final inputSchema = {
            'type': 'object',
            'properties': properties,
            'required': required,
          };
          final schemaBytes = utf8.encode(jsonEncode(inputSchema)).length;
          appendCapability(
            Capability(
              id: CapabilityId(
                ConnectionId(id),
                CapabilityKind.mcpPrompt,
                prompt.name,
              ),
              title: title,
              description: description,
              permission: PermissionLevel.read,
              inputSchema: inputSchema,
            ),
            [prompt.name, title, description, ...properties.keys],
            schemaBytes: schemaBytes,
          );
        }
        cursor = page.nextCursor;
        _validateNextCursor(cursor, seen, pageCount);
      } while (cursor != null);
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

void _validateNextCursor(String? cursor, Set<String> seen, int pageCount) {
  if (cursor == null) return;
  if (pageCount >= _maxMcpPagesPerList ||
      utf8.encode(cursor).length > _maxMcpCursorBytes ||
      !seen.add(cursor)) {
    throw const FormatException('MCP 目录分页超过 Android 限制');
  }
}
