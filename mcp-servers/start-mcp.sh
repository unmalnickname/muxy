#!/bin/bash
# Start all MCP servers for the agent workflow.
# Usage: ./start-mcp.sh [--foreground]

MCP_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_DIR="$MCP_DIR/logs"
mkdir -p "$LOG_DIR"

echo "=== Starting MCP Servers ==="

# Graphify MCP (port 8100)
if [ -f "$MCP_DIR/graphify-mcp.py" ]; then
    python3 "$MCP_DIR/graphify-mcp.py" --serve --port 8100 &
    echo "[graphify-mcp] PID $! — HTTP :8100, stdio available"
fi

# Archon MCP (port 8101)
if [ -f "$MCP_DIR/archon-mcp.py" ]; then
    python3 "$MCP_DIR/archon-mcp.py" --serve --port 8101 &
    echo "[archon-mcp]   PID $! — HTTP :8101, stdio available"
fi

echo ""
echo "MCP servers running. To test:"
echo "  curl -X POST http://localhost:8100 -d '{\"method\":\"list_tools\",\"id\":1}'"
echo "  curl -X POST http://localhost:8101 -d '{\"method\":\"list_tools\",\"id\":1}'"
echo ""
echo "To stop: pkill -f 'graphify-mcp\|archon-mcp'"
