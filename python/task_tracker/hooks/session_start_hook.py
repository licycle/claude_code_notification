#!/usr/bin/env python3
"""
session_start_hook.py - SessionStart Hook
Detects resume events and links session chains
"""
import os
import sys
from pathlib import Path

# Add parent paths for imports
sys.path.insert(0, str(Path(__file__).parent.parent))
sys.path.insert(0, str(Path(__file__).parent))

from utils import read_hook_input, write_hook_output, log
from services.database import add_session_link, get_session, cleanup_pending_session


def main():
    log("SESSION_START", "Hook triggered")

    input_data = read_hook_input()
    log("SESSION_START", f"Input keys: {list(input_data.keys())}")

    session_id = input_data.get('session_id')
    source = input_data.get('source', 'startup')  # 'startup', 'resume', 'clear'
    transcript_path = input_data.get('transcript_path', '')

    log("SESSION_START", f"Session: {session_id}, Source: {source}")

    # Get pending session ID from environment (set by shell wrapper)
    pending_id = os.environ.get('CLAUDE_PENDING_SESSION_ID', '')

    if not session_id:
        log("SESSION_START", "No session_id, exiting")
        write_hook_output()
        return

    if source == 'resume' and transcript_path:
        # Note: Don't cleanup pending session here - it will be cleaned up
        # in goal_tracker.py when user actually submits a prompt
        # This ensures pending session remains visible until user starts working

        # Extract original session ID from transcript path
        # transcript_path format: ~/.claude/projects/.../<session_id>.jsonl
        try:
            original_id = Path(transcript_path).stem
            log("SESSION_START", f"Resume detected: {original_id[:8]}... -> {session_id[:8]}...")

            # Verify original session exists in our database
            original_session = get_session(original_id)
            if original_session:
                # Record the link
                add_session_link(original_id, session_id)
                log("SESSION_START", f"Session link recorded")
            else:
                log("SESSION_START", f"Original session {original_id[:8]}... not found in database")

        except Exception as e:
            log("SESSION_START", f"Failed to process resume: {e}")

    elif source == 'startup':
        log("SESSION_START", "New session startup, no link needed")

    elif source == 'clear':
        log("SESSION_START", "Session cleared, no link needed")

    write_hook_output()


if __name__ == '__main__':
    try:
        main()
    except Exception as e:
        log("SESSION_START_ERROR", f"Unhandled exception: {e}")
        write_hook_output()
