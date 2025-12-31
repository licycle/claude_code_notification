#!/usr/bin/env python3
"""
Workflow Engine
Executes YAML-defined workflows with step dependencies and hook support
"""
import json
from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum
from pathlib import Path
from typing import Dict, Any, List, Optional, Callable

import yaml

from .claude_agent import ClaudeAgent, AgentConfig
from .hooks import HookManager, HookExecutionError

# Support both relative imports (when used as package) and absolute imports (when installed)
try:
    from ..services.todo_service import (
        create_workflow_run,
        update_workflow_run,
        add_workflow_step_log,
        create_todo,
        create_global_task,
    )
except ImportError:
    try:
        # Try task_tracker.services (when task_tracker is in sys.path parent)
        from task_tracker.services.todo_service import (
            create_workflow_run,
            update_workflow_run,
            add_workflow_step_log,
            create_todo,
            create_global_task,
        )
    except ImportError:
        # Fallback for direct services import
        from services.todo_service import (
            create_workflow_run,
            update_workflow_run,
            add_workflow_step_log,
            create_todo,
            create_global_task,
        )


class StepStatus(Enum):
    """Step execution status"""
    PENDING = "pending"
    RUNNING = "running"
    COMPLETED = "completed"
    FAILED = "failed"
    SKIPPED = "skipped"


@dataclass
class StepResult:
    """Step execution result"""
    step_id: str
    status: StepStatus
    output: Any = None
    error: Optional[str] = None
    started_at: Optional[datetime] = None
    completed_at: Optional[datetime] = None


@dataclass
class WorkflowRunState:
    """Workflow run state"""
    workflow_name: str
    task_id: Optional[int]
    run_id: Optional[int] = None
    status: str = "pending"
    current_step: Optional[str] = None
    context: Dict = field(default_factory=dict)
    results: Dict[str, StepResult] = field(default_factory=dict)
    started_at: Optional[datetime] = None
    completed_at: Optional[datetime] = None


class WorkflowEngine:
    """
    Workflow Execution Engine

    Features:
    - YAML workflow definitions
    - Step dependency management (topological sort)
    - Pluggable hook system
    - Claude Agent integration
    - Subprocess isolation for hooks
    """

    # Default workflows directory
    DEFAULT_WORKFLOWS_DIR = Path(__file__).parent.parent / 'workflows'
    USER_WORKFLOWS_DIR = Path.home() / '.claude-task-tracker' / 'workflows'

    def __init__(self, workflow_path: str = None, workflow_name: str = None):
        """
        Initialize workflow engine

        Args:
            workflow_path: Full path to workflow YAML file
            workflow_name: Name of workflow to load from default/user directories
        """
        if workflow_path:
            self.workflow = self._load_workflow(workflow_path)
        elif workflow_name:
            self.workflow = self._load_workflow_by_name(workflow_name)
        else:
            self.workflow = None

        self.hooks = HookManager()
        self.run: Optional[WorkflowRunState] = None

    def _load_workflow_by_name(self, name: str) -> Dict:
        """Load workflow by name from default or user directories"""
        # Try user workflows first
        user_path = self.USER_WORKFLOWS_DIR / f"{name}.yaml"
        if user_path.exists():
            return self._load_workflow(str(user_path))

        # Try default workflows
        default_path = self.DEFAULT_WORKFLOWS_DIR / f"{name}.yaml"
        if default_path.exists():
            return self._load_workflow(str(default_path))

        raise FileNotFoundError(f"Workflow '{name}' not found")

    def _load_workflow(self, path: str) -> Dict:
        """Load workflow definition from YAML file"""
        with open(path, 'r') as f:
            workflow = yaml.safe_load(f)

        # Handle inheritance
        if 'extends' in workflow:
            base_name = workflow['extends']
            base = self._load_workflow_by_name(base_name)
            workflow = self._merge_workflows(base, workflow)

        return workflow

    def _merge_workflows(self, base: Dict, child: Dict) -> Dict:
        """Merge workflows (inheritance)"""
        result = base.copy()

        # Merge steps
        if 'steps' in child:
            base_steps = {s['id']: s for s in base.get('steps', [])}

            for step in child['steps']:
                step_id = step['id']
                if step.get('override'):
                    base_steps[step_id] = step
                elif step.get('insert_after'):
                    # Insert after specified step
                    after_id = step['insert_after']
                    new_steps = []
                    for s in base.get('steps', []):
                        new_steps.append(s)
                        if s['id'] == after_id:
                            new_steps.append(step)
                    result['steps'] = new_steps
                    continue
                else:
                    base_steps[step_id] = step

            if 'steps' not in result or not any(s.get('insert_after') for s in child['steps']):
                result['steps'] = list(base_steps.values())

        # Merge hooks
        if 'hooks' in child:
            result['hooks'] = {**base.get('hooks', {}), **child['hooks']}

        # Override other fields
        for key in ['name', 'version', 'description', 'inputs', 'error_handling']:
            if key in child:
                result[key] = child[key]

        return result

    def execute(self, inputs: Dict[str, Any]) -> WorkflowRunState:
        """
        Execute complete workflow

        Args:
            inputs: Input parameters for the workflow

        Returns:
            Workflow run state with results
        """
        if not self.workflow:
            raise ValueError("No workflow loaded")

        # Initialize run state
        self.run = WorkflowRunState(
            workflow_name=self.workflow.get('name', 'unnamed'),
            task_id=inputs.get('task_id'),
            context={'inputs': inputs, 'steps': {}},
            started_at=datetime.now()
        )
        self.run.status = "running"

        # Create database record
        self.run.run_id = create_workflow_run(
            workflow_name=self.run.workflow_name,
            task_id=self.run.task_id,
            context=self.run.context
        )
        update_workflow_run(self.run.run_id, status='running')

        try:
            # Execute steps in topological order
            for step in self._topological_sort():
                # Check condition
                if not self._evaluate_condition(step):
                    result = StepResult(
                        step_id=step['id'],
                        status=StepStatus.SKIPPED
                    )
                    self.run.results[step['id']] = result
                    add_workflow_step_log(
                        self.run.run_id, step['id'], 'skipped'
                    )
                    continue

                # Execute step
                self.run.current_step = step['id']
                update_workflow_run(
                    self.run.run_id,
                    current_step=step['id']
                )

                result = self._execute_step(step)
                self.run.results[step['id']] = result

                # Update context
                self.run.context['steps'][step['id']] = {
                    'output': result.output,
                    'status': result.status.value
                }

                # Log to database
                add_workflow_step_log(
                    self.run.run_id,
                    step['id'],
                    result.status.value,
                    output=result.output,
                    error=result.error
                )

                # Handle failure
                if result.status == StepStatus.FAILED:
                    if not self._handle_error(step, result):
                        self.run.status = "failed"
                        break
            else:
                self.run.status = "completed"

        except Exception as e:
            self.run.status = "failed"
            self.run.results['_engine'] = StepResult(
                step_id='_engine',
                status=StepStatus.FAILED,
                error=str(e)
            )

        self.run.completed_at = datetime.now()

        # Update database
        update_workflow_run(
            self.run.run_id,
            status=self.run.status,
            context=self.run.context
        )

        return self.run

    def _execute_step(self, step: Dict) -> StepResult:
        """Execute single step"""
        result = StepResult(
            step_id=step['id'],
            status=StepStatus.RUNNING,
            started_at=datetime.now()
        )

        try:
            # Execute before hooks
            self._execute_hooks(step.get('hooks', {}).get('before', []))

            # Execute based on type
            step_type = step.get('type', 'action')

            if step_type == 'claude_agent':
                output = self._execute_claude_agent_step(step)
            elif step_type == 'interactive':
                output = self._execute_interactive_step(step)
            elif step_type == 'action':
                output = self._execute_action_step(step)
            elif step_type == 'python':
                output = self._execute_python_step(step)
            elif step_type == 'shell':
                output = self._execute_shell_step(step)
            else:
                raise ValueError(f"Unknown step type: {step_type}")

            result.output = output
            result.status = StepStatus.COMPLETED

            # Execute after hooks
            self._execute_hooks(
                step.get('hooks', {}).get('after', []),
                step_output=output
            )

        except Exception as e:
            result.status = StepStatus.FAILED
            result.error = str(e)

        result.completed_at = datetime.now()
        return result

    def _execute_claude_agent_step(self, step: Dict) -> Any:
        """Execute Claude Agent step"""
        config_dict = step.get('config', {})

        # 从 inputs 读取 api_profile (用户通过 CLI 指定)
        api_profile = self.run.context.get('inputs', {}).get('api_profile')
        if api_profile and 'api_profile' not in config_dict:
            config_dict['api_profile'] = api_profile

        config = AgentConfig(**config_dict)

        project_paths = self.run.context['inputs'].get('project_paths', ['.'])
        project_path = project_paths[0] if project_paths else '.'

        agent = ClaudeAgent(project_path, config)

        prompt = self._render_template(step.get('prompt', ''))
        result = agent.execute(prompt, self.run.context)

        if not result.get('success'):
            raise Exception(result.get('error', 'Agent execution failed'))

        return result.get('data')

    def _execute_interactive_step(self, step: Dict) -> Any:
        """Execute interactive step (requires user input)"""
        # In non-interactive mode, return the context data
        # In real implementation, this would display UI and wait for input
        config = step.get('config', {})

        if config.get('display_mode') == 'preview':
            # Return preview data for confirmation
            return {
                'preview': self.run.context.get('steps', {}).get(
                    step.get('depends_on', [None])[-1] if step.get('depends_on') else None,
                    {}
                ).get('output'),
                'confirmed': True,  # Auto-confirm in non-interactive mode
                'edits': None
            }

        return {'confirmed': True}

    def _execute_action_step(self, step: Dict) -> Any:
        """Execute predefined action"""
        action = step.get('action')

        if action == 'save_todos_to_database':
            return self._action_save_todos()
        elif action == 'use_cached_analysis':
            return self._action_use_cached_analysis()
        else:
            raise ValueError(f"Unknown action: {action}")

    def _execute_python_step(self, step: Dict) -> Any:
        """Execute Python code step"""
        hook_def = {'type': 'python', 'script': step.get('script', '')}
        result = self.hooks.execute(hook_def, self.run.context)
        return result.get('output')

    def _execute_shell_step(self, step: Dict) -> Any:
        """Execute shell command step"""
        hook_def = {'type': 'shell', 'command': step.get('command', '')}
        result = self.hooks.execute(hook_def, self.run.context)
        return result.get('output')

    def _execute_hooks(self, hook_names: List[str], step_output: Any = None):
        """Execute list of hooks"""
        for hook_name in hook_names:
            hook_def = self.workflow.get('hooks', {}).get(hook_name)
            if not hook_def:
                continue
            self.hooks.execute(hook_def, self.run.context, step_output)

    def _render_template(self, template: str) -> str:
        """Render template with context using Jinja2 or fallback"""
        # Try to use Jinja2 if available
        try:
            from jinja2 import Template, Environment, BaseLoader

            # Create environment with custom filters
            env = Environment(loader=BaseLoader())
            env.filters['tojson'] = lambda x: json.dumps(x, ensure_ascii=False)

            tmpl = env.from_string(template)
            return tmpl.render(**self.run.context)
        except ImportError:
            # Fallback to simple string replacement
            result = template

            def replace_vars(text: str, data: Dict, prefix: str = "") -> str:
                for key, value in data.items():
                    var_name = f"{prefix}{key}" if prefix else key
                    if isinstance(value, dict):
                        text = replace_vars(text, value, f"{var_name}.")
                    else:
                        if isinstance(value, (list, dict)):
                            value = json.dumps(value, ensure_ascii=False)
                        text = text.replace(f"{{{{ {var_name} }}}}", str(value))
                        text = text.replace(f"{{{{{var_name}}}}}", str(value))
                return text

            result = replace_vars(result, self.run.context)
            return result

    def _topological_sort(self) -> List[Dict]:
        """Sort steps by dependency (topological sort)"""
        steps = {s['id']: s for s in self.workflow.get('steps', [])}
        in_degree = {s['id']: 0 for s in self.workflow.get('steps', [])}
        graph = {s['id']: [] for s in self.workflow.get('steps', [])}

        for step in self.workflow.get('steps', []):
            for dep in step.get('depends_on', []):
                if dep in graph:
                    graph[dep].append(step['id'])
                    in_degree[step['id']] += 1

        queue = [s for s, d in in_degree.items() if d == 0]
        result = []

        while queue:
            step_id = queue.pop(0)
            result.append(steps[step_id])
            for next_id in graph[step_id]:
                in_degree[next_id] -= 1
                if in_degree[next_id] == 0:
                    queue.append(next_id)

        return result

    def _evaluate_condition(self, step: Dict) -> bool:
        """Evaluate step condition"""
        condition = step.get('condition')
        if not condition:
            return True

        # Simple evaluation: check for {{ variable }} patterns
        rendered = self._render_template(condition)
        return rendered.lower() in ('true', '1', 'yes')

    def _handle_error(self, step: Dict, result: StepResult) -> bool:
        """Handle step error, return True if can continue"""
        error_handling = self.workflow.get('error_handling', {})
        fallback = error_handling.get('fallback', {}).get(step['id'])

        if fallback:
            # Execute fallback action
            fallback_step = {'id': f"{step['id']}_fallback", 'action': fallback.get('action')}
            fallback_result = self._execute_action_step(fallback_step)
            self.run.context['steps'][step['id']] = {
                'output': fallback_result,
                'status': 'completed',
                'fallback': True
            }
            return True

        # Check retry configuration
        retry = error_handling.get('retry', {})
        max_attempts = retry.get('max_attempts', 0)
        if max_attempts > 0:
            # Retry logic would go here
            pass

        return False

    # ============================================================================
    # Built-in Actions
    # ============================================================================

    def _action_save_todos(self) -> Dict:
        """Save generated todos to database"""
        # Get generated todos from previous step
        steps_context = self.run.context.get('steps', {})

        # Find the step that generated todos
        todos_data = None
        for step_id, step_data in steps_context.items():
            output = step_data.get('output', {})
            if isinstance(output, dict) and 'todos' in output:
                todos_data = output
                break

        if not todos_data:
            return {'saved': 0, 'error': 'No todos found to save'}

        saved_todos = []
        task_id = self.run.task_id

        for todo_def in todos_data.get('todos', []):
            todo = create_todo(
                project_path=todo_def.get('project_path', self.run.context['inputs'].get('project_paths', ['.'])[0]),
                title=todo_def.get('title', 'Untitled'),
                description=todo_def.get('description'),
                global_task_id=task_id,
                priority=todo_def.get('priority', 0),
                estimated_minutes=todo_def.get('estimated_minutes'),
                actor='system'
            )
            saved_todos.append(todo.id)

        return {
            'saved': len(saved_todos),
            'todo_ids': saved_todos
        }

    def _action_use_cached_analysis(self) -> Dict:
        """Use cached project analysis"""
        import hashlib

        inputs = self.run.context.get('inputs', {})
        project_paths = inputs.get('project_paths', [])

        paths_str = str(sorted(project_paths))
        cache_key = hashlib.md5(paths_str.encode()).hexdigest()

        cache_dir = Path.home() / '.claude-task-tracker' / 'cache'
        cache_file = cache_dir / f'analysis_{cache_key}.json'

        if cache_file.exists():
            with open(cache_file) as f:
                return json.load(f)

        return {'cached': False, 'error': 'No cached analysis found'}


# ============================================================================
# Utility Functions
# ============================================================================

def list_available_workflows() -> List[Dict]:
    """List all available workflows"""
    workflows = []

    # Default workflows
    default_dir = WorkflowEngine.DEFAULT_WORKFLOWS_DIR
    if default_dir.exists():
        for f in default_dir.glob('*.yaml'):
            with open(f) as file:
                wf = yaml.safe_load(file)
                workflows.append({
                    'name': wf.get('name', f.stem),
                    'description': wf.get('description', ''),
                    'path': str(f),
                    'source': 'default'
                })

    # User workflows
    user_dir = WorkflowEngine.USER_WORKFLOWS_DIR
    if user_dir.exists():
        for f in user_dir.glob('*.yaml'):
            with open(f) as file:
                wf = yaml.safe_load(file)
                workflows.append({
                    'name': wf.get('name', f.stem),
                    'description': wf.get('description', ''),
                    'path': str(f),
                    'source': 'user'
                })

    return workflows
