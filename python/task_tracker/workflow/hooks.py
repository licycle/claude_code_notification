#!/usr/bin/env python3
"""
Hook Manager
Provides isolated execution of user-defined hooks (Python, Shell, Claude Agent)
"""
import subprocess
import json
import os
from typing import Dict, Any, Optional

from .claude_agent import ClaudeAgent


class HookExecutionError(Exception):
    """Hook execution error"""
    pass


class HookManager:
    """
    Hook Manager

    Supports three hook types, all executed in subprocess isolation:
    - python: Python scripts
    - shell: Shell commands
    - claude_agent: Claude Agent tasks
    """

    def __init__(self, timeout: int = 30):
        self.timeout = timeout

    def execute(
        self,
        hook_def: Dict,
        context: Dict,
        step_output: Any = None
    ) -> Dict[str, Any]:
        """
        Execute hook (subprocess isolated)

        Args:
            hook_def: Hook definition from workflow
            context: Workflow context
            step_output: Output from previous step (optional)

        Returns:
            Hook execution result
        """
        hook_type = hook_def.get('type', 'python')

        # Prepare environment variables
        env = os.environ.copy()
        env['HOOK_CONTEXT'] = json.dumps(context, ensure_ascii=False, default=str)
        if step_output is not None:
            env['STEP_OUTPUT'] = json.dumps(step_output, ensure_ascii=False, default=str)

        # Add custom environment variables
        for key, value in hook_def.get('env', {}).items():
            env[key] = self._render_value(value, context, step_output)

        if hook_type == 'python':
            return self._execute_python(hook_def, env)
        elif hook_type == 'shell':
            return self._execute_shell(hook_def, env)
        elif hook_type == 'claude_agent':
            return self._execute_claude_agent(hook_def, context, step_output)
        else:
            raise ValueError(f"Unknown hook type: {hook_type}")

    def _execute_python(self, hook_def: Dict, env: Dict) -> Dict[str, Any]:
        """Execute Python script in subprocess"""
        script = hook_def.get('script', '')
        if not script:
            return {"success": True, "output": None}

        try:
            result = subprocess.run(
                ['python3', '-c', script],
                env=env,
                capture_output=True,
                text=True,
                timeout=self.timeout
            )

            if result.returncode != 0:
                raise HookExecutionError(f"Python hook failed: {result.stderr}")

            try:
                return {"success": True, "output": json.loads(result.stdout)}
            except json.JSONDecodeError:
                return {"success": True, "output": result.stdout}

        except subprocess.TimeoutExpired:
            raise HookExecutionError(f"Python hook timed out ({self.timeout}s)")

    def _execute_shell(self, hook_def: Dict, env: Dict) -> Dict[str, Any]:
        """Execute Shell command in subprocess"""
        command = hook_def.get('command', '')
        if not command:
            return {"success": True, "output": None}

        try:
            result = subprocess.run(
                command,
                shell=True,
                env=env,
                capture_output=True,
                text=True,
                timeout=self.timeout
            )

            if result.returncode != 0:
                raise HookExecutionError(f"Shell hook failed: {result.stderr}")

            return {
                "success": True,
                "output": {
                    "stdout": result.stdout,
                    "stderr": result.stderr,
                    "returncode": result.returncode
                }
            }

        except subprocess.TimeoutExpired:
            raise HookExecutionError(f"Shell hook timed out ({self.timeout}s)")

    def _execute_claude_agent(
        self,
        hook_def: Dict,
        context: Dict,
        step_output: Any
    ) -> Dict[str, Any]:
        """Execute Claude Agent hook"""
        project_path = context.get('inputs', {}).get('project_paths', ['.'])[0]
        agent = ClaudeAgent(project_path)

        if not agent.is_available():
            return {
                "success": False,
                "error": "Claude CLI not available"
            }

        prompt = hook_def.get('prompt', '')
        prompt = self._render_template(prompt, context, step_output)

        result = agent.execute(prompt)
        return {
            "success": result.get('success', False),
            "output": result.get('data', {})
        }

    def _render_value(self, value: str, context: Dict, step_output: Any) -> str:
        """Render template value"""
        return self._render_template(str(value), context, step_output)

    def _render_template(self, template: str, context: Dict, step_output: Any) -> str:
        """Simple template rendering (replaces {{ variable }} patterns)"""
        result = template

        # Replace context variables
        def replace_var(match_str: str, data: Dict, prefix: str = "") -> str:
            for key, value in data.items():
                var_name = f"{prefix}{key}" if prefix else key
                if isinstance(value, dict):
                    match_str = replace_var(match_str, value, f"{var_name}.")
                else:
                    if isinstance(value, (list, dict)):
                        value = json.dumps(value, ensure_ascii=False)
                    match_str = match_str.replace(f"{{{{ {var_name} }}}}", str(value))
                    match_str = match_str.replace(f"{{{{{var_name}}}}}", str(value))
            return match_str

        result = replace_var(result, context)

        # Replace step_output
        if step_output is not None:
            if isinstance(step_output, dict):
                result = replace_var(result, {'step_output': step_output})
            else:
                result = result.replace("{{ step_output }}", str(step_output))
                result = result.replace("{{step_output}}", str(step_output))

        return result
