#!/usr/bin/env python3
"""Archon MCP Server — list and run workflows from any AI agent.

Usage:
  python archon-mcp.py              # stdio mode (for AI agents)
  python archon-mcp.py --serve      # HTTP mode (port 8101)

Protocol: MCP stdio transport (JSON-RPC 2.0 over stdin/stdout)
"""

import json
import os
import subprocess
import sys

ARCHON_BIN = os.path.expanduser("~/.bun/bin/archon")


def archon_run(*args, cwd=None, timeout=120):
    try:
        result = subprocess.run(
            [ARCHON_BIN, *args],
            cwd=cwd or os.getcwd(),
            capture_output=True,
            text=True,
            timeout=timeout,
        )
        return result.stdout, result.stderr, result.returncode
    except FileNotFoundError:
        return None, "archon not found", -1
    except subprocess.TimeoutExpired:
        return None, "timeout", -1


TOOLS = [
    {
        "name": "archon_list_workflows",
        "description": "List all available Archon workflows in the current project. Use this to discover what development pipelines exist.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "cwd": {"type": "string", "description": "Project directory (default: current dir)"},
            },
        },
    },
    {
        "name": "archon_run_workflow",
        "description": "Run an Archon workflow. This is the main entry point for structured AI development — plan, implement, review, and create PRs.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "workflow": {"type": "string", "description": "Workflow name (e.g. agent-feature, agent-fix, agent-hotfix, agent-chore, agent-review)"},
                "message": {"type": "string", "description": "Description of what to do"},
                "cwd": {"type": "string", "description": "Project directory (default: current dir)"},
                "branch": {"type": "string", "description": "Branch name for isolated worktree (default: auto-generated)"},
                "no_worktree": {"type": "boolean", "description": "Run on current branch without worktree isolation"},
            },
            "required": ["workflow", "message"],
        },
    },
    {
        "name": "archon_workflow_status",
        "description": "Check status of running or recent workflows. Shows progress, failures, and artifacts.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "cwd": {"type": "string", "description": "Project directory (default: current dir)"},
            },
        },
    },
    {
        "name": "archon_list_worktrees",
        "description": "List all active worktrees (isolated branch environments). Shows what branches are being worked on.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "cwd": {"type": "string", "description": "Project directory (default: current dir)"},
            },
        },
    },
    {
        "name": "archon_complete_branch",
        "description": "Mark a branch as complete — removes worktree + local and remote branches after PR merge.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "branch": {"type": "string", "description": "Branch name to complete"},
                "cwd": {"type": "string", "description": "Project directory (default: current dir)"},
            },
            "required": ["branch"],
        },
    },
    {
        "name": "archon_validate_workflows",
        "description": "Validate all workflow YAML definitions. Run after editing .archon/workflows/ files.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "cwd": {"type": "string", "description": "Project directory (default: current dir)"},
            },
        },
    },
]


def handle(req):
    method = req.get("method", "")
    req_id = req.get("id")

    if method == "initialize":
        return {
            "jsonrpc": "2.0", "id": req_id,
            "result": {
                "protocolVersion": "0.1.0",
                "capabilities": {"tools": {}},
                "serverInfo": {"name": "archon-mcp", "version": "1.0.0"},
            },
        }
    elif method == "list_tools":
        return {"jsonrpc": "2.0", "id": req_id, "result": {"tools": TOOLS}}
    elif method == "call_tool":
        return call_tool(req)
    else:
        return {"jsonrpc": "2.0", "id": req_id, "error": {"code": -32601, "message": f"Unknown: {method}"}}


def call_tool(req):
    name = req.get("params", {}).get("name", "")
    args = req.get("params", {}).get("arguments", {})
    req_id = req.get("id")
    cwd = args.get("cwd", os.getcwd())

    if name == "archon_list_workflows":
        out, err, rc = archon_run("workflow", "list", "--json", cwd=cwd)
        if rc != 0:
            return err_resp(req_id, f"Failed: {err}")
        return ok_resp(req_id, out or "No workflows found")

    elif name == "archon_run_workflow":
        workflow = args.get("workflow")
        message = args.get("message")
        branch = args.get("branch")
        no_worktree = args.get("no_worktree", False)
        cmd = ["workflow", "run", workflow, message]
        if branch:
            cmd.extend(["--branch", branch])
        if no_worktree:
            cmd.append("--no-worktree")
        out, err, rc = archon_run(*cmd, cwd=cwd, timeout=600)
        if rc != 0:
            return err_resp(req_id, f"Workflow failed: {err}")
        return ok_resp(req_id, out or f"Workflow '{workflow}' completed")

    elif name == "archon_workflow_status":
        out, err, rc = archon_run("workflow", "status", cwd=cwd)
        if rc != 0:
            return ok_resp(req_id, f"No running workflows: {err}")
        return ok_resp(req_id, out or "No active workflows")

    elif name == "archon_list_worktrees":
        out, err, rc = archon_run("isolation", "list", cwd=cwd)
        if rc != 0:
            return ok_resp(req_id, f"No worktrees: {err}")
        return ok_resp(req_id, out or "No active worktrees")

    elif name == "archon_complete_branch":
        branch = args.get("branch")
        out, err, rc = archon_run("complete", branch, cwd=cwd)
        if rc != 0:
            return err_resp(req_id, f"Failed to complete branch: {err}")
        return ok_resp(req_id, out or f"Branch '{branch}' completed")

    elif name == "archon_validate_workflows":
        out, err, rc = archon_run("validate", "workflows", cwd=cwd)
        if rc == 0:
            return ok_resp(req_id, "All workflows valid")
        return ok_resp(req_id, err or "Validation issues found")

    return err_resp(req_id, f"Unknown tool: {name}")


def err_resp(req_id, msg):
    return {"jsonrpc": "2.0", "id": req_id, "error": {"code": -32000, "message": msg}}


def ok_resp(req_id, text):
    return {"jsonrpc": "2.0", "id": req_id, "result": {"content": [{"type": "text", "text": text}]}}


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
            resp = handle(req)
            write_stdio(resp)
        except json.JSONDecodeError as e:
            write_stdio({"jsonrpc": "2.0", "error": {"code": -32700, "message": str(e)}})
        except Exception as e:
            write_stdio({"jsonrpc": "2.0", "error": {"code": -32603, "message": str(e)}})


def main_http(port=8101):
    from http.server import HTTPServer, BaseHTTPRequestHandler

    class Handler(BaseHTTPRequestHandler):
        def do_POST(self):
            length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(length)
            try:
                req = json.loads(body)
                resp = handle(req)
            except Exception as e:
                resp = {"jsonrpc": "2.0", "error": {"code": -32700, "message": str(e)}}
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps(resp).encode())

        def log_message(self, fmt, *args):
            pass

    server = HTTPServer(("", port), Handler)
    print(f"[archon-mcp] HTTP serving on port {port}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    if "--serve" in sys.argv:
        port = 8101
        if "--port" in sys.argv:
            idx = sys.argv.index("--port")
            if idx + 1 < len(sys.argv):
                port = int(sys.argv[idx + 1])
        main_http(port)
    else:
        main_stdio()
