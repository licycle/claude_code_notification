#!/usr/bin/env python3
"""
database.py - Task Tracker Database Module
SQLite-based storage for multi-session task tracking
"""
import sqlite3
import json
import os
from pathlib import Path
from datetime import datetime
from typing import Optional, List, Dict, Any
from contextlib import contextmanager

# Database path
DB_DIR = Path.home() / '.claude-task-tracker'
DB_PATH = DB_DIR / 'tasks.db'

# Schema SQL
SCHEMA_SQL = """
-- Task sessions table (one per Claude Code session)
CREATE TABLE IF NOT EXISTS sessions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id TEXT UNIQUE NOT NULL,
    project TEXT NOT NULL,
    original_goal TEXT NOT NULL,
    current_status TEXT DEFAULT 'working',
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    last_activity TEXT DEFAULT CURRENT_TIMESTAMP
);

-- Goal evolution table (track goal changes over time)
CREATE TABLE IF NOT EXISTS goal_evolution (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id TEXT NOT NULL,
    goal_content TEXT NOT NULL,
    timestamp TEXT DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (session_id) REFERENCES sessions(session_id) ON DELETE CASCADE
);

-- Progress table (current todo state)
CREATE TABLE IF NOT EXISTS progress (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id TEXT UNIQUE NOT NULL,
    todos_json TEXT,
    completed_count INTEGER DEFAULT 0,
    total_count INTEGER DEFAULT 0,
    updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (session_id) REFERENCES sessions(session_id) ON DELETE CASCADE
);

-- Pending decisions table (questions waiting for user)
CREATE TABLE IF NOT EXISTS pending_decisions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id TEXT NOT NULL,
    question TEXT NOT NULL,
    options_json TEXT,
    context TEXT,
    resolved INTEGER DEFAULT 0,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    resolved_at TEXT,
    FOREIGN KEY (session_id) REFERENCES sessions(session_id) ON DELETE CASCADE
);

-- Snapshots table (state at Stop events)
CREATE TABLE IF NOT EXISTS snapshots (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id TEXT NOT NULL,
    last_user_message TEXT,
    last_assistant_message TEXT,
    summary_json TEXT,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (session_id) REFERENCES sessions(session_id) ON DELETE CASCADE
);

-- Timeline table (all events for a session)
CREATE TABLE IF NOT EXISTS timeline (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id TEXT NOT NULL,
    event_type TEXT NOT NULL,
    content TEXT,
    metadata_json TEXT,
    timestamp TEXT DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (session_id) REFERENCES sessions(session_id) ON DELETE CASCADE
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_sessions_status ON sessions(current_status);
CREATE INDEX IF NOT EXISTS idx_sessions_activity ON sessions(last_activity);
CREATE INDEX IF NOT EXISTS idx_timeline_session ON timeline(session_id);
CREATE INDEX IF NOT EXISTS idx_timeline_type ON timeline(event_type);
CREATE INDEX IF NOT EXISTS idx_pending_unresolved ON pending_decisions(session_id, resolved);
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


def get_session(session_id: str) -> Optional[Dict]:
    """Get session by ID"""
    with get_connection() as conn:
        cursor = conn.execute(
            "SELECT * FROM sessions WHERE session_id = ?",
            (session_id,)
        )
        row = cursor.fetchone()
        return dict(row) if row else None


def create_session(session_id: str, project: str, original_goal: str) -> None:
    """Create a new session"""
    now = datetime.now().isoformat()
    with get_connection() as conn:
        conn.execute(
            """INSERT OR IGNORE INTO sessions
               (session_id, project, original_goal, created_at, last_activity)
               VALUES (?, ?, ?, ?, ?)""",
            (session_id, project, original_goal, now, now)
        )
        # Record to timeline
        conn.execute(
            """INSERT INTO timeline (session_id, event_type, content, timestamp)
               VALUES (?, 'goal_set', ?, ?)""",
            (session_id, original_goal, now)
        )
        # Initialize progress
        conn.execute(
            """INSERT OR IGNORE INTO progress (session_id) VALUES (?)""",
            (session_id,)
        )


def update_session_status(session_id: str, status: str) -> None:
    """Update session status"""
    now = datetime.now().isoformat()
    with get_connection() as conn:
        conn.execute(
            """UPDATE sessions SET current_status = ?, last_activity = ?
               WHERE session_id = ?""",
            (status, now, session_id)
        )
        conn.execute(
            """INSERT INTO timeline (session_id, event_type, content, timestamp)
               VALUES (?, 'status_change', ?, ?)""",
            (session_id, status, now)
        )


def update_progress(session_id: str, todos: List[Dict]) -> None:
    """Update progress with todo list"""
    completed = sum(1 for t in todos if t.get('status') == 'completed')
    total = len(todos)
    now = datetime.now().isoformat()

    with get_connection() as conn:
        conn.execute(
            """INSERT OR REPLACE INTO progress
               (session_id, todos_json, completed_count, total_count, updated_at)
               VALUES (?, ?, ?, ?, ?)""",
            (session_id, json.dumps(todos, ensure_ascii=False), completed, total, now)
        )
        # Update session activity
        conn.execute(
            """UPDATE sessions SET last_activity = ? WHERE session_id = ?""",
            (now, session_id)
        )
        # Record to timeline
        conn.execute(
            """INSERT INTO timeline (session_id, event_type, metadata_json, timestamp)
               VALUES (?, 'progress_update', ?, ?)""",
            (session_id, json.dumps({'completed': completed, 'total': total}), now)
        )


def get_progress(session_id: str) -> Optional[Dict]:
    """Get current progress for a session"""
    with get_connection() as conn:
        cursor = conn.execute(
            "SELECT * FROM progress WHERE session_id = ?",
            (session_id,)
        )
        row = cursor.fetchone()
        if row:
            result = dict(row)
            if result.get('todos_json'):
                result['todos'] = json.loads(result['todos_json'])
            return result
        return None


def add_pending_decision(session_id: str, question: str, options: List[str], context: str = None) -> int:
    """Add a pending decision"""
    now = datetime.now().isoformat()
    with get_connection() as conn:
        cursor = conn.execute(
            """INSERT INTO pending_decisions (session_id, question, options_json, context, created_at)
               VALUES (?, ?, ?, ?, ?)""",
            (session_id, question, json.dumps(options, ensure_ascii=False), context, now)
        )
        # Update session activity
        conn.execute(
            """UPDATE sessions SET last_activity = ? WHERE session_id = ?""",
            (now, session_id)
        )
        return cursor.lastrowid


def resolve_pending_decisions(session_id: str) -> None:
    """Mark all pending decisions as resolved"""
    now = datetime.now().isoformat()
    with get_connection() as conn:
        conn.execute(
            """UPDATE pending_decisions SET resolved = 1, resolved_at = ?
               WHERE session_id = ? AND resolved = 0""",
            (now, session_id)
        )


def get_pending_decisions(session_id: str) -> List[Dict]:
    """Get unresolved pending decisions for a session"""
    with get_connection() as conn:
        cursor = conn.execute(
            """SELECT * FROM pending_decisions
               WHERE session_id = ? AND resolved = 0
               ORDER BY created_at DESC""",
            (session_id,)
        )
        return [dict(row) for row in cursor.fetchall()]


def save_snapshot(session_id: str, last_user: str, last_assistant: str, summary: Dict = None) -> None:
    """Save a state snapshot"""
    now = datetime.now().isoformat()
    with get_connection() as conn:
        conn.execute(
            """INSERT INTO snapshots
               (session_id, last_user_message, last_assistant_message, summary_json, created_at)
               VALUES (?, ?, ?, ?, ?)""",
            (session_id, last_user, last_assistant,
             json.dumps(summary, ensure_ascii=False) if summary else None, now)
        )


def get_latest_snapshot(session_id: str) -> Optional[Dict]:
    """Get the latest snapshot for a session"""
    with get_connection() as conn:
        cursor = conn.execute(
            """SELECT * FROM snapshots WHERE session_id = ?
               ORDER BY created_at DESC LIMIT 1""",
            (session_id,)
        )
        row = cursor.fetchone()
        if row:
            result = dict(row)
            if result.get('summary_json'):
                result['summary'] = json.loads(result['summary_json'])
            return result
        return None


def get_active_sessions() -> List[Dict]:
    """Get all active (non-completed) sessions with their latest state"""
    with get_connection() as conn:
        cursor = conn.execute(
            """SELECT s.*,
                      p.todos_json, p.completed_count, p.total_count,
                      (SELECT question FROM pending_decisions pd
                       WHERE pd.session_id = s.session_id AND pd.resolved = 0
                       ORDER BY pd.created_at DESC LIMIT 1) as pending_question,
                      (SELECT options_json FROM pending_decisions pd
                       WHERE pd.session_id = s.session_id AND pd.resolved = 0
                       ORDER BY pd.created_at DESC LIMIT 1) as pending_options
               FROM sessions s
               LEFT JOIN progress p ON s.session_id = p.session_id
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


def get_session_timeline(session_id: str, limit: int = 50) -> List[Dict]:
    """Get timeline events for a session"""
    with get_connection() as conn:
        cursor = conn.execute(
            """SELECT * FROM timeline WHERE session_id = ?
               ORDER BY timestamp DESC LIMIT ?""",
            (session_id, limit)
        )
        results = []
        for row in cursor.fetchall():
            item = dict(row)
            if item.get('metadata_json'):
                item['metadata'] = json.loads(item['metadata_json'])
            results.append(item)
        return results


def add_timeline_event(session_id: str, event_type: str, content: str = None, metadata: Dict = None) -> None:
    """Add an event to the timeline"""
    now = datetime.now().isoformat()
    with get_connection() as conn:
        conn.execute(
            """INSERT INTO timeline (session_id, event_type, content, metadata_json, timestamp)
               VALUES (?, ?, ?, ?, ?)""",
            (session_id, event_type, content,
             json.dumps(metadata, ensure_ascii=False) if metadata else None, now)
        )


def mark_session_completed(session_id: str) -> None:
    """Mark a session as completed"""
    update_session_status(session_id, 'completed')


def get_round_count(session_id: str) -> int:
    """
    获取用户输入轮数（goal_set + user_input 事件数）
    轮数 = 1 (goal_set) + count(user_input events)
    """
    with get_connection() as conn:
        cursor = conn.execute(
            """SELECT COUNT(*) FROM timeline
               WHERE session_id = ?
               AND event_type IN ('goal_set', 'user_input')""",
            (session_id,)
        )
        return cursor.fetchone()[0]


def get_latest_user_input(session_id: str) -> Optional[str]:
    """
    获取最新的用户输入内容
    优先返回最新的 user_input 事件，如果没有则返回 goal_set 事件
    """
    with get_connection() as conn:
        cursor = conn.execute(
            """SELECT content FROM timeline
               WHERE session_id = ?
               AND event_type IN ('goal_set', 'user_input')
               ORDER BY timestamp DESC
               LIMIT 1""",
            (session_id,)
        )
        row = cursor.fetchone()
        return row[0] if row else None


def cleanup_old_sessions(days: int = 7) -> int:
    """Clean up sessions older than specified days"""
    with get_connection() as conn:
        cursor = conn.execute(
            """DELETE FROM sessions
               WHERE julianday('now') - julianday(last_activity) > ?""",
            (days,)
        )
        return cursor.rowcount


# ============================================================================
# Timeline Node Aggregation (v2 UI Support)
# ============================================================================

def aggregate_timeline_nodes(session_id: str, max_nodes: int = 20) -> List[Dict]:
    """
    Aggregate raw timeline events into meaningful nodes for UI display.

    Aggregation Rules:
    - SHOW: goal_set, consecutive 3+ todo completions, status changes to waiting_*,
            snapshots with summary, all todos completed
    - HIDE: single progress_update, consecutive same status_change,
            changes < 30s apart, empty snapshots

    Returns:
        List of nodes: [{time, type, title, description, status}]
        - type: start, milestone, waiting, permission, snapshot, complete
        - status: completed, current, pending
    """
    with get_connection() as conn:
        cursor = conn.execute(
            """SELECT * FROM timeline WHERE session_id = ?
               ORDER BY timestamp ASC""",
            (session_id,)
        )
        raw_events = [dict(row) for row in cursor.fetchall()]

    if not raw_events:
        return []

    nodes = []
    last_event_time = None
    consecutive_progress = 0
    last_completed_count = 0
    last_status = None

    for event in raw_events:
        try:
            event_time = datetime.fromisoformat(event['timestamp'])
        except (ValueError, TypeError):
            continue

        event_type = event.get('event_type', '')
        content = event.get('content', '') or ''
        metadata = {}
        if event.get('metadata_json'):
            try:
                metadata = json.loads(event['metadata_json'])
            except (json.JSONDecodeError, TypeError):
                pass

        # Skip if too close to last event (< 30 seconds) for status_change
        if last_event_time and event_type == 'status_change':
            time_diff = (event_time - last_event_time).total_seconds()
            if time_diff < 30:
                continue

        node = None

        # Handle different event types
        if event_type == 'goal_set':
            node = {
                'time': event_time.strftime('%H:%M'),
                'type': 'start',
                'title': '开始任务',
                'description': content[:50] if content else '任务开始',
                'status': 'completed'
            }

        elif event_type == 'status_change':
            if content == last_status:
                continue  # Skip duplicate status
            last_status = content

            if content == 'waiting_for_user':
                node = {
                    'time': event_time.strftime('%H:%M'),
                    'type': 'waiting',
                    'title': '等待决策',
                    'description': '需要用户输入',
                    'status': 'current'
                }
            elif content == 'waiting_permission':
                node = {
                    'time': event_time.strftime('%H:%M'),
                    'type': 'permission',
                    'title': '等待权限',
                    'description': '需要权限确认',
                    'status': 'current'
                }
            elif content == 'completed':
                node = {
                    'time': event_time.strftime('%H:%M'),
                    'type': 'complete',
                    'title': '任务完成',
                    'description': '已完成全部步骤',
                    'status': 'completed'
                }

        elif event_type == 'progress_update':
            completed = metadata.get('completed', 0)
            total = metadata.get('total', 0)

            # Track consecutive completions
            if completed > last_completed_count:
                consecutive_progress += (completed - last_completed_count)
            last_completed_count = completed

            # Create milestone for 3+ consecutive completions
            if consecutive_progress >= 3:
                node = {
                    'time': event_time.strftime('%H:%M'),
                    'type': 'milestone',
                    'title': '阶段完成',
                    'description': f'已完成 {completed}/{total} 项',
                    'status': 'completed'
                }
                consecutive_progress = 0

            # All todos completed
            if completed == total and total > 0:
                node = {
                    'time': event_time.strftime('%H:%M'),
                    'type': 'complete',
                    'title': '全部完成',
                    'description': f'已完成全部 {total} 项任务',
                    'status': 'completed'
                }

        if node:
            nodes.append(node)
            last_event_time = event_time

    # Mark last node as current if not completed
    if nodes and nodes[-1]['type'] not in ['complete']:
        nodes[-1]['status'] = 'current'

    # Limit to max_nodes (take most recent)
    return nodes[-max_nodes:] if len(nodes) > max_nodes else nodes


def get_session_summary(session_id: str) -> Optional[Dict]:
    """
    Get aggregated session summary for menu bar display.

    Returns a complete summary including:
    - Session info (project, goal, status)
    - Progress (completed/total, todos)
    - Pending decisions
    - Aggregated timeline nodes
    """
    session = get_session(session_id)
    if not session:
        return None

    progress = get_progress(session_id)
    pending_list = get_pending_decisions(session_id)
    timeline_nodes = aggregate_timeline_nodes(session_id, max_nodes=10)

    return {
        'session_id': session_id,
        'project': session.get('project', ''),
        'original_goal': session.get('original_goal', ''),
        'status': session.get('current_status', 'unknown'),
        'completed': progress.get('completed_count', 0) if progress else 0,
        'total': progress.get('total_count', 0) if progress else 0,
        'todos': progress.get('todos', []) if progress else [],
        'pending_question': pending_list[0].get('question') if pending_list else None,
        'pending_options': json.loads(pending_list[0].get('options_json', '[]')) if pending_list else [],
        'timeline': timeline_nodes,
        'last_activity': session.get('last_activity', ''),
        'created_at': session.get('created_at', '')
    }


def get_all_session_summaries() -> List[Dict]:
    """
    Get summaries for all active sessions.
    Used by Swift menu bar to display task list.
    """
    sessions = get_active_sessions()
    summaries = []
    for s in sessions:
        summary = get_session_summary(s['session_id'])
        if summary:
            summaries.append(summary)
    return summaries


def write_state_file_for_swift():
    """
    Write all session summaries to state file for Swift app to read.
    Called periodically or after significant updates.
    """
    state_dir = Path.home() / '.claude-task-tracker' / 'state'
    state_dir.mkdir(parents=True, exist_ok=True)

    summaries = get_all_session_summaries()

    # Write to all_sessions.json
    all_sessions_file = state_dir / 'all_sessions.json'
    with open(all_sessions_file, 'w') as f:
        json.dump({s['session_id']: s for s in summaries}, f, indent=2, ensure_ascii=False)


# Initialize database on import
init_database()
