#!/usr/bin/env python3
"""
goal_tracker.py - UserPromptSubmit Hook
Captures user's original goal when a new session starts
"""
import sys
from pathlib import Path

# Add parent paths for imports
sys.path.insert(0, str(Path(__file__).parent.parent))
sys.path.insert(0, str(Path(__file__).parent))

from utils import read_hook_input, write_hook_output, log, get_project_name
from services.database import get_session, create_session, add_timeline_event, resolve_pending_decisions


def main():
    log("GOAL", "Hook triggered")

    input_data = read_hook_input()

    session_id = input_data.get('session_id')
    prompt = input_data.get('prompt', '')
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

    # Check if session already exists
    session = get_session(session_id)

    if session is None:
        # New session - record original goal
        project_name = get_project_name(cwd)
        log("GOAL", f"Creating new session for project: {project_name}")

        create_session(session_id, cwd, prompt)
        log("GOAL", f"Session created with goal: {prompt[:100]}...")
    else:
        # Existing session - record as user input event
        log("GOAL", f"Existing session, recording user input")

        # Mark any pending decisions as resolved (user responded)
        resolve_pending_decisions(session_id)

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
