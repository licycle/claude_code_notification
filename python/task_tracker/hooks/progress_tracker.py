#!/usr/bin/env python3
"""
progress_tracker.py - PostToolUse Hook
Tracks TodoWrite and AskUserQuestion tool calls
"""
import sys
import json
from pathlib import Path

# Add parent paths for imports
sys.path.insert(0, str(Path(__file__).parent.parent))
sys.path.insert(0, str(Path(__file__).parent))

from utils import read_hook_input, write_hook_output, log, get_project_name, safe_json_parse
from services.database import (
    get_session, update_progress, add_pending_decision,
    update_session_status, get_progress
)
from services.notification import notify_decision_needed


def main():
    log("PROGRESS", "Hook triggered")

    input_data = read_hook_input()

    session_id = input_data.get('session_id')
    tool_name = input_data.get('tool_name', '')
    tool_input = input_data.get('tool_input', {})
    tool_response = input_data.get('tool_response', {})
    cwd = input_data.get('cwd', '')

    if not session_id:
        log("PROGRESS", "No session_id, exiting")
        write_hook_output()
        return

    log("PROGRESS", f"Session: {session_id}, Tool: {tool_name}")

    # Get session info
    session = get_session(session_id)
    if not session:
        log("PROGRESS", "Session not found, exiting")
        write_hook_output()
        return

    project_name = get_project_name(session.get('project', cwd))

    # Fix: These statuses should resume to 'working' when a tool executes
    # Tool execution means the blocking condition has been resolved
    SHOULD_RESUME_WORKING = {
        'waiting_permission',   # Permission granted
        'waiting_for_user',     # User answered question
        'idle',                 # Resumed from idle
        'rate_limited',         # Rate limit ended
    }

    current_status = session.get('current_status', '')
    if current_status in SHOULD_RESUME_WORKING:
        log("PROGRESS", f"Status '{current_status}' -> 'working' (tool executed)")
        update_session_status(session_id, 'working')

    # Handle TodoWrite
    if tool_name == 'TodoWrite':
        handle_todo_write(session_id, tool_input, project_name)

    # Handle AskUserQuestion
    elif tool_name == 'AskUserQuestion':
        handle_ask_user_question(session_id, tool_input, project_name)

    write_hook_output()


def handle_todo_write(session_id: str, tool_input, project_name: str):
    """Handle TodoWrite tool call"""
    log("PROGRESS", "Processing TodoWrite")

    # Parse tool input
    tool_input = safe_json_parse(tool_input)

    if not isinstance(tool_input, dict):
        log("PROGRESS", f"Invalid tool_input type: {type(tool_input)}")
        return

    todos = tool_input.get('todos', [])

    if not todos:
        log("PROGRESS", "No todos in input")
        return

    log("PROGRESS", f"Found {len(todos)} todos")

    # Update progress in database
    update_progress(session_id, todos)

    # Count progress
    completed = sum(1 for t in todos if t.get('status') == 'completed')
    total = len(todos)

    log("PROGRESS", f"Progress: {completed}/{total}")

    # Update session status based on todos
    in_progress = any(t.get('status') == 'in_progress' for t in todos)
    if in_progress:
        update_session_status(session_id, 'working')
    elif completed == total and total > 0:
        update_session_status(session_id, 'completed')


def handle_ask_user_question(session_id: str, tool_input, project_name: str):
    """Handle AskUserQuestion tool call"""
    log("PROGRESS", "Processing AskUserQuestion")

    # Parse tool input
    tool_input = safe_json_parse(tool_input)

    if not isinstance(tool_input, dict):
        log("PROGRESS", f"Invalid tool_input type: {type(tool_input)}")
        return

    questions = tool_input.get('questions', [])

    if not questions:
        log("PROGRESS", "No questions in input")
        return

    # Get first question
    q = questions[0]
    question = q.get('question', '')
    options = [opt.get('label', '') for opt in q.get('options', [])]

    log("PROGRESS", f"Question: {question[:50]}...")

    # Add pending decision to database
    add_pending_decision(session_id, question, options)

    # Update session status
    update_session_status(session_id, 'waiting_for_user')

    # Get current progress for notification
    progress = get_progress(session_id)
    completed = progress.get('completed_count', 0) if progress else 0
    total = progress.get('total_count', 0) if progress else 0

    # Send notification
    notify_decision_needed(
        session_id=session_id,
        project_name=project_name,
        question=question,
        options=options,
        completed=completed,
        total=total
    )


if __name__ == '__main__':
    try:
        main()
    except Exception as e:
        log("PROGRESS_ERROR", f"Unhandled exception: {e}")
        import traceback
        log("PROGRESS_ERROR", traceback.format_exc())
        write_hook_output()
