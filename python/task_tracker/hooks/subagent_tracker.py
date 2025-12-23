#!/usr/bin/env python3
"""
subagent_tracker.py - SubagentStart/SubagentStop Hook
Tracks when Claude delegates work to subagents

Usage:
  python3 subagent_tracker.py start  # For SubagentStart
  python3 subagent_tracker.py stop   # For SubagentStop
"""
import sys
from pathlib import Path

# Add parent paths for imports
sys.path.insert(0, str(Path(__file__).parent.parent))
sys.path.insert(0, str(Path(__file__).parent))

from utils import read_hook_input, write_hook_output, log
from services.database import get_session, update_session_status
from services.db_timeline import add_timeline_event


def handle_start(input_data: dict):
    """Handle SubagentStart event"""
    log("SUBAGENT", "SubagentStart hook triggered")

    session_id = input_data.get('session_id')
    agent_name = input_data.get('agent_name', '')
    delegation_reason = input_data.get('delegation_reason', '')

    if not session_id:
        log("SUBAGENT", "No session_id, exiting")
        return

    log("SUBAGENT", f"Session: {session_id}, Agent: {agent_name}")

    # Get session info
    session = get_session(session_id)
    if not session:
        log("SUBAGENT", "Session not found, exiting")
        return

    session_pk = session.get('id')
    if not session_pk:
        log("SUBAGENT", "No session_pk, exiting")
        return

    # Update session status to subagent_working
    update_session_status(session_id, 'subagent_working')
    log("SUBAGENT", "Status updated to subagent_working")

    # Record timeline event
    metadata = {
        'agent_name': agent_name,
        'reason': delegation_reason[:200] if delegation_reason else ''
    }
    add_timeline_event(
        session_id=session_id,
        event_type='subagent_start',
        content=agent_name,
        metadata=metadata
    )
    log("SUBAGENT", f"Timeline event recorded: subagent_start for {agent_name}")


def handle_stop(input_data: dict):
    """Handle SubagentStop event"""
    log("SUBAGENT", "SubagentStop hook triggered")

    session_id = input_data.get('session_id')
    agent_name = input_data.get('agent_name', '')
    agent_id = input_data.get('agent_id', '')

    if not session_id:
        log("SUBAGENT", "No session_id, exiting")
        return

    log("SUBAGENT", f"Session: {session_id}, Agent: {agent_name}, ID: {agent_id}")

    # Get session info
    session = get_session(session_id)
    if not session:
        log("SUBAGENT", "Session not found, exiting")
        return

    session_pk = session.get('id')
    if not session_pk:
        log("SUBAGENT", "No session_pk, exiting")
        return

    # Update session status back to working
    update_session_status(session_id, 'working')
    log("SUBAGENT", "Status updated to working")

    # Record timeline event
    metadata = {
        'agent_name': agent_name,
        'agent_id': agent_id
    }
    add_timeline_event(
        session_id=session_id,
        event_type='subagent_stop',
        content=agent_name,
        metadata=metadata
    )
    log("SUBAGENT", f"Timeline event recorded: subagent_stop for {agent_name}")


def main():
    # Determine mode from command line argument
    mode = 'start'
    if len(sys.argv) > 1:
        mode = sys.argv[1].lower()

    input_data = read_hook_input()

    if mode == 'start':
        handle_start(input_data)
    elif mode == 'stop':
        handle_stop(input_data)
    else:
        log("SUBAGENT", f"Unknown mode: {mode}")

    write_hook_output()


if __name__ == '__main__':
    try:
        main()
    except Exception as e:
        log("SUBAGENT_ERROR", f"Unhandled exception: {e}")
        import traceback
        log("SUBAGENT_ERROR", traceback.format_exc())
        write_hook_output()
