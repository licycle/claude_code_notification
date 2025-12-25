#!/usr/bin/env python3
"""
goal_tracker.py - UserPromptSubmit Hook
Captures user's original goal when a new session starts
"""
import sys
import os
from pathlib import Path

# Add parent paths for imports
sys.path.insert(0, str(Path(__file__).parent.parent))
sys.path.insert(0, str(Path(__file__).parent))

from utils import read_hook_input, write_hook_output, log, get_project_name, get_env_info
from services.database import (
    get_session, create_session, add_timeline_event, resolve_pending_decisions,
    update_session_status, link_pending_session, update_session_shell_pid
)


def main():
    log("GOAL", "Hook triggered")

    input_data = read_hook_input()
    log("GOAL", f"Input keys: {list(input_data.keys())}")

    session_id = input_data.get('session_id')
    # Try both field names (prompt and userPrompt)
    prompt = input_data.get('prompt') or input_data.get('userPrompt', '')
    cwd = input_data.get('cwd', '')

    if not session_id:
        log("GOAL", "No session_id, exiting")
        write_hook_output()
        return

    if not prompt:
        log("GOAL", "No prompt, exiting")
        write_hook_output()
        return

    log("GOAL", f"Session: {session_id}, Prompt length: {len(prompt)}")

    # Check for pending session to link
    pending_id = os.environ.get('CLAUDE_PENDING_SESSION_ID', '')
    if pending_id:
        log("GOAL", f"Found pending_id: {pending_id[:8]}..., attempting to link")
        try:
            # New simplified link - just updates session_id field, no FK issues!
            session_pk = link_pending_session(pending_id, session_id, goal=prompt)
            if session_pk:
                log("GOAL", f"Successfully linked pending session (pk={session_pk}) to {session_id}")
                log("GOAL", f"Updated with goal: {prompt[:100]}...")
                write_hook_output()
                return
            else:
                log("GOAL", "Pending session not found, will create new session")
        except Exception as e:
            log("GOAL", f"Failed to link pending session: {e}, will create new session")

    # Check if session already exists
    session = get_session(session_id)

    if session is None:
        # New session - record original goal
        # Status starts as 'working' because user just submitted a prompt
        project_name = get_project_name(cwd)
        log("GOAL", f"Creating new session for project: {project_name}")

        # Get window info for terminal jumping
        env_info = get_env_info()
        terminal_pid = int(env_info.get('pid', 0)) or None
        shell_pid = int(env_info.get('shell_pid', 0)) or None
        window_id = int(env_info.get('window_id', 0)) or None

        create_session(
            session_id=session_id,
            project=cwd,
            original_goal=prompt,
            account_alias=env_info.get('account_alias', 'default'),
            bundle_id=env_info.get('bundle_id'),
            terminal_pid=terminal_pid,
            shell_pid=shell_pid,
            window_id=window_id,
            initial_status='working'  # User submitted prompt, so working
        )
        log("GOAL", f"Session created with goal: {prompt[:100]}...")
    else:
        # Existing session - record as user input event
        current_status = session.get('current_status', 'idle')
        log("GOAL", f"Existing session (status: {current_status}), recording user input")

        # Update shell_pid for terminal switching support
        env_info = get_env_info()
        shell_pid = int(env_info.get('shell_pid', 0)) or None
        if shell_pid:
            update_session_shell_pid(session_id, shell_pid)

        # Mark any pending decisions as resolved (user responded)
        resolve_pending_decisions(session_id)

        # Update status to working (user submitted new prompt)
        update_session_status(session_id, 'working')

        # Add to timeline
        add_timeline_event(
            session_id=session_id,
            event_type='user_input',
            content=prompt[:500]  # Truncate long prompts
        )

    write_hook_output()


if __name__ == '__main__':
    try:
        main()
    except Exception as e:
        log("GOAL_ERROR", f"Unhandled exception: {e}")
        write_hook_output()
