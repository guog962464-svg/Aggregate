import 'package:mcp_dart/mcp_dart.dart' as mcp;

import 'android_host_mcp_fixture.dart';

Future<void> main() async {
  final server = createAndroidHostMcpFixture(
    name: 'aggregate-stdio-fixture',
    resourceUri: 'aggregate://stdio-fixture/resource',
    resourceText: 'stdio-fixture-resource',
  );
  await server.connect(mcp.StdioServerTransport());
}
