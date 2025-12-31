# Todo 工作流使用指南

本文档介绍如何使用 Claude Monitor 的全局任务和 Todo 管理功能。

## 概述

Todo 工作流系统提供：
- **全局任务 (Global Task)**: 跨项目的高层次目标
- **项目级 Todo**: 具体可执行项，绑定到特定项目
- **自动关联**: Session 与 Todo 的自动关联
- **MCP 集成**: Claude Code 可通过 MCP 工具操作 Todo

## 使用方式

### 1. Swift UI 创建任务

1. 打开 Claude Monitor 应用
2. 点击 "Task Center" 打开任务中心
3. 切换到 "Todos" 标签页
4. 点击 "+" 按钮创建新任务
5. 填写任务信息：
   - 标题（必填）
   - 描述（可选）
   - 目标项目路径
   - 优先级
   - 是否自动分解
6. 点击 "Create Task" 创建

如果勾选了"自动分解"，系统会在后台调用 AI 分析项目并生成具体的 Todo 列表。

### 2. CLI 命令行管理

```bash
# 创建全局任务
claude-todo task create "实现用户认证系统"

# 创建任务并自动分解
claude-todo task create "实现用户认证系统" --decompose --projects /path/to/project

# 查看任务列表
claude-todo task list

# 查看任务详情
claude-todo task show 1

# 创建 Todo
claude-todo todo add "添加 JWT 中间件" --project /path/to/project

# 查看项目 Todos
claude-todo todo list --project /path/to/project

# 开始执行 Todo
claude-todo todo start 42

# 完成 Todo
claude-todo todo complete 42 --summary "已实现 JWT 验证中间件"
```

### 3. Slash 命令 (/hl-todo)

在 Claude Code 中使用 `/hl-todo` 命令来加载和执行项目待办：

```
/hl-todo              # 列出待办并开始第一个
/hl-todo next         # 执行下一个待办
/hl-todo 42           # 执行指定 ID 的 Todo
```

执行流程：
1. Claude 调用 MCP `list_todos` 获取项目待办
2. 显示待办列表供确认
3. 调用 `start_todo` 开始执行
4. Claude 根据 Todo 描述完成任务
5. 调用 `complete_todo` 标记完成

### 4. MCP 工具直接调用

Claude Code 可以直接使用以下 MCP 工具：

| 工具 | 说明 |
|------|------|
| `list_todos` | 列出项目相关的 Todos |
| `get_todo` | 获取 Todo 详情 |
| `start_todo` | 开始执行 Todo |
| `complete_todo` | 完成 Todo |
| `split_todo` | 拆分 Todo 为子任务 |
| `create_todo` | 创建新 Todo |
| `update_todo` | 更新 Todo |

## 自动关联机制

### Session 开始时

当你在某个项目目录启动 Claude Code 时：
1. `goal_tracker.py` hook 会检查该项目是否有 `in_progress` 状态的 Todo
2. 如果有，自动将当前 Session 关联到该 Todo
3. 如果只有 `pending` Todo，会在日志中记录（不自动关联）

### Session 结束时

当 Claude Code 停止时：
1. `snapshot_hook.py` hook 检查 Session 关联的 Todo
2. 将 Todo 链接状态更新为 `paused`
3. 用户需要手动完成 Todo（或使用 MCP 工具）

## 状态说明

### Todo 状态

| 状态 | 说明 |
|------|------|
| `pending` | 待开始 |
| `in_progress` | 执行中 |
| `blocked` | 被阻塞 |
| `completed` | 已完成 |
| `cancelled` | 已取消 |

### Session-Todo 链接状态

| 状态 | 说明 |
|------|------|
| `active` | Session 正在处理此 Todo |
| `paused` | Session 已暂停 |
| `completed` | Session 完成了此 Todo |

## 配置

### MCP Server 配置

确保 `~/.mcp.json` 包含：

```json
{
  "mcpServers": {
    "claude-todo": {
      "transport": "http",
      "url": "http://127.0.0.1:8765/mcp"
    }
  }
}
```

### 启动 MCP Server

```bash
# 手动启动
claude-todo server start

# 后台启动
claude-todo server start --daemon

# 检查状态
claude-todo server status

# 停止
claude-todo server stop
```

## 工作流示例

### 示例 1: 功能开发

1. 在 UI 中创建任务 "实现用户登录功能"，勾选自动分解
2. 系统分析项目后生成 Todos:
   - #1 添加登录表单组件
   - #2 实现认证 API
   - #3 添加 Session 管理
   - #4 编写测试
3. 在项目目录启动 Claude Code
4. 运行 `/hl-todo` 开始第一个任务
5. 完成后继续 `/hl-todo next`

### 示例 2: 手动管理

```bash
# 创建 Todo
claude-todo todo add "修复登录页面 CSS" --project ~/projects/myapp --priority 2

# 在 Claude Code 中
/hl-todo 123  # 执行刚创建的 Todo
```

## 故障排除

### MCP Server 无法连接

```bash
# 检查服务状态
claude-todo server status

# 查看日志
tail -f ~/.claude-task-tracker/logs/mcp.log
```

### Todo 不显示

确保数据库表已创建：

```bash
sqlite3 ~/.claude-task-tracker/tasks.db ".tables"
# 应该包含: global_tasks, todos, session_todo_links
```

### Hook 不生效

检查 Claude Code hooks 配置：

```bash
cat ~/.claude/settings.json | grep hooks
```
