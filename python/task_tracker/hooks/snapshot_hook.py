#!/usr/bin/env python3
"""
snapshot_hook.py - Stop Hook
Generates task snapshot and summary when Claude stops
Also handles rate limit detection (merged from stop_hook.py)
"""
import sys
import os
from pathlib import Path
from collections import deque

# Add parent paths for imports
sys.path.insert(0, str(Path(__file__).parent.parent))
sys.path.insert(0, str(Path(__file__).parent))

from utils import (
    read_hook_input, write_hook_output, log, get_project_name,
    parse_transcript, extract_last_message, extract_todos_from_transcript,
    detect_pending_question
)
from services.database import (
    get_session, update_session_status, save_snapshot,
    get_progress, get_pending_decisions
)
from services.summary_service import get_summary_service
from services.notification import (
    notify_task_idle, notify_decision_needed, send_rich_notification
)

# Rate limit detection keywords
RATE_LIMIT_KEYWORDS = [
    'rate limit', 'rate_limit', 'too many requests',
    '429', 'quota exceeded', 'overloaded'
]


def get_last_n_lines(filepath, n=3):
    """Read last n lines from file efficiently"""
    try:
        with open(os.path.expanduser(filepath), 'rb') as f:
            return deque(f, n)
    except Exception as e:
        log("SNAPSHOT", f"Failed to read file: {e}")
        return []


def detect_rate_limit(transcript_path):
    """Check last 3 records in transcript for rate limit errors"""
    if not transcript_path:
        return False, None

    last_lines = get_last_n_lines(transcript_path, 3)

    for line in last_lines:
        try:
            content = line.decode('utf-8', errors='ignore').lower()
            for keyword in RATE_LIMIT_KEYWORDS:
                if keyword in content:
                    return True, keyword
        except:
            pass

    return False, None


def notify_rate_limit(session_id: str, project_name: str, keyword: str):
    """Send rate limit notification"""
    account_alias = os.environ.get('CLAUDE_ACCOUNT_ALIAS', 'default')
    return send_rich_notification(
        session_id=session_id,
        title=f"Rate Limit [{account_alias}]",
        message=f"Claude API rate limit detected ({keyword})",
        notification_type='rate_limited',
        project_name=project_name,
        sound='Basso'
    )


def main():
    log("SNAPSHOT", "Hook triggered")

    input_data = read_hook_input()

    session_id = input_data.get('session_id')
    transcript_path = input_data.get('transcript_path', '')
    cwd = input_data.get('cwd', '')

    if not session_id:
        log("SNAPSHOT", "No session_id, exiting")
        write_hook_output()
        return

    log("SNAPSHOT", f"Session: {session_id}")

    # Get session info
    session = get_session(session_id)
    if not session:
        log("SNAPSHOT", "Session not found, exiting")
        write_hook_output()
        return

    project_name = get_project_name(session.get('project', cwd))
    original_goal = session.get('original_goal', '')

    # Parse transcript
    events = []
    if transcript_path:
        log("SNAPSHOT", f"Parsing transcript: {transcript_path}")
        events = parse_transcript(transcript_path)
        log("SNAPSHOT", f"Found {len(events)} events")

    # Extract messages
    last_user = extract_last_message(events, 'user')
    last_assistant = extract_last_message(events, 'assistant', strip_system_reminders=True)

    # Extract todos from transcript (may be more up-to-date than DB)
    todos = extract_todos_from_transcript(events)

    # Get progress info
    progress = get_progress(session_id)
    if todos:
        completed = sum(1 for t in todos if t.get('status') == 'completed')
        total = len(todos)
    elif progress:
        completed = progress.get('completed_count', 0)
        total = progress.get('total_count', 0)
    else:
        completed = 0
        total = 0

    # Check for pending decisions
    pending_decisions = get_pending_decisions(session_id)
    pending_question = None
    pending_options = []
    if pending_decisions:
        pd = pending_decisions[0]
        pending_question = pd.get('question')
        try:
            import json
            pending_options = json.loads(pd.get('options_json', '[]'))
        except:
            pending_options = []

    # Generate summary
    log("SNAPSHOT", "Generating summary...")
    summary_service = get_summary_service()

    context = {
        'original_goal': original_goal,
        'last_user_message': last_user,
        'last_assistant_message': last_assistant,
        'todos': todos,
        'completed': completed,
        'total': total,
        'pending_question': pending_question
    }

    summary = summary_service.summarize(context)
    log("SNAPSHOT", f"Summary generated: {summary.get('current_task', '')[:50]}")

    # Save snapshot to database
    save_snapshot(session_id, last_user, last_assistant, summary)

    # Check for rate limit FIRST (before other notifications)
    has_rate_limit, rate_limit_keyword = detect_rate_limit(transcript_path)
    if has_rate_limit:
        log("SNAPSHOT", f"Rate limit detected: {rate_limit_keyword}")
        update_session_status(session_id, 'rate_limited')
        notify_rate_limit(session_id, project_name, rate_limit_keyword)
        log("SNAPSHOT", "Rate limit notification sent")
        write_hook_output()
        return

    # Update session status
    update_session_status(session_id, 'idle')

    # Send notification
    if pending_question:
        # If there's a pending question, prioritize that
        notify_decision_needed(
            session_id=session_id,
            project_name=project_name,
            question=pending_question,
            options=pending_options,
            completed=completed,
            total=total,
            summary=summary
        )
    else:
        # Normal idle notification with summary
        notify_task_idle(
            session_id=session_id,
            project_name=project_name,
            original_goal=summary.get('current_task', original_goal),
            completed=completed,
            total=total,
            summary=summary
        )

    log("SNAPSHOT", "Snapshot complete")
    write_hook_output()


if __name__ == '__main__':
    try:
        main()
    except Exception as e:
        log("SNAPSHOT_ERROR", f"Unhandled exception: {e}")
        import traceback
        log("SNAPSHOT_ERROR", traceback.format_exc())
        write_hook_output()
