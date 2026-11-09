"""Independent MCP fixture (official Python SDK 2.x)."""

import argparse

from mcp.server.mcpserver import MCPServer

server = MCPServer("aggregate-phase0", version="1.0.0")


@server.tool(structured_output=True)
def add(a: int, b: int) -> dict[str, int]:
    """Add two integers."""
    return {"sum": a + b}


@server.resource("memo://phase0/readme", mime_type="text/plain")
def readme() -> str:
    """Read the phase-zero fixture memo."""
    return "Aggregate phase 0 resource"


@server.prompt()
def welcome(name: str) -> str:
    """Build a greeting prompt."""
    return f"Greet {name} in one sentence."


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("transport", choices=["stdio", "http"])
    parser.add_argument("--port", type=int, default=8765)
    args = parser.parse_args()
    if args.transport == "stdio":
        server.run(transport="stdio")
    else:
        server.run(transport="streamable-http", host="127.0.0.1", port=args.port)
