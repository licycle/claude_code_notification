#!/usr/bin/env python3
"""
todo_cli.py - CLI Tool for Claude Todo System
Provides command-line interface for managing global tasks, todos, workflows, and MCP server

Usage:
    claude-todo task create "Task title"
    claude-todo todo list --project /path/to/project
    claude-todo workflow run task-decomposition
    claude-todo server start --daemon
"""
import argparse
import json
import os
import sys
from datetime import datetime
from pathlib import Path
from typing import Optional

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent.parent))

from task_tracker.services.todo_service import (
    create_global_task,
    get_global_task,
    list_global_tasks,
    update_global_task,
    archive_global_task,
    create_todo,
    get_todo,
    list_todos,
    update_todo,
    start_todo,
    complete_todo,
    split_todo,
    get_project_todo_stats,
    list_workflow_runs,
    get_workflow_run,
    get_workflow_step_logs,
)
from task_tracker.mcp.server import (
    start_server,
    stop_server,
    server_status,
    is_server_running,
)


# ============================================================================
# Output Formatting
# ============================================================================

def format_priority(priority: int) -> str:
    """Format priority as string"""
    return {0: '○', 1: '●', 2: '◉'}[priority]


def format_status(status: str) -> str:
    """Format status with color indicator"""
    indicators = {
        'active': '[ACTIVE]',
        'completed': '[DONE]',
        'archived': '[ARCHIVED]',
        'pending': '[ ]',
        'in_progress': '[→]',
        'blocked': '[!]',
        'cancelled': '[×]',
        'running': '[RUN]',
        'failed': '[ERR]',
    }
    return indicators.get(status, f'[{status}]')


def print_table(headers: list, rows: list, widths: list = None):
    """Print formatted table"""
    if not widths:
        widths = [max(len(str(row[i])) for row in rows + [headers]) for i in range(len(headers))]

    header_line = ' | '.join(h.ljust(w) for h, w in zip(headers, widths))
    separator = '-+-'.join('-' * w for w in widths)

    print(header_line)
    print(separator)
    for row in rows:
        print(' | '.join(str(cell).ljust(w) for cell, w in zip(row, widths)))


def print_json(data):
    """Print data as formatted JSON"""
    print(json.dumps(data, ensure_ascii=False, indent=2, default=str))


# ============================================================================
# Task Commands
# ============================================================================

def cmd_task_create(args):
    """Create a new global task"""
    task = create_global_task(
        title=args.title,
        description=args.desc,
        priority=args.priority
    )
    print(f"Created task #{task.id}: {task.title}")
    if args.json:
        print_json(task.to_dict())


def cmd_task_list(args):
    """List global tasks"""
    tasks = list_global_tasks(
        status=args.status if args.status != 'all' else None,
        limit=args.limit
    )

    if args.json:
        print_json([t.to_dict() for t in tasks])
        return

    if not tasks:
        print("No tasks found")
        return

    headers = ['ID', 'P', 'Status', 'Title', 'Progress']
    rows = []
    for t in tasks:
        progress = f"{t.completed_todo_count}/{t.todo_count}" if t.todo_count > 0 else "-"
        rows.append([
            t.id,
            format_priority(t.priority),
            format_status(t.status),
            t.title[:40],
            progress
        ])

    print_table(headers, rows, [4, 2, 10, 40, 10])


def cmd_task_show(args):
    """Show task details"""
    task = get_global_task(args.task_id)
    if not task:
        print(f"Task #{args.task_id} not found")
        sys.exit(1)

    if args.json:
        print_json(task.to_dict())
        return

    print(f"Task #{task.id}: {task.title}")
    print(f"Status: {task.status}")
    print(f"Priority: {format_priority(task.priority)}")
    print(f"Created: {task.created_at}")
    if task.description:
        print(f"\nDescription:\n{task.description}")
    print(f"\nProgress: {task.completed_todo_count}/{task.todo_count} todos completed")


def cmd_task_update(args):
    """Update a global task"""
    task = update_global_task(
        task_id=args.task_id,
        title=args.title,
        description=args.desc,
        status=args.status,
        priority=args.priority
    )
    if task:
        print(f"Updated task #{task.id}")
    else:
        print(f"Task #{args.task_id} not found")
        sys.exit(1)


def cmd_task_archive(args):
    """Archive a global task"""
    task = archive_global_task(args.task_id)
    if task:
        print(f"Archived task #{task.id}")
    else:
        print(f"Task #{args.task_id} not found")
        sys.exit(1)


# ============================================================================
# Todo Commands
# ============================================================================

def cmd_todo_add(args):
    """Create a new todo"""
    project = args.project or os.getcwd()
    todo = create_todo(
        project_path=project,
        title=args.title,
        description=args.desc,
        global_task_id=args.task,
        priority=args.priority,
        estimated_minutes=args.time
    )
    print(f"Created todo #{todo.id}: {todo.title}")
    if args.json:
        print_json(todo.to_dict())


def cmd_todo_list(args):
    """List todos"""
    project = args.project or (os.getcwd() if not args.all else None)
    todos = list_todos(
        project_path=project,
        status=args.status if args.status != 'all' else None,
        global_task_id=args.task,
        include_children=args.children,
        limit=args.limit
    )

    if args.json:
        print_json([t.to_dict() for t in todos])
        return

    if not todos:
        print("No todos found")
        return

    headers = ['ID', 'P', 'Status', 'Title', 'Est', 'Project']
    rows = []
    for t in todos:
        est = f"{t.estimated_minutes}m" if t.estimated_minutes else "-"
        proj = Path(t.project_path).name[:15]
        rows.append([
            t.id,
            format_priority(t.priority),
            format_status(t.status),
            t.title[:35],
            est,
            proj
        ])

    print_table(headers, rows, [4, 2, 8, 35, 5, 15])

    # Show stats if project specified
    if project:
        stats = get_project_todo_stats(project)
        print(f"\nStats: {stats['pending']} pending, {stats['in_progress']} in progress, {stats['completed']} completed")


def cmd_todo_show(args):
    """Show todo details"""
    todo = get_todo(args.todo_id, include_children=True)
    if not todo:
        print(f"Todo #{args.todo_id} not found")
        sys.exit(1)

    if args.json:
        print_json(todo.to_dict())
        return

    print(f"Todo #{todo.id}: {todo.title}")
    print(f"Status: {todo.status}")
    print(f"Priority: {format_priority(todo.priority)}")
    print(f"Project: {todo.project_path}")
    print(f"Created: {todo.created_at}")
    if todo.estimated_minutes:
        print(f"Estimated: {todo.estimated_minutes} minutes")
    if todo.actual_minutes:
        print(f"Actual: {todo.actual_minutes} minutes")
    if todo.description:
        print(f"\nDescription:\n{todo.description}")
    if todo.completion_summary:
        print(f"\nCompletion Summary:\n{todo.completion_summary}")
    if todo.children:
        print(f"\nSub-todos ({len(todo.children)}):")
        for child in todo.children:
            print(f"  {format_status(child.status)} #{child.id}: {child.title}")


def cmd_todo_update(args):
    """Update a todo"""
    todo = update_todo(
        todo_id=args.todo_id,
        title=args.title,
        description=args.desc,
        status=args.status,
        priority=args.priority,
        estimated_minutes=args.time
    )
    if todo:
        print(f"Updated todo #{todo.id}")
    else:
        print(f"Todo #{args.todo_id} not found")
        sys.exit(1)


def cmd_todo_start(args):
    """Start a todo"""
    todo = start_todo(args.todo_id, actor='user')
    if todo:
        print(f"Started todo #{todo.id}: {todo.title}")
    else:
        print(f"Todo #{args.todo_id} not found")
        sys.exit(1)


def cmd_todo_complete(args):
    """Complete a todo"""
    todo = complete_todo(
        todo_id=args.todo_id,
        summary=args.summary,
        actual_minutes=args.time,
        actor='user'
    )
    if todo:
        print(f"Completed todo #{todo.id}: {todo.title}")
    else:
        print(f"Todo #{args.todo_id} not found")
        sys.exit(1)


def cmd_todo_split(args):
    """Split a todo into sub-todos"""
    sub_todos = []
    for title in args.subtasks:
        sub_todos.append({'title': title})

    created = split_todo(args.todo_id, sub_todos, actor='user')
    if created:
        print(f"Split todo #{args.todo_id} into {len(created)} sub-todos:")
        for t in created:
            print(f"  #{t.id}: {t.title}")
    else:
        print(f"Failed to split todo #{args.todo_id}")
        sys.exit(1)


# ============================================================================
# Workflow Commands
# ============================================================================

def cmd_workflow_list(args):
    """List available workflows"""
    # List default workflows
    default_workflows = [
        {'name': 'task-decomposition', 'description': 'Decompose global task into project todos'},
    ]

    # List user workflows
    user_workflow_dir = Path.home() / '.claude-task-tracker' / 'workflows'
    user_workflows = []
    if user_workflow_dir.exists():
        for f in user_workflow_dir.glob('*.yaml'):
            user_workflows.append({'name': f.stem, 'description': f'User workflow: {f.stem}'})

    all_workflows = default_workflows + user_workflows

    if args.json:
        print_json(all_workflows)
        return

    headers = ['Name', 'Description']
    rows = [[w['name'], w['description']] for w in all_workflows]
    print_table(headers, rows, [25, 50])


def cmd_workflow_status(args):
    """Show workflow run status"""
    run = get_workflow_run(args.run_id)
    if not run:
        print(f"Workflow run #{args.run_id} not found")
        sys.exit(1)

    if args.json:
        print_json(run.to_dict())
        return

    print(f"Workflow: {run.workflow_name}")
    print(f"Status: {format_status(run.status)}")
    print(f"Current Step: {run.current_step or '-'}")
    print(f"Started: {run.started_at or '-'}")
    print(f"Completed: {run.completed_at or '-'}")

    # Show step logs
    logs = get_workflow_step_logs(run.id)
    if logs:
        print("\nStep Logs:")
        for log in logs:
            print(f"  {format_status(log['status'])} {log['step_id']}")
            if log['error']:
                print(f"    Error: {log['error']}")


def cmd_workflow_runs(args):
    """List recent workflow runs"""
    runs = list_workflow_runs(
        workflow_name=args.name,
        status=args.status if args.status != 'all' else None,
        limit=args.limit
    )

    if args.json:
        print_json([r.to_dict() for r in runs])
        return

    if not runs:
        print("No workflow runs found")
        return

    headers = ['ID', 'Workflow', 'Status', 'Step', 'Started']
    rows = []
    for r in runs:
        started = r.started_at.strftime('%m-%d %H:%M') if r.started_at else '-'
        rows.append([
            r.id,
            r.workflow_name[:20],
            format_status(r.status),
            (r.current_step or '-')[:15],
            started
        ])

    print_table(headers, rows, [5, 20, 10, 15, 12])


def cmd_workflow_run(args):
    """Run a workflow"""
    from task_tracker.workflow.engine import WorkflowEngine

    # Parse input parameters
    inputs = {}
    if args.inputs:
        for inp in args.inputs:
            if '=' in inp:
                key, value = inp.split('=', 1)
                # Try to parse as JSON for complex values
                try:
                    inputs[key] = json.loads(value)
                except json.JSONDecodeError:
                    inputs[key] = value

    # Add project paths if specified
    if args.projects:
        inputs['project_paths'] = args.projects

    # Add task info if specified
    if args.task_id:
        inputs['task_id'] = args.task_id
        task = get_global_task(args.task_id)
        if task:
            inputs['task_title'] = task.title
            inputs['task_description'] = task.description or ''

    try:
        print(f"Loading workflow: {args.name}")
        engine = WorkflowEngine(workflow_name=args.name)

        print(f"Executing workflow with inputs: {list(inputs.keys())}")
        result = engine.execute(inputs)

        print(f"\nWorkflow completed with status: {format_status(result.status)}")
        print(f"Run ID: {result.run_id}")

        if args.json:
            print_json({
                'run_id': result.run_id,
                'status': result.status,
                'results': {k: {'status': v.status.value, 'output': v.output}
                           for k, v in result.results.items()}
            })
        else:
            print(f"\nStep Results:")
            for step_id, step_result in result.results.items():
                status_str = format_status(step_result.status.value)
                print(f"  {status_str} {step_id}")
                if step_result.error:
                    print(f"      Error: {step_result.error}")

        if result.status == 'failed':
            sys.exit(1)

    except FileNotFoundError as e:
        print(f"Error: {e}")
        sys.exit(1)
    except Exception as e:
        print(f"Workflow execution failed: {e}")
        sys.exit(1)


def cmd_task_decompose(args):
    """Decompose a global task into project todos using AI workflow"""
    from task_tracker.workflow.engine import WorkflowEngine
    from task_tracker.workflow.claude_agent import list_api_profiles

    # Get task info
    task = get_global_task(args.task_id)
    if not task:
        print(f"Task #{args.task_id} not found")
        sys.exit(1)

    # Determine project paths
    project_paths = args.projects if args.projects else [os.getcwd()]

    # Handle API profile
    api_profile = getattr(args, 'api_profile', None)
    if api_profile:
        available = list_api_profiles()
        if api_profile not in available:
            print(f"API profile '{api_profile}' not found")
            print(f"Available profiles: {', '.join(available)}")
            sys.exit(1)
        print(f"Using API profile: {api_profile}")

    print(f"Decomposing task #{task.id}: {task.title}")
    print(f"Projects: {', '.join(project_paths)}")

    # Prepare inputs
    inputs = {
        'task_id': task.id,
        'task_title': task.title,
        'task_description': task.description or '',
        'project_paths': project_paths,
        'api_profile': api_profile,  # 传递 api_profile
    }

    # Use specified workflow or default
    workflow_name = args.workflow or 'task-decomposition'

    try:
        engine = WorkflowEngine(workflow_name=workflow_name)
        print(f"\nRunning workflow: {workflow_name}")

        result = engine.execute(inputs)

        print(f"\nDecomposition completed with status: {format_status(result.status)}")

        if result.status == 'completed':
            # Show created todos
            save_result = result.results.get('save_todos')
            if save_result and save_result.output:
                saved_count = save_result.output.get('saved', 0)
                todo_ids = save_result.output.get('todo_ids', [])
                print(f"Created {saved_count} todos: {todo_ids}")
        else:
            print("Decomposition failed. Check workflow logs for details.")
            if args.json:
                print_json({
                    'status': result.status,
                    'errors': {k: v.error for k, v in result.results.items() if v.error}
                })
            sys.exit(1)

    except FileNotFoundError:
        print(f"Workflow '{workflow_name}' not found")
        sys.exit(1)
    except Exception as e:
        print(f"Decomposition failed: {e}")
        sys.exit(1)


# ============================================================================
# Server Commands
# ============================================================================

def cmd_server_start(args):
    """Start the MCP server"""
    if is_server_running():
        status = server_status()
        print(f"Server already running at {status['url']} (PID: {status['pid']})")
        return

    print(f"Starting MCP server...")
    start_server(host=args.host, port=args.port, daemon=args.daemon)


def cmd_server_stop(args):
    """Stop the MCP server"""
    if stop_server():
        print("Server stopped")
    else:
        print("Server is not running")


def cmd_server_status(args):
    """Show server status"""
    status = server_status()

    if args.json:
        print_json(status)
        return

    if status['running']:
        print(f"Server is RUNNING")
        print(f"  URL: {status['url']}")
        print(f"  PID: {status['pid']}")
    else:
        print("Server is NOT RUNNING")
    print(f"\nConfiguration:")
    print(f"  Host: {status['config']['host']}")
    print(f"  Port: {status['config']['port']}")


def cmd_server_restart(args):
    """Restart the MCP server"""
    if is_server_running():
        print("Stopping server...")
        stop_server()
    print("Starting server...")
    start_server(host=args.host, port=args.port, daemon=args.daemon)


# ============================================================================
# API Commands
# ============================================================================

def cmd_api_list(args):
    """List available API profiles from claude-api"""
    from task_tracker.workflow.claude_agent import list_api_profiles, load_api_profile

    profiles = list_api_profiles()
    if not profiles:
        print("No API profiles found.")
        print("Add profiles using: claude-api add <name> ANTHROPIC_BASE_URL=... ANTHROPIC_AUTH_TOKEN=...")
        return

    print("Available API profiles:")
    for name in profiles:
        profile = load_api_profile(name)
        model = profile.get('ANTHROPIC_MODEL', profile.get('OPENAI_MODEL', 'N/A'))
        base_url = profile.get('ANTHROPIC_BASE_URL', profile.get('OPENAI_API_BASE', 'N/A'))
        print(f"  {name}:")
        print(f"    Model: {model}")
        print(f"    URL: {base_url}")


# ============================================================================
# Main Entry Point
# ============================================================================

def main():
    parser = argparse.ArgumentParser(
        prog='claude-todo',
        description='Claude Todo System CLI'
    )
    parser.add_argument('--json', action='store_true', help='Output as JSON')
    subparsers = parser.add_subparsers(dest='command', help='Available commands')

    # -------------------- Task Commands --------------------
    task_parser = subparsers.add_parser('task', help='Manage global tasks')
    task_sub = task_parser.add_subparsers(dest='subcommand')

    # task create
    create_p = task_sub.add_parser('create', help='Create a new global task')
    create_p.add_argument('title', help='Task title')
    create_p.add_argument('--desc', '-d', help='Task description')
    create_p.add_argument('--priority', '-p', type=int, choices=[0, 1, 2], default=0,
                         help='Priority: 0=normal, 1=high, 2=urgent')
    create_p.add_argument('--json', action='store_true')
    create_p.set_defaults(func=cmd_task_create)

    # task list
    list_p = task_sub.add_parser('list', help='List global tasks')
    list_p.add_argument('--status', '-s', choices=['all', 'active', 'completed', 'archived'],
                       default='active')
    list_p.add_argument('--limit', '-n', type=int, default=20)
    list_p.add_argument('--json', action='store_true')
    list_p.set_defaults(func=cmd_task_list)

    # task show
    show_p = task_sub.add_parser('show', help='Show task details')
    show_p.add_argument('task_id', type=int, help='Task ID')
    show_p.add_argument('--json', action='store_true')
    show_p.set_defaults(func=cmd_task_show)

    # task update
    update_p = task_sub.add_parser('update', help='Update a task')
    update_p.add_argument('task_id', type=int, help='Task ID')
    update_p.add_argument('--title', '-t')
    update_p.add_argument('--desc', '-d')
    update_p.add_argument('--status', '-s', choices=['active', 'completed', 'archived'])
    update_p.add_argument('--priority', '-p', type=int, choices=[0, 1, 2])
    update_p.set_defaults(func=cmd_task_update)

    # task archive
    archive_p = task_sub.add_parser('archive', help='Archive a task')
    archive_p.add_argument('task_id', type=int, help='Task ID')
    archive_p.set_defaults(func=cmd_task_archive)

    # task decompose
    decompose_p = task_sub.add_parser('decompose', help='Decompose a task into todos using AI')
    decompose_p.add_argument('task_id', type=int, help='Task ID to decompose')
    decompose_p.add_argument('--projects', nargs='+', help='Project paths to analyze')
    decompose_p.add_argument('--api-profile', dest='api_profile', help='API profile name from claude-api (e.g., kimi)')
    decompose_p.add_argument('--workflow', help='Workflow name (default: task-decomposition)')
    decompose_p.add_argument('--json', action='store_true')
    decompose_p.set_defaults(func=cmd_task_decompose)

    # -------------------- Todo Commands --------------------
    todo_parser = subparsers.add_parser('todo', help='Manage todos')
    todo_sub = todo_parser.add_subparsers(dest='subcommand')

    # todo add
    add_p = todo_sub.add_parser('add', help='Create a new todo')
    add_p.add_argument('title', help='Todo title')
    add_p.add_argument('--project', help='Project path (default: current directory)')
    add_p.add_argument('--desc', '-d', help='Description')
    add_p.add_argument('--task', '-t', type=int, help='Global task ID to link')
    add_p.add_argument('--priority', '-p', type=int, choices=[0, 1, 2], default=0)
    add_p.add_argument('--time', type=int, help='Estimated time in minutes')
    add_p.add_argument('--json', action='store_true')
    add_p.set_defaults(func=cmd_todo_add)

    # todo list
    list_p = todo_sub.add_parser('list', help='List todos')
    list_p.add_argument('--project', help='Project path')
    list_p.add_argument('--all', '-a', action='store_true', help='List all projects')
    list_p.add_argument('--status', '-s',
                       choices=['all', 'pending', 'in_progress', 'blocked', 'completed', 'cancelled'],
                       default='all')
    list_p.add_argument('--task', '-t', type=int, help='Filter by global task ID')
    list_p.add_argument('--children', '-c', action='store_true', help='Include children')
    list_p.add_argument('--limit', '-n', type=int, default=20)
    list_p.add_argument('--json', action='store_true')
    list_p.set_defaults(func=cmd_todo_list)

    # todo show
    show_p = todo_sub.add_parser('show', help='Show todo details')
    show_p.add_argument('todo_id', type=int, help='Todo ID')
    show_p.add_argument('--json', action='store_true')
    show_p.set_defaults(func=cmd_todo_show)

    # todo update
    update_p = todo_sub.add_parser('update', help='Update a todo')
    update_p.add_argument('todo_id', type=int, help='Todo ID')
    update_p.add_argument('--title', '-t')
    update_p.add_argument('--desc', '-d')
    update_p.add_argument('--status', '-s',
                         choices=['pending', 'in_progress', 'blocked', 'completed', 'cancelled'])
    update_p.add_argument('--priority', '-p', type=int, choices=[0, 1, 2])
    update_p.add_argument('--time', type=int, help='Estimated time in minutes')
    update_p.set_defaults(func=cmd_todo_update)

    # todo start
    start_p = todo_sub.add_parser('start', help='Start a todo')
    start_p.add_argument('todo_id', type=int, help='Todo ID')
    start_p.set_defaults(func=cmd_todo_start)

    # todo complete
    complete_p = todo_sub.add_parser('complete', help='Complete a todo')
    complete_p.add_argument('todo_id', type=int, help='Todo ID')
    complete_p.add_argument('--summary', '-s', help='Completion summary')
    complete_p.add_argument('--time', type=int, help='Actual time spent in minutes')
    complete_p.set_defaults(func=cmd_todo_complete)

    # todo split
    split_p = todo_sub.add_parser('split', help='Split a todo into sub-todos')
    split_p.add_argument('todo_id', type=int, help='Todo ID')
    split_p.add_argument('subtasks', nargs='+', help='Sub-task titles')
    split_p.set_defaults(func=cmd_todo_split)

    # -------------------- Workflow Commands --------------------
    wf_parser = subparsers.add_parser('workflow', help='Manage workflows')
    wf_sub = wf_parser.add_subparsers(dest='subcommand')

    # workflow list
    list_p = wf_sub.add_parser('list', help='List available workflows')
    list_p.add_argument('--json', action='store_true')
    list_p.set_defaults(func=cmd_workflow_list)

    # workflow status
    status_p = wf_sub.add_parser('status', help='Show workflow run status')
    status_p.add_argument('run_id', type=int, help='Run ID')
    status_p.add_argument('--json', action='store_true')
    status_p.set_defaults(func=cmd_workflow_status)

    # workflow runs
    runs_p = wf_sub.add_parser('runs', help='List recent workflow runs')
    runs_p.add_argument('--name', help='Filter by workflow name')
    runs_p.add_argument('--status', '-s',
                       choices=['all', 'pending', 'running', 'completed', 'failed', 'cancelled'],
                       default='all')
    runs_p.add_argument('--limit', '-n', type=int, default=10)
    runs_p.add_argument('--json', action='store_true')
    runs_p.set_defaults(func=cmd_workflow_runs)

    # workflow run
    run_p = wf_sub.add_parser('run', help='Execute a workflow')
    run_p.add_argument('name', help='Workflow name')
    run_p.add_argument('--input', '-i', action='append', dest='inputs',
                      help='Input parameter (key=value format, can be used multiple times)')
    run_p.add_argument('--projects', nargs='+', help='Project paths')
    run_p.add_argument('--task-id', type=int, help='Global task ID to associate')
    run_p.add_argument('--json', action='store_true')
    run_p.set_defaults(func=cmd_workflow_run)

    # -------------------- Server Commands --------------------
    srv_parser = subparsers.add_parser('server', help='Manage MCP server')
    srv_sub = srv_parser.add_subparsers(dest='subcommand')

    # server start
    start_p = srv_sub.add_parser('start', help='Start the MCP server')
    start_p.add_argument('--host', default=None)
    start_p.add_argument('--port', type=int, default=None)
    start_p.add_argument('--daemon', '-d', action='store_true', help='Run in background')
    start_p.set_defaults(func=cmd_server_start)

    # server stop
    stop_p = srv_sub.add_parser('stop', help='Stop the MCP server')
    stop_p.set_defaults(func=cmd_server_stop)

    # server status
    status_p = srv_sub.add_parser('status', help='Show server status')
    status_p.add_argument('--json', action='store_true')
    status_p.set_defaults(func=cmd_server_status)

    # server restart
    restart_p = srv_sub.add_parser('restart', help='Restart the MCP server')
    restart_p.add_argument('--host', default=None)
    restart_p.add_argument('--port', type=int, default=None)
    restart_p.add_argument('--daemon', '-d', action='store_true')
    restart_p.set_defaults(func=cmd_server_restart)

    # -------------------- API Commands --------------------
    api_parser = subparsers.add_parser('api', help='Manage API profiles')
    api_sub = api_parser.add_subparsers(dest='subcommand')

    # api list
    api_list_p = api_sub.add_parser('list', help='List available API profiles')
    api_list_p.set_defaults(func=cmd_api_list)

    # Parse and execute
    args = parser.parse_args()

    if not args.command:
        parser.print_help()
        sys.exit(0)

    if hasattr(args, 'func'):
        args.func(args)
    else:
        # Show subcommand help
        if args.command == 'task':
            task_parser.print_help()
        elif args.command == 'todo':
            todo_parser.print_help()
        elif args.command == 'workflow':
            wf_parser.print_help()
        elif args.command == 'server':
            srv_parser.print_help()


if __name__ == '__main__':
    main()
