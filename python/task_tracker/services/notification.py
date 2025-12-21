#!/usr/bin/env python3
"""
notification.py - Rich Notification Service
Sends rich notifications via ClaudeMonitor Swift app
"""
import json
import subprocess
import os
from pathlib import Path
from datetime import datetime
from typing import Dict, Optional, List

# Paths
STATE_DIR = Path.home() / '.claude-task-tracker' / 'state'
BIN_PATH = Path.home() / 'Applications' / 'ClaudeMonitor.app' / 'Contents' / 'MacOS' / 'ClaudeMonitor'
LOG_FILE = Path.home() / '.claude-task-tracker' / 'logs' / 'notification.log'


def log(tag: str, msg: str):
    """Write to log file"""
    try:
        LOG_FILE.parent.mkdir(parents=True, exist_ok=True)
        with open(LOG_FILE, 'a') as f:
            ts = datetime.now().strftime("%H:%M:%S")
            f.write(f"[{ts}] [{tag}] {msg}\n")
    except Exception:
        pass


def get_env_info() -> Dict:
    """Get terminal environment info from environment variables"""
    return {
        'bundle_id': os.environ.get('CLAUDE_TERM_BUNDLE_ID', 'com.apple.Terminal'),
        'pid': os.environ.get('CLAUDE_TERM_PID', '0'),
        'window_id': os.environ.get('CLAUDE_CG_WINDOW_ID', '0'),
        'account_alias': os.environ.get('CLAUDE_ACCOUNT_ALIAS', 'default')
    }


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
    sound: str = 'Glass'
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
        'timestamp': datetime.now().isoformat()
    }

    # Write to state file for ClaudeMonitor to read
    _write_state_file(session_id, payload)

    # Send notification via Swift app with rich data
    return _send_via_swift_app(payload, env_info)


def _send_via_swift_app(payload: Dict, env_info: Dict) -> bool:
    """Send notification via ClaudeMonitor Swift app"""
    try:
        # Format title with account alias
        alias = env_info['account_alias']
        title = payload['title']
        if alias and alias != 'default':
            title = f"{title} [{alias}]"

        # Build rich message body
        message_parts = []

        # Add progress bar if available
        progress = payload.get('progress', {})
        if progress.get('total', 0) > 0:
            completed = progress.get('completed', 0)
            total = progress['total']
            bar_length = 10
            filled = int(bar_length * completed / total)
            bar = '█' * filled + '░' * (bar_length - filled)
            message_parts.append(f"{bar} {completed}/{total}")

        # Add main message
        message_parts.append(payload['message'])

        # Add pending question if any
        pending = payload.get('pending_decision')
        if pending and pending.get('question'):
            message_parts.append(f"⚠️ {pending['question']}")

        body = '\n'.join(message_parts)

        # Call Swift app
        cmd = [
            str(BIN_PATH),
            'notify',
            title,
            body,
            payload.get('sound', 'Glass'),
            env_info['bundle_id'],
            env_info['pid'],
            env_info['window_id']
        ]

        log("SEND", f"Calling: {cmd[0]} notify ...")

        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=10
        )

        if result.returncode == 0:
            log("SUCCESS", f"Notification sent: {title}")
            return True
        else:
            log("ERROR", f"Failed with code {result.returncode}: {result.stderr}")
            return False

    except subprocess.TimeoutExpired:
        log("ERROR", "Notification timeout")
        return False
    except FileNotFoundError:
        log("ERROR", f"ClaudeMonitor not found at {BIN_PATH}")
        # Fallback to osascript
        return _send_via_osascript(payload)
    except Exception as e:
        log("ERROR", f"Failed to send notification: {e}")
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

        log("SUCCESS", f"Sent via osascript: {title}")
        return True

    except Exception as e:
        log("ERROR", f"osascript fallback failed: {e}")
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

        log("STATE", f"Wrote state for session {session_id}")

    except Exception as e:
        log("ERROR", f"Failed to write state file: {e}")


# Convenience functions for different notification types

def notify_task_idle(session_id: str, project_name: str, original_goal: str,
                     completed: int = 0, total: int = 0, summary: Dict = None):
    """Notify that a task is idle (waiting for user input)"""
    return send_rich_notification(
        session_id=session_id,
        title=f"Claude 空闲 - {project_name}",
        message=original_goal[:100] if original_goal else "等待用户输入",
        notification_type='idle',
        project_name=project_name,
        original_goal=original_goal,
        progress_completed=completed,
        progress_total=total,
        summary=summary,
        sound='Glass'
    )


def notify_decision_needed(session_id: str, project_name: str, question: str,
                           options: List[str] = None, completed: int = 0, total: int = 0):
    """Notify that user decision is needed"""
    return send_rich_notification(
        session_id=session_id,
        title=f"需要决策 - {project_name}",
        message=question[:100],
        notification_type='decision_needed',
        project_name=project_name,
        pending_question=question,
        pending_options=options,
        progress_completed=completed,
        progress_total=total,
        sound='Sosumi'
    )


def notify_permission_needed(session_id: str, project_name: str, message: str):
    """Notify that permission is needed"""
    return send_rich_notification(
        session_id=session_id,
        title=f"权限确认 - {project_name}",
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
        title=f"任务完成 - {project_name}",
        message=original_goal[:100] if original_goal else "任务已完成",
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
        title=f"进度更新 - {project_name}",
        message=current_task or f"已完成 {completed}/{total} 项",
        notification_type='progress',
        project_name=project_name,
        progress_completed=completed,
        progress_total=total,
        sound='Pop'
    )
