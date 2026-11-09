import 'dart:io';

import 'package:mcp_dart/mcp_dart.dart';

Future<void> main(List<String> args) async {
  if (args.length != 2 || !['stdio', 'http'].contains(args.first)) {
    stderr.writeln(
      'usage: dart run bin/phase0.dart stdio|http fixture-path|url',
    );
    exitCode = 2;
    return;
  }

  final client = McpClient(
    const Implementation(name: 'aggregate-phase0-probe', version: '1.0.0'),
  );
  final transport = args.first == 'stdio'
      ? StdioClientTransport(
          StdioServerParameters(
            command: '${Directory.current.path}/.venv/bin/python',
            args: [args[1], 'stdio'],
          ),
        )
      : StreamableHttpClientTransport(Uri.parse(args[1]));

  try {
    await client.connect(transport).timeout(const Duration(seconds: 12));
    print('connected server=${client.getServerVersion()?.version}');

    final tools = await client.listTools().timeout(const Duration(seconds: 8));
    if (!tools.tools.any((tool) => tool.name == 'add')) {
      throw StateError('add tool missing');
    }
    final result = await client
        .callTool(
          const CallToolRequest(name: 'add', arguments: {'a': 7, 'b': 5}),
        )
        .timeout(const Duration(seconds: 8));
    print('tools=${tools.tools.map((tool) => tool.name).toList()}');
    print('tool_result=${result.toJson()}');
    final structured = result.toJson()['structuredContent'];
    if (structured is! Map || structured['sum'] != 12) {
      throw StateError('unexpected structured tool result: $structured');
    }

    final resources = await client.listResources().timeout(
      const Duration(seconds: 8),
    );
    if (!resources.resources.any(
      (resource) => resource.uri == 'memo://phase0/readme',
    )) {
      throw StateError('fixture resource missing');
    }
    final resource = await client
        .readResource(const ReadResourceRequest(uri: 'memo://phase0/readme'))
        .timeout(const Duration(seconds: 8));
    print(
      'resources=${resources.resources.map((resource) => resource.uri).toList()}',
    );
    print('resource_result=${resource.toJson()}');
    if (!resource.toJson().toString().contains('Aggregate phase 0 resource')) {
      throw StateError('unexpected resource content');
    }

    final prompts = await client.listPrompts().timeout(
      const Duration(seconds: 8),
    );
    if (!prompts.prompts.any((prompt) => prompt.name == 'welcome')) {
      throw StateError('welcome prompt missing');
    }
    final prompt = await client
        .getPrompt(
          const GetPromptRequest(
            name: 'welcome',
            arguments: {'name': 'Aggregate'},
          ),
        )
        .timeout(const Duration(seconds: 8));
    print('prompts=${prompts.prompts.map((prompt) => prompt.name).toList()}');
    print('prompt_result=${prompt.toJson()}');
    if (!prompt.toJson().toString().contains('Greet Aggregate')) {
      throw StateError('unexpected prompt content');
    }
    print('PASS ${args.first}');
  } finally {
    await client.close();
  }
}
