#!/usr/bin/env python3
"""
MCP Server for Claude Todo System
Provides HTTP-based MCP server for Claude Code integration

Usage:
    python3 -m task_tracker.mcp.server [--port PORT] [--host HOST]

Or start via CLI:
    claude-todo server start
"""
import argparse
import json
import logging
import os
import signal
import sys
from http.server import HTTPServer, BaseHTTPRequestHandler
from pathlib import Path
from typing import Dict, Any, Callable
from urllib.parse import parse_qs, urlparse

from .config import get_mcp_config, DEFAULT_CONFIG
from .tools import (
    list_todos,
    get_todo,
    start_todo,
    complete_todo,
    split_todo,
    create_todo,
    update_todo,
    get_pending_todos,
)

# Configure logging - support environment variable for log directory
# This allows Swift app to specify log location when launching MCP server
LOG_DIR = Path(os.environ.get('CLAUDE_LOG_DIR',
               str(Path.home() / '.claude-task-tracker' / 'logs')))
LOG_DIR.mkdir(parents=True, exist_ok=True)
LOG_FILE = LOG_DIR / 'mcp_server.log'

# Fallback log directory if primary is protected by macOS
FALLBACK_LOG_DIR = Path('/tmp/claude/logs')
FALLBACK_LOG_FILE = FALLBACK_LOG_DIR / 'mcp_server.log'


def _setup_logging():
    """Setup logging with fallback for protected directories"""
    handlers = [logging.StreamHandler()]

    # Try primary log file
    try:
        LOG_FILE.parent.mkdir(parents=True, exist_ok=True)
        # Test if we can write to the file
        with open(LOG_FILE, 'a') as f:
            pass
        handlers.append(logging.FileHandler(LOG_FILE))
    except (PermissionError, OSError):
        # Fallback to /tmp/claude/logs
        try:
            FALLBACK_LOG_DIR.mkdir(parents=True, exist_ok=True)
            handlers.append(logging.FileHandler(FALLBACK_LOG_FILE))
            print(f"Warning: Using fallback log: {FALLBACK_LOG_FILE}", file=sys.stderr)
        except (PermissionError, OSError):
            # Only use stderr if all else fails
            print("Warning: File logging disabled, using stderr only", file=sys.stderr)

    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
        handlers=handlers
    )


_setup_logging()
logger = logging.getLogger('mcp_server')

# PID file for daemon management
# Use /tmp/claude/ to avoid macOS sandbox permission issues
PID_DIR = Path('/tmp/claude')
PID_DIR.mkdir(parents=True, exist_ok=True)
PID_FILE = PID_DIR / 'mcp_server.pid'


# ============================================================================
# MCP Protocol Types
# ============================================================================

MCP_PROTOCOL_VERSION = "2024-11-05"

TOOL_DEFINITIONS = [
    {
        "name": "list_todos",
        "description": "List todos for a project. Returns todos with their status, priority, and progress.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "project_path": {
                    "type": "string",
                    "description": "Project path to filter by. If not specified, uses current project."
                },
                "status": {
                    "type": "string",
                    "enum": ["all", "pending", "in_progress", "blocked", "completed", "cancelled"],
                    "default": "all",
                    "description": "Filter by todo status"
                },
                "include_children": {
                    "type": "boolean",
                    "default": True,
                    "description": "Whether to include child todos"
                },
                "limit": {
                    "type": "integer",
                    "default": 20,
                    "description": "Maximum number of todos to return"
                }
            }
        }
    },
    {
        "name": "get_todo",
        "description": "Get detailed information about a specific todo including its dependencies.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "todo_id": {
                    "type": "integer",
                    "description": "The ID of the todo"
                },
                "include_children": {
                    "type": "boolean",
                    "default": True,
                    "description": "Whether to include child todos"
                }
            },
            "required": ["todo_id"]
        }
    },
    {
        "name": "start_todo",
        "description": "Start working on a todo. Marks the todo as 'in_progress' and links it to the current session.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "todo_id": {
                    "type": "integer",
                    "description": "The ID of the todo to start"
                },
                "notes": {
                    "type": "string",
                    "description": "Optional notes about starting this todo"
                }
            },
            "required": ["todo_id"]
        }
    },
    {
        "name": "complete_todo",
        "description": "Mark a todo as completed with an optional summary of what was accomplished.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "todo_id": {
                    "type": "integer",
                    "description": "The ID of the todo to complete"
                },
                "summary": {
                    "type": "string",
                    "description": "A brief summary of what was accomplished"
                },
                "actual_minutes": {
                    "type": "integer",
                    "description": "Actual time spent in minutes"
                }
            },
            "required": ["todo_id"]
        }
    },
    {
        "name": "split_todo",
        "description": "Split a todo into smaller sub-todos for better task management.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "todo_id": {
                    "type": "integer",
                    "description": "The ID of the parent todo to split"
                },
                "sub_todos": {
                    "type": "array",
                    "items": {
                        "type": "object",
                        "properties": {
                            "title": {"type": "string", "description": "Title of the sub-todo"},
                            "description": {"type": "string", "description": "Description"},
                            "priority": {"type": "integer", "description": "0=normal, 1=high, 2=urgent"},
                            "estimated_minutes": {"type": "integer", "description": "Time estimate"}
                        },
                        "required": ["title"]
                    },
                    "description": "List of sub-todo definitions"
                }
            },
            "required": ["todo_id", "sub_todos"]
        }
    },
    {
        "name": "create_todo",
        "description": "Create a new todo for the current project.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "title": {
                    "type": "string",
                    "description": "Title of the todo"
                },
                "project_path": {
                    "type": "string",
                    "description": "Project path. If not specified, uses current project."
                },
                "description": {
                    "type": "string",
                    "description": "Detailed description"
                },
                "priority": {
                    "type": "integer",
                    "enum": [0, 1, 2],
                    "default": 0,
                    "description": "0=normal, 1=high, 2=urgent"
                },
                "estimated_minutes": {
                    "type": "integer",
                    "description": "Time estimate in minutes"
                },
                "global_task_id": {
                    "type": "integer",
                    "description": "Optional global task to link to"
                },
                "parent_todo_id": {
                    "type": "integer",
                    "description": "Optional parent todo for sub-tasks"
                }
            },
            "required": ["title"]
        }
    },
    {
        "name": "update_todo",
        "description": "Update an existing todo's properties.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "todo_id": {
                    "type": "integer",
                    "description": "The ID of the todo to update"
                },
                "title": {
                    "type": "string",
                    "description": "New title"
                },
                "description": {
                    "type": "string",
                    "description": "New description"
                },
                "status": {
                    "type": "string",
                    "enum": ["pending", "in_progress", "blocked", "completed", "cancelled"],
                    "description": "New status"
                },
                "priority": {
                    "type": "integer",
                    "enum": [0, 1, 2],
                    "description": "New priority"
                },
                "estimated_minutes": {
                    "type": "integer",
                    "description": "New time estimate"
                }
            },
            "required": ["todo_id"]
        }
    }
]

# Tool function mapping
TOOL_HANDLERS: Dict[str, Callable] = {
    "list_todos": list_todos,
    "get_todo": get_todo,
    "start_todo": start_todo,
    "complete_todo": complete_todo,
    "split_todo": split_todo,
    "create_todo": create_todo,
    "update_todo": update_todo,
}


# ============================================================================
# MCP HTTP Handler
# ============================================================================

class MCPRequestHandler(BaseHTTPRequestHandler):
    """HTTP Request Handler for MCP Protocol"""

    def log_message(self, format, *args):
        """Override to use our logger"""
        logger.info("%s - %s", self.address_string(), format % args)

    def _send_json_response(self, data: Dict, status: int = 200):
        """Send JSON response"""
        response = json.dumps(data, ensure_ascii=False)
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', len(response.encode('utf-8')))
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
        self.end_headers()
        self.wfile.write(response.encode('utf-8'))

    def _send_error_response(self, error: str, status: int = 400):
        """Send error response"""
        self._send_json_response({
            "jsonrpc": "2.0",
            "error": {
                "code": -32600,
                "message": error
            }
        }, status)

    def do_OPTIONS(self):
        """Handle CORS preflight"""
        self.send_response(200)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
        self.end_headers()

    def do_GET(self):
        """Handle GET requests"""
        parsed = urlparse(self.path)

        if parsed.path == '/health':
            self._send_json_response({"status": "ok", "version": MCP_PROTOCOL_VERSION})
        elif parsed.path == '/mcp':
            # Return server capabilities
            self._send_json_response({
                "protocolVersion": MCP_PROTOCOL_VERSION,
                "capabilities": {
                    "tools": {}
                },
                "serverInfo": {
                    "name": "claude-todo-server",
                    "version": "1.0.0"
                }
            })
        else:
            self._send_error_response("Not Found", 404)

    def do_POST(self):
        """Handle POST requests (MCP calls)"""
        if self.path != '/mcp':
            self._send_error_response("Not Found", 404)
            return

        try:
            content_length = int(self.headers.get('Content-Length', 0))
            body = self.rfile.read(content_length).decode('utf-8')
            request = json.loads(body)

            logger.info(f"MCP Request: {request.get('method')}")

            response = self._handle_mcp_request(request)
            self._send_json_response(response)

        except json.JSONDecodeError as e:
            self._send_error_response(f"Invalid JSON: {e}")
        except Exception as e:
            logger.exception("Error handling request")
            self._send_error_response(f"Internal error: {e}", 500)

    def _handle_mcp_request(self, request: Dict) -> Dict:
        """Handle MCP JSON-RPC request"""
        method = request.get('method')
        params = request.get('params', {})
        request_id = request.get('id')

        if method == 'initialize':
            return self._handle_initialize(request_id, params)
        elif method == 'tools/list':
            return self._handle_tools_list(request_id)
        elif method == 'tools/call':
            return self._handle_tools_call(request_id, params)
        else:
            return {
                "jsonrpc": "2.0",
                "id": request_id,
                "error": {
                    "code": -32601,
                    "message": f"Method not found: {method}"
                }
            }

    def _handle_initialize(self, request_id, params: Dict) -> Dict:
        """Handle initialize request"""
        return {
            "jsonrpc": "2.0",
            "id": request_id,
            "result": {
                "protocolVersion": MCP_PROTOCOL_VERSION,
                "capabilities": {
                    "tools": {}
                },
                "serverInfo": {
                    "name": "claude-todo-server",
                    "version": "1.0.0"
                }
            }
        }

    def _handle_tools_list(self, request_id) -> Dict:
        """Handle tools/list request"""
        return {
            "jsonrpc": "2.0",
            "id": request_id,
            "result": {
                "tools": TOOL_DEFINITIONS
            }
        }

    def _handle_tools_call(self, request_id, params: Dict) -> Dict:
        """Handle tools/call request"""
        tool_name = params.get('name')
        tool_args = params.get('arguments', {})

        if tool_name not in TOOL_HANDLERS:
            return {
                "jsonrpc": "2.0",
                "id": request_id,
                "error": {
                    "code": -32602,
                    "message": f"Unknown tool: {tool_name}"
                }
            }

        try:
            handler = TOOL_HANDLERS[tool_name]
            result = handler(**tool_args)

            return {
                "jsonrpc": "2.0",
                "id": request_id,
                "result": {
                    "content": [
                        {
                            "type": "text",
                            "text": json.dumps(result, ensure_ascii=False, indent=2)
                        }
                    ]
                }
            }

        except Exception as e:
            logger.exception(f"Error calling tool {tool_name}")
            return {
                "jsonrpc": "2.0",
                "id": request_id,
                "error": {
                    "code": -32603,
                    "message": str(e)
                }
            }


# ============================================================================
# Server Management
# ============================================================================

def write_pid_file():
    """Write PID file for daemon management"""
    PID_FILE.parent.mkdir(parents=True, exist_ok=True)
    PID_FILE.write_text(str(os.getpid()))


def remove_pid_file():
    """Remove PID file with error handling for sandbox restrictions"""
    if PID_FILE.exists():
        try:
            PID_FILE.unlink()
        except (PermissionError, OSError) as e:
            logger.warning(f"Could not remove PID file: {e}")


def get_server_pid() -> int:
    """Get server PID from file"""
    if PID_FILE.exists():
        try:
            return int(PID_FILE.read_text().strip())
        except (ValueError, IOError):
            pass
    return None


def is_server_running() -> bool:
    """Check if server is running"""
    pid = get_server_pid()
    if pid:
        try:
            os.kill(pid, 0)
            return True
        except OSError:
            # Process not running, clean up stale PID file
            remove_pid_file()
    return False


def start_server(host: str = None, port: int = None, daemon: bool = False):
    """Start the MCP server"""
    config = get_mcp_config()
    host = host or config.get('host', DEFAULT_CONFIG['host'])
    port = port or config.get('port', DEFAULT_CONFIG['port'])

    if is_server_running():
        logger.warning(f"Server already running with PID {get_server_pid()}")
        return

    if daemon:
        # Fork to background
        pid = os.fork()
        if pid > 0:
            # Parent process
            print(f"Server started in background with PID {pid}")
            return

        # Child process
        os.setsid()
        # Close standard file descriptors
        sys.stdin.close()
        sys.stdout.close()
        sys.stderr.close()

    # Set up signal handlers
    def signal_handler(signum, frame):
        logger.info("Received shutdown signal")
        remove_pid_file()
        sys.exit(0)

    signal.signal(signal.SIGTERM, signal_handler)
    signal.signal(signal.SIGINT, signal_handler)

    write_pid_file()

    server = HTTPServer((host, port), MCPRequestHandler)
    logger.info(f"MCP Server starting on http://{host}:{port}/mcp")

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        logger.info("Server stopped by user")
    finally:
        remove_pid_file()
        server.server_close()


def stop_server():
    """Stop the MCP server"""
    pid = get_server_pid()
    if not pid:
        print("Server is not running")
        return False

    try:
        os.kill(pid, signal.SIGTERM)
        print(f"Server (PID {pid}) stopped")
        remove_pid_file()
        return True
    except OSError as e:
        print(f"Failed to stop server: {e}")
        remove_pid_file()
        return False


def server_status() -> Dict:
    """Get server status"""
    running = is_server_running()
    config = get_mcp_config()

    return {
        "running": running,
        "pid": get_server_pid() if running else None,
        "url": f"http://{config['host']}:{config['port']}/mcp",
        "config": config
    }


# ============================================================================
# Main Entry Point
# ============================================================================

def main():
    parser = argparse.ArgumentParser(description='Claude Todo MCP Server')
    parser.add_argument('--host', default=None, help='Host to bind to')
    parser.add_argument('--port', type=int, default=None, help='Port to listen on')
    parser.add_argument('--daemon', '-d', action='store_true', help='Run in background')

    args = parser.parse_args()

    start_server(host=args.host, port=args.port, daemon=args.daemon)


if __name__ == '__main__':
    main()
