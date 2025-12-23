#!/usr/bin/env python3
"""
session_cleanup.py - Session Cleanup Script
Called by shell wrapper when Claude Code exits (including ctrl+c)
Marks the specific session as completed (not all sessions)
"""
import sys
import os
from pathlib import Path
from datetime import datetime

# Add parent paths for imports
sys.path.insert(0, str(Path(__file__).parent.parent))
sys.path.insert(0, str(Path(__file__).parent))

from utils import log
from services.database import get_connection, cleanup_pending_session


def cleanup_session(pending_id: str = None):
    """
    Mark the specified session as completed when Claude Code exits.

    Args:
        pending_id: The pending session UUID from wrapper.

    With the new schema:
    - pending_id is stored in the `pending_id` field
    - session_id is NULL for pending sessions, or real session_id after linking

    This is called on exit (ctrl+c, normal exit, etc.) to ensure
    the status bar shows the correct state.
    """
    if not pending_id:
        log("CLEANUP", "No pending_id provided, skipping cleanup")
        return 0

    log("CLEANUP", f"Starting cleanup for session: {pending_id[:8]}...")

    try:
        now = datetime.now().isoformat()

        with get_connection() as conn:
            # Find session by pending_id (works for both linked and unlinked sessions)
            cursor = conn.execute(
                """SELECT id, session_id, pending_id, current_status
                   FROM sessions
                   WHERE pending_id = ?
                     AND current_status NOT IN ('completed', 'rate_limited')""",
                (pending_id,)
            )
            matching_sessions = cursor.fetchall()

            if not matching_sessions:
                log("CLEANUP", f"No active session found for {pending_id[:8]}...")
                return 0

            # Mark matching session(s) as completed
            count = 0
            for row in matching_sessions:
                session_pk = row['id']
                session_id = row['session_id']
                old_status = row['current_status']

                display_id = session_id[:8] if session_id else f"pending_{pending_id[:8]}"
                log("CLEANUP", f"Marking session {display_id}... as completed (was: {old_status})")

                # Update status directly using session pk
                conn.execute(
                    """UPDATE sessions SET current_status = 'completed', last_activity = ?
                       WHERE id = ?""",
                    (now, session_pk)
                )

                # Add timeline event
                conn.execute(
                    """INSERT INTO timeline (session_pk, event_type, content, timestamp)
                       VALUES (?, 'status_change', 'completed', ?)""",
                    (session_pk, now)
                )

                count += 1

            log("CLEANUP", f"Cleaned up {count} session(s) for {pending_id[:8]}...")
            return count

    except Exception as e:
        log("CLEANUP_ERROR", f"Failed to cleanup session {pending_id[:8]}...: {e}")
        return 0


def main():
    """Main entry point - accepts pending_id as command line argument"""
    pending_id = sys.argv[1] if len(sys.argv) > 1 else None
    cleanup_session(pending_id)


if __name__ == '__main__':
    try:
        main()
    except Exception as e:
        log("CLEANUP_ERROR", f"Unhandled exception: {e}")
