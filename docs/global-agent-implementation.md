# 全局 Agent 工作流系统 - 实现方案

> 版本: 1.0
> 日期: 2025-12-30
> 状态: 待实现
>
> **注意**: 本文档包含具体代码实现细节，实现完成后可删除。
> 架构设计请参考 [global-agent-architecture.md](./global-agent-architecture.md)

## 目录

1. [数据库表结构](#1-数据库表结构)
2. [Python 数据模型](#2-python-数据模型)
3. [Swift 数据模型](#3-swift-数据模型)
4. [MCP Server 实现](#4-mcp-server-实现)
5. [CLI 实现](#5-cli-实现)
6. [Workflow Engine 实现](#6-workflow-engine-实现)
7. [Claude Agent 封装](#7-claude-agent-封装)
8. [Hook 管理器实现](#8-hook-管理器实现)
9. [工作流定义示例](#9-工作流定义示例)
10. [AI 提示词模板](#10-ai-提示词模板)

---

## 1. 数据库表结构

### 1.1 global_tasks (全局任务表)

```sql
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
```

### 1.2 todos (Todo 表)

```sql
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
```

### 1.3 todo_dependencies (Todo 依赖表)

```sql
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
```

### 1.4 session_todo_links (Session-Todo 关联表)

```sql
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
```

### 1.5 todo_executions (Todo 执行记录表)

```sql
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
```

### 1.6 workflow_runs (工作流运行记录)

```sql
CREATE TABLE IF NOT EXISTS workflow_runs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    workflow_name TEXT NOT NULL,
    task_id INTEGER,
    status TEXT NOT NULL DEFAULT 'pending',
    -- pending, running, completed, failed, cancelled
    current_step TEXT,
    context_json TEXT,
    started_at TEXT,
    completed_at TEXT,
    created_at TEXT DEFAULT (datetime('now')),

    FOREIGN KEY (task_id) REFERENCES global_tasks(id)
);

CREATE INDEX IF NOT EXISTS idx_workflow_runs_task ON workflow_runs(task_id);
CREATE INDEX IF NOT EXISTS idx_workflow_runs_status ON workflow_runs(status);
```

### 1.7 workflow_step_logs (工作流步骤日志)

```sql
CREATE TABLE IF NOT EXISTS workflow_step_logs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    run_id INTEGER NOT NULL,
    step_id TEXT NOT NULL,
    status TEXT NOT NULL,
    -- pending, running, completed, failed, skipped
    output_json TEXT,
    error TEXT,
    started_at TEXT,
    completed_at TEXT,

    FOREIGN KEY (run_id) REFERENCES workflow_runs(id)
);

CREATE INDEX IF NOT EXISTS idx_workflow_step_logs_run ON workflow_step_logs(run_id);
```

---

## 2. Python 数据模型

```python
# python/task_tracker/services/todo_service.py

from dataclasses import dataclass
from typing import Optional, List
from datetime import datetime

@dataclass
class GlobalTask:
    id: int
    title: str
    description: Optional[str]
    status: str  # active, completed, archived
    priority: int  # 0, 1, 2
    created_at: datetime
    updated_at: datetime
    completed_at: Optional[datetime]
    metadata: Optional[dict]
    # 聚合字段
    todo_count: int = 0
    completed_todo_count: int = 0

@dataclass
class Todo:
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
    metadata: Optional[dict]
    # 关联数据
    children: Optional[List['Todo']] = None
    linked_sessions: Optional[List[int]] = None

@dataclass
class TodoExecution:
    id: int
    todo_id: int
    session_pk: Optional[int]
    action: str  # created, started, completed, split, etc.
    actor: str  # user, claude_code, system, ai
    details: Optional[dict]
    created_at: datetime
```

---

## 3. Swift 数据模型

```swift
// swift/Services/DatabaseModels.swift

struct GlobalTask {
    let id: Int
    let title: String
    let description: String?
    let status: String
    let priority: Int
    let createdAt: Date
    let updatedAt: Date
    let completedAt: Date?
    let metadata: [String: Any]?
    // 聚合字段
    let todoCount: Int
    let completedTodoCount: Int

    var completionPercentage: Double {
        guard todoCount > 0 else { return 0 }
        return Double(completedTodoCount) / Double(todoCount) * 100
    }
}

struct TodoItem {
    let id: Int
    let globalTaskId: Int?
    let parentTodoId: Int?
    let projectPath: String
    let title: String
    let description: String?
    let status: String
    let priority: Int
    let estimatedMinutes: Int?
    let actualMinutes: Int?
    let createdAt: Date
    let updatedAt: Date
    let completedAt: Date?
    let completionSummary: String?
    // 关联数据
    let children: [TodoItem]?
    let linkedSessions: [SessionInfo]?

    var isCompleted: Bool { status == "completed" }
    var isBlocked: Bool { status == "blocked" }
    var isInProgress: Bool { status == "in_progress" }
}

struct TodoExecution {
    let id: Int
    let todoId: Int
    let sessionPk: Int?
    let action: String
    let actor: String
    let details: [String: Any]?
    let createdAt: Date
}

struct WorkflowRun {
    let id: Int
    let workflowName: String
    let taskId: Int?
    let status: String
    let currentStep: String?
    let startedAt: Date?
    let completedAt: Date?
}

struct WorkflowStepLog {
    let id: Int
    let runId: Int
    let stepId: String
    let status: String
    let error: String?
    let startedAt: Date?
    let completedAt: Date?
}
```

---

## 4. MCP Server 实现

```python
# python/task_tracker/mcp/server.py

from fastmcp import FastMCP
from .tools import (
    list_todos, get_todo, start_todo, complete_todo,
    split_todo, create_todo, update_todo
)

mcp = FastMCP("Claude Todo Server")

# 注册工具
mcp.tool(list_todos)
mcp.tool(get_todo)
mcp.tool(start_todo)
mcp.tool(complete_todo)
mcp.tool(split_todo)
mcp.tool(create_todo)
mcp.tool(update_todo)

# 可选：注册资源（用于提供项目 Todos 作为上下文）
@mcp.resource("todo://project/{project_path}")
def get_project_todos_resource(project_path: str):
    """提供项目 Todos 作为 MCP 资源"""
    todos = get_todos_for_project(project_path)
    return format_todos_as_resource(todos)

if __name__ == "__main__":
    mcp.run(transport="http", host="127.0.0.1", port=8765)
```

### MCP 工具实现示例

```python
# python/task_tracker/mcp/tools.py

from typing import List, Optional
from ..services.todo_service import TodoService

todo_service = TodoService()

def list_todos(
    project_path: Optional[str] = None,
    status: str = "all",
    include_children: bool = True,
    limit: int = 20
) -> dict:
    """
    列出项目相关的 Todos
    """
    todos = todo_service.list_todos(
        project_path=project_path,
        status=status if status != "all" else None,
        include_children=include_children,
        limit=limit
    )
    return {
        "todos": [todo.to_dict() for todo in todos],
        "count": len(todos)
    }

def start_todo(todo_id: int, session_id: Optional[str] = None) -> dict:
    """
    将 Todo 标记为进行中
    """
    todo = todo_service.start_todo(todo_id, session_id)
    return {
        "success": True,
        "todo": todo.to_dict()
    }

def complete_todo(
    todo_id: int,
    summary: Optional[str] = None,
    actual_minutes: Optional[int] = None
) -> dict:
    """
    完成 Todo
    """
    todo = todo_service.complete_todo(
        todo_id,
        summary=summary,
        actual_minutes=actual_minutes
    )
    return {
        "success": True,
        "todo": todo.to_dict()
    }

def split_todo(todo_id: int, sub_todos: List[dict]) -> dict:
    """
    拆分 Todo 为子任务
    """
    created = todo_service.split_todo(todo_id, sub_todos)
    return {
        "success": True,
        "parent_todo_id": todo_id,
        "sub_todos": [t.to_dict() for t in created]
    }
```

---

## 5. CLI 实现

```python
# python/task_tracker/cli/todo_cli.py

import argparse
from ..services.todo_service import TodoService

def main():
    parser = argparse.ArgumentParser(prog='claude-todo')
    subparsers = parser.add_subparsers(dest='command')

    # task 命令组
    task_parser = subparsers.add_parser('task')
    task_sub = task_parser.add_subparsers(dest='subcommand')

    # task create
    create_parser = task_sub.add_parser('create')
    create_parser.add_argument('title')
    create_parser.add_argument('--desc', default='')
    create_parser.add_argument('--priority', type=int, default=0)

    # task list
    list_parser = task_sub.add_parser('list')
    list_parser.add_argument('--status', default='active')
    list_parser.add_argument('--format', default='table')

    # task decompose
    decompose_parser = task_sub.add_parser('decompose')
    decompose_parser.add_argument('task_id', type=int)
    decompose_parser.add_argument('--projects', nargs='+')
    decompose_parser.add_argument('--workflow', default='task-decomposition')

    # todo 命令组
    todo_parser = subparsers.add_parser('todo')
    todo_sub = todo_parser.add_subparsers(dest='subcommand')

    # todo add
    add_parser = todo_sub.add_parser('add')
    add_parser.add_argument('title')
    add_parser.add_argument('--project', required=True)
    add_parser.add_argument('--task', type=int)
    add_parser.add_argument('--priority', type=int, default=0)

    # todo list
    todo_list_parser = todo_sub.add_parser('list')
    todo_list_parser.add_argument('--project')
    todo_list_parser.add_argument('--status', default='all')

    # workflow 命令组
    workflow_parser = subparsers.add_parser('workflow')
    workflow_sub = workflow_parser.add_subparsers(dest='subcommand')

    # workflow list
    workflow_sub.add_parser('list')

    # workflow run
    run_parser = workflow_sub.add_parser('run')
    run_parser.add_argument('name')
    run_parser.add_argument('--input', action='append', dest='inputs')

    # workflow status
    status_parser = workflow_sub.add_parser('status')
    status_parser.add_argument('run_id', type=int)

    # server 命令组
    server_parser = subparsers.add_parser('server')
    server_sub = server_parser.add_subparsers(dest='subcommand')

    # server start
    start_server = server_sub.add_parser('start')
    start_server.add_argument('--port', type=int, default=8765)
    start_server.add_argument('--daemon', action='store_true')

    # server stop
    server_sub.add_parser('stop')

    # server status
    server_sub.add_parser('status')

    args = parser.parse_args()
    handle_command(args)

if __name__ == '__main__':
    main()
```

---

## 6. Workflow Engine 实现

```python
# python/task_tracker/workflow/engine.py

from typing import Dict, Any, List, Optional
from dataclasses import dataclass, field
from pathlib import Path
from enum import Enum
import yaml
import json
from datetime import datetime

from .claude_agent import ClaudeAgent, AgentConfig
from .hooks import HookManager

class StepStatus(Enum):
    PENDING = "pending"
    RUNNING = "running"
    COMPLETED = "completed"
    FAILED = "failed"
    SKIPPED = "skipped"

@dataclass
class StepResult:
    step_id: str
    status: StepStatus
    output: Any = None
    error: Optional[str] = None
    started_at: Optional[datetime] = None
    completed_at: Optional[datetime] = None

@dataclass
class WorkflowRun:
    workflow_name: str
    task_id: int
    status: str = "pending"
    current_step: Optional[str] = None
    context: Dict = field(default_factory=dict)
    results: Dict[str, StepResult] = field(default_factory=dict)
    started_at: Optional[datetime] = None
    completed_at: Optional[datetime] = None

class WorkflowEngine:
    """
    工作流执行引擎

    支持：
    - YAML 工作流定义
    - 步骤依赖管理（拓扑排序）
    - 可插拔 Hook 系统
    - Claude Agent 集成
    - 子进程隔离执行
    """

    def __init__(self, workflow_path: str):
        self.workflow = self._load_workflow(workflow_path)
        self.hooks = HookManager()
        self.run: Optional[WorkflowRun] = None

    def _load_workflow(self, path: str) -> Dict:
        """加载工作流定义"""
        with open(path, 'r') as f:
            workflow = yaml.safe_load(f)

        # 处理继承
        if 'extends' in workflow:
            base_path = Path(path).parent / f"{workflow['extends']}.yaml"
            base = self._load_workflow(str(base_path))
            workflow = self._merge_workflows(base, workflow)

        return workflow

    def _merge_workflows(self, base: Dict, child: Dict) -> Dict:
        """合并工作流（继承）"""
        result = base.copy()

        # 合并 steps
        if 'steps' in child:
            base_steps = {s['id']: s for s in base.get('steps', [])}
            for step in child['steps']:
                if step.get('override'):
                    base_steps[step['id']] = step
                elif step.get('insert_after'):
                    # 处理插入
                    pass
                else:
                    base_steps[step['id']] = step
            result['steps'] = list(base_steps.values())

        # 合并 hooks
        if 'hooks' in child:
            result['hooks'] = {**base.get('hooks', {}), **child['hooks']}

        return result

    def execute(self, inputs: Dict[str, Any]) -> WorkflowRun:
        """执行完整工作流"""
        self.run = WorkflowRun(
            workflow_name=self.workflow['name'],
            task_id=inputs.get('task_id', 0),
            context={'inputs': inputs, 'steps': {}},
            started_at=datetime.now()
        )
        self.run.status = "running"

        try:
            # 按拓扑顺序执行步骤
            for step in self._topological_sort():
                if not self._evaluate_condition(step):
                    self.run.results[step['id']] = StepResult(
                        step_id=step['id'],
                        status=StepStatus.SKIPPED
                    )
                    continue

                self.run.current_step = step['id']
                result = self._execute_step(step)
                self.run.results[step['id']] = result

                self.run.context['steps'][step['id']] = {
                    'output': result.output,
                    'status': result.status.value
                }

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
        self._save_run_to_db()
        return self.run

    def _execute_step(self, step: Dict) -> StepResult:
        """执行单个步骤"""
        result = StepResult(
            step_id=step['id'],
            status=StepStatus.RUNNING,
            started_at=datetime.now()
        )

        try:
            # 执行前置 Hooks
            self._execute_hooks(step.get('hooks', {}).get('before', []))

            # 根据类型执行
            if step['type'] == 'claude_agent':
                output = self._execute_claude_agent_step(step)
            elif step['type'] == 'interactive':
                output = self._execute_interactive_step(step)
            elif step['type'] == 'action':
                output = self._execute_action_step(step)
            elif step['type'] == 'python':
                output = self._execute_python_step(step)
            elif step['type'] == 'shell':
                output = self._execute_shell_step(step)
            else:
                raise ValueError(f"Unknown step type: {step['type']}")

            result.output = output
            result.status = StepStatus.COMPLETED

            # 执行后置 Hooks
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
        """执行 Claude Agent 步骤"""
        config = AgentConfig(**step.get('config', {}))
        project_path = self.run.context['inputs'].get('project_paths', ['.'])[0]

        agent = ClaudeAgent(project_path, config)
        prompt = self._render_template(step['prompt'])
        result = agent.execute(prompt, self.run.context)

        if not result.get('success'):
            raise Exception(result.get('error', 'Agent execution failed'))

        return result.get('data')

    def _execute_hooks(self, hook_names: List[str], step_output: Any = None):
        """执行 Hook 列表"""
        for hook_name in hook_names:
            hook_def = self.workflow.get('hooks', {}).get(hook_name)
            if not hook_def:
                continue
            self.hooks.execute(hook_def, self.run.context, step_output)

    def _render_template(self, template: str) -> str:
        """渲染 Jinja2 模板"""
        from jinja2 import Template
        return Template(template).render(**self.run.context)

    def _topological_sort(self) -> List[Dict]:
        """按依赖关系拓扑排序步骤"""
        steps = {s['id']: s for s in self.workflow['steps']}
        in_degree = {s['id']: 0 for s in self.workflow['steps']}
        graph = {s['id']: [] for s in self.workflow['steps']}

        for step in self.workflow['steps']:
            for dep in step.get('depends_on', []):
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
        """评估步骤条件"""
        condition = step.get('condition')
        if not condition:
            return True
        from jinja2 import Template
        result = Template(condition).render(**self.run.context)
        return result.lower() in ('true', '1', 'yes')

    def _handle_error(self, step: Dict, result: StepResult) -> bool:
        """处理错误，返回是否可以继续"""
        error_handling = self.workflow.get('error_handling', {})
        fallback = error_handling.get('fallback', {}).get(step['id'])

        if fallback:
            # 执行降级策略
            return True

        retry = error_handling.get('retry', {})
        if retry.get('max_attempts', 0) > 0:
            # 重试逻辑
            pass

        return False

    def _save_run_to_db(self):
        """保存运行记录到数据库"""
        import sqlite3
        from pathlib import Path

        db_path = Path.home() / '.claude-task-tracker' / 'tasks.db'
        conn = sqlite3.connect(str(db_path))

        conn.execute("""
            INSERT INTO workflow_runs
            (workflow_name, task_id, status, current_step, context_json, started_at, completed_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
        """, (
            self.run.workflow_name,
            self.run.task_id,
            self.run.status,
            self.run.current_step,
            json.dumps(self.run.context),
            self.run.started_at.isoformat() if self.run.started_at else None,
            self.run.completed_at.isoformat() if self.run.completed_at else None
        ))

        run_id = conn.execute("SELECT last_insert_rowid()").fetchone()[0]

        for step_id, result in self.run.results.items():
            conn.execute("""
                INSERT INTO workflow_step_logs
                (run_id, step_id, status, output_json, error, started_at, completed_at)
                VALUES (?, ?, ?, ?, ?, ?, ?)
            """, (
                run_id,
                step_id,
                result.status.value,
                json.dumps(result.output) if result.output else None,
                result.error,
                result.started_at.isoformat() if result.started_at else None,
                result.completed_at.isoformat() if result.completed_at else None
            ))

        conn.commit()
        conn.close()
```

---

## 7. Claude Agent 封装

```python
# python/task_tracker/workflow/claude_agent.py

import subprocess
import json
from dataclasses import dataclass
from typing import Optional, Dict, Any, List
from pathlib import Path

@dataclass
class AgentConfig:
    """Claude Agent 配置"""
    mode: str = "autonomous"      # autonomous | interactive
    timeout: int = 180            # 超时时间（秒）
    output_format: str = "json"   # json | text
    max_turns: int = 10           # 最大轮次
    skip_permissions: bool = False  # 跳过权限确认（仅用于容器环境）

class ClaudeAgent:
    """
    Claude Code CLI Agent 封装

    利用 Claude Code 的自主代码探索能力：
    - Glob: 文件模式匹配
    - Grep: 代码内容搜索
    - Read: 文件读取
    - Bash: 命令执行
    """

    def __init__(self, project_path: str, config: Optional[AgentConfig] = None):
        self.project_path = Path(project_path)
        self.config = config or AgentConfig()

    def execute(self, prompt: str, context: Optional[Dict] = None) -> Dict[str, Any]:
        """
        执行 Claude Agent 任务

        Args:
            prompt: 任务提示词（支持模板变量）
            context: 上下文变量，用于模板渲染

        Returns:
            Agent 执行结果（JSON 格式）
        """
        # 渲染模板变量
        if context:
            prompt = self._render_template(prompt, context)

        # 构建命令
        cmd = self._build_command(prompt)

        # 执行
        try:
            result = subprocess.run(
                cmd,
                cwd=str(self.project_path),
                capture_output=True,
                text=True,
                timeout=self.config.timeout
            )

            if result.returncode != 0:
                return {
                    "success": False,
                    "error": result.stderr,
                    "raw_output": result.stdout
                }

            return self._parse_output(result.stdout)

        except subprocess.TimeoutExpired:
            return {
                "success": False,
                "error": f"Agent 执行超时 ({self.config.timeout}s)"
            }

    def _build_command(self, prompt: str) -> List[str]:
        """构建 Claude CLI 命令"""
        cmd = ["claude", "-p", prompt]

        if self.config.output_format == "json":
            cmd.extend(["--output-format", "stream-json"])

        if self.config.skip_permissions:
            cmd.append("--dangerously-skip-permissions")

        return cmd

    def _render_template(self, template: str, context: Dict) -> str:
        """渲染 Jinja2 模板"""
        from jinja2 import Template
        return Template(template).render(**context)

    def _parse_output(self, output: str) -> Dict[str, Any]:
        """解析 Claude 输出，提取 JSON 结果"""
        lines = output.strip().split('\n')

        # stream-json 格式：每行一个 JSON 对象
        for line in reversed(lines):
            try:
                data = json.loads(line)
                if isinstance(data, dict):
                    if 'result' in data:
                        return {"success": True, "data": data['result']}
                    if 'content' in data:
                        return {"success": True, "data": data['content']}
            except json.JSONDecodeError:
                continue

        # 尝试直接解析为 JSON
        try:
            return {"success": True, "data": json.loads(output)}
        except json.JSONDecodeError:
            return {"success": True, "data": {"raw_output": output}}
```

---

## 8. Hook 管理器实现

```python
# python/task_tracker/workflow/hooks.py

import subprocess
import json
import os
from typing import Dict, Any, Optional

from .claude_agent import ClaudeAgent

class HookManager:
    """
    Hook 管理器

    支持三种 Hook 类型，全部使用子进程隔离执行：
    - python: Python 脚本
    - shell: Shell 命令
    - claude_agent: Claude Agent 任务
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
        执行 Hook（子进程隔离）
        """
        hook_type = hook_def.get('type', 'python')

        # 准备环境变量
        env = os.environ.copy()
        env['HOOK_CONTEXT'] = json.dumps(context)
        if step_output is not None:
            env['STEP_OUTPUT'] = json.dumps(step_output)

        # 添加自定义环境变量
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
        """子进程执行 Python 脚本"""
        script = hook_def.get('script', '')

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
            return json.loads(result.stdout)
        except json.JSONDecodeError:
            return {"output": result.stdout}

    def _execute_shell(self, hook_def: Dict, env: Dict) -> Dict[str, Any]:
        """子进程执行 Shell 命令"""
        command = hook_def.get('command', '')

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
            "stdout": result.stdout,
            "stderr": result.stderr,
            "returncode": result.returncode
        }

    def _execute_claude_agent(
        self,
        hook_def: Dict,
        context: Dict,
        step_output: Any
    ) -> Dict[str, Any]:
        """执行 Claude Agent Hook"""
        project_path = context.get('inputs', {}).get('project_paths', ['.'])[0]
        agent = ClaudeAgent(project_path)

        prompt = hook_def.get('prompt', '')
        from jinja2 import Template
        prompt = Template(prompt).render(**context, step_output=step_output)

        result = agent.execute(prompt)
        return result.get('data', {})

    def _render_value(self, value: str, context: Dict, step_output: Any) -> str:
        """渲染模板值"""
        from jinja2 import Template
        return Template(str(value)).render(**context, step_output=step_output)


class HookExecutionError(Exception):
    """Hook 执行错误"""
    pass
```

---

## 9. 工作流定义示例

### 9.1 默认任务分解工作流

```yaml
# python/task_tracker/workflows/task-decomposition.yaml

name: "task-decomposition"
version: "1.0"
description: "将全局任务分解为项目级 Todos"

inputs:
  task_id:
    type: integer
    required: true
  task_title:
    type: string
    required: true
  task_description:
    type: string
    required: true
  project_paths:
    type: array
    required: true

steps:
  - id: analyze_projects
    name: "分析项目结构"
    type: claude_agent
    config:
      timeout: 180
      output_format: json
    prompt: |
      分析以下项目的代码结构：
      {% for path in project_paths %}
      - {{ path }}
      {% endfor %}

      任务上下文：{{ task_title }}
      {{ task_description }}

      请使用 Glob/Grep/Read 工具探索每个项目，返回 JSON 格式的分析结果。
    hooks:
      before:
        - validate_project_paths
      after:
        - cache_analysis_result

  - id: generate_todos
    name: "生成 Todo 列表"
    type: claude_agent
    depends_on: [analyze_projects]
    config:
      timeout: 120
    prompt: |
      基于项目分析结果，为任务生成具体的 Todos：

      任务：{{ task_title }}
      描述：{{ task_description }}
      分析结果：{{ steps.analyze_projects.output | tojson }}

      返回 JSON 格式的 Todo 列表。
    hooks:
      after:
        - validate_todos
        - calculate_total_time

  - id: user_confirmation
    name: "用户确认"
    type: interactive
    depends_on: [generate_todos]
    config:
      display_mode: preview
      allow_edit: true

  - id: save_todos
    name: "保存 Todos"
    type: action
    depends_on: [user_confirmation]
    condition: "{{ steps.user_confirmation.confirmed }}"
    action: save_todos_to_database
    hooks:
      after:
        - notify_completion

hooks:
  validate_project_paths:
    type: python
    script: |
      from pathlib import Path
      import json, os
      context = json.loads(os.environ['HOOK_CONTEXT'])
      for path in context['inputs']['project_paths']:
          if not Path(path).exists():
              raise ValueError(f"项目路径不存在: {path}")
      print(json.dumps({"valid": True}))

  cache_analysis_result:
    type: python
    script: |
      import json, hashlib, os
      from pathlib import Path
      context = json.loads(os.environ['HOOK_CONTEXT'])
      step_output = json.loads(os.environ['STEP_OUTPUT'])
      paths_str = str(sorted(context['inputs']['project_paths']))
      cache_key = hashlib.md5(paths_str.encode()).hexdigest()
      cache_dir = Path.home() / '.claude-task-tracker' / 'cache'
      cache_dir.mkdir(parents=True, exist_ok=True)
      (cache_dir / f'analysis_{cache_key}.json').write_text(json.dumps(step_output))
      print(json.dumps({"cached": True}))

  validate_todos:
    type: claude_agent
    prompt: |
      验证以下 Todo 列表的质量：
      {{ step_output | tojson }}
      返回验证结果。

  calculate_total_time:
    type: python
    script: |
      import json, os
      step_output = json.loads(os.environ['STEP_OUTPUT'])
      todos = step_output.get('todos', [])
      total = sum(t.get('estimated_minutes', 60) for t in todos)
      step_output['total_hours'] = round(total / 60, 1)
      print(json.dumps(step_output))

  notify_completion:
    type: shell
    command: |
      ~/Applications/ClaudeMonitor.app/Contents/MacOS/ClaudeMonitor notify \
        "任务分解完成" "已生成 Todos"

error_handling:
  retry:
    max_attempts: 3
    backoff: exponential
  fallback:
    analyze_projects:
      action: use_cached_analysis
```

### 9.2 用户自定义工作流示例

```yaml
# ~/.claude-task-tracker/workflows/my-workflow.yaml

name: "my-task-decomposition"
version: "1.0"
description: "我的自定义任务分解流程"

extends: task-decomposition

steps:
  - id: security_check
    name: "安全检查"
    type: claude_agent
    insert_after: analyze_projects
    prompt: |
      检查项目中的安全隐患，返回 JSON 格式报告。

  - id: generate_todos
    override: true
    name: "生成 Todo（含安全任务）"
    type: claude_agent
    depends_on: [analyze_projects, security_check]
    prompt: |
      基于分析和安全检查结果，生成 Todos。
      优先生成安全修复的 Todo。

hooks:
  notify_slack:
    type: shell
    command: |
      curl -X POST "$SLACK_WEBHOOK" -d '{"text": "任务分解完成"}'
    env:
      SLACK_WEBHOOK: "${SLACK_WEBHOOK}"

step_hooks:
  save_todos:
    after:
      - notify_completion
      - notify_slack
```

---

## 10. AI 提示词模板

### 10.1 项目分析提示词

```python
PROJECT_ANALYSIS_PROMPT = """
# 项目分析请求

## 任务上下文
{task_title}
{task_description}

## 分析目标
请深入分析当前项目，为任务分解提供以下信息：

### 1. 项目概览
- 识别项目类型
- 识别主要技术栈和框架
- 识别项目的分层架构

### 2. 相关代码定位
- 找出与任务相关的现有代码文件
- 识别需要修改的核心模块
- 找出可以复用的现有实现

### 3. 依赖分析
- 列出需要的新依赖
- 检查与现有依赖的兼容性

### 4. 实现建议
- 推荐的实现路径
- 需要创建的新文件
- 需要修改的现有文件

## 输出格式
返回 JSON 格式。
"""
```

### 10.2 Todo 生成提示词

```python
TODO_GENERATION_PROMPT = """
# Todo 生成请求

## 全局任务
标题：{task_title}
描述：{task_description}

## 项目分析结果
{analysis_results_json}

## 生成要求

请基于分析生成具体的 Todo 列表。

### Todo 质量标准
1. **原子性**：每个 Todo 是独立可完成的工作单元
2. **可验证**：完成标准清晰
3. **有依赖关系**：标明依赖
4. **时间可估**：提供合理的时间估算

### 命名规范
- 标题使用动词开头：实现、添加、修复、重构、测试
- 避免模糊词汇：优化、改进、处理
- 包含具体对象：在 XXX 中添加 YYY

### 输出格式
```json
{
  "todos": [
    {
      "project_path": "/path/to/project",
      "title": "简洁的标题",
      "description": "详细描述",
      "priority": 0,
      "estimated_minutes": 60,
      "dependencies": [],
      "acceptance_criteria": ["验收标准"]
    }
  ],
  "execution_order": [0, 1, 2],
  "total_estimated_hours": 8.5
}
```
"""
```

### 10.3 完成总结提示词

```python
COMPLETION_SUMMARY_PROMPT = """
请根据以下信息生成一个简洁的任务完成总结。

任务标题: {todo_title}
任务描述: {todo_description}

执行记录摘要:
{transcript_excerpt}

请生成 2-3 句话的完成总结，说明:
1. 完成了什么
2. 关键变更
3. 任何注意事项
"""
```

---

## 附录: 配置文件示例

### ~/.claude-task-tracker/config.json

```json
{
  "todo": {
    "enabled": true,
    "mcp_server": {
      "enabled": true,
      "host": "127.0.0.1",
      "port": 8765,
      "auto_start": true
    },
    "ai_decompose": {
      "enabled": true,
      "provider": "third_party"
    },
    "ai_summary": {
      "enabled": true,
      "provider": "third_party"
    }
  },
  "task_decomposition": {
    "enabled": true,
    "claude_integration": {
      "method": "cli",
      "timeout_seconds": 180,
      "max_retries": 2
    },
    "analysis": {
      "include_dependencies": true,
      "include_tests": true,
      "max_files_to_analyze": 50
    },
    "todo_generation": {
      "min_todos": 2,
      "max_todos": 20,
      "require_time_estimate": true
    },
    "confirmation": {
      "required": true,
      "auto_approve_threshold": 5
    }
  },
  "summary": {
    "provider": "third_party",
    "third_party": {
      "enabled": true,
      "base_url": "https://api.openai.com/v1",
      "api_key": "sk-...",
      "model": "gpt-4"
    }
  }
}
```
