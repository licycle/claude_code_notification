#!/usr/bin/env python3
"""
notification_tracker.py - Notification Hook
Detects idle, permission, and elicitation states
"""
import sys
from pathlib import Path

# Add parent paths for imports
sys.path.insert(0, str(Path(__file__).parent.parent))
sys.path.insert(0, str(Path(__file__).parent))

from utils import read_hook_input, write_hook_output, log, get_project_name
from services.database import get_session, update_session_status, get_progress, get_latest_user_input
from services.notification import (
    notify_task_idle, notify_decision_needed, notify_permission_needed
)
from services.summary_service import get_summary_service


def main():
    log("NOTIF", "Hook triggered")

    input_data = read_hook_input()

    session_id = input_data.get('session_id')
    notification_type = input_data.get('notification_type', '')
    message = input_data.get('message', '')
    cwd = input_data.get('cwd', '')

    if not session_id:
        log("NOTIF", "No session_id, exiting")
        write_hook_output()
        return

    log("NOTIF", f"Session: {session_id}, Type: {notification_type}")

    # Get session info
    session = get_session(session_id)
    if not session:
        log("NOTIF", "Session not found, exiting")
        write_hook_output()
        return

    project_name = get_project_name(session.get('project', cwd))
    original_goal = session.get('original_goal', '')

    # Get current progress
    progress = get_progress(session_id)
    completed = progress.get('completed_count', 0) if progress else 0
    total = progress.get('total_count', 0) if progress else 0

    # Handle different notification types
    if notification_type == 'idle_prompt':
        handle_idle(session_id, project_name, original_goal, completed, total)

    elif notification_type == 'elicitation_dialog':
        handle_elicitation(session_id, project_name, message, completed, total)

    elif notification_type == 'permission_prompt':
        handle_permission(session_id, project_name, message)

    elif notification_type == 'auth_success':
        # Just log, no notification needed for auth success
        log("NOTIF", "Auth success event - no notification")

    else:
        # Handle any other notification types
        log("NOTIF", f"Other notification type: {notification_type}")
        # Send a generic notification if we have a message
        if message:
            from services.notification import send_rich_notification
            send_rich_notification(
                session_id=session_id,
                title=f"Claude - {project_name}",
                message=message[:100],
                notification_type=notification_type or 'info',
                project_name=project_name,
                sound='Glass'
            )

    write_hook_output()


def handle_idle(session_id: str, project_name: str, original_goal: str,
                completed: int, total: int):
    """Handle idle_prompt - Claude is waiting for input"""
    log("NOTIF", "Handling idle state")

    # Update session status
    update_session_status(session_id, 'idle')

    # Get latest user input from timeline
    latest_user_input = get_latest_user_input(session_id)
    log("NOTIF", f"Latest user input: {latest_user_input[:50] if latest_user_input else 'None'}...")

    # Generate summary for consistent mode display
    summary_service = get_summary_service()
    context = {
        'original_goal': original_goal,
        'completed': completed,
        'total': total,
        'last_user_message': latest_user_input or original_goal  # Use latest input for RAW mode
    }
    summary = summary_service.summarize(context)

    # Send notification
    notify_task_idle(
        session_id=session_id,
        project_name=project_name,
        original_goal=original_goal,
        completed=completed,
        total=total,
        summary=summary
    )


def handle_elicitation(session_id: str, project_name: str, message: str,
                       completed: int, total: int):
    """Handle elicitation_dialog - Claude is asking a question"""
    log("NOTIF", "Handling elicitation dialog")

    # Update session status
    update_session_status(session_id, 'waiting_for_user')

    # Generate summary for consistent mode display
    summary_service = get_summary_service()
    context = {
        'pending_question': message,
        'completed': completed,
        'total': total
    }
    summary = summary_service.summarize(context)

    # Send notification
    notify_decision_needed(
        session_id=session_id,
        project_name=project_name,
        question=message or "请回答问题",
        completed=completed,
        total=total,
        summary=summary
    )


def handle_permission(session_id: str, project_name: str, message: str):
    """Handle permission_prompt - Claude needs permission"""
    log("NOTIF", "Handling permission request")

    # Update session status
    update_session_status(session_id, 'waiting_permission')

    # Send notification
    notify_permission_needed(
        session_id=session_id,
        project_name=project_name,
        message=message or "Claude 需要权限确认"
    )


if __name__ == '__main__':
    try:
        main()
    except Exception as e:
        log("NOTIF_ERROR", f"Unhandled exception: {e}")
        import traceback
        log("NOTIF_ERROR", traceback.format_exc())
        write_hook_output()
