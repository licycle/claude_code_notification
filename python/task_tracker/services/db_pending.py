#!/usr/bin/env python3
"""
db_pending.py - Pending Session and Lifecycle Operations
Pending session support, active sessions query, snapshot operations, session lifecycle
"""
import json
from datetime import datetime
from typing import Optional, List, Dict, Any

from .database import get_connection, update_session_status


# ============================================================================
# Snapshot Operations
# ============================================================================

def save_snapshot(session_id: str, last_user: str, last_assistant: str, summary: Dict = None) -> None:
    """Save a state snapshot"""
    now = datetime.now().isoformat()
    with get_connection() as conn:
        # Get session_pk
        cursor = conn.execute(
            "SELECT id FROM sessions WHERE session_id = ?",
            (session_id,)
        )
        row = cursor.fetchone()
        if not row:
            return
        session_pk = row['id']

        conn.execute(
            """INSERT INTO snapshots
               (session_pk, last_user_message, last_assistant_message, summary_json, created_at)
               VALUES (?, ?, ?, ?, ?)""",
            (session_pk, last_user, last_assistant,
             json.dumps(summary, ensure_ascii=False) if summary else None, now)
        )


def get_latest_snapshot(session_id: str) -> Optional[Dict]:
    """Get the latest snapshot for a session"""
    with get_connection() as conn:
        cursor = conn.execute(
            """SELECT sn.* FROM snapshots sn
               JOIN sessions s ON sn.session_pk = s.id
               WHERE s.session_id = ?
               ORDER BY sn.created_at DESC LIMIT 1""",
            (session_id,)
        )
        row = cursor.fetchone()
        if row:
            result = dict(row)
            if result.get('summary_json'):
                result['summary'] = json.loads(result['summary_json'])
            return result
        return None


# ============================================================================
# Session Lifecycle Operations
# ============================================================================

def mark_session_completed(session_id: str) -> None:
    """Mark a session as completed"""
    update_session_status(session_id, 'completed')


def cleanup_old_sessions(days: int = 7) -> int:
    """Clean up sessions older than specified days"""
    with get_connection() as conn:
        cursor = conn.execute(
            """DELETE FROM sessions
               WHERE julianday('now') - julianday(last_activity) > ?""",
            (days,)
        )
        return cursor.rowcount


def cleanup_active_sessions_by_shell_pid(shell_pid: int) -> int:
    """
    Clean up all active sessions for a given shell_pid.
    Called when a new Claude Code instance starts in the same shell.
    This ensures old sessions are marked as completed before creating new ones.

    Returns:
        Number of sessions cleaned up
    """
    now = datetime.now().isoformat()
    with get_connection() as conn:
        cursor = conn.execute(
            """UPDATE sessions
               SET current_status = 'completed', last_activity = ?
               WHERE shell_pid = ?
               AND current_status != 'completed'""",
            (now, shell_pid)
        )
        return cursor.rowcount


# ============================================================================
# Pending Session Support (for pre-prompt idle state)
# ============================================================================

def create_pending_session(
    pending_id: str,
    project: str,
    account_alias: str = 'default',
    bundle_id: str = None,
    terminal_pid: int = None,
    shell_pid: int = None,
    window_id: int = None
) -> int:
    """
    Create a pending session before user submits first prompt.
    This allows the status bar to show 'idle' state immediately when Claude starts.

    Returns:
        session_pk: The primary key (id) of the created session
    """
    now = datetime.now().isoformat()

    with get_connection() as conn:
        # Cleanup stale pending sessions for this project (> 15 minutes old)
        conn.execute(
            """DELETE FROM sessions
               WHERE pending_id IS NOT NULL
               AND session_id IS NULL
               AND project = ?
               AND julianday('now') - julianday(created_at) > 0.01""",
            (project,)
        )

        cursor = conn.execute(
            """INSERT INTO sessions
               (session_id, pending_id, project, original_goal, current_status, created_at, last_activity,
                account_alias, bundle_id, terminal_pid, shell_pid, window_id)
               VALUES (NULL, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
            (pending_id, project, '等待输入...', 'idle', now, now,
             account_alias, bundle_id, terminal_pid, shell_pid, window_id)
        )
        session_pk = cursor.lastrowid

        # Initialize progress
        conn.execute(
            """INSERT INTO progress (session_pk) VALUES (?)""",
            (session_pk,)
        )
        return session_pk


def link_pending_session(pending_id: str, real_session_id: str, goal: str = None) -> Optional[int]:
    """
    Link a pending session to the real session_id.
    Called when UserPromptSubmit hook fires with the real session_id.

    This is now simple: just update the session_id field, no need to update primary key!

    Returns:
        session_pk if successful, None otherwise
    """
    now = datetime.now().isoformat()

    with get_connection() as conn:
        # Find pending session
        cursor = conn.execute(
            "SELECT id FROM sessions WHERE pending_id = ? AND session_id IS NULL",
            (pending_id,)
        )
        row = cursor.fetchone()

        if not row:
            return None

        session_pk = row['id']

        # Update session_id and status - no FK issues since we're not changing the primary key!
        if goal:
            conn.execute(
                """UPDATE sessions
                   SET session_id = ?, original_goal = ?, current_status = 'working', last_activity = ?
                   WHERE id = ?""",
                (real_session_id, goal, now, session_pk)
            )
            # Add goal_set event
            conn.execute(
                """INSERT INTO timeline (session_pk, event_type, content, timestamp)
                   VALUES (?, 'goal_set', ?, ?)""",
                (session_pk, goal, now)
            )
        else:
            conn.execute(
                """UPDATE sessions
                   SET session_id = ?, current_status = 'working', last_activity = ?
                   WHERE id = ?""",
                (real_session_id, now, session_pk)
            )

        return session_pk


def get_pending_session_by_project(project: str) -> Optional[Dict]:
    """Get pending session for a project if exists"""
    with get_connection() as conn:
        cursor = conn.execute(
            """SELECT * FROM sessions
               WHERE pending_id IS NOT NULL AND session_id IS NULL AND project = ?
               ORDER BY created_at DESC LIMIT 1""",
            (project,)
        )
        row = cursor.fetchone()
        return dict(row) if row else None


def get_session_by_pending_id(pending_id: str) -> Optional[Dict]:
    """Get session by pending_id"""
    with get_connection() as conn:
        cursor = conn.execute(
            "SELECT * FROM sessions WHERE pending_id = ?",
            (pending_id,)
        )
        row = cursor.fetchone()
        return dict(row) if row else None


def cleanup_pending_session(pending_id: str) -> int:
    """
    Clean up a pending session (mark as completed).
    Called when Claude exits without user submitting a prompt.

    Returns:
        Number of sessions cleaned up
    """
    now = datetime.now().isoformat()
    with get_connection() as conn:
        cursor = conn.execute(
            """UPDATE sessions
               SET current_status = 'completed', last_activity = ?
               WHERE pending_id = ? AND session_id IS NULL AND current_status != 'completed'""",
            (now, pending_id)
        )
        return cursor.rowcount


# ============================================================================
# Active Sessions Query
# ============================================================================

def get_active_sessions() -> List[Dict]:
    """Get all active (non-completed) sessions with their latest state"""
    with get_connection() as conn:
        cursor = conn.execute(
            """SELECT s.*,
                      p.todos_json, p.completed_count, p.total_count,
                      (SELECT question FROM pending_decisions pd
                       WHERE pd.session_pk = s.id AND pd.resolved = 0
                       ORDER BY pd.created_at DESC LIMIT 1) as pending_question,
                      (SELECT options_json FROM pending_decisions pd
                       WHERE pd.session_pk = s.id AND pd.resolved = 0
                       ORDER BY pd.created_at DESC LIMIT 1) as pending_options
               FROM sessions s
               LEFT JOIN progress p ON s.id = p.session_pk
               WHERE s.current_status != 'completed'
               ORDER BY s.last_activity DESC"""
        )
        results = []
        for row in cursor.fetchall():
            item = dict(row)
            if item.get('todos_json'):
                item['todos'] = json.loads(item['todos_json'])
            if item.get('pending_options'):
                item['pending_options'] = json.loads(item['pending_options'])
            results.append(item)
        return results


def get_all_session_summaries() -> List[Dict]:
    """
    Get summaries for all active sessions.
    Used by Swift menu bar to display task list.
    """
    from .db_timeline import get_session_summary

    sessions = get_active_sessions()
    summaries = []
    for s in sessions:
        # For pending sessions (session_id is NULL), use pending_id for display
        sid = s.get('session_id')
        if sid:
            summary = get_session_summary(sid)
            if summary:
                summaries.append(summary)
        else:
            # Pending session - create summary directly from session data
            summaries.append({
                'session_id': f"pending_{s.get('pending_id', '')}",
                'project': s.get('project', ''),
                'original_goal': s.get('original_goal', '等待输入...'),
                'status': s.get('current_status', 'idle'),
                'completed': s.get('completed_count', 0) or 0,
                'total': s.get('total_count', 0) or 0,
                'todos': [],
                'pending_question': None,
                'pending_options': [],
                'timeline': [],
                'last_activity': s.get('last_activity', ''),
                'created_at': s.get('created_at', ''),
                'account_alias': s.get('account_alias', 'default'),
                'bundle_id': s.get('bundle_id'),
                'terminal_pid': s.get('terminal_pid'),
                'window_id': s.get('window_id'),
                'round_count': 0
            })
    return summaries


__all__ = [
    'save_snapshot',
    'get_latest_snapshot',
    'mark_session_completed',
    'cleanup_old_sessions',
    'cleanup_active_sessions_by_shell_pid',
    'create_pending_session',
    'link_pending_session',
    'get_pending_session_by_project',
    'get_session_by_pending_id',
    'cleanup_pending_session',
    'get_active_sessions',
    'get_all_session_summaries',
]
