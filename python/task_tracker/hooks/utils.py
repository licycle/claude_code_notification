#!/usr/bin/env python3
"""
utils.py - Hook Utilities
Common utilities for all hook scripts
"""
import sys
import json
import os
import re
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Any

# Add parent directory to path for imports
TASK_TRACKER_DIR = Path(__file__).parent.parent
sys.path.insert(0, str(TASK_TRACKER_DIR))

LOG_DIR = Path.home() / '.claude-task-tracker' / 'logs'


def log(tag: str, msg: str, log_file: str = 'hooks.log'):
    """Write to log file

    Args:
        tag: Log tag (e.g., 'GOAL', 'PROGRESS', 'ERROR')
        msg: Log message
        log_file: Log file name (default: hooks.log)
    """
    try:
        LOG_DIR.mkdir(parents=True, exist_ok=True)
        log_path = LOG_DIR / log_file
        with open(log_path, 'a') as f:
            ts = datetime.now().strftime("%H:%M:%S")
            f.write(f"[{ts}] [{tag}] {msg}\n")
    except Exception:
        pass


def get_account_alias() -> str:
    """Get account alias from environment variable or infer from config path"""
    alias = os.environ.get('CLAUDE_ACCOUNT_ALIAS')
    if alias:
        return alias

    config_dir = os.environ.get('CLAUDE_CONFIG_DIR', '')
    if config_dir:
        basename = Path(config_dir).name
        if basename == '.claude':
            return 'default'
        elif basename.startswith('.claude-'):
            return basename[8:]

    return 'default'


def get_env_info() -> Dict[str, str]:
    """Get terminal environment info from environment variables"""
    return {
        'bundle_id': os.environ.get('CLAUDE_TERM_BUNDLE_ID', 'com.apple.Terminal'),
        'pid': os.environ.get('CLAUDE_TERM_PID', '0'),
        'window_id': os.environ.get('CLAUDE_CG_WINDOW_ID', '0'),
        'account_alias': get_account_alias(),
        'config_dir': os.environ.get('CLAUDE_CONFIG_DIR', '')
    }


def read_hook_input() -> Dict:
    """Read hook input from stdin"""
    try:
        data = sys.stdin.read()
        if data:
            return json.loads(data)
    except json.JSONDecodeError as e:
        log("ERROR", f"Failed to parse JSON input: {e}")
    except Exception as e:
        log("ERROR", f"Failed to read input: {e}")
    return {}


def write_hook_output(
    continue_execution: bool = True,
    suppress_output: bool = True,
    system_message: str = None,
    stop_reason: str = None
) -> None:
    """Write hook response to stdout and exit"""
    output = {
        "continue": continue_execution,
        "suppressOutput": suppress_output
    }

    if system_message:
        output["systemMessage"] = system_message

    if stop_reason and not continue_execution:
        output["stopReason"] = stop_reason

    print(json.dumps(output))
    sys.exit(0)


def parse_transcript(transcript_path: str) -> List[Dict]:
    """Parse transcript JSONL file"""
    events = []
    path = Path(transcript_path)

    if not path.exists():
        log("WARN", f"Transcript file not found: {transcript_path}")
        return events

    try:
        with open(path, 'r', encoding='utf-8') as f:
            for line in f:
                line = line.strip()
                if line:
                    try:
                        events.append(json.loads(line))
                    except json.JSONDecodeError:
                        continue
    except Exception as e:
        log("ERROR", f"Failed to parse transcript: {e}")

    return events


def extract_last_message(events: List[Dict], msg_type: str, strip_system_reminders: bool = True) -> str:
    """Extract last message of given type from events"""
    for event in reversed(events):
        if event.get('type') == msg_type:
            content = event.get('message', {}).get('content', '')

            # Handle string content
            if isinstance(content, str):
                text = content
            # Handle array content (text blocks)
            elif isinstance(content, list):
                text = '\n'.join([
                    item.get('text', '')
                    for item in content
                    if item.get('type') == 'text'
                ])
            else:
                continue

            # Strip system reminders if requested
            if strip_system_reminders and msg_type == 'assistant':
                text = re.sub(r'<system-reminder>[\s\S]*?</system-reminder>', '', text)
                text = re.sub(r'\n{3,}', '\n\n', text).strip()

            return text

    return ''


def extract_todos_from_transcript(events: List[Dict]) -> List[Dict]:
    """Extract latest todo list from transcript events"""
    for event in reversed(events):
        # Check for TodoWrite tool calls
        if event.get('tool_name') == 'TodoWrite':
            tool_input = event.get('tool_input', {})

            # Parse tool input
            if isinstance(tool_input, str):
                try:
                    tool_input = json.loads(tool_input)
                except json.JSONDecodeError:
                    continue

            todos = tool_input.get('todos', [])
            if todos:
                return todos

        # Also check tool_response
        tool_response = event.get('tool_response', {})
        if tool_response:
            if isinstance(tool_response, str):
                try:
                    tool_response = json.loads(tool_response)
                except json.JSONDecodeError:
                    continue

            if isinstance(tool_response, dict) and 'todos' in tool_response:
                return tool_response['todos']

    return []


def get_project_name(cwd: str) -> str:
    """Extract project name from working directory"""
    if not cwd:
        return 'Unknown'
    return Path(cwd).name or 'Unknown'


def detect_pending_question(events: List[Dict]) -> Optional[Dict]:
    """Detect if there's a pending AskUserQuestion"""
    for event in reversed(events):
        if event.get('tool_name') == 'AskUserQuestion':
            tool_input = event.get('tool_input', {})

            if isinstance(tool_input, str):
                try:
                    tool_input = json.loads(tool_input)
                except json.JSONDecodeError:
                    continue

            questions = tool_input.get('questions', [])
            if questions:
                q = questions[0]
                return {
                    'question': q.get('question', ''),
                    'options': [opt.get('label', '') for opt in q.get('options', [])]
                }

            # If no response yet, it's pending
            if not event.get('tool_response'):
                return {'question': 'Waiting for response', 'options': []}

    return None


def safe_json_parse(data: Any) -> Any:
    """Safely parse JSON if string, otherwise return as-is"""
    if isinstance(data, str):
        try:
            return json.loads(data)
        except json.JSONDecodeError:
            pass
    return data
