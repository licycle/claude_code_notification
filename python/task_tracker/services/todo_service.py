#!/usr/bin/env python3
"""
todo_service.py - Todo Service Module
Provides CRUD operations for Global Tasks and Todos
"""
import json
from dataclasses import dataclass, field, asdict
from datetime import datetime
from typing import Optional, List, Dict, Any
from pathlib import Path

from .database import get_connection, DB_PATH


# ============================================================================
# Data Models
# ============================================================================

@dataclass
class GlobalTask:
    """Global Task model - high-level cross-project objective"""
    id: int
    title: str
    description: Optional[str]
    status: str  # active, completed, archived
    priority: int  # 0=normal, 1=high, 2=urgent
    created_at: datetime
    updated_at: datetime
    completed_at: Optional[datetime]
    metadata: Optional[Dict] = None
    # Aggregated fields
    todo_count: int = 0
    completed_todo_count: int = 0

    def to_dict(self) -> Dict:
        return {
            'id': self.id,
            'title': self.title,
            'description': self.description,
            'status': self.status,
            'priority': self.priority,
            'created_at': self.created_at.isoformat() if self.created_at else None,
            'updated_at': self.updated_at.isoformat() if self.updated_at else None,
            'completed_at': self.completed_at.isoformat() if self.completed_at else None,
            'metadata': self.metadata,
            'todo_count': self.todo_count,
            'completed_todo_count': self.completed_todo_count,
        }


@dataclass
class Todo:
    """Todo model - project-level actionable item"""
    id: int
    global_task_id: Optional[int]
    parent_todo_id: Optional[int]
    project_path: str
    title: str
    description: Optional[str]
    status: str  # pending, in_progress, blocked, completed, cancelled
    priority: int
    estimated_minutes: Optional[int]
    actual_minutes: Optional[int]
    created_at: datetime
    updated_at: datetime
    completed_at: Optional[datetime]
    completion_summary: Optional[str]
    metadata: Optional[Dict] = None
    # Related data
    children: Optional[List['Todo']] = None
    linked_sessions: Optional[List[int]] = None

    def to_dict(self) -> Dict:
        result = {
            'id': self.id,
            'global_task_id': self.global_task_id,
            'parent_todo_id': self.parent_todo_id,
            'project_path': self.project_path,
            'title': self.title,
            'description': self.description,
            'status': self.status,
            'priority': self.priority,
            'estimated_minutes': self.estimated_minutes,
            'actual_minutes': self.actual_minutes,
            'created_at': self.created_at.isoformat() if self.created_at else None,
            'updated_at': self.updated_at.isoformat() if self.updated_at else None,
            'completed_at': self.completed_at.isoformat() if self.completed_at else None,
            'completion_summary': self.completion_summary,
            'metadata': self.metadata,
        }
        if self.children is not None:
            result['children'] = [c.to_dict() for c in self.children]
        if self.linked_sessions is not None:
            result['linked_sessions'] = self.linked_sessions
        return result


@dataclass
class TodoExecution:
    """Todo Execution record - operation log"""
    id: int
    todo_id: int
    session_pk: Optional[int]
    action: str  # created, started, completed, split, etc.
    actor: str  # user, claude_code, system, ai
    details: Optional[Dict]
    created_at: datetime

    def to_dict(self) -> Dict:
        return {
            'id': self.id,
            'todo_id': self.todo_id,
            'session_pk': self.session_pk,
            'action': self.action,
            'actor': self.actor,
            'details': self.details,
            'created_at': self.created_at.isoformat() if self.created_at else None,
        }


@dataclass
class WorkflowRun:
    """Workflow Run record"""
    id: int
    workflow_name: str
    task_id: Optional[int]
    status: str  # pending, running, completed, failed, cancelled
    current_step: Optional[str]
    context: Optional[Dict]
    started_at: Optional[datetime]
    completed_at: Optional[datetime]
    created_at: datetime

    def to_dict(self) -> Dict:
        return {
            'id': self.id,
            'workflow_name': self.workflow_name,
            'task_id': self.task_id,
            'status': self.status,
            'current_step': self.current_step,
            'context': self.context,
            'started_at': self.started_at.isoformat() if self.started_at else None,
            'completed_at': self.completed_at.isoformat() if self.completed_at else None,
            'created_at': self.created_at.isoformat() if self.created_at else None,
        }


# ============================================================================
# Helper Functions
# ============================================================================

def _parse_datetime(value: str) -> Optional[datetime]:
    """Parse datetime string to datetime object"""
    if not value:
        return None
    try:
        return datetime.fromisoformat(value)
    except ValueError:
        return None


def _parse_json(value: str) -> Optional[Dict]:
    """Parse JSON string to dict"""
    if not value:
        return None
    try:
        return json.loads(value)
    except (json.JSONDecodeError, TypeError):
        return None


def _row_to_global_task(row) -> GlobalTask:
    """Convert database row to GlobalTask object"""
    # Handle optional aggregated fields that may not be in all queries
    keys = row.keys() if hasattr(row, 'keys') else []
    todo_count = row['todo_count'] if 'todo_count' in keys else 0
    completed_todo_count = row['completed_todo_count'] if 'completed_todo_count' in keys else 0

    return GlobalTask(
        id=row['id'],
        title=row['title'],
        description=row['description'],
        status=row['status'],
        priority=row['priority'],
        created_at=_parse_datetime(row['created_at']),
        updated_at=_parse_datetime(row['updated_at']),
        completed_at=_parse_datetime(row['completed_at']),
        metadata=_parse_json(row['metadata_json']),
        todo_count=todo_count or 0,
        completed_todo_count=completed_todo_count or 0,
    )


def _row_to_todo(row) -> Todo:
    """Convert database row to Todo object"""
    return Todo(
        id=row['id'],
        global_task_id=row['global_task_id'],
        parent_todo_id=row['parent_todo_id'],
        project_path=row['project_path'],
        title=row['title'],
        description=row['description'],
        status=row['status'],
        priority=row['priority'],
        estimated_minutes=row['estimated_minutes'],
        actual_minutes=row['actual_minutes'],
        created_at=_parse_datetime(row['created_at']),
        updated_at=_parse_datetime(row['updated_at']),
        completed_at=_parse_datetime(row['completed_at']),
        completion_summary=row['completion_summary'],
        metadata=_parse_json(row['metadata_json']),
    )


def _row_to_execution(row) -> TodoExecution:
    """Convert database row to TodoExecution object"""
    return TodoExecution(
        id=row['id'],
        todo_id=row['todo_id'],
        session_pk=row['session_pk'],
        action=row['action'],
        actor=row['actor'],
        details=_parse_json(row['details_json']),
        created_at=_parse_datetime(row['created_at']),
    )


# ============================================================================
# Global Task Operations
# ============================================================================

def create_global_task(
    title: str,
    description: str = None,
    priority: int = 0,
    metadata: Dict = None
) -> GlobalTask:
    """Create a new global task"""
    now = datetime.now().isoformat()
    with get_connection() as conn:
        cursor = conn.execute(
            """INSERT INTO global_tasks (title, description, priority, metadata_json, created_at, updated_at)
               VALUES (?, ?, ?, ?, ?, ?)""",
            (title, description, priority, json.dumps(metadata) if metadata else None, now, now)
        )
        task_id = cursor.lastrowid

        cursor = conn.execute("SELECT * FROM global_tasks WHERE id = ?", (task_id,))
        return _row_to_global_task(cursor.fetchone())


def get_global_task(task_id: int) -> Optional[GlobalTask]:
    """Get a global task by ID with todo counts"""
    with get_connection() as conn:
        cursor = conn.execute(
            """SELECT gt.*,
                      (SELECT COUNT(*) FROM todos WHERE global_task_id = gt.id) as todo_count,
                      (SELECT COUNT(*) FROM todos WHERE global_task_id = gt.id AND status = 'completed') as completed_todo_count
               FROM global_tasks gt WHERE gt.id = ?""",
            (task_id,)
        )
        row = cursor.fetchone()
        return _row_to_global_task(row) if row else None


def list_global_tasks(
    status: str = None,
    limit: int = 50,
    offset: int = 0
) -> List[GlobalTask]:
    """List global tasks with optional filtering"""
    with get_connection() as conn:
        query = """SELECT gt.*,
                          (SELECT COUNT(*) FROM todos WHERE global_task_id = gt.id) as todo_count,
                          (SELECT COUNT(*) FROM todos WHERE global_task_id = gt.id AND status = 'completed') as completed_todo_count
                   FROM global_tasks gt"""
        params = []

        if status:
            query += " WHERE gt.status = ?"
            params.append(status)

        query += " ORDER BY gt.priority DESC, gt.created_at DESC LIMIT ? OFFSET ?"
        params.extend([limit, offset])

        cursor = conn.execute(query, params)
        return [_row_to_global_task(row) for row in cursor.fetchall()]


def update_global_task(
    task_id: int,
    title: str = None,
    description: str = None,
    status: str = None,
    priority: int = None,
    metadata: Dict = None
) -> Optional[GlobalTask]:
    """Update a global task"""
    now = datetime.now().isoformat()
    with get_connection() as conn:
        updates = ["updated_at = ?"]
        params = [now]

        if title is not None:
            updates.append("title = ?")
            params.append(title)
        if description is not None:
            updates.append("description = ?")
            params.append(description)
        if status is not None:
            updates.append("status = ?")
            params.append(status)
            if status == 'completed':
                updates.append("completed_at = ?")
                params.append(now)
        if priority is not None:
            updates.append("priority = ?")
            params.append(priority)
        if metadata is not None:
            updates.append("metadata_json = ?")
            params.append(json.dumps(metadata))

        params.append(task_id)
        conn.execute(
            f"UPDATE global_tasks SET {', '.join(updates)} WHERE id = ?",
            params
        )

    return get_global_task(task_id)


def archive_global_task(task_id: int) -> Optional[GlobalTask]:
    """Archive a global task"""
    return update_global_task(task_id, status='archived')


# ============================================================================
# Todo Operations
# ============================================================================

def create_todo(
    project_path: str,
    title: str,
    description: str = None,
    global_task_id: int = None,
    parent_todo_id: int = None,
    priority: int = 0,
    estimated_minutes: int = None,
    metadata: Dict = None,
    actor: str = 'user'
) -> Todo:
    """Create a new todo"""
    now = datetime.now().isoformat()
    with get_connection() as conn:
        cursor = conn.execute(
            """INSERT INTO todos
               (global_task_id, parent_todo_id, project_path, title, description,
                priority, estimated_minutes, metadata_json, created_at, updated_at)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
            (global_task_id, parent_todo_id, project_path, title, description,
             priority, estimated_minutes, json.dumps(metadata) if metadata else None, now, now)
        )
        todo_id = cursor.lastrowid

        # Record execution
        conn.execute(
            """INSERT INTO todo_executions (todo_id, action, actor, created_at)
               VALUES (?, 'created', ?, ?)""",
            (todo_id, actor, now)
        )

        cursor = conn.execute("SELECT * FROM todos WHERE id = ?", (todo_id,))
        return _row_to_todo(cursor.fetchone())


def get_todo(todo_id: int, include_children: bool = False) -> Optional[Todo]:
    """Get a todo by ID"""
    with get_connection() as conn:
        cursor = conn.execute("SELECT * FROM todos WHERE id = ?", (todo_id,))
        row = cursor.fetchone()
        if not row:
            return None

        todo = _row_to_todo(row)

        if include_children:
            cursor = conn.execute(
                "SELECT * FROM todos WHERE parent_todo_id = ? ORDER BY priority DESC, created_at",
                (todo_id,)
            )
            todo.children = [_row_to_todo(r) for r in cursor.fetchall()]

        return todo


def list_todos(
    project_path: str = None,
    global_task_id: int = None,
    status: str = None,
    parent_todo_id: int = None,
    include_children: bool = False,
    limit: int = 50,
    offset: int = 0
) -> List[Todo]:
    """List todos with optional filtering"""
    with get_connection() as conn:
        query = "SELECT * FROM todos WHERE 1=1"
        params = []

        if project_path:
            query += " AND project_path = ?"
            params.append(project_path)
        if global_task_id is not None:
            query += " AND global_task_id = ?"
            params.append(global_task_id)
        if status:
            query += " AND status = ?"
            params.append(status)
        if parent_todo_id is not None:
            query += " AND parent_todo_id = ?"
            params.append(parent_todo_id)
        elif not include_children:
            # Only get top-level todos by default
            query += " AND parent_todo_id IS NULL"

        query += " ORDER BY priority DESC, created_at DESC LIMIT ? OFFSET ?"
        params.extend([limit, offset])

        cursor = conn.execute(query, params)
        todos = [_row_to_todo(row) for row in cursor.fetchall()]

        if include_children:
            for todo in todos:
                cursor = conn.execute(
                    "SELECT * FROM todos WHERE parent_todo_id = ? ORDER BY priority DESC, created_at",
                    (todo.id,)
                )
                todo.children = [_row_to_todo(r) for r in cursor.fetchall()]

        return todos


def update_todo(
    todo_id: int,
    title: str = None,
    description: str = None,
    status: str = None,
    priority: int = None,
    estimated_minutes: int = None,
    actual_minutes: int = None,
    completion_summary: str = None,
    metadata: Dict = None,
    actor: str = 'user'
) -> Optional[Todo]:
    """Update a todo"""
    now = datetime.now().isoformat()
    with get_connection() as conn:
        updates = ["updated_at = ?"]
        params = [now]

        if title is not None:
            updates.append("title = ?")
            params.append(title)
        if description is not None:
            updates.append("description = ?")
            params.append(description)
        if status is not None:
            updates.append("status = ?")
            params.append(status)
            if status == 'completed':
                updates.append("completed_at = ?")
                params.append(now)
        if priority is not None:
            updates.append("priority = ?")
            params.append(priority)
        if estimated_minutes is not None:
            updates.append("estimated_minutes = ?")
            params.append(estimated_minutes)
        if actual_minutes is not None:
            updates.append("actual_minutes = ?")
            params.append(actual_minutes)
        if completion_summary is not None:
            updates.append("completion_summary = ?")
            params.append(completion_summary)
        if metadata is not None:
            updates.append("metadata_json = ?")
            params.append(json.dumps(metadata))

        params.append(todo_id)
        conn.execute(
            f"UPDATE todos SET {', '.join(updates)} WHERE id = ?",
            params
        )

    return get_todo(todo_id)


def start_todo(todo_id: int, session_pk: int = None, actor: str = 'user') -> Optional[Todo]:
    """Start a todo (mark as in_progress)"""
    now = datetime.now().isoformat()
    with get_connection() as conn:
        conn.execute(
            "UPDATE todos SET status = 'in_progress', updated_at = ? WHERE id = ?",
            (now, todo_id)
        )

        conn.execute(
            """INSERT INTO todo_executions (todo_id, session_pk, action, actor, created_at)
               VALUES (?, ?, 'started', ?, ?)""",
            (todo_id, session_pk, actor, now)
        )

        # Create session-todo link if session provided
        if session_pk:
            conn.execute(
                """INSERT INTO session_todo_links (session_pk, todo_id, started_at)
                   VALUES (?, ?, ?)""",
                (session_pk, todo_id, now)
            )

    return get_todo(todo_id)


def complete_todo(
    todo_id: int,
    summary: str = None,
    actual_minutes: int = None,
    session_pk: int = None,
    actor: str = 'user'
) -> Optional[Todo]:
    """Complete a todo"""
    now = datetime.now().isoformat()
    with get_connection() as conn:
        updates = ["status = 'completed'", "completed_at = ?", "updated_at = ?"]
        params = [now, now]

        if summary:
            updates.append("completion_summary = ?")
            params.append(summary)
        if actual_minutes is not None:
            updates.append("actual_minutes = ?")
            params.append(actual_minutes)

        params.append(todo_id)
        conn.execute(
            f"UPDATE todos SET {', '.join(updates)} WHERE id = ?",
            params
        )

        conn.execute(
            """INSERT INTO todo_executions (todo_id, session_pk, action, actor, created_at)
               VALUES (?, ?, 'completed', ?, ?)""",
            (todo_id, session_pk, actor, now)
        )

        # Update session-todo link if exists
        if session_pk:
            conn.execute(
                """UPDATE session_todo_links
                   SET status = 'completed', ended_at = ?
                   WHERE session_pk = ? AND todo_id = ? AND status = 'working'""",
                (now, session_pk, todo_id)
            )

    return get_todo(todo_id)


def split_todo(
    todo_id: int,
    sub_todos: List[Dict],
    session_pk: int = None,
    actor: str = 'user'
) -> List[Todo]:
    """Split a todo into sub-todos"""
    now = datetime.now().isoformat()
    created_todos = []

    with get_connection() as conn:
        # Get parent todo info
        cursor = conn.execute("SELECT project_path, global_task_id FROM todos WHERE id = ?", (todo_id,))
        parent = cursor.fetchone()
        if not parent:
            return []

        project_path = parent['project_path']
        global_task_id = parent['global_task_id']

        # Create sub-todos
        for sub in sub_todos:
            cursor = conn.execute(
                """INSERT INTO todos
                   (global_task_id, parent_todo_id, project_path, title, description,
                    priority, estimated_minutes, created_at, updated_at)
                   VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)""",
                (global_task_id, todo_id, project_path,
                 sub.get('title', 'Sub-task'),
                 sub.get('description'),
                 sub.get('priority', 0),
                 sub.get('estimated_minutes'),
                 now, now)
            )
            sub_todo_id = cursor.lastrowid

            cursor = conn.execute("SELECT * FROM todos WHERE id = ?", (sub_todo_id,))
            created_todos.append(_row_to_todo(cursor.fetchone()))

        # Record split action
        conn.execute(
            """INSERT INTO todo_executions (todo_id, session_pk, action, actor, details_json, created_at)
               VALUES (?, ?, 'split', ?, ?, ?)""",
            (todo_id, session_pk, actor, json.dumps({'sub_todo_ids': [t.id for t in created_todos]}), now)
        )

    return created_todos


def add_todo_dependency(todo_id: int, depends_on_todo_id: int) -> bool:
    """Add a dependency between todos"""
    try:
        with get_connection() as conn:
            conn.execute(
                "INSERT INTO todo_dependencies (todo_id, depends_on_todo_id) VALUES (?, ?)",
                (todo_id, depends_on_todo_id)
            )
        return True
    except Exception:
        return False


def get_todo_dependencies(todo_id: int) -> List[Todo]:
    """Get todos that this todo depends on"""
    with get_connection() as conn:
        cursor = conn.execute(
            """SELECT t.* FROM todos t
               JOIN todo_dependencies td ON t.id = td.depends_on_todo_id
               WHERE td.todo_id = ?""",
            (todo_id,)
        )
        return [_row_to_todo(row) for row in cursor.fetchall()]


def get_todo_executions(todo_id: int, limit: int = 50) -> List[TodoExecution]:
    """Get execution history for a todo"""
    with get_connection() as conn:
        cursor = conn.execute(
            "SELECT * FROM todo_executions WHERE todo_id = ? ORDER BY created_at DESC LIMIT ?",
            (todo_id, limit)
        )
        return [_row_to_execution(row) for row in cursor.fetchall()]


# ============================================================================
# Session-Todo Link Operations
# ============================================================================

def link_session_to_todo(session_pk: int, todo_id: int, notes: str = None) -> int:
    """Link a session to a todo"""
    now = datetime.now().isoformat()
    with get_connection() as conn:
        cursor = conn.execute(
            "INSERT INTO session_todo_links (session_pk, todo_id, started_at, notes) VALUES (?, ?, ?, ?)",
            (session_pk, todo_id, now, notes)
        )
        return cursor.lastrowid


def get_todos_for_session(session_pk: int) -> List[Todo]:
    """Get all todos linked to a session"""
    with get_connection() as conn:
        cursor = conn.execute(
            """SELECT t.* FROM todos t
               JOIN session_todo_links stl ON t.id = stl.todo_id
               WHERE stl.session_pk = ?""",
            (session_pk,)
        )
        return [_row_to_todo(row) for row in cursor.fetchall()]


def get_active_todo_for_session(session_pk: int) -> Optional[Todo]:
    """Get the active (working) todo for a session"""
    with get_connection() as conn:
        cursor = conn.execute(
            """SELECT t.* FROM todos t
               JOIN session_todo_links stl ON t.id = stl.todo_id
               WHERE stl.session_pk = ? AND stl.status = 'working'
               ORDER BY stl.started_at DESC LIMIT 1""",
            (session_pk,)
        )
        row = cursor.fetchone()
        return _row_to_todo(row) if row else None


# ============================================================================
# Workflow Operations
# ============================================================================

def create_workflow_run(
    workflow_name: str,
    task_id: int = None,
    context: Dict = None
) -> int:
    """Create a new workflow run"""
    now = datetime.now().isoformat()
    with get_connection() as conn:
        cursor = conn.execute(
            """INSERT INTO workflow_runs (workflow_name, task_id, context_json, created_at)
               VALUES (?, ?, ?, ?)""",
            (workflow_name, task_id, json.dumps(context) if context else None, now)
        )
        return cursor.lastrowid


def update_workflow_run(
    run_id: int,
    status: str = None,
    current_step: str = None,
    context: Dict = None
) -> None:
    """Update a workflow run"""
    now = datetime.now().isoformat()
    with get_connection() as conn:
        updates = []
        params = []

        if status:
            updates.append("status = ?")
            params.append(status)
            if status == 'running' and not current_step:
                updates.append("started_at = ?")
                params.append(now)
            elif status in ('completed', 'failed', 'cancelled'):
                updates.append("completed_at = ?")
                params.append(now)
        if current_step is not None:
            updates.append("current_step = ?")
            params.append(current_step)
        if context is not None:
            updates.append("context_json = ?")
            params.append(json.dumps(context))

        if updates:
            params.append(run_id)
            conn.execute(
                f"UPDATE workflow_runs SET {', '.join(updates)} WHERE id = ?",
                params
            )


def get_workflow_run(run_id: int) -> Optional[WorkflowRun]:
    """Get a workflow run by ID"""
    with get_connection() as conn:
        cursor = conn.execute("SELECT * FROM workflow_runs WHERE id = ?", (run_id,))
        row = cursor.fetchone()
        if not row:
            return None
        return WorkflowRun(
            id=row['id'],
            workflow_name=row['workflow_name'],
            task_id=row['task_id'],
            status=row['status'],
            current_step=row['current_step'],
            context=_parse_json(row['context_json']),
            started_at=_parse_datetime(row['started_at']),
            completed_at=_parse_datetime(row['completed_at']),
            created_at=_parse_datetime(row['created_at']),
        )


def list_workflow_runs(
    workflow_name: str = None,
    task_id: int = None,
    status: str = None,
    limit: int = 20
) -> List[WorkflowRun]:
    """List workflow runs with optional filtering"""
    with get_connection() as conn:
        query = "SELECT * FROM workflow_runs WHERE 1=1"
        params = []

        if workflow_name:
            query += " AND workflow_name = ?"
            params.append(workflow_name)
        if task_id is not None:
            query += " AND task_id = ?"
            params.append(task_id)
        if status:
            query += " AND status = ?"
            params.append(status)

        query += " ORDER BY created_at DESC LIMIT ?"
        params.append(limit)

        cursor = conn.execute(query, params)
        return [WorkflowRun(
            id=row['id'],
            workflow_name=row['workflow_name'],
            task_id=row['task_id'],
            status=row['status'],
            current_step=row['current_step'],
            context=_parse_json(row['context_json']),
            started_at=_parse_datetime(row['started_at']),
            completed_at=_parse_datetime(row['completed_at']),
            created_at=_parse_datetime(row['created_at']),
        ) for row in cursor.fetchall()]


def add_workflow_step_log(
    run_id: int,
    step_id: str,
    status: str,
    output: Any = None,
    error: str = None
) -> int:
    """Add a step log to a workflow run"""
    now = datetime.now().isoformat()
    with get_connection() as conn:
        started_at = now if status == 'running' else None
        completed_at = now if status in ('completed', 'failed', 'skipped') else None

        cursor = conn.execute(
            """INSERT INTO workflow_step_logs
               (run_id, step_id, status, output_json, error, started_at, completed_at)
               VALUES (?, ?, ?, ?, ?, ?, ?)""",
            (run_id, step_id, status, json.dumps(output) if output else None, error, started_at, completed_at)
        )
        return cursor.lastrowid


def get_workflow_step_logs(run_id: int) -> List[Dict]:
    """Get all step logs for a workflow run"""
    with get_connection() as conn:
        cursor = conn.execute(
            "SELECT * FROM workflow_step_logs WHERE run_id = ? ORDER BY id",
            (run_id,)
        )
        return [{
            'id': row['id'],
            'run_id': row['run_id'],
            'step_id': row['step_id'],
            'status': row['status'],
            'output': _parse_json(row['output_json']),
            'error': row['error'],
            'started_at': row['started_at'],
            'completed_at': row['completed_at'],
        } for row in cursor.fetchall()]


# ============================================================================
# Statistics & Queries
# ============================================================================

def get_project_todo_stats(project_path: str) -> Dict:
    """Get todo statistics for a project"""
    with get_connection() as conn:
        cursor = conn.execute(
            """SELECT
                  COUNT(*) as total,
                  SUM(CASE WHEN status = 'pending' THEN 1 ELSE 0 END) as pending,
                  SUM(CASE WHEN status = 'in_progress' THEN 1 ELSE 0 END) as in_progress,
                  SUM(CASE WHEN status = 'blocked' THEN 1 ELSE 0 END) as blocked,
                  SUM(CASE WHEN status = 'completed' THEN 1 ELSE 0 END) as completed,
                  SUM(CASE WHEN status = 'cancelled' THEN 1 ELSE 0 END) as cancelled
               FROM todos WHERE project_path = ?""",
            (project_path,)
        )
        row = cursor.fetchone()
        return {
            'total': row['total'] or 0,
            'pending': row['pending'] or 0,
            'in_progress': row['in_progress'] or 0,
            'blocked': row['blocked'] or 0,
            'completed': row['completed'] or 0,
            'cancelled': row['cancelled'] or 0,
        }


def get_pending_todos_for_project(project_path: str, limit: int = 10) -> List[Todo]:
    """Get pending todos for a project, ordered by priority"""
    return list_todos(
        project_path=project_path,
        status='pending',
        limit=limit
    )


def get_in_progress_todos() -> List[Todo]:
    """Get all in-progress todos across all projects"""
    return list_todos(status='in_progress', limit=100)


# Export all functions
__all__ = [
    # Data models
    'GlobalTask',
    'Todo',
    'TodoExecution',
    'WorkflowRun',
    # Global Task operations
    'create_global_task',
    'get_global_task',
    'list_global_tasks',
    'update_global_task',
    'archive_global_task',
    # Todo operations
    'create_todo',
    'get_todo',
    'list_todos',
    'update_todo',
    'start_todo',
    'complete_todo',
    'split_todo',
    'add_todo_dependency',
    'get_todo_dependencies',
    'get_todo_executions',
    # Session-Todo link operations
    'link_session_to_todo',
    'get_todos_for_session',
    'get_active_todo_for_session',
    # Workflow operations
    'create_workflow_run',
    'update_workflow_run',
    'get_workflow_run',
    'list_workflow_runs',
    'add_workflow_step_log',
    'get_workflow_step_logs',
    # Statistics
    'get_project_todo_stats',
    'get_pending_todos_for_project',
    'get_in_progress_todos',
]
