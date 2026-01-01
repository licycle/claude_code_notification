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
    window_id INTEGER,
    global_task_id INTEGER        -- 关联全局任务 (用于 decompose)
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

-- prompts 表：存储完整提示词用于展示
CREATE TABLE IF NOT EXISTS prompts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_pk INTEGER NOT NULL,
    round_number INTEGER DEFAULT 1,
    content TEXT NOT NULL,
    char_count INTEGER DEFAULT 0,
    word_count INTEGER DEFAULT 0,
    estimated_tokens INTEGER DEFAULT 0,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (session_pk) REFERENCES sessions(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_prompts_session ON prompts(session_pk);

-- session_links 表：Resume 会话关联
CREATE TABLE IF NOT EXISTS session_links (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    original_session_id TEXT NOT NULL,
    resumed_session_id TEXT NOT NULL,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_session_links_original ON session_links(original_session_id);
CREATE INDEX IF NOT EXISTS idx_session_links_resumed ON session_links(resumed_session_id);

-- session_usage 表：会话用量统计
CREATE TABLE IF NOT EXISTS session_usage (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_pk INTEGER UNIQUE NOT NULL,
    total_input_chars INTEGER DEFAULT 0,
    total_output_chars INTEGER DEFAULT 0,
    total_input_words INTEGER DEFAULT 0,
    total_output_words INTEGER DEFAULT 0,
    estimated_input_tokens INTEGER DEFAULT 0,
    estimated_output_tokens INTEGER DEFAULT 0,
    last_processed_line INTEGER DEFAULT 0,
    updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (session_pk) REFERENCES sessions(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_session_usage_session ON session_usage(session_pk);

-- ============================================================================
-- Global Task & Todo System Tables (v2.0)
-- ============================================================================

-- global_tasks 表：全局任务，跨项目的高层次目标
CREATE TABLE IF NOT EXISTS global_tasks (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    title TEXT NOT NULL,
    description TEXT,
    status TEXT DEFAULT 'active' CHECK (status IN ('active', 'completed', 'archived')),
    priority INTEGER DEFAULT 0 CHECK (priority IN (0, 1, 2)),  -- 0=normal, 1=high, 2=urgent
    created_at TEXT DEFAULT (datetime('now', 'localtime')),
    updated_at TEXT DEFAULT (datetime('now', 'localtime')),
    completed_at TEXT,
    metadata_json TEXT  -- 扩展字段，存储任意元数据
);

CREATE INDEX IF NOT EXISTS idx_global_tasks_status ON global_tasks(status);
CREATE INDEX IF NOT EXISTS idx_global_tasks_priority ON global_tasks(priority);

-- todos 表：项目级 Todo，支持层级
CREATE TABLE IF NOT EXISTS todos (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    global_task_id INTEGER,                 -- 关联全局任务 (可NULL表示独立Todo)
    parent_todo_id INTEGER,                 -- 父Todo (支持子任务层级)
    project_path TEXT NOT NULL,             -- 项目路径
    title TEXT NOT NULL,
    description TEXT,
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'in_progress', 'blocked', 'completed', 'cancelled')),
    priority INTEGER DEFAULT 0 CHECK (priority IN (0, 1, 2)),
    estimated_minutes INTEGER,              -- 预估时间（分钟）
    actual_minutes INTEGER,                 -- 实际时间（分钟）
    created_at TEXT DEFAULT (datetime('now', 'localtime')),
    updated_at TEXT DEFAULT (datetime('now', 'localtime')),
    completed_at TEXT,
    completion_summary TEXT,                -- AI 生成的完成总结
    metadata_json TEXT,
    FOREIGN KEY (global_task_id) REFERENCES global_tasks(id) ON DELETE SET NULL,
    FOREIGN KEY (parent_todo_id) REFERENCES todos(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_todos_global_task ON todos(global_task_id);
CREATE INDEX IF NOT EXISTS idx_todos_parent ON todos(parent_todo_id);
CREATE INDEX IF NOT EXISTS idx_todos_project ON todos(project_path);
CREATE INDEX IF NOT EXISTS idx_todos_status ON todos(status);
CREATE INDEX IF NOT EXISTS idx_todos_priority ON todos(priority);

-- todo_dependencies 表：Todo 之间的依赖关系
CREATE TABLE IF NOT EXISTS todo_dependencies (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    todo_id INTEGER NOT NULL,
    depends_on_todo_id INTEGER NOT NULL,
    created_at TEXT DEFAULT (datetime('now', 'localtime')),
    FOREIGN KEY (todo_id) REFERENCES todos(id) ON DELETE CASCADE,
    FOREIGN KEY (depends_on_todo_id) REFERENCES todos(id) ON DELETE CASCADE,
    UNIQUE (todo_id, depends_on_todo_id)
);

CREATE INDEX IF NOT EXISTS idx_todo_deps_todo ON todo_dependencies(todo_id);
CREATE INDEX IF NOT EXISTS idx_todo_deps_depends_on ON todo_dependencies(depends_on_todo_id);

-- session_todo_links 表：Session 与 Todo 的关联
CREATE TABLE IF NOT EXISTS session_todo_links (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_pk INTEGER NOT NULL,
    todo_id INTEGER NOT NULL,
    started_at TEXT DEFAULT (datetime('now', 'localtime')),
    ended_at TEXT,
    status TEXT DEFAULT 'working' CHECK (status IN ('working', 'completed', 'paused', 'cancelled')),
    notes TEXT,
    FOREIGN KEY (session_pk) REFERENCES sessions(id) ON DELETE CASCADE,
    FOREIGN KEY (todo_id) REFERENCES todos(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_session_todo_links_session ON session_todo_links(session_pk);
CREATE INDEX IF NOT EXISTS idx_session_todo_links_todo ON session_todo_links(todo_id);
CREATE INDEX IF NOT EXISTS idx_session_todo_links_status ON session_todo_links(status);

-- todo_executions 表：Todo 执行记录（操作日志）
CREATE TABLE IF NOT EXISTS todo_executions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    todo_id INTEGER NOT NULL,
    session_pk INTEGER,                     -- 可为NULL（非Session触发的操作）
    action TEXT NOT NULL CHECK (action IN ('created', 'started', 'paused', 'resumed', 'blocked', 'unblocked', 'completed', 'cancelled', 'split', 'note')),
    actor TEXT DEFAULT 'user' CHECK (actor IN ('user', 'claude_code', 'system', 'ai')),
    details_json TEXT,                      -- 操作详情（如拆分信息、阻塞原因等）
    created_at TEXT DEFAULT (datetime('now', 'localtime')),
    FOREIGN KEY (todo_id) REFERENCES todos(id) ON DELETE CASCADE,
    FOREIGN KEY (session_pk) REFERENCES sessions(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_todo_executions_todo ON todo_executions(todo_id);
CREATE INDEX IF NOT EXISTS idx_todo_executions_session ON todo_executions(session_pk);
CREATE INDEX IF NOT EXISTS idx_todo_executions_action ON todo_executions(action);
CREATE INDEX IF NOT EXISTS idx_todo_executions_created ON todo_executions(created_at);

-- workflow_runs 表：工作流运行记录
CREATE TABLE IF NOT EXISTS workflow_runs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    workflow_name TEXT NOT NULL,
    task_id INTEGER,                        -- 关联全局任务（可为NULL）
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'running', 'completed', 'failed', 'cancelled')),
    current_step TEXT,
    context_json TEXT,                      -- 工作流上下文
    started_at TEXT,
    completed_at TEXT,
    created_at TEXT DEFAULT (datetime('now', 'localtime')),
    FOREIGN KEY (task_id) REFERENCES global_tasks(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_workflow_runs_task ON workflow_runs(task_id);
CREATE INDEX IF NOT EXISTS idx_workflow_runs_status ON workflow_runs(status);

-- workflow_step_logs 表：工作流步骤执行日志
CREATE TABLE IF NOT EXISTS workflow_step_logs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    run_id INTEGER NOT NULL,
    step_id TEXT NOT NULL,
    status TEXT NOT NULL CHECK (status IN ('pending', 'running', 'completed', 'failed', 'skipped')),
    output_json TEXT,
    error TEXT,
    started_at TEXT,
    completed_at TEXT,
    FOREIGN KEY (run_id) REFERENCES workflow_runs(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_workflow_step_logs_run ON workflow_step_logs(run_id);
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


def update_session_shell_pid(session_id: str, shell_pid: int) -> None:
    """Update session's shell_pid for terminal switching support"""
    now = datetime.now().isoformat()
    with get_connection() as conn:
        conn.execute(
            """UPDATE sessions SET shell_pid = ?, last_activity = ?
               WHERE session_id = ?""",
            (shell_pid, now, session_id)
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


# ============================================================================
# Prompt Operations (for prompt history display)
# ============================================================================

def add_prompt(session_id: str, content: str, round_number: int = 1) -> int:
    """Add a prompt record for a session

    Args:
        session_id: The session ID
        content: Full prompt content
        round_number: Which round of conversation (1-based)

    Returns:
        The ID of the inserted prompt record, or -1 if failed
    """
    char_count = len(content)
    # For Chinese/mixed text, use character-based estimation
    # English: ~4 chars per token, Chinese: ~1.5 chars per token
    # Use a conservative estimate of 2 chars per token
    word_count = len(content.split())
    estimated_tokens = max(char_count // 2, word_count)

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
            """INSERT INTO prompts
               (session_pk, round_number, content, char_count, word_count, estimated_tokens, created_at)
               VALUES (?, ?, ?, ?, ?, ?, ?)""",
            (session_pk, round_number, content, char_count, word_count, estimated_tokens, now)
        )
        return cursor.lastrowid


def get_prompts(session_id: str) -> List[Dict]:
    """Get all prompts for a session

    Returns:
        List of prompt records ordered by round_number
    """
    with get_connection() as conn:
        cursor = conn.execute(
            """SELECT p.* FROM prompts p
               JOIN sessions s ON p.session_pk = s.id
               WHERE s.session_id = ?
               ORDER BY p.round_number ASC""",
            (session_id,)
        )
        return [dict(row) for row in cursor.fetchall()]


def get_prompt_count(session_id: str) -> int:
    """Get the number of prompts for a session"""
    with get_connection() as conn:
        cursor = conn.execute(
            """SELECT COUNT(*) as cnt FROM prompts p
               JOIN sessions s ON p.session_pk = s.id
               WHERE s.session_id = ?""",
            (session_id,)
        )
        row = cursor.fetchone()
        return row['cnt'] if row else 0


# ============================================================================
# Session Link Operations (for resume tracking)
# ============================================================================

def add_session_link(original_session_id: str, resumed_session_id: str) -> int:
    """Record a session resume link

    Args:
        original_session_id: The original session that was resumed from
        resumed_session_id: The new session created by resume

    Returns:
        The ID of the inserted link record
    """
    now = datetime.now().isoformat()
    with get_connection() as conn:
        cursor = conn.execute(
            """INSERT INTO session_links (original_session_id, resumed_session_id, created_at)
               VALUES (?, ?, ?)""",
            (original_session_id, resumed_session_id, now)
        )
        return cursor.lastrowid


def get_resumed_from(session_id: str) -> Optional[str]:
    """Get the original session ID that this session was resumed from

    Returns:
        The original session_id, or None if not a resumed session
    """
    with get_connection() as conn:
        cursor = conn.execute(
            """SELECT original_session_id FROM session_links
               WHERE resumed_session_id = ?
               ORDER BY created_at DESC LIMIT 1""",
            (session_id,)
        )
        row = cursor.fetchone()
        return row['original_session_id'] if row else None


def get_resume_chain(session_id: str) -> List[str]:
    """Get the full chain of resumed sessions

    Returns:
        List of session_ids from oldest to newest in the resume chain
    """
    chain = [session_id]
    current = session_id

    with get_connection() as conn:
        # Walk backwards to find all ancestors
        while True:
            cursor = conn.execute(
                """SELECT original_session_id FROM session_links
                   WHERE resumed_session_id = ?""",
                (current,)
            )
            row = cursor.fetchone()
            if not row:
                break
            current = row['original_session_id']
            chain.insert(0, current)

    return chain


# ============================================================================
# Session Usage Operations (for token estimation)
# ============================================================================

def update_session_usage(
    session_id: str,
    input_chars: int = 0,
    output_chars: int = 0,
    input_words: int = 0,
    output_words: int = 0,
    actual_input_tokens: int = 0,
    actual_output_tokens: int = 0,
    last_processed_line: int = 0,
    incremental: bool = False
) -> None:
    """Update or insert session usage statistics

    Args:
        incremental: If True, add to existing values. If False, replace.
        last_processed_line: Line number in transcript that was last processed.

    If actual_input_tokens/actual_output_tokens are provided (from API),
    use them directly. Otherwise, estimate from chars/words.
    """
    # Use actual API token counts if available, otherwise estimate
    if actual_input_tokens > 0 or actual_output_tokens > 0:
        estimated_input = actual_input_tokens
        estimated_output = actual_output_tokens
    else:
        # Fallback: ~2 chars per token for mixed Chinese/English
        estimated_input = max(input_chars // 2, input_words)
        estimated_output = max(output_chars // 2, output_words)

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

        if incremental:
            # Incremental mode: add to existing values
            conn.execute(
                """INSERT INTO session_usage
                   (session_pk, total_input_chars, total_output_chars,
                    total_input_words, total_output_words,
                    estimated_input_tokens, estimated_output_tokens,
                    last_processed_line, updated_at)
                   VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                   ON CONFLICT(session_pk) DO UPDATE SET
                    total_input_chars = total_input_chars + excluded.total_input_chars,
                    total_output_chars = total_output_chars + excluded.total_output_chars,
                    total_input_words = total_input_words + excluded.total_input_words,
                    total_output_words = total_output_words + excluded.total_output_words,
                    estimated_input_tokens = estimated_input_tokens + excluded.estimated_input_tokens,
                    estimated_output_tokens = estimated_output_tokens + excluded.estimated_output_tokens,
                    last_processed_line = excluded.last_processed_line,
                    updated_at = excluded.updated_at""",
                (session_pk, input_chars, output_chars, input_words, output_words,
                 estimated_input, estimated_output, last_processed_line, now)
            )
        else:
            # Replace mode: overwrite existing values
            conn.execute(
                """INSERT INTO session_usage
                   (session_pk, total_input_chars, total_output_chars,
                    total_input_words, total_output_words,
                    estimated_input_tokens, estimated_output_tokens,
                    last_processed_line, updated_at)
                   VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                   ON CONFLICT(session_pk) DO UPDATE SET
                    total_input_chars = excluded.total_input_chars,
                    total_output_chars = excluded.total_output_chars,
                    total_input_words = excluded.total_input_words,
                    total_output_words = excluded.total_output_words,
                    estimated_input_tokens = excluded.estimated_input_tokens,
                    estimated_output_tokens = excluded.estimated_output_tokens,
                    last_processed_line = excluded.last_processed_line,
                    updated_at = excluded.updated_at""",
                (session_pk, input_chars, output_chars, input_words, output_words,
                 estimated_input, estimated_output, last_processed_line, now)
            )


def get_last_processed_line(session_id: str) -> int:
    """Get the last processed line number for incremental parsing"""
    with get_connection() as conn:
        cursor = conn.execute(
            """SELECT su.last_processed_line FROM session_usage su
               JOIN sessions s ON su.session_pk = s.id
               WHERE s.session_id = ?""",
            (session_id,)
        )
        row = cursor.fetchone()
        return row['last_processed_line'] if row else 0


def get_session_usage(session_id: str) -> Optional[Dict]:
    """Get usage statistics for a session

    Returns:
        Dict with usage stats, or None if not found
    """
    with get_connection() as conn:
        cursor = conn.execute(
            """SELECT su.* FROM session_usage su
               JOIN sessions s ON su.session_pk = s.id
               WHERE s.session_id = ?""",
            (session_id,)
        )
        row = cursor.fetchone()
        return dict(row) if row else None


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
    cleanup_active_sessions_by_shell_pid,
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
    'update_session_shell_pid',
    # Progress
    'update_progress',
    'get_progress',
    # Pending Decisions
    'add_pending_decision',
    'resolve_pending_decisions',
    'get_pending_decisions',
    # Prompts
    'add_prompt',
    'get_prompts',
    'get_prompt_count',
    # Session Links (Resume)
    'add_session_link',
    'get_resumed_from',
    'get_resume_chain',
    # Session Usage
    'update_session_usage',
    'get_session_usage',
    'get_last_processed_line',
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
    'cleanup_active_sessions_by_shell_pid',
    'create_pending_session',
    'link_pending_session',
    'get_pending_session_by_project',
    'get_session_by_pending_id',
    'cleanup_pending_session',
    'get_active_sessions',
    'get_all_session_summaries',
]
