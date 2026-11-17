import 'package:mcp_dart/mcp_dart.dart' as mcp;

mcp.McpServer createAndroidHostMcpFixture({
  required String name,
  required String resourceUri,
  required String resourceText,
}) {
  final server = mcp.McpServer(
    mcp.Implementation(name: name, version: '1.0'),
    options: const mcp.McpServerOptions(protocol: mcp.McpProtocol.stable),
  );
  server.registerTool(
    'fixture_echo',
    description: 'Returns a fixture marker',
    inputSchema: mcp.JsonSchema.object(
      properties: {'value': mcp.JsonSchema.string()},
      required: ['value'],
    ),
    callback: (arguments, _) async => mcp.CallToolResult.fromContent([
      mcp.TextContent(text: 'tool-fixture:${arguments['value']}'),
    ]),
  );
  server.registerResource(
    'Isolated MCP resource',
    resourceUri,
    (description: 'A loopback-only A5.5 fixture', mimeType: 'text/plain'),
    (uri, _) async => mcp.ReadResourceResult(
      contents: [
        mcp.TextResourceContents(
          uri: uri.toString(),
          text: resourceText,
          mimeType: 'text/plain',
        ),
      ],
    ),
  );
  server.registerPrompt(
    'fixture_prompt',
    description: 'Returns a fixture marker',
    callback: (_, _) async => mcp.GetPromptResult(
      messages: [
        mcp.PromptMessage(
          role: mcp.PromptMessageRole.user,
          content: mcp.TextContent(text: 'prompt-fixture:$resourceText'),
        ),
      ],
    ),
  );
  return server;
}
