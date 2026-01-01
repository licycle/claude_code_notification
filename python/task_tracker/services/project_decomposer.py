#!/usr/bin/env python3
"""
project_decomposer.py - Simplified Project Decomposition Service

Uses a single Claude CLI call to analyze projects and generate todos.
Replaces the complex workflow engine approach.
"""
import subprocess
import json
import os
import re
from dataclasses import dataclass, field
from typing import Optional, Dict, Any, List
from pathlib import Path

from task_tracker.hooks.utils import log


# ============================================================================
# Configuration
# ============================================================================

API_PROFILES_PATH = Path.home() / '.claude-hooks' / 'api_profiles.json'
ACCOUNTS_PATH = Path.home() / '.claude-hooks' / 'accounts.json'


def load_accounts() -> Dict[str, str]:
    """Load accounts from accounts.json"""
    if not ACCOUNTS_PATH.exists():
        return {}
    try:
        with open(ACCOUNTS_PATH) as f:
            return json.load(f)
    except (json.JSONDecodeError, IOError):
        return {}


# ============================================================================
# Exceptions
# ============================================================================

class DecomposeError(Exception):
    """Base exception for decomposition errors"""
    pass


class ProjectNotFoundError(DecomposeError):
    """Project path does not exist"""
    pass


class ClaudeNotFoundError(DecomposeError):
    """Claude CLI not found"""
    pass


class ClaudeTimeoutError(DecomposeError):
    """Claude CLI timed out"""
    pass


class OutputParseError(DecomposeError):
    """Could not parse Claude output as JSON"""
    pass


class ValidationError(DecomposeError):
    """Generated todos failed validation"""
    pass


# ============================================================================
# Data Classes
# ============================================================================

@dataclass
class DecomposeResult:
    """Result of project decomposition"""
    analysis: Dict[str, Any] = field(default_factory=dict)
    todos: List[Dict[str, Any]] = field(default_factory=list)
    total_estimated_minutes: int = 0
    raw_output: str = ""

    @property
    def total_estimated_hours(self) -> float:
        return round(self.total_estimated_minutes / 60, 1)


# ============================================================================
# API Profile Support
# ============================================================================

def load_api_profile(profile_name: str) -> Optional[Dict[str, str]]:
    """
    Load API profile from ~/.claude-hooks/api_profiles.json

    Profile format:
    {
      "kimi": {
        "ANTHROPIC_BASE_URL": "https://api.moonshot.cn/anthropic",
        "ANTHROPIC_AUTH_TOKEN": "sk-xxx",
        "ANTHROPIC_MODEL": "kimi-k2-thinking"
      }
    }
    """
    if not API_PROFILES_PATH.exists():
        return None

    try:
        with open(API_PROFILES_PATH) as f:
            profiles = json.load(f)
            return profiles.get(profile_name)
    except (json.JSONDecodeError, IOError):
        return None


def list_api_profiles() -> List[str]:
    """List available API profile names"""
    if not API_PROFILES_PATH.exists():
        return []

    try:
        with open(API_PROFILES_PATH) as f:
            profiles = json.load(f)
            return list(profiles.keys())
    except (json.JSONDecodeError, IOError):
        return []


# ============================================================================
# Prompt Template
# ============================================================================

DECOMPOSE_PROMPT = """You are an expert software engineer. Analyze the following project(s) and decompose the given task into actionable todos.

## Task
Title: {task_title}
Description: {task_description}

## Project Paths
{project_paths_list}

## Instructions

1. **Explore the codebase thoroughly:**
   - For complex exploration, use the Task tool with subagent_type="Explore" to efficiently search the codebase
   - Use Glob to find relevant files by pattern
   - Use Grep to search for code patterns and keywords
   - Use Read to examine key files in detail
   - Use LS to understand directory structure
   - Use WebSearch/WebFetch if you need to look up documentation

2. **Based on your analysis, use the TodoWrite tool** to create todos that:
   - Are atomic and independently completable
   - Start with action verbs (Implement, Add, Fix, Refactor, Test, Create, Update)
   - Reference specific files or modules
   - Include both `content` (what to do) and `activeForm` (doing what) fields

## Requirements
- Each todo should be atomic and independently completable
- Use action verbs: Implement, Add, Fix, Refactor, Test, Create, Update
- Include specific file/module references when possible
- Status should be "pending" for new todos

## Example TodoWrite call:
```
TodoWrite with todos=[
  {{"content": "Implement user authentication in auth.py", "status": "pending", "activeForm": "Implementing user authentication"}},
  {{"content": "Add unit tests for auth module", "status": "pending", "activeForm": "Adding unit tests"}}
]
```

IMPORTANT: You MUST use the TodoWrite tool to create the todo list.
"""


# ============================================================================
# Project Decomposer
# ============================================================================

class ProjectDecomposer:
    """
    Single-call project analysis and todo generation.

    Usage:
        decomposer = ProjectDecomposer(
            project_paths=["/path/to/project"],
            api_profile="kimi"  # Optional
        )
        result = decomposer.decompose("Task title", "Task description")
        print(result.todos)
    """

    def __init__(
        self,
        project_paths: List[str],
        api_profile: str = None,
        account_alias: str = None,
        timeout: int = 300,
        max_turns: int = 15
    ):
        self.project_paths = [str(Path(p).resolve()) for p in project_paths]
        self.api_profile = api_profile
        self.account_alias = account_alias or 'default'
        self.timeout = timeout
        self.max_turns = max_turns

        # Log initialization
        log("DECOMPOSE", f"ProjectDecomposer initialized")
        log("DECOMPOSE", f"  project_paths: {self.project_paths}")
        log("DECOMPOSE", f"  api_profile: {self.api_profile}")
        log("DECOMPOSE", f"  account_alias: {self.account_alias}")

    def validate_projects(self) -> None:
        """Validate that all project paths exist"""
        for path in self.project_paths:
            if not Path(path).exists():
                raise ProjectNotFoundError(f"Project path not found: {path}")

    def decompose(
        self,
        task_title: str,
        task_description: str = "",
        global_task_id: int = None
    ) -> DecomposeResult:
        """
        Execute single Claude CLI call to analyze project and generate todos.

        The todos are automatically synced to database via PostToolUse hook
        when Claude calls TodoWrite tool. This method just executes Claude
        and returns a summary of the operation.

        Args:
            task_title: Title of the task to decompose
            task_description: Optional description of the task
            global_task_id: Optional global task ID to link todos to

        Returns:
            DecomposeResult with analysis and todos

        Raises:
            ProjectNotFoundError: If project path doesn't exist
            ClaudeNotFoundError: If Claude CLI not found
            ClaudeTimeoutError: If execution times out
        """
        # Store global_task_id for session linking
        self.global_task_id = global_task_id

        # Log start
        log("DECOMPOSE", f"Starting decomposition: {task_title}")
        if global_task_id:
            log("DECOMPOSE", f"Global task ID: {global_task_id}")

        # Validate
        self.validate_projects()

        # Build prompt
        prompt = self._build_prompt(task_title, task_description)

        # Execute Claude CLI (hooks will automatically handle TodoWrite)
        raw_output = self._execute_claude(prompt)

        # Parse result from output (for display only, todos are stored by hooks)
        result = self._parse_result(raw_output)
        result.raw_output = raw_output

        # Cleanup any idle sessions created by claude -p
        self._cleanup_idle_sessions()

        log("DECOMPOSE", f"Decomposition complete. Todos synced via PostToolUse hook.")
        return result

    def _extract_todos_from_transcript(self) -> List[Dict]:
        """
        DEPRECATED: This method is no longer used.
        Todos are now automatically synced via PostToolUse hook in progress_tracker.py
        when Claude calls TodoWrite tool.

        Kept for reference/backward compatibility.
        """
        try:
            # Find transcript directory
            config_dir = Path.home() / '.claude'
            projects_dir = config_dir / 'projects'

            if not projects_dir.exists():
                log("DECOMPOSE", "No projects directory found")
                return []

            # Find the most recent transcript for this project
            project_path = self.project_paths[0]
            # Claude uses a hash of the project path as directory name
            project_hash = project_path.replace('/', '-').replace('\\', '-')
            if project_hash.startswith('-'):
                project_hash = project_hash[1:]

            project_dir = projects_dir / project_hash
            if not project_dir.exists():
                log("DECOMPOSE", f"Project transcript dir not found: {project_dir}")
                return []

            # Find most recent .jsonl file
            jsonl_files = list(project_dir.glob('*.jsonl'))
            if not jsonl_files:
                log("DECOMPOSE", "No transcript files found")
                return []

            # Sort by modification time, get most recent
            latest_transcript = max(jsonl_files, key=lambda f: f.stat().st_mtime)
            log("DECOMPOSE", f"Reading transcript: {latest_transcript.name}")

            # Parse transcript and extract TodoWrite calls
            todos = []
            with open(latest_transcript, 'r', encoding='utf-8') as f:
                for line in f:
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        event = json.loads(line)
                        # Check for TodoWrite tool calls
                        if event.get('tool_name') == 'TodoWrite':
                            tool_input = event.get('tool_input', {})
                            if isinstance(tool_input, str):
                                tool_input = json.loads(tool_input)
                            todo_list = tool_input.get('todos', [])
                            if todo_list:
                                todos = todo_list  # Use the last TodoWrite call
                    except json.JSONDecodeError:
                        continue

            log("DECOMPOSE", f"Extracted {len(todos)} todos from transcript")
            return todos

        except Exception as e:
            log("DECOMPOSE", f"Failed to extract todos from transcript: {e}")
            return []

    def _store_todos_to_db(self, todos: List[Dict], global_task_id: int = None) -> List[int]:
        """
        DEPRECATED: This method is no longer used.
        Todos are now automatically synced via PostToolUse hook in progress_tracker.py
        when Claude calls TodoWrite tool.

        Kept for reference/backward compatibility.
        """
        try:
            from task_tracker.services.todo_service import create_todo, update_todo

            project_path = self.project_paths[0]
            stored_ids = []

            for todo_item in todos:
                # Handle both formats: 'content' (TodoWrite) and 'title' (JSON)
                title = todo_item.get('content') or todo_item.get('title', '')
                if not title:
                    continue

                description = todo_item.get('description', '')
                priority = todo_item.get('priority', 0)
                estimated_minutes = todo_item.get('estimated_minutes')
                status = todo_item.get('status', 'pending')

                # Create todo
                todo = create_todo(
                    project_path=project_path,
                    title=title,
                    description=description,
                    global_task_id=global_task_id,
                    priority=priority,
                    estimated_minutes=estimated_minutes,
                    metadata={'activeForm': todo_item.get('activeForm', '')},
                    actor='ai'
                )

                if todo:
                    # Update status if not pending
                    if status != 'pending':
                        update_todo(todo.id, status=status, actor='ai')
                    stored_ids.append(todo.id)
                    log("DECOMPOSE", f"  Created todo #{todo.id}: {title[:40]}...")

            return stored_ids

        except Exception as e:
            log("DECOMPOSE", f"Failed to store todos: {e}")
            import traceback
            log("DECOMPOSE", traceback.format_exc())
            return []

    def _cleanup_idle_sessions(self) -> None:
        """
        Mark idle sessions for this project as completed.

        claude -p doesn't trigger Stop hook, leaving sessions in 'idle' state.
        This method cleans up those zombie sessions.
        """
        try:
            from task_tracker.services.database import get_connection
            from datetime import datetime

            now = datetime.now().isoformat()
            project_path = self.project_paths[0]

            with get_connection() as conn:
                # Find recent idle sessions for this project (last 10 minutes)
                cursor = conn.execute("""
                    SELECT id, session_id FROM sessions
                    WHERE project = ? AND current_status = 'idle'
                    AND datetime(last_activity) > datetime('now', '-10 minutes')
                """, (project_path,))

                rows = cursor.fetchall()
                for row in rows:
                    session_pk = row['id']
                    session_id = row['session_id']

                    # Update status to completed
                    conn.execute("""
                        UPDATE sessions SET current_status = 'completed', last_activity = ?
                        WHERE id = ?
                    """, (now, session_pk))

                    # Add timeline event
                    conn.execute("""
                        INSERT INTO timeline (session_pk, event_type, content, timestamp)
                        VALUES (?, 'status_change', 'completed (auto-cleanup)', ?)
                    """, (session_pk, now))

                if rows:
                    conn.commit()

        except Exception:
            # Silently ignore cleanup errors - not critical
            pass

    def _build_prompt(self, task_title: str, task_description: str) -> str:
        """Build comprehensive analysis + todo generation prompt"""
        project_paths_list = "\n".join(f"- {p}" for p in self.project_paths)

        return DECOMPOSE_PROMPT.format(
            task_title=task_title,
            task_description=task_description or "(No description provided)",
            project_paths_list=project_paths_list
        )

    def _execute_claude(self, prompt: str) -> str:
        """Execute Claude CLI directly with environment variables"""
        # Get config_path from accounts.json
        accounts = load_accounts()
        config_path = accounts.get(self.account_alias)
        if not config_path:
            config_path = str(Path.home() / '.claude')
            log("DECOMPOSE", f"  Account '{self.account_alias}' not found, using default: {config_path}")

        # Log execution start
        log("DECOMPOSE", f"Executing claude directly: {self.account_alias}")
        log("DECOMPOSE", f"  Config path: {config_path}")
        log("DECOMPOSE", f"  API profile: {self.api_profile or 'none'}")
        log("DECOMPOSE", f"  Working dir: {self.project_paths[0]}")

        try:
            # Build environment with API profile
            env = os.environ.copy()
            env['CLAUDE_CONFIG_DIR'] = config_path
            env['CLAUDE_ACCOUNT_ALIAS'] = self.account_alias

            # Set pending session ID and global task ID for hook tracking
            import uuid
            pending_id = str(uuid.uuid4())
            env['CLAUDE_PENDING_SESSION_ID'] = pending_id
            env['CLAUDE_TERM_BUNDLE_ID'] = 'com.claude.decomposer'
            env['CLAUDE_TERM_PID'] = str(os.getpid())
            env['CLAUDE_SHELL_PID'] = str(os.getpid())
            env['CLAUDE_CG_WINDOW_ID'] = '0'

            # Set global_task_id for sync_todos_to_global_table() in progress_tracker
            if hasattr(self, 'global_task_id') and self.global_task_id:
                env['CLAUDE_DECOMPOSE_TASK_ID'] = str(self.global_task_id)
                log("DECOMPOSE", f"  Global task ID: {self.global_task_id}")

            # Load API profile if specified
            if self.api_profile:
                profile = load_api_profile(self.api_profile)
                if profile:
                    env.update(profile)
                    log("DECOMPOSE", f"  API profile loaded: {list(profile.keys())}")

            # Build command args
            # All non-code-modifying tools for exploration + TodoWrite for output
            allowed_tools = ','.join([
                'Task',       # Explore subagent for deep search
                'Read',       # Read files
                'Glob',       # File pattern matching
                'Grep',       # Content search
                'LS',         # Directory listing
                'WebSearch',  # Web search for docs
                'WebFetch',   # Fetch web content
                'TodoWrite',  # Create todos (triggers hook sync)
            ])
            cmd = [
                'claude',
                '-p', prompt,
                '--allowedTools', allowed_tools,
                '--max-turns', str(self.max_turns)
            ]

            log("DECOMPOSE", f"  Command: {' '.join(cmd[:5])}...")

            result = subprocess.run(
                cmd,
                cwd=self.project_paths[0],
                capture_output=True,
                text=True,
                timeout=self.timeout,
                env=env
            )

            log("DECOMPOSE", f"  Exit code: {result.returncode}")

            # Check for EMFILE error (too many open files)
            if 'EMFILE' in result.stderr:
                log("DECOMPOSE_ERROR", "EMFILE: too many open files")
                raise DecomposeError(
                    "Too many open files (EMFILE). "
                    "Please run in a new terminal or restart terminal."
                )

            if result.returncode != 0:
                error_msg = result.stderr or f"Exit code: {result.returncode}"
                log("DECOMPOSE_ERROR", f"Claude CLI failed: {error_msg}")
                raise DecomposeError(f"Claude CLI failed: {error_msg}")

            log("DECOMPOSE", f"  Output length: {len(result.stdout)} chars")
            return result.stdout

        except subprocess.TimeoutExpired:
            log("DECOMPOSE_ERROR", f"Timeout after {self.timeout}s")
            raise ClaudeTimeoutError(f"Claude CLI timed out after {self.timeout}s")

    def _parse_result(self, output: str) -> DecomposeResult:
        """Parse Claude output - now tolerant since todos are synced via TodoWrite hook"""
        log("DECOMPOSE", "Parsing output...")

        # Try to extract JSON if present (for backward compatibility)
        data = None

        # Strategy 1: JSON in markdown code block
        json_block_match = re.search(r'```json\s*([\s\S]*?)\s*```', output)
        if json_block_match:
            try:
                data = json.loads(json_block_match.group(1))
                log("DECOMPOSE", "  Found JSON in code block")
            except json.JSONDecodeError:
                pass

        # Strategy 2: Generic code block
        if data is None:
            code_block_match = re.search(r'```\s*([\s\S]*?)\s*```', output)
            if code_block_match:
                try:
                    data = json.loads(code_block_match.group(1))
                    log("DECOMPOSE", "  Found JSON in generic block")
                except json.JSONDecodeError:
                    pass

        # Strategy 3: Find outermost { } pair
        if data is None:
            brace_count = 0
            start_idx = -1
            end_idx = -1
            for i, char in enumerate(output):
                if char == '{':
                    if brace_count == 0:
                        start_idx = i
                    brace_count += 1
                elif char == '}':
                    brace_count -= 1
                    if brace_count == 0 and start_idx >= 0:
                        end_idx = i + 1
                        break

            if start_idx >= 0 and end_idx > start_idx:
                try:
                    data = json.loads(output[start_idx:end_idx])
                    log("DECOMPOSE", "  Found bare JSON")
                except json.JSONDecodeError:
                    pass

        # If no JSON found, that's OK - todos are synced via TodoWrite hook
        if data is None:
            log("DECOMPOSE", "  No JSON found - todos synced via TodoWrite hook")
            return DecomposeResult(
                analysis={'note': 'Todos synced via TodoWrite hook'},
                todos=[],
                total_estimated_minutes=0
            )

        # Build result from JSON if found
        todos = data.get('todos', [])
        analysis = data.get('analysis', {})
        total_minutes = data.get('total_estimated_minutes', 0)

        if not total_minutes and todos:
            total_minutes = sum(t.get('estimated_minutes', 60) for t in todos)

        log("DECOMPOSE", f"  Parsed: {len(todos)} todos, {total_minutes} minutes")

        return DecomposeResult(
            analysis=analysis,
            todos=todos,
            total_estimated_minutes=total_minutes
        )

    def _validate_todos(self, todos: List[Dict]) -> None:
        """Validate todos - now optional since todos may be synced via hook"""
        # If no todos from JSON, that's OK - they may have been synced via TodoWrite hook
        if not todos:
            log("DECOMPOSE", "No todos from JSON output - check hooks.log for TodoWrite sync")
            return

        for i, todo in enumerate(todos):
            if not todo.get('title'):
                log("DECOMPOSE", f"Todo {i} missing title, skipping validation")
                continue

            # Set default project_path if not specified
            if not todo.get('project_path'):
                todo['project_path'] = self.project_paths[0]


# ============================================================================
# Convenience Function
# ============================================================================

def decompose_task(
    task_title: str,
    task_description: str = "",
    project_paths: List[str] = None,
    api_profile: str = None,
    timeout: int = 300
) -> DecomposeResult:
    """
    Convenience function to decompose a task.

    Args:
        task_title: Title of the task
        task_description: Optional description
        project_paths: List of project paths (defaults to cwd)
        api_profile: Optional API profile name
        timeout: Timeout in seconds

    Returns:
        DecomposeResult with analysis and todos
    """
    if not project_paths:
        project_paths = [os.getcwd()]

    decomposer = ProjectDecomposer(
        project_paths=project_paths,
        api_profile=api_profile,
        timeout=timeout
    )

    return decomposer.decompose(task_title, task_description)
