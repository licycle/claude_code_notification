#!/usr/bin/env python3
"""
pre_tool_tracker.py - PreToolUse Hook
Updates status when a tool is about to execute
Note: Does NOT record to timeline to avoid excessive events
"""
import sys
from pathlib import Path

# Add parent paths for imports
sys.path.insert(0, str(Path(__file__).parent.parent))
sys.path.insert(0, str(Path(__file__).parent))

from utils import read_hook_input, write_hook_output, log
from services.database import get_session, update_session_status


def main():
    log("PRETOOL", "PreToolUse hook triggered")

    input_data = read_hook_input()

    session_id = input_data.get('session_id')
    tool_name = input_data.get('tool_name', '')

    if not session_id:
        log("PRETOOL", "No session_id, exiting")
        write_hook_output()
        return

    log("PRETOOL", f"Session: {session_id}, Tool: {tool_name}")

    # Get session info
    session = get_session(session_id)
    if not session:
        log("PRETOOL", "Session not found, exiting")
        write_hook_output()
        return

    # Update session status to executing_tool
    # Only update if current status is 'working' to avoid overwriting more specific states
    current_status = session.get('current_status', '')
    if current_status in ('working', 'executing_tool'):
        update_session_status(session_id, 'executing_tool')
        log("PRETOOL", f"Status updated to executing_tool (was: {current_status})")
    else:
        log("PRETOOL", f"Status not updated, current: {current_status}")

    # Note: No timeline event recorded to avoid excessive data

    write_hook_output()


if __name__ == '__main__':
    try:
        main()
    except Exception as e:
        log("PRETOOL_ERROR", f"Unhandled exception: {e}")
        import traceback
        log("PRETOOL_ERROR", traceback.format_exc())
        write_hook_output()
