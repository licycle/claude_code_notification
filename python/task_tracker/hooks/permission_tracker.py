#!/usr/bin/env python3
"""
permission_tracker.py - PermissionRequest Hook
Detects when Claude requests permission to use a tool
"""
import sys
from pathlib import Path

# Add parent paths for imports
sys.path.insert(0, str(Path(__file__).parent.parent))
sys.path.insert(0, str(Path(__file__).parent))

from utils import read_hook_input, write_hook_output, log
from services.database import get_session, update_session_status
from services.db_timeline import add_timeline_event


def main():
    log("PERM", "PermissionRequest hook triggered")

    input_data = read_hook_input()

    session_id = input_data.get('session_id')
    tool_name = input_data.get('tool_name', '')
    permission_decision = input_data.get('permissionDecision', '')
    cwd = input_data.get('cwd', '')

    if not session_id:
        log("PERM", "No session_id, exiting")
        write_hook_output()
        return

    log("PERM", f"Session: {session_id}, Tool: {tool_name}, Decision: {permission_decision}")

    # Get session info
    session = get_session(session_id)
    if not session:
        log("PERM", "Session not found, exiting")
        write_hook_output()
        return

    session_pk = session.get('id')
    if not session_pk:
        log("PERM", "No session_pk, exiting")
        write_hook_output()
        return

    # Update session status to waiting_permission
    update_session_status(session_id, 'waiting_permission')
    log("PERM", "Status updated to waiting_permission")

    # Record timeline event
    metadata = {
        'tool_name': tool_name,
        'decision': permission_decision
    }
    add_timeline_event(
        session_pk=session_pk,
        event_type='permission_request',
        content=tool_name,
        metadata=metadata
    )
    log("PERM", f"Timeline event recorded: permission_request for {tool_name}")

    write_hook_output()


if __name__ == '__main__':
    try:
        main()
    except Exception as e:
        log("PERM_ERROR", f"Unhandled exception: {e}")
        import traceback
        log("PERM_ERROR", traceback.format_exc())
        write_hook_output()
