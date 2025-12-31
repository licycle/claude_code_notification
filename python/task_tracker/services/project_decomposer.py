#!/usr/bin/env python3
"""
project_decomposer.py - Simplified Project Decomposition Service

Uses a single Claude CLI call to analyze projects and generate todos.
Replaces the complex workflow engine approach.
"""
import subprocess
import json
import shutil
import os
import re
from dataclasses import dataclass, field
from typing import Optional, Dict, Any, List
from pathlib import Path


# ============================================================================
# Configuration
# ============================================================================

API_PROFILES_PATH = Path.home() / '.claude-hooks' / 'api_profiles.json'


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

1. First, explore the codebase:
   - Use Glob to find relevant files
   - Use Grep to search for patterns
   - Use Read to examine key files

2. Based on your analysis, generate todos that:
   - Are atomic and independently completable
   - Start with action verbs (Implement, Add, Fix, Refactor, Test, Create, Update)
   - Reference specific files or modules
   - Have realistic time estimates

## Required Output Format

Return a single JSON object (wrap in ```json ... ``` markers):
```json
{{
  "analysis": {{
    "project_type": "string (e.g., python, typescript, swift)",
    "tech_stack": ["list", "of", "technologies"],
    "relevant_files": ["list", "of", "key", "files"],
    "patterns": ["existing", "code", "patterns"]
  }},
  "todos": [
    {{
      "project_path": "/absolute/path/to/project",
      "title": "Action verb + specific task (e.g., 'Implement JWT authentication')",
      "description": "Detailed description of what needs to be done",
      "priority": 0,
      "estimated_minutes": 60,
      "files_involved": ["file1.py", "file2.py"],
      "acceptance_criteria": ["Criterion 1", "Criterion 2"]
    }}
  ],
  "execution_order": [0, 1, 2],
  "total_estimated_minutes": 480
}}
```

## Requirements
- Each todo should be atomic and independently completable
- Use action verbs: Implement, Add, Fix, Refactor, Test, Create, Update
- Avoid vague words: Optimize, Improve, Handle (be specific)
- Include specific file/module references when possible
- Priority: 0=normal, 1=high, 2=urgent

IMPORTANT: Your response MUST contain a valid JSON object wrapped in ```json ... ``` markers.
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
        timeout: int = 300,
        max_turns: int = 15
    ):
        self.project_paths = [str(Path(p).resolve()) for p in project_paths]
        self.api_profile = api_profile
        self.timeout = timeout
        self.max_turns = max_turns

        # Load API profile settings
        self._api_base_url = ""
        self._api_key = ""
        self._model = ""
        if api_profile:
            profile = load_api_profile(api_profile)
            if profile:
                self._api_base_url = profile.get('ANTHROPIC_BASE_URL', '')
                self._api_key = profile.get('ANTHROPIC_AUTH_TOKEN', '')
                self._model = profile.get('ANTHROPIC_MODEL', '')

        # Find Claude CLI
        self._claude_path = self._find_claude()

    def _find_claude(self) -> Optional[str]:
        """Find Claude CLI executable"""
        paths = [
            shutil.which('claude'),
            '/usr/local/bin/claude',
            str(Path.home() / '.local' / 'bin' / 'claude'),
            str(Path.home() / '.nvm' / 'versions' / 'node' / 'v24.11.0' / 'bin' / 'claude'),
        ]
        for path in paths:
            if path and Path(path).exists():
                return path
        return None

    def validate_projects(self) -> None:
        """Validate that all project paths exist"""
        for path in self.project_paths:
            if not Path(path).exists():
                raise ProjectNotFoundError(f"Project path not found: {path}")

    def decompose(
        self,
        task_title: str,
        task_description: str = ""
    ) -> DecomposeResult:
        """
        Execute single Claude CLI call to analyze project and generate todos.

        Args:
            task_title: Title of the task to decompose
            task_description: Optional description of the task

        Returns:
            DecomposeResult with analysis and todos

        Raises:
            ProjectNotFoundError: If project path doesn't exist
            ClaudeNotFoundError: If Claude CLI not found
            ClaudeTimeoutError: If execution times out
            OutputParseError: If JSON parsing fails
            ValidationError: If todos are invalid
        """
        # Validate
        self.validate_projects()

        if not self._claude_path:
            raise ClaudeNotFoundError(
                "Claude CLI not found. Please install claude-code."
            )

        # Build prompt
        prompt = self._build_prompt(task_title, task_description)

        # Execute Claude CLI
        raw_output = self._execute_claude(prompt)

        # Parse result
        result = self._parse_result(raw_output)
        result.raw_output = raw_output

        # Validate todos
        self._validate_todos(result.todos)

        # Cleanup any idle sessions created by claude -p
        self._cleanup_idle_sessions()

        return result

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
        """Execute Claude CLI with structured output"""
        cmd = [
            self._claude_path,
            "-p", prompt,
            "--allowedTools", "Read,Grep,Glob",
            "--max-turns", str(self.max_turns),
        ]

        # Prepare environment with API profile
        env = os.environ.copy()
        if self._api_base_url:
            env['ANTHROPIC_BASE_URL'] = self._api_base_url
        if self._api_key:
            env['ANTHROPIC_AUTH_TOKEN'] = self._api_key
        if self._model:
            env['ANTHROPIC_MODEL'] = self._model
        # Disable non-essential traffic for third-party APIs
        if self._api_base_url:
            env['CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC'] = '1'

        try:
            result = subprocess.run(
                cmd,
                cwd=self.project_paths[0],
                capture_output=True,
                text=True,
                timeout=self.timeout,
                env=env
            )

            if result.returncode != 0:
                error_msg = result.stderr or f"Exit code: {result.returncode}"
                raise DecomposeError(f"Claude CLI failed: {error_msg}")

            return result.stdout

        except subprocess.TimeoutExpired:
            raise ClaudeTimeoutError(f"Claude CLI timed out after {self.timeout}s")
        except FileNotFoundError:
            raise ClaudeNotFoundError("Claude CLI executable not found")

    def _parse_result(self, output: str) -> DecomposeResult:
        """Extract JSON from Claude output with multiple fallback strategies"""
        data = None

        # Strategy 1: JSON in markdown code block (preferred)
        json_block_match = re.search(r'```json\s*([\s\S]*?)\s*```', output)
        if json_block_match:
            try:
                data = json.loads(json_block_match.group(1))
            except json.JSONDecodeError:
                pass

        # Strategy 2: Generic code block
        if data is None:
            code_block_match = re.search(r'```\s*([\s\S]*?)\s*```', output)
            if code_block_match:
                try:
                    data = json.loads(code_block_match.group(1))
                except json.JSONDecodeError:
                    pass

        # Strategy 3: Find outermost { } pair (bare JSON)
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
                except json.JSONDecodeError:
                    pass

        if data is None:
            raise OutputParseError(
                "Could not extract JSON from Claude output. "
                f"Output preview: {output[:500]}..."
            )

        # Build result
        todos = data.get('todos', [])
        analysis = data.get('analysis', {})
        total_minutes = data.get('total_estimated_minutes', 0)

        # Calculate total if not provided
        if not total_minutes and todos:
            total_minutes = sum(t.get('estimated_minutes', 60) for t in todos)

        return DecomposeResult(
            analysis=analysis,
            todos=todos,
            total_estimated_minutes=total_minutes
        )

    def _validate_todos(self, todos: List[Dict]) -> None:
        """Validate that todos have required fields"""
        if not todos:
            raise ValidationError("No todos generated")

        for i, todo in enumerate(todos):
            if not todo.get('title'):
                raise ValidationError(f"Todo {i} missing title")

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
