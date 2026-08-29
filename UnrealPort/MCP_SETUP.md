# Unreal MCP setup

The project uses the Unreal Engine MCP plugins already enabled in `DerClue.uproject`.

1. Open `UnrealPort/DerClue.uproject` with Unreal Engine 5.8.
2. In the Unreal console run `ModelContextProtocol.StartServer`.
3. The local server listens at `http://127.0.0.1:8000/mcp`.
4. Claude Code, Codex or another MCP client can use the checked-in `UnrealPort/.mcp.json` configuration.

The level itself remains the source of truth. Generated editor state, caches and build output are intentionally excluded from Git.
