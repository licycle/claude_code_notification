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


def _extract_user_message_from_system_reminder(text: str) -> Optional[str]:
    """Extract user message from system-reminder or tool_result content.

    Looks for patterns:
    1. <system-reminder>The user sent the following message: {message}</system-reminder>
    2. user sent the following message:\n{message}\n\nPlease address...

    Skips code file content (contains line number prefix like '→').
    """
    # Skip if this looks like code file content (has line number prefix)
    if '→' in text[:300]:
        return None

    # Pattern 1: With system-reminder tag
    pattern1 = r'<system-reminder>\s*The user sent the following message:\s*\n([^\n<]+)'
    match = re.search(pattern1, text, re.IGNORECASE)
    if match:
        return match.group(1).strip()

    # Pattern 2: Direct format (no tag)
    pattern2 = r'user sent the following message:\s*\n([^\n]+)\n'
    match = re.search(pattern2, text, re.IGNORECASE)
    if match:
        return match.group(1).strip()

    return None


def extract_all_user_messages(events: List[Dict]) -> List[str]:
    """Extract all user messages from transcript events.

    Sources:
    1. Direct user input (type=user, content=string)
    2. queue-operation events (operation=enqueue, content=string)
    3. system-reminder in tool_result

    Returns list of user messages in chronological order.
    """
    messages = []

    for event in events:
        event_type = event.get('type', '')

        # Source 1: Direct user input
        if event_type == 'user':
            content = event.get('message', {}).get('content', '')
            if isinstance(content, str) and content.strip():
                # Clean system reminders
                clean = re.sub(r'<system-reminder>[\s\S]*?</system-reminder>', '', content).strip()
                if clean:
                    messages.append(clean)

        # Source 2: queue-operation (enqueue)
        elif event_type == 'queue-operation' and event.get('operation') == 'enqueue':
            content = event.get('content', '')
            if content and isinstance(content, str):
                messages.append(content.strip())

    # Deduplicate while preserving order
    seen = set()
    unique_messages = []
    for msg in messages:
        # Use first 50 chars as key to handle slight variations
        key = msg[:50]
        if key not in seen:
            seen.add(key)
            unique_messages.append(msg)

    return unique_messages


def get_user_round_count(events: List[Dict]) -> int:
    """Get total user input round count from transcript events."""
    return len(extract_all_user_messages(events))


def extract_last_message(events: List[Dict], msg_type: str, strip_system_reminders: bool = True) -> str:
    """Extract last message of given type from events.

    For 'user' type, skips tool_result events and finds actual user input.
    Also extracts user messages from system-reminder tags in tool_result.
    """
    # First pass: look for user messages in system-reminders (tool_result content)
    if msg_type == 'user':
        for event in reversed(events):
            if event.get('type') == 'user':
                content = event.get('message', {}).get('content', '')
                if isinstance(content, list):
                    for item in content:
                        if item.get('type') == 'tool_result':
                            result_content = item.get('content', '')
                            if isinstance(result_content, str):
                                user_msg = _extract_user_message_from_system_reminder(result_content)
                                if user_msg:
                                    return user_msg

    # Second pass: look for direct user input (string content)
    for event in reversed(events):
        if event.get('type') == msg_type:
            content = event.get('message', {}).get('content', '')

            # Handle string content (real user input)
            if isinstance(content, str):
                text = content.strip()
                if text:  # Only return non-empty strings
                    # Strip system reminders if requested
                    if strip_system_reminders:
                        text = re.sub(r'<system-reminder>[\s\S]*?</system-reminder>', '', text)
                        text = re.sub(r'\n{3,}', '\n\n', text).strip()
                    return text
                continue  # Empty string, keep searching

            # Handle array content (text blocks or tool_result)
            elif isinstance(content, list):
                # Check if this is a tool_result event (skip it for user messages)
                has_tool_result = any(item.get('type') == 'tool_result' for item in content)
                if msg_type == 'user' and has_tool_result:
                    continue  # Skip tool_result, keep searching for real user input

                # Extract text from text blocks
                text = '\n'.join([
                    item.get('text', '')
                    for item in content
                    if item.get('type') == 'text'
                ])

                if text.strip():  # Only return non-empty text
                    # Strip system reminders if requested
                    if strip_system_reminders:
                        text = re.sub(r'<system-reminder>[\s\S]*?</system-reminder>', '', text)
                        text = re.sub(r'\n{3,}', '\n\n', text).strip()
                    return text
                continue  # Empty text, keep searching
            else:
                continue

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
