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


def cleanup_stale_sessions(max_age_minutes: int = 5):
    """
    Mark sessions as completed if they haven't been active recently.

    This handles the case where Claude Code exits without triggering Stop event
    (e.g., ctrl+c, terminal close, crash).

    Args:
        max_age_minutes: Sessions inactive for longer than this are marked completed
    """
    log("CLEANUP", "Starting session cleanup")

    cutoff_time = datetime.now() - timedelta(minutes=max_age_minutes)
    cutoff_str = cutoff_time.isoformat()

    try:
        with get_connection() as conn:
            # Find sessions that are not completed and haven't been active recently
            cursor = conn.execute(
                """SELECT session_id, current_status, last_activity
                   FROM sessions
                   WHERE current_status NOT IN ('completed', 'rate_limited')
                   AND last_activity < ?""",
                (cutoff_str,)
            )
            stale_sessions = cursor.fetchall()

            if not stale_sessions:
                log("CLEANUP", "No stale sessions found")
                return 0

            # Mark each stale session as completed
            count = 0
            for row in stale_sessions:
                session_id = row[0]
                old_status = row[1]
                log("CLEANUP", f"Marking session {session_id[:8]}... as completed (was: {old_status})")
                update_session_status(session_id, 'completed')
                count += 1

            log("CLEANUP", f"Cleaned up {count} stale sessions")
            return count

    except Exception as e:
        log("CLEANUP_ERROR", f"Failed to cleanup sessions: {e}")
        return 0


def main():
    """Main entry point"""
    # Get max age from environment or use default (5 minutes)
    max_age = int(os.environ.get('CLAUDE_CLEANUP_MAX_AGE', '5'))
    cleanup_stale_sessions(max_age)


if __name__ == '__main__':
    try:
        main()
    except Exception as e:
        log("CLEANUP_ERROR", f"Unhandled exception: {e}")
