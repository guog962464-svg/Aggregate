# Local mcp_dart transport patch

This package contains the `lib/` sources, `pubspec.yaml`, and MIT license from
[`mcp_dart` 2.4.3](https://github.com/leehack/mcp_dart/tree/v2.4.3). Keep the
upstream license and attribution with these sources.

The only local API change is `StreamableHttpClientTransportOptions.httpClient`,
which lets Aggregate inject an HTTP client that bounds response bytes and
rejects redirects. The rest of the API stays on the 2.4.3 source baseline.

When updating this copy, diff it against the chosen upstream tag, reapply the
small transport injection patch, and run the Aggregate MCP/Android tests.
