#!/usr/bin/env python3
"""
session_cleanup.py - Session Cleanup Script
Called by shell wrapper when Claude Code exits (including ctrl+c)
Marks active sessions as completed
"""
import sys
import os
from pathlib import Path
from datetime import datetime, timedelta

# Add parent paths for imports
sys.path.insert(0, str(Path(__file__).parent.parent))
sys.path.insert(0, str(Path(__file__).parent))

from utils import log
from services.database import get_connection, update_session_status


def cleanup_current_session():
    """
    Mark all active sessions as completed when Claude Code exits.

    This is called on exit (ctrl+c, normal exit, etc.) to ensure
    the status bar shows the correct state.
    """
    log("CLEANUP", "Starting session cleanup on exit")

    try:
        with get_connection() as conn:
            # Find all sessions that are not completed
            cursor = conn.execute(
                """SELECT session_id, current_status
                   FROM sessions
                   WHERE current_status NOT IN ('completed', 'rate_limited')"""
            )
            active_sessions = cursor.fetchall()

            if not active_sessions:
                log("CLEANUP", "No active sessions to cleanup")
                return 0

            # Mark each active session as completed
            count = 0
            for row in active_sessions:
                session_id = row[0]
                old_status = row[1]
                log("CLEANUP", f"Marking session {session_id[:8]}... as completed (was: {old_status})")
                update_session_status(session_id, 'completed')
                count += 1

            log("CLEANUP", f"Cleaned up {count} active sessions")
            return count

    except Exception as e:
        log("CLEANUP_ERROR", f"Failed to cleanup sessions: {e}")
        return 0


def main():
    """Main entry point"""
    cleanup_current_session()


if __name__ == '__main__':
    try:
        main()
    except Exception as e:
        log("CLEANUP_ERROR", f"Unhandled exception: {e}")
