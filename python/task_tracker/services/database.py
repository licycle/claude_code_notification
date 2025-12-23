#!/usr/bin/env python3
"""
database.py - Task Tracker Database Module
SQLite-based storage for multi-session task tracking

New Schema Design (v2):
- Uses auto-increment `id` as primary key for sessions table
- `session_id` is a regular field (can be NULL for pending sessions)
- `pending_id` field for linking pending sessions
- Child tables use `session_pk` (references sessions.id) as foreign key
"""
import sqlite3
import json
from pathlib import Path
from datetime import datetime
from typing import Optional, List, Dict, Any
from contextlib import contextmanager

# Database path
DB_DIR = Path.home() / '.claude-task-tracker'
DB_PATH = DB_DIR / 'tasks.db'

# Schema SQL - New design with auto-increment id as primary key
SCHEMA_SQL = """
-- Main table: uses auto-increment id as primary key
CREATE TABLE IF NOT EXISTS sessions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id TEXT,              -- Real session_id (NULL for pending)
    pending_id TEXT,              -- Pending session UUID
    project TEXT NOT NULL,
    original_goal TEXT NOT NULL,
    current_status TEXT DEFAULT 'idle',
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    last_activity TEXT DEFAULT CURRENT_TIMESTAMP,
    account_alias TEXT DEFAULT 'default',
    bundle_id TEXT,
    terminal_pid INTEGER,
    shell_pid INTEGER,
    window_id INTEGER
);

-- Indexes
CREATE UNIQUE INDEX IF NOT EXISTS idx_sessions_session_id ON sessions(session_id) WHERE session_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_sessions_pending_id ON sessions(pending_id) WHERE pending_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_sessions_status ON sessions(current_status);
CREATE INDEX IF NOT EXISTS idx_sessions_activity ON sessions(last_activity);

-- Child tables: use session_pk referencing sessions.id
CREATE TABLE IF NOT EXISTS progress (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_pk INTEGER NOT NULL,
    todos_json TEXT,
    completed_count INTEGER DEFAULT 0,
    total_count INTEGER DEFAULT 0,
    updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (session_pk) REFERENCES sessions(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS timeline (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_pk INTEGER NOT NULL,
    event_type TEXT NOT NULL,
    content TEXT,
    metadata_json TEXT,
    timestamp TEXT DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (session_pk) REFERENCES sessions(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS pending_decisions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_pk INTEGER NOT NULL,
    question TEXT NOT NULL,
    options_json TEXT,
    context TEXT,
    resolved INTEGER DEFAULT 0,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    resolved_at TEXT,
    FOREIGN KEY (session_pk) REFERENCES sessions(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS snapshots (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_pk INTEGER NOT NULL,
    last_user_message TEXT,
    last_assistant_message TEXT,
    summary_json TEXT,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (session_pk) REFERENCES sessions(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS goal_evolution (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_pk INTEGER NOT NULL,
    goal_content TEXT NOT NULL,
    timestamp TEXT DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (session_pk) REFERENCES sessions(id) ON DELETE CASCADE
);

-- Index for progress lookup
CREATE UNIQUE INDEX IF NOT EXISTS idx_progress_session ON progress(session_pk);
"""


@contextmanager
def get_connection():
    """Get a database connection with row factory"""
    DB_DIR.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(DB_PATH), timeout=10.0)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    try:
        yield conn
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


def init_database():
    """Initialize database tables"""
    with get_connection() as conn:
        conn.executescript(SCHEMA_SQL)


# ============================================================================
# Session Operations
# ============================================================================

def get_session(session_id: str) -> Optional[Dict]:
    """Get session by session_id"""
    with get_connection() as conn:
        cursor = conn.execute(
            "SELECT * FROM sessions WHERE session_id = ?",
            (session_id,)
        )
        row = cursor.fetchone()
        return dict(row) if row else None


def get_session_pk(session_id: str) -> Optional[int]:
    """Get session primary key (id) by session_id"""
    with get_connection() as conn:
        cursor = conn.execute(
            "SELECT id FROM sessions WHERE session_id = ?",
            (session_id,)
        )
        row = cursor.fetchone()
        return row['id'] if row else None


def create_session(
    session_id: str,
    project: str,
    original_goal: str,
    account_alias: str = 'default',
    bundle_id: str = None,
    terminal_pid: int = None,
    shell_pid: int = None,
    window_id: int = None,
    initial_status: str = 'working'
) -> int:
    """Create a new session with optional window info for terminal jumping

    Args:
        initial_status: Initial session status. 'working' when user submits prompt,
                       'idle' if session is created before user input.

    Returns:
        session_pk: The primary key (id) of the created session
    """
    now = datetime.now().isoformat()
    with get_connection() as conn:
        cursor = conn.execute(
            """INSERT INTO sessions
               (session_id, project, original_goal, current_status, created_at, last_activity,
                account_alias, bundle_id, terminal_pid, shell_pid, window_id)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
            (session_id, project, original_goal, initial_status, now, now,
             account_alias, bundle_id, terminal_pid, shell_pid, window_id)
        )
        session_pk = cursor.lastrowid

        # Record to timeline
        conn.execute(
            """INSERT INTO timeline (session_pk, event_type, content, timestamp)
               VALUES (?, 'goal_set', ?, ?)""",
            (session_pk, original_goal, now)
        )
        # Initialize progress
        conn.execute(
            """INSERT INTO progress (session_pk) VALUES (?)""",
            (session_pk,)
        )
        return session_pk


def update_session_status(session_id: str, status: str) -> None:
    """Update session status"""
    now = datetime.now().isoformat()
    with get_connection() as conn:
        # Get session_pk first
        cursor = conn.execute(
            "SELECT id FROM sessions WHERE session_id = ?",
            (session_id,)
        )
        row = cursor.fetchone()
        if not row:
            return
        session_pk = row['id']

        conn.execute(
            """UPDATE sessions SET current_status = ?, last_activity = ?
               WHERE id = ?""",
            (status, now, session_pk)
        )
        conn.execute(
            """INSERT INTO timeline (session_pk, event_type, content, timestamp)
               VALUES (?, 'status_change', ?, ?)""",
            (session_pk, status, now)
        )


# ============================================================================
# Progress Operations
# ============================================================================

def update_progress(session_id: str, todos: List[Dict]) -> None:
    """Update progress with todo list"""
    completed = sum(1 for t in todos if t.get('status') == 'completed')
    total = len(todos)
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
            """INSERT OR REPLACE INTO progress
               (session_pk, todos_json, completed_count, total_count, updated_at)
               VALUES (?, ?, ?, ?, ?)""",
            (session_pk, json.dumps(todos, ensure_ascii=False), completed, total, now)
        )
        # Update session activity
        conn.execute(
            """UPDATE sessions SET last_activity = ? WHERE id = ?""",
            (now, session_pk)
        )
        # Record to timeline
        conn.execute(
            """INSERT INTO timeline (session_pk, event_type, metadata_json, timestamp)
               VALUES (?, 'progress_update', ?, ?)""",
            (session_pk, json.dumps({'completed': completed, 'total': total}), now)
        )


def get_progress(session_id: str) -> Optional[Dict]:
    """Get current progress for a session"""
    with get_connection() as conn:
        cursor = conn.execute(
            """SELECT p.* FROM progress p
               JOIN sessions s ON p.session_pk = s.id
               WHERE s.session_id = ?""",
            (session_id,)
        )
        row = cursor.fetchone()
        if row:
            result = dict(row)
            if result.get('todos_json'):
                result['todos'] = json.loads(result['todos_json'])
            return result
        return None


# ============================================================================
# Pending Decisions Operations
# ============================================================================

def add_pending_decision(session_id: str, question: str, options: List[str], context: str = None) -> int:
    """Add a pending decision"""
    now = datetime.now().isoformat()
    with get_connection() as conn:
        # Get session_pk
        cursor = conn.execute(
            "SELECT id FROM sessions WHERE session_id = ?",
            (session_id,)
        )
        row = cursor.fetchone()
        if not row:
            return -1
        session_pk = row['id']

        cursor = conn.execute(
            """INSERT INTO pending_decisions (session_pk, question, options_json, context, created_at)
               VALUES (?, ?, ?, ?, ?)""",
            (session_pk, question, json.dumps(options, ensure_ascii=False), context, now)
        )
        # Update session activity
        conn.execute(
            """UPDATE sessions SET last_activity = ? WHERE id = ?""",
            (now, session_pk)
        )
        return cursor.lastrowid


def resolve_pending_decisions(session_id: str) -> None:
    """Mark all pending decisions as resolved"""
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
            """UPDATE pending_decisions SET resolved = 1, resolved_at = ?
               WHERE session_pk = ? AND resolved = 0""",
            (now, session_pk)
        )


def get_pending_decisions(session_id: str) -> List[Dict]:
    """Get unresolved pending decisions for a session"""
    with get_connection() as conn:
        cursor = conn.execute(
            """SELECT pd.* FROM pending_decisions pd
               JOIN sessions s ON pd.session_pk = s.id
               WHERE s.session_id = ? AND pd.resolved = 0
               ORDER BY pd.created_at DESC""",
            (session_id,)
        )
        return [dict(row) for row in cursor.fetchall()]


# Initialize database on import
init_database()

# Re-export from submodules for backward compatibility
from .db_timeline import (
    add_timeline_event,
    get_session_timeline,
    aggregate_timeline_nodes,
    get_round_count,
    get_latest_user_input,
    get_session_summary,
    write_state_file_for_swift,
)

from .db_pending import (
    save_snapshot,
    get_latest_snapshot,
    mark_session_completed,
    cleanup_old_sessions,
    create_pending_session,
    link_pending_session,
    get_pending_session_by_project,
    get_session_by_pending_id,
    cleanup_pending_session,
    get_active_sessions,
    get_all_session_summaries,
)

__all__ = [
    # Connection
    'get_connection',
    'init_database',
    # Session
    'get_session',
    'get_session_pk',
    'create_session',
    'update_session_status',
    # Progress
    'update_progress',
    'get_progress',
    # Pending Decisions
    'add_pending_decision',
    'resolve_pending_decisions',
    'get_pending_decisions',
    # From db_timeline
    'add_timeline_event',
    'get_session_timeline',
    'aggregate_timeline_nodes',
    'get_round_count',
    'get_latest_user_input',
    'get_session_summary',
    'write_state_file_for_swift',
    # From db_pending
    'save_snapshot',
    'get_latest_snapshot',
    'mark_session_completed',
    'cleanup_old_sessions',
    'create_pending_session',
    'link_pending_session',
    'get_pending_session_by_project',
    'get_session_by_pending_id',
    'cleanup_pending_session',
    'get_active_sessions',
    'get_all_session_summaries',
]
