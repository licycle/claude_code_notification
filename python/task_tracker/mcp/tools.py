#!/usr/bin/env python3
"""
MCP Tools Implementation
Provides tools for Claude Code to interact with the Todo system
"""
import os
from typing import Optional, List, Dict, Any

from ..services.todo_service import (
    list_todos as _list_todos,
    get_todo as _get_todo,
    start_todo as _start_todo,
    complete_todo as _complete_todo,
    split_todo as _split_todo,
    create_todo as _create_todo,
    update_todo as _update_todo,
    get_todo_dependencies,
    get_pending_todos_for_project,
    get_project_todo_stats,
)


def _get_current_project() -> str:
    """Get current project path from environment or cwd

    Priority:
    1. CLAUDE_PROJECT_DIR - explicitly set by Claude Code
    2. PWD - user's shell current directory (more reliable than cwd for MCP)
    3. os.getcwd() - fallback
    """
    # First try explicit Claude project dir
    project_dir = os.environ.get('CLAUDE_PROJECT_DIR')
    if project_dir:
        return project_dir

    # Try PWD (user's shell directory, not MCP server's cwd)
    pwd = os.environ.get('PWD')
    if pwd:
        return pwd

    # Fallback to cwd
    return os.getcwd()


def _get_session_pk() -> Optional[int]:
    """Get current session pk from environment"""
    session_pk = os.environ.get('CLAUDE_SESSION_PK')
    return int(session_pk) if session_pk else None


def list_todos(
    project_path: Optional[str] = None,
    status: str = "all",
    include_children: bool = True,
    limit: int = 20
) -> Dict[str, Any]:
    """
    List todos for a project.

    Args:
        project_path: Project path to filter by. If not specified, uses current project.
        status: Filter by status: 'all', 'pending', 'in_progress', 'blocked', 'completed', 'cancelled'
        include_children: Whether to include child todos
        limit: Maximum number of todos to return

    Returns:
        Dict with 'todos' list and 'count'
    """
    if not project_path:
        project_path = _get_current_project()

    status_filter = status if status != "all" else None

    todos = _list_todos(
        project_path=project_path,
        status=status_filter,
        include_children=include_children,
        limit=limit
    )

    return {
        "todos": [todo.to_dict() for todo in todos],
        "count": len(todos),
        "project_path": project_path,
        "stats": get_project_todo_stats(project_path)
    }


def get_todo(todo_id: int, include_children: bool = True) -> Dict[str, Any]:
    """
    Get detailed information about a specific todo.

    Args:
        todo_id: The ID of the todo
        include_children: Whether to include child todos

    Returns:
        Dict with todo details, dependencies, and execution history
    """
    todo = _get_todo(todo_id, include_children=include_children)

    if not todo:
        return {
            "success": False,
            "error": f"Todo with ID {todo_id} not found"
        }

    dependencies = get_todo_dependencies(todo_id)

    return {
        "success": True,
        "todo": todo.to_dict(),
        "dependencies": [d.to_dict() for d in dependencies]
    }


def start_todo(todo_id: int, notes: str = None) -> Dict[str, Any]:
    """
    Start working on a todo. Marks the todo as 'in_progress'.

    Args:
        todo_id: The ID of the todo to start
        notes: Optional notes about starting this todo

    Returns:
        Dict with success status and updated todo
    """
    session_pk = _get_session_pk()

    todo = _start_todo(
        todo_id=todo_id,
        session_pk=session_pk,
        actor='claude_code'
    )

    if not todo:
        return {
            "success": False,
            "error": f"Failed to start todo {todo_id}"
        }

    return {
        "success": True,
        "todo": todo.to_dict(),
        "message": f"Started working on: {todo.title}"
    }


def complete_todo(
    todo_id: int,
    summary: Optional[str] = None,
    actual_minutes: Optional[int] = None
) -> Dict[str, Any]:
    """
    Mark a todo as completed.

    Args:
        todo_id: The ID of the todo to complete
        summary: A brief summary of what was accomplished
        actual_minutes: Actual time spent in minutes

    Returns:
        Dict with success status and updated todo
    """
    session_pk = _get_session_pk()

    todo = _complete_todo(
        todo_id=todo_id,
        summary=summary,
        actual_minutes=actual_minutes,
        session_pk=session_pk,
        actor='claude_code'
    )

    if not todo:
        return {
            "success": False,
            "error": f"Failed to complete todo {todo_id}"
        }

    return {
        "success": True,
        "todo": todo.to_dict(),
        "message": f"Completed: {todo.title}"
    }


def split_todo(todo_id: int, sub_todos: List[Dict]) -> Dict[str, Any]:
    """
    Split a todo into smaller sub-todos.

    Args:
        todo_id: The ID of the parent todo to split
        sub_todos: List of sub-todo definitions, each containing:
            - title (required): Title of the sub-todo
            - description (optional): Description
            - priority (optional): 0=normal, 1=high, 2=urgent
            - estimated_minutes (optional): Time estimate

    Returns:
        Dict with success status and created sub-todos
    """
    session_pk = _get_session_pk()

    created = _split_todo(
        todo_id=todo_id,
        sub_todos=sub_todos,
        session_pk=session_pk,
        actor='claude_code'
    )

    if not created:
        return {
            "success": False,
            "error": f"Failed to split todo {todo_id}"
        }

    return {
        "success": True,
        "parent_todo_id": todo_id,
        "sub_todos": [t.to_dict() for t in created],
        "message": f"Created {len(created)} sub-todos"
    }


def create_todo(
    title: str,
    project_path: Optional[str] = None,
    description: Optional[str] = None,
    priority: int = 0,
    estimated_minutes: Optional[int] = None,
    global_task_id: Optional[int] = None,
    parent_todo_id: Optional[int] = None
) -> Dict[str, Any]:
    """
    Create a new todo.

    Args:
        title: Title of the todo
        project_path: Project path. If not specified, uses current project.
        description: Detailed description
        priority: 0=normal, 1=high, 2=urgent
        estimated_minutes: Time estimate in minutes
        global_task_id: Optional global task to link to
        parent_todo_id: Optional parent todo (for sub-tasks)

    Returns:
        Dict with success status and created todo
    """
    if not project_path:
        project_path = _get_current_project()

    todo = _create_todo(
        project_path=project_path,
        title=title,
        description=description,
        global_task_id=global_task_id,
        parent_todo_id=parent_todo_id,
        priority=priority,
        estimated_minutes=estimated_minutes,
        actor='claude_code'
    )

    return {
        "success": True,
        "todo": todo.to_dict(),
        "message": f"Created todo: {todo.title}"
    }


def update_todo(
    todo_id: int,
    title: Optional[str] = None,
    description: Optional[str] = None,
    status: Optional[str] = None,
    priority: Optional[int] = None,
    estimated_minutes: Optional[int] = None
) -> Dict[str, Any]:
    """
    Update an existing todo.

    Args:
        todo_id: The ID of the todo to update
        title: New title (optional)
        description: New description (optional)
        status: New status: 'pending', 'in_progress', 'blocked', 'completed', 'cancelled'
        priority: New priority: 0=normal, 1=high, 2=urgent
        estimated_minutes: New time estimate

    Returns:
        Dict with success status and updated todo
    """
    todo = _update_todo(
        todo_id=todo_id,
        title=title,
        description=description,
        status=status,
        priority=priority,
        estimated_minutes=estimated_minutes,
        actor='claude_code'
    )

    if not todo:
        return {
            "success": False,
            "error": f"Failed to update todo {todo_id}"
        }

    return {
        "success": True,
        "todo": todo.to_dict(),
        "message": f"Updated todo: {todo.title}"
    }


def get_pending_todos(project_path: Optional[str] = None, limit: int = 10) -> Dict[str, Any]:
    """
    Get pending todos for quick reference.

    Args:
        project_path: Project path. If not specified, uses current project.
        limit: Maximum number of todos to return

    Returns:
        Dict with pending todos and project stats
    """
    if not project_path:
        project_path = _get_current_project()

    todos = get_pending_todos_for_project(project_path, limit)

    return {
        "todos": [todo.to_dict() for todo in todos],
        "count": len(todos),
        "project_path": project_path,
        "stats": get_project_todo_stats(project_path)
    }
