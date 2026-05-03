#!/usr/bin/env python3
"""Graphify MCP Server — query knowledge graph from any agent.

Usage:
  python graphify-mcp.py          # stdio mode (for AI agents)
  python graphify-mcp.py --serve  # HTTP mode (port 8100)

Protocol: MCP stdio transport (JSON-RPC 2.0 over stdin/stdout)
"""

import json
import os
import subprocess
import sys
import re

GRAPHIFY_DIR = os.path.expanduser("~/projects/graphify")

def graphify_run(*args, timeout=30):
    try:
        result = subprocess.run(
            ["uv", "run", "graphify", *args],
            cwd=os.getcwd(),
            capture_output=True,
            text=True,
            timeout=timeout,
        )
        return result.stdout, result.stderr, result.returncode
    except FileNotFoundError:
        try:
            result = subprocess.run(
                ["python3", "-m", "graphify", *args],
                cwd=os.getcwd(),
                capture_output=True,
                text=True,
                timeout=timeout,
            )
            return result.stdout, result.stderr, result.returncode
        except FileNotFoundError:
            return None, "graphify not found", -1
    except subprocess.TimeoutExpired:
        return None, "timeout", -1


TOOLS = [
    {
        "name": "graphify_scan",
        "description": "Scan project and build/update knowledge graph. Call after significant code changes.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "path": {"type": "string", "description": "Project path (default: current dir)"},
                "quiet": {"type": "boolean", "description": "Suppress output"},
            },
        },
    },
    {
        "name": "graphify_query",
        "description": "Query the knowledge graph for module relationships, dependencies, and structure. Use to understand codebase architecture before making changes.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "query": {
                    "type": "string",
                    "description": "Search term: module name, file path, class, or function",
                },
                "type": {
                    "type": "string",
                    "description": "What to return",
                    "enum": ["dependencies", "dependents", "all"],
                    "default": "all",
                },
            },
            "required": ["query"],
        },
    },
    {
        "name": "graphify_community",
        "description": "List clustered communities in the knowledge graph. Shows how modules group together — useful for understanding bounded contexts.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "min_size": {
                    "type": "integer",
                    "description": "Minimum cluster size to include",
                    "default": 3,
                },
            },
        },
    },
    {
        "name": "graphify_agent_attribution",
        "description": "Show which AI agents modified which parts of the codebase. Helps understand context of previous agent sessions.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "agent": {
                    "type": "string",
                    "description": "Filter by agent name (opencode, claude-code, hermes, pi)",
                },
                "since": {
                    "type": "string",
                    "description": "Show changes since date (YYYY-MM-DD)",
                },
            },
        },
    },
]


def handle_initialize(req):
    return {
        "jsonrpc": "2.0",
        "id": req.get("id"),
        "result": {
            "protocolVersion": "0.1.0",
            "capabilities": {"tools": {}},
            "serverInfo": {"name": "graphify-mcp", "version": "1.0.0"},
        },
    }


def handle_list_tools(req):
    return {"jsonrpc": "2.0", "id": req.get("id"), "result": {"tools": TOOLS}}


def handle_call_tool(req):
    name = req.get("params", {}).get("name", "")
    args = req.get("params", {}).get("arguments", {})
    tool_id = req.get("id")

    if name == "graphify_scan":
        path = args.get("path", os.getcwd())
        quiet = args.get("quiet", False)
        stdout, stderr, rc = graphify_run("scan", path, "--quiet" if quiet else "")
        if rc != 0:
            return error(tool_id, f"Scan failed: {stderr}")
        return result(tool_id, stdout or "Scan complete")

    elif name == "graphify_query":
        query = args.get("query", "")
        result_type = args.get("type", "all")
        stdout, stderr, rc = graphify_run("query", query)
        if rc != 0:
            return error(tool_id, f"Query failed: {stderr}")
        lines = stdout.strip().split("\n") if stdout else []
        deps = [l for l in lines if "->" in l or "depends" in l.lower()]
        if result_type == "dependencies":
            return result(tool_id, "\n".join(deps) if deps else "No dependencies found")
        elif result_type == "dependents":
            deps_of = [l for l in lines if "depended" in l.lower() or "<-" in l]
            return result(tool_id, "\n".join(deps_of) if deps_of else "No dependents found")
        return result(tool_id, stdout or "No results")

    elif name == "graphify_community":
        min_size = args.get("min_size", 3)
        stdout, stderr, rc = graphify_run("cluster")
        if rc != 0:
            return result(tool_id, f"Community detection skipped: {stderr}")
        return result(tool_id, stdout or "No communities found")

    elif name == "graphify_agent_attribution":
        agent = args.get("agent", "")
        since = args.get("since", "")
        stdout, stderr, rc = graphify_run("agent-attribution")
        if rc != 0:
            return result(tool_id, f"Agent attribution unavailable: {stderr}")
        lines = stdout.strip().split("\n") if stdout else []
        if agent:
            lines = [l for l in lines if agent.lower() in l.lower()]
        return result(tool_id, "\n".join(lines) if lines else "No attribution data")

    return error(tool_id, f"Unknown tool: {name}")


def error(req_id, msg):
    return {"jsonrpc": "2.0", "id": req_id, "error": {"code": -32000, "message": msg}}


def result(req_id, text):
    return {
        "jsonrpc": "2.0",
        "id": req_id,
        "result": {
            "content": [{"type": "text", "text": text}],
        },
    }


HANDLERS = {
    "initialize": handle_initialize,
    "list_tools": handle_list_tools,
    "call_tool": handle_call_tool,
}


STDIN = sys.stdin.buffer
STDOUT = sys.stdout.buffer


def read_stdio():
    headers = {}
    while True:
        raw = STDIN.readline()
        if not raw:
            return None
        line = raw.decode().strip()
        if line == "":
            break
        if ":" in line:
            key, val = line.split(":", 1)
            headers[key.strip().lower()] = val.strip()
    length = int(headers.get("content-length", 0))
    if length == 0:
        return None
    raw = STDIN.read(length)
    return json.loads(raw.decode())


def write_stdio(obj):
    out = json.dumps(obj).encode()
    STDOUT.write(f"Content-Length: {len(out)}\r\n\r\n".encode())
    STDOUT.write(out)
    STDOUT.flush()


def main_stdio():
    while True:
        try:
            req = read_stdio()
            if req is None:
                break
            method = req.get("method", "")
            handler = HANDLERS.get(method)
            if handler:
                response = handler(req)
            else:
                response = {"jsonrpc": "2.0", "id": req.get("id"), "error": {"code": -32601, "message": f"Unknown method: {method}"}}
            write_stdio(response)
        except json.JSONDecodeError as e:
            write_stdio({"jsonrpc": "2.0", "error": {"code": -32700, "message": str(e)}})
        except Exception as e:
            write_stdio({"jsonrpc": "2.0", "error": {"code": -32603, "message": str(e)}})


def main_http(port=8100):
    from http.server import HTTPServer, BaseHTTPRequestHandler

    class Handler(BaseHTTPRequestHandler):
        def do_POST(self):
            length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(length)
            try:
                req = json.loads(body)
                method = req.get("method", "")
                handler = HANDLERS.get(method)
                if handler:
                    resp = handler(req)
                else:
                    resp = {"jsonrpc": "2.0", "id": req.get("id"), "error": {"code": -32601, "message": f"Unknown method: {method}"}}
            except Exception as e:
                resp = {"jsonrpc": "2.0", "error": {"code": -32700, "message": str(e)}}
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps(resp).encode())

        def log_message(self, fmt, *args):
            pass

    server = HTTPServer(("", port), Handler)
    print(f"[graphify-mcp] HTTP serving on port {port}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    if "--serve" in sys.argv:
        port = 8100
        if "--port" in sys.argv:
            idx = sys.argv.index("--port")
            if idx + 1 < len(sys.argv):
                port = int(sys.argv[idx + 1])
        main_http(port)
    else:
        main_stdio()
