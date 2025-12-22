#!/usr/bin/env python3
"""
notification.py - Rich Notification Service
Sends rich notifications via ClaudeMonitor Swift app

v2: Uses notification_formatter for structured title/subtitle/body format
"""
import sys
import json
import subprocess
from pathlib import Path
from datetime import datetime
from typing import Dict, List

# Add parent paths for imports when running as script
_current_dir = Path(__file__).parent
_parent_dir = _current_dir.parent
if str(_parent_dir) not in sys.path:
    sys.path.insert(0, str(_parent_dir))
if str(_current_dir) not in sys.path:
    sys.path.insert(0, str(_current_dir))

from notification_formatter import format_notification, get_category_identifier
from hooks.utils import log, get_env_info
from services.database import get_round_count

# Paths
STATE_DIR = Path.home() / '.claude-task-tracker' / 'state'
BIN_PATH = Path.home() / 'Applications' / 'ClaudeMonitor.app' / 'Contents' / 'MacOS' / 'ClaudeMonitor'


def _log(tag: str, msg: str):
    """Wrapper for log with notification-specific log file"""
    log(tag, msg, log_file='notification.log')


def send_rich_notification(
    session_id: str,
    title: str,
    message: str,
    notification_type: str = 'task_status',
    project_name: str = None,
    original_goal: str = None,
    progress_completed: int = 0,
    progress_total: int = 0,
    pending_question: str = None,
    pending_options: List[str] = None,
    summary: Dict = None,
    sound: str = 'Glass',
    round_count: int = 0
) -> bool:
    """
    Send rich notification with task details.

    The notification includes structured data that can be displayed
    in a rich notification UI.
    """
    env_info = get_env_info()

    # Build notification payload for Swift app
    payload = {
        'session_id': session_id,
        'notification_type': notification_type,
        'title': title,
        'message': message,
        'sound': sound,
        'project_name': project_name,
        'original_goal': original_goal,
        'progress': {
            'completed': progress_completed,
            'total': progress_total
        },
        'pending_decision': {
            'question': pending_question,
            'options': pending_options or []
        } if pending_question else None,
        'summary': summary,
        'terminal': {
            'bundle_id': env_info['bundle_id'],
            'pid': env_info['pid'],
            'window_id': env_info['window_id']
        },
        'account_alias': env_info['account_alias'],
        'timestamp': datetime.now().isoformat(),
        'round_count': round_count  # Pass round count in payload
    }

    # Write to state file for ClaudeMonitor to read
    _write_state_file(session_id, payload)

    # Send notification via Swift app with rich data
    return _send_via_swift_app(payload, env_info)


def _send_via_swift_app(payload: Dict, env_info: Dict) -> bool:
    """Send notification via ClaudeMonitor Swift app (v2 format)"""
    try:
        # Use v2 formatter for structured notification
        pending = payload.get('pending_decision')
        summary = payload.get('summary', {}) or {}

        # Use round count from payload (transcript-based), fallback to database
        session_id = payload.get('session_id', '')
        round_count = payload.get('round_count', 0)
        if round_count == 0 and session_id:
            round_count = get_round_count(session_id)

        formatted = format_notification(
            notification_type=payload.get('notification_type', 'idle'),
            session_id=session_id,
            account_alias=env_info['account_alias'],
            round_count=round_count,
            current_task=summary.get('current_task') or payload.get('message', ''),
            project_name=payload.get('project_name', ''),
            original_goal=payload.get('original_goal', ''),
            message=payload.get('message', ''),
            pending_question=pending.get('question') if pending else None,
            summary=summary  # Pass summary for raw mode detection
        )

        # Get category identifier
        category = get_category_identifier(payload.get('notification_type', 'idle'))

        # Call Swift app with v2 format (includes subtitle)
        # Args: notify <title> <message> <subtitle> <sound> <category> <bundle_id> <pid> <cgWindowID>
        cmd = [
            str(BIN_PATH),
            'notify',
            formatted['title'],
            formatted['body'],
            formatted['subtitle'],
            payload.get('sound', 'Glass'),
            category,
            env_info['bundle_id'],
            env_info['pid'],
            env_info['window_id']
        ]

        _log("SEND", f"Calling: {cmd[0]} notify ...")
        _log("SEND", f"  title: {formatted['title']}")
        _log("SEND", f"  subtitle: {formatted['subtitle']}")
        _log("SEND", f"  body: {formatted['body'][:50]}...")

        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=10
        )

        if result.returncode == 0:
            _log("SUCCESS", f"Notification sent: {formatted['title']}")
            return True
        else:
            _log("ERROR", f"Failed with code {result.returncode}: {result.stderr}")
            return False

    except subprocess.TimeoutExpired:
        _log("ERROR", "Notification timeout")
        return False
    except FileNotFoundError:
        _log("ERROR", f"ClaudeMonitor not found at {BIN_PATH}")
        # Fallback to osascript
        return _send_via_osascript(payload)
    except Exception as e:
        _log("ERROR", f"Failed to send notification: {e}")
        return False


def _send_via_osascript(payload: Dict) -> bool:
    """Fallback: send notification via osascript"""
    try:
        title = payload['title']
        message = payload['message']

        script = f'display notification "{message}" with title "{title}" sound name "Glass"'

        subprocess.run(
            ['osascript', '-e', script],
            check=True,
            capture_output=True,
            timeout=5
        )

        _log("SUCCESS", f"Sent via osascript: {title}")
        return True

    except Exception as e:
        _log("ERROR", f"osascript fallback failed: {e}")
        return False


def _write_state_file(session_id: str, payload: Dict):
    """Write session state to file for ClaudeMonitor to read"""
    try:
        STATE_DIR.mkdir(parents=True, exist_ok=True)

        # Individual session state file
        session_file = STATE_DIR / f'{session_id}.json'
        with open(session_file, 'w') as f:
            json.dump(payload, f, indent=2, ensure_ascii=False)

        # Update combined sessions file
        all_sessions_file = STATE_DIR / 'all_sessions.json'
        all_sessions = {}

        if all_sessions_file.exists():
            try:
                with open(all_sessions_file, 'r') as f:
                    all_sessions = json.load(f)
            except (json.JSONDecodeError, IOError):
                all_sessions = {}

        all_sessions[session_id] = payload

        with open(all_sessions_file, 'w') as f:
            json.dump(all_sessions, f, indent=2, ensure_ascii=False)

        _log("STATE", f"Wrote state for session {session_id}")

    except Exception as e:
        _log("ERROR", f"Failed to write state file: {e}")


# Convenience functions for different notification types

def notify_task_idle(session_id: str, project_name: str, original_goal: str,
                     completed: int = 0, total: int = 0, summary: Dict = None,
                     round_count: int = 0):
    """Notify that a task is idle (waiting for user input)"""
    return send_rich_notification(
        session_id=session_id,
        title=f"Idle - {project_name}",
        message=original_goal[:100] if original_goal else "Waiting for input",
        notification_type='idle',
        project_name=project_name,
        original_goal=original_goal,
        progress_completed=completed,
        progress_total=total,
        summary=summary,
        sound='Glass',
        round_count=round_count
    )


def notify_decision_needed(session_id: str, project_name: str, question: str,
                           options: List[str] = None, completed: int = 0, total: int = 0,
                           summary: Dict = None, round_count: int = 0):
    """Notify that user decision is needed"""
    return send_rich_notification(
        session_id=session_id,
        title=f"Decision Needed - {project_name}",
        message=question[:100],
        notification_type='decision_needed',
        project_name=project_name,
        pending_question=question,
        pending_options=options,
        progress_completed=completed,
        progress_total=total,
        summary=summary,
        sound='Sosumi',
        round_count=round_count
    )


def notify_permission_needed(session_id: str, project_name: str, message: str):
    """Notify that permission is needed"""
    return send_rich_notification(
        session_id=session_id,
        title=f"Permission - {project_name}",
        message=message[:100],
        notification_type='permission_needed',
        project_name=project_name,
        sound='Sosumi'
    )


def notify_task_completed(session_id: str, project_name: str, original_goal: str,
                          completed: int = 0, total: int = 0):
    """Notify that a task is completed"""
    return send_rich_notification(
        session_id=session_id,
        title=f"Completed - {project_name}",
        message=original_goal[:100] if original_goal else "Task completed",
        notification_type='completed',
        project_name=project_name,
        original_goal=original_goal,
        progress_completed=completed,
        progress_total=total,
        sound='Hero'
    )


def notify_progress_update(session_id: str, project_name: str,
                           completed: int, total: int, current_task: str = None):
    """Notify progress update (optional, for significant milestones)"""
    return send_rich_notification(
        session_id=session_id,
        title=f"Progress - {project_name}",
        message=current_task or f"Completed {completed}/{total}",
        notification_type='progress',
        project_name=project_name,
        progress_completed=completed,
        progress_total=total,
        sound='Pop'
    )
