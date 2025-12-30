# 全局 Agent 工作流系统 - 架构设计

> 版本: 1.0
> 日期: 2025-12-30
> 状态: 设计阶段

## 目录

1. [系统概述](#1-系统概述)
2. [核心概念](#2-核心概念)
3. [系统架构](#3-系统架构)
4. [数据模型设计](#4-数据模型设计)
5. [MCP Server 设计](#5-mcp-server-设计)
6. [CLI 工具设计](#6-cli-工具设计)
7. [Swift UI 设计](#7-swift-ui-设计)
8. [Hook 增强设计](#8-hook-增强设计)
9. [AI 集成设计](#9-ai-集成设计)
   - [9.1 任务分解](#91-任务分解)
   - [9.2 完成总结生成](#92-完成总结生成)
   - [9.3 全局任务分解工作流](#93-全局任务分解工作流)
   - [9.4 可自定义 Hook 工作流引擎](#94-可自定义-hook-工作流引擎)
10. [实现路线图](#10-实现路线图)

---

## 1. 系统概述

### 1.1 背景

Claude Monitor 当前是一个 macOS 原生应用，为 Claude Code 提供桌面通知和会话管理功能。现有系统基于**会话级别**的被动追踪，缺乏：

- 跨项目的全局任务管理
- 主动的 Todo 调度和执行
- Claude Code 与任务系统的双向交互

### 1.2 目标

构建一个**全局 Agent 工作流系统**，实现：

1. **全局任务管理**：用户可以创建跨项目的高层次任务
2. **项目级 Todo 分发**：任务可以分解为具体的项目级 Todo
3. **Claude Code 集成**：通过 MCP Server 让 Claude Code 主动调用 Todo 系统
4. **执行追踪**：记录每个 Todo 的执行过程和完成情况
5. **AI 辅助**：支持任务分解和完成总结的 AI 生成
6. **可自定义工作流**：用户可定义自己的任务分解和处理流程

### 1.3 设计原则

- **渐进式扩展**：在现有架构基础上扩展，保持向后兼容
- **最小可用**：优先实现核心功能，快速验证后迭代
- **标准协议**：使用 MCP 标准协议，确保与 Claude Code 的兼容性
- **数据统一**：复用现有 SQLite 数据库，统一数据管理
- **可扩展性**：通过 Hook 机制支持用户自定义扩展

---

## 2. 核心概念

### 2.1 实体层级

```
┌─────────────────────────────────────────────────────────────┐
│                     全局任务 (Global Task)                    │
│  高层次目标，可跨多个项目                                      │
│  例："为所有微服务实现统一认证"                                │
└─────────────────────────┬───────────────────────────────────┘
                          │ 1:N
                          ▼
┌─────────────────────────────────────────────────────────────┐
│                    项目级 Todo (Todo)                         │
│  具体可执行项，绑定到特定项目                                  │
│  例："在 auth-service 中实现 JWT 验证"                        │
└─────────────────────────┬───────────────────────────────────┘
                          │ 1:N (可选层级)
                          ▼
┌─────────────────────────────────────────────────────────────┐
│                     子 Todo (Sub-Todo)                        │
│  Claude Code 运行时可拆分的更细粒度任务                        │
│  例："添加 JWT 中间件"、"编写验证测试"                        │
└─────────────────────────┬───────────────────────────────────┘
                          │ N:M
                          ▼
┌─────────────────────────────────────────────────────────────┐
│                 Claude Code Session                          │
│  实际执行 Todo 的会话记录                                     │
└─────────────────────────────────────────────────────────────┘
```

### 2.2 状态定义

**全局任务状态**：
| 状态 | 说明 |
|------|------|
| `active` | 活跃中，有待完成的 Todo |
| `completed` | 所有关联 Todo 已完成 |
| `archived` | 已归档，不再显示 |

**Todo 状态**：
| 状态 | 说明 |
|------|------|
| `pending` | 待开始 |
| `in_progress` | 执行中（关联活跃 Session） |
| `blocked` | 被阻塞（依赖未满足或遇到问题） |
| `completed` | 已完成 |
| `cancelled` | 已取消 |

**工作流状态**：
| 状态 | 说明 |
|------|------|
| `pending` | 待执行 |
| `running` | 执行中 |
| `completed` | 已完成 |
| `failed` | 执行失败 |
| `cancelled` | 已取消 |

### 2.3 关键流程

**流程 1：创建全局任务**
```
用户 → CLI/Swift UI → 创建 Global Task
                          ↓
                   (可选) AI 分解
                          ↓
                   生成项目级 Todos
                          ↓
                   存储到数据库
```

**流程 2：执行 Todo**
```
用户启动 Claude Code
         ↓
MCP Server 返回项目相关 Todos
         ↓
Claude Code 选择/开始 Todo
         ↓
执行过程中可拆分为子 Todo
         ↓
完成后调用 complete_todo
         ↓
(可选) AI 生成完成总结
```

**流程 3：自定义工作流执行**
```
用户定义工作流 (YAML)
         ↓
Workflow Engine 解析和调度
         ↓
Claude Agent 自主探索代码
         ↓
执行自定义 Hooks
         ↓
生成结果并存储
```

---

## 3. 系统架构

### 3.1 整体架构图

```
┌───────────────────────────────────────────────────────────────────┐
│                          用户交互层                                │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐   │
│  │  Swift UI   │  │    CLI      │  │     Claude Code         │   │
│  │  (macOS App)│  │ (命令行工具) │  │  (通过 MCP 调用)        │   │
│  └──────┬──────┘  └──────┬──────┘  └───────────┬─────────────┘   │
└─────────┼────────────────┼─────────────────────┼─────────────────┘
          │                │                     │
          │                │                     │ MCP Protocol
          ▼                ▼                     ▼
┌─────────────────────────────────────────────────────────────────┐
│                         服务层                                    │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │                    MCP Server (后台服务)                      │ │
│  │  - HTTP Transport: http://localhost:8765/mcp                │ │
│  │  - 提供 Todo CRUD 工具                                       │ │
│  │  - 管理 Session-Todo 关联                                    │ │
│  └─────────────────────────────────────────────────────────────┘ │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │                    Todo Service                              │ │
│  │  - 全局任务管理                                               │ │
│  │  - Todo 层级管理                                              │ │
│  │  - 执行记录追踪                                               │ │
│  └─────────────────────────────────────────────────────────────┘ │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │                    Workflow Engine                           │ │
│  │  - YAML 工作流解析                                           │ │
│  │  - 步骤调度和执行                                             │ │
│  │  - Hook 管理                                                  │ │
│  │  - Claude Agent 集成                                         │ │
│  └─────────────────────────────────────────────────────────────┘ │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │                    AI Service (现有)                          │ │
│  │  - 任务分解                                                   │ │
│  │  - 完成总结生成                                               │ │
│  └─────────────────────────────────────────────────────────────┘ │
└───────────────────────────────────┬─────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────┐
│                         数据层                                    │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │               SQLite Database                                │ │
│  │  ~/.claude-task-tracker/tasks.db                            │ │
│  │                                                              │ │
│  │  既有表: sessions, progress, timeline, snapshots, ...       │ │
│  │  新增表: global_tasks, todos, workflow_runs, ...            │ │
│  └─────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

### 3.2 组件交互

```
                     ┌──────────────────┐
                     │    Swift App     │
                     │  (StatusBar +    │
                     │   Management)    │
                     └────────┬─────────┘
                              │ 读取 DB
                              │ 启动 MCP Server
                              ▼
┌─────────────┐      ┌──────────────────┐      ┌─────────────┐
│    CLI      │─────▶│   MCP Server     │◀─────│ Claude Code │
│ (todo_cli)  │      │  (后台服务)       │      │  (MCP 客户端)│
└─────────────┘      └────────┬─────────┘      └──────┬──────┘
      │                       │                       │
      │                       ▼                       │
      │              ┌──────────────────┐             │
      │              │  Workflow Engine │             │
      │              │  (工作流执行)     │             │
      │              └────────┬─────────┘             │
      │                       │                       │
      │                       ▼                       │
      │              ┌──────────────────┐             │
      └─────────────▶│  Todo Service    │◀────────────┘
                     │  (todo_service.py)│
                     └────────┬─────────┘
                              │
                              ▼
                     ┌──────────────────┐
                     │   SQLite DB      │
                     └──────────────────┘
```

### 3.3 目录结构

```
python/task_tracker/
├── cli/
│   ├── api_manager.py          # (现有)
│   ├── account_manager.py      # (现有)
│   └── todo_cli.py             # 新增: CLI 入口
├── hooks/
│   ├── goal_tracker.py         # 修改: 增加 Todo 感知
│   ├── progress_tracker.py     # (现有)
│   ├── notification_tracker.py # (现有)
│   └── snapshot_hook.py        # 修改: 增加 Todo 完成处理
├── services/
│   ├── database.py             # 修改: 增加新表
│   ├── todo_service.py         # 新增: Todo 服务
│   ├── summary_service.py      # (现有) 复用 AI 功能
│   └── notification.py         # (现有)
├── workflow/                   # 新增: 工作流引擎
│   ├── __init__.py
│   ├── engine.py               # 工作流引擎核心
│   ├── parser.py               # YAML 解析器
│   ├── hooks.py                # Hook 管理器
│   └── claude_agent.py         # Claude Agent 封装
├── workflows/                  # 新增: 默认工作流定义
│   ├── task-decomposition.yaml
│   └── code-review.yaml
└── mcp/
    ├── __init__.py             # 新增
    ├── server.py               # 新增: MCP Server 主入口
    ├── tools.py                # 新增: MCP 工具实现
    └── config.py               # 新增: 配置管理

swift/
├── Services/
│   ├── DatabaseModels.swift    # 修改: 新增数据模型
│   ├── DatabaseManager.swift   # 修改: 新增查询方法
│   └── TodoDatabaseManager.swift  # 新增: Todo 专用查询
└── UI/
    ├── Todo/
    │   ├── TodoListView.swift      # 新增
    │   ├── TodoDetailView.swift    # 新增
    │   └── GlobalTaskView.swift    # 新增
    └── Workflow/
        └── WorkflowStatusView.swift # 新增: 工作流状态预览
```

---

## 4. 数据模型设计

### 4.1 ER 图

```
┌────────────────────┐
│    global_tasks    │
│────────────────────│
│ id (PK)            │
│ title              │
│ description        │
│ status             │
│ priority           │
│ created_at         │
│ updated_at         │
│ completed_at       │
│ metadata_json      │
└─────────┬──────────┘
          │ 1:N (可选)
          │
┌─────────▼──────────┐      ┌─────────────────────┐
│       todos        │      │  todo_dependencies  │
│────────────────────│      │─────────────────────│
│ id (PK)            │◀─────│ todo_id (FK)        │
│ global_task_id(FK) │      │ depends_on_id (FK)  │
│ parent_todo_id(FK) │◀┐    └─────────────────────┘
│ project_path       │ │
│ title              │ │ Self-reference
│ description        │─┘ (Parent-Child)
│ status             │
│ priority           │
│ estimated_minutes  │
│ actual_minutes     │
│ created_at         │
│ completed_at       │
│ completion_summary │
│ metadata_json      │
└─────────┬──────────┘
          │ N:M
          │
┌─────────▼──────────┐      ┌─────────────────────┐
│ session_todo_links │      │   todo_executions   │
│────────────────────│      │─────────────────────│
│ id (PK)            │      │ id (PK)             │
│ session_pk (FK)    │      │ todo_id (FK)        │
│ todo_id (FK)       │      │ session_pk (FK)     │
│ started_at         │      │ action              │
│ ended_at           │      │ actor               │
│ status             │      │ details_json        │
│ notes              │      │ created_at          │
└─────────┬──────────┘      └─────────────────────┘
          │
┌─────────▼──────────┐      ┌─────────────────────┐
│     sessions       │      │   workflow_runs     │
│    (现有表)        │      │─────────────────────│
└────────────────────┘      │ id (PK)             │
                            │ workflow_name       │
                            │ task_id (FK)        │
                            │ status              │
                            │ current_step        │
                            │ context_json        │
                            │ started_at          │
                            │ completed_at        │
                            └─────────┬───────────┘
                                      │ 1:N
                            ┌─────────▼───────────┐
                            │ workflow_step_logs  │
                            │─────────────────────│
                            │ id (PK)             │
                            │ run_id (FK)         │
                            │ step_id             │
                            │ status              │
                            │ output_json         │
                            │ error               │
                            │ started_at          │
                            │ completed_at        │
                            └─────────────────────┘
```

### 4.2 核心表说明

| 表名 | 说明 |
|------|------|
| `global_tasks` | 全局任务，跨项目的高层次目标 |
| `todos` | 项目级 Todo，支持层级（parent_todo_id） |
| `todo_dependencies` | Todo 之间的依赖关系 |
| `session_todo_links` | Session 与 Todo 的关联 |
| `todo_executions` | Todo 执行记录（操作日志） |
| `workflow_runs` | 工作流执行记录 |
| `workflow_step_logs` | 工作流步骤执行日志 |

---

## 5. MCP Server 设计

### 5.1 概述

MCP (Model Context Protocol) Server 是 Claude Code 与 Todo 系统交互的桥梁。它作为**独立后台服务**运行，提供标准化的工具接口。

### 5.2 技术选型

- **协议**: MCP 2024-11-05
- **传输**: HTTP (支持远程访问和多客户端)
- **框架**: FastMCP (Python SDK)
- **端口**: 8765 (默认)

### 5.3 工具列表

| 工具名 | 说明 | 主要参数 |
|--------|------|----------|
| `list_todos` | 列出项目相关的 Todos | project_path, status, limit |
| `get_todo` | 获取 Todo 详情 | todo_id |
| `start_todo` | 开始执行 Todo | todo_id, session_id |
| `complete_todo` | 完成 Todo | todo_id, summary |
| `split_todo` | 拆分 Todo 为子任务 | todo_id, sub_todos |
| `create_todo` | 创建 Todo | title, project_path, priority |
| `update_todo` | 更新 Todo | todo_id, status, priority |

### 5.4 配置方式

**全局 MCP 配置** `~/.mcp.json`:
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

### 5.5 启动方式

1. **随 Swift App 启动**（推荐）
2. **手动启动**: `python3 -m task_tracker.mcp.server`
3. **系统服务**: launchd plist 配置

---

## 6. CLI 工具设计

### 6.1 命令结构

```
claude-todo <command> [subcommand] [options]

Commands:
  task      管理全局任务
  todo      管理 Todos
  workflow  管理工作流
  server    管理 MCP Server
```

### 6.2 命令概览

#### task 命令组
| 命令 | 说明 |
|------|------|
| `task create` | 创建全局任务 |
| `task list` | 列出全局任务 |
| `task show` | 查看任务详情 |
| `task update` | 更新任务 |
| `task archive` | 归档任务 |
| `task decompose` | AI 分解任务为 Todos |

#### todo 命令组
| 命令 | 说明 |
|------|------|
| `todo add` | 创建 Todo |
| `todo list` | 列出 Todos |
| `todo show` | 查看 Todo 详情 |
| `todo update` | 更新 Todo |
| `todo start` | 开始执行 Todo |
| `todo complete` | 完成 Todo |
| `todo split` | 拆分 Todo |

#### workflow 命令组
| 命令 | 说明 |
|------|------|
| `workflow list` | 列出可用工作流 |
| `workflow run` | 运行工作流 |
| `workflow validate` | 验证工作流定义 |
| `workflow status` | 查看运行状态 |
| `workflow cancel` | 取消运行中的工作流 |
| `workflow logs` | 查看步骤日志 |

#### server 命令组
| 命令 | 说明 |
|------|------|
| `server start` | 启动 MCP Server |
| `server stop` | 停止 MCP Server |
| `server status` | 查看 Server 状态 |
| `server restart` | 重启 Server |

---

## 7. Swift UI 设计

### 7.1 新增视图

#### TodoListView - Todo 列表视图
- 按项目分组显示
- 支持树形层级展示
- 状态/项目/优先级筛选
- 拖拽排序（可选）

#### TodoDetailView - Todo 详情视图
- 基本信息展示
- 子任务列表
- 执行历史
- 关联 Sessions

#### GlobalTaskView - 全局任务视图
- 任务列表
- 完成进度条
- Todo 统计

#### WorkflowStatusView - 工作流状态视图
- 运行中的工作流列表
- 步骤执行状态
- 进度指示
- 取消操作

### 7.2 TaskCenter 增强

在现有 TaskCenter 中添加标签页：
- **Sessions**: 现有会话列表
- **Todos**: Todo 列表视图
- **Workflows**: 工作流状态预览
- **Reports**: 报告视图

### 7.3 StatusBar 增强

在状态栏 Popover 中显示：
- 活跃 Sessions 数量
- 待处理 Todos 数量
- 最近 Todos 快速访问

---

## 8. Hook 增强设计

### 8.1 goal_tracker.py 增强

在用户提交 prompt 时：
- 检查当前项目的 Todos
- 自动关联 Session 到 in_progress 的 Todo
- 可选：在系统消息中提示可用的 Todos

### 8.2 snapshot_hook.py 增强

在 Session 完成时：
- 处理关联的 Todos
- 更新 session_todo_link 状态
- 记录执行日志
- 可选：生成 AI 完成总结

---

## 9. AI 集成设计

### 9.1 任务分解

将全局任务分解为项目级 Todos：
- 输入：任务标题、描述、目标项目列表
- 输出：Todo 列表（标题、描述、优先级、预估时间）
- 复用现有 `summary_service.py` 的 AI 调用能力

### 9.2 完成总结生成

根据 Session transcript 生成 Todo 完成总结：
- 输入：Todo 信息、Session transcript
- 输出：2-3 句话的完成总结
- 说明完成内容、关键变更、注意事项

### 9.3 全局任务分解工作流

多阶段智能工作流：

```
┌──────────────┐    ┌──────────────┐    ┌──────────────────────┐
│ 1. 任务输入   │───▶│ 2. 项目发现   │───▶│ 3. 代码结构分析      │
│   (用户)      │    │   (自动)      │    │   (Claude Code)      │
└──────────────┘    └──────────────┘    └──────────────────────┘
                                                   │
                                                   ▼
┌──────────────┐    ┌──────────────┐    ┌──────────────────────┐
│ 6. 存储执行   │◀───│ 5. 用户确认   │◀───│ 4. Todo 生成         │
│   (系统)      │    │   (交互)      │    │   (AI 分解)          │
└──────────────┘    └──────────────┘    └──────────────────────┘
```

#### 步骤说明

| 步骤 | 说明 | 执行者 |
|------|------|--------|
| 任务输入 | 用户通过 CLI/UI 创建全局任务 | 用户 |
| 项目发现 | 验证或自动发现目标项目 | 系统 |
| 代码结构分析 | 利用 Claude Code 自主探索代码 | Claude Agent |
| Todo 生成 | 基于分析结果生成 Todo 列表 | AI |
| 用户确认 | 展示预览，允许编辑和调整 | 用户 |
| 存储执行 | 批量创建 Todos 并记录 | 系统 |

#### Claude Code 集成方式

| 方式 | 说明 | 适用场景 |
|------|------|----------|
| CLI 调用 | `claude -p` 非交互模式 | CLI 工具 |
| MCP 双向集成 | Claude Code 调用 MCP 工具 | Claude Code 内部 |
| Skill 集成 | Claude Code Skill 封装 | 最佳用户体验 |

### 9.4 可自定义 Hook 工作流引擎

#### 9.4.1 设计目标

1. **声明式工作流** - YAML 定义，易于理解和维护
2. **可插拔 Hook** - 用户可在任意步骤前后插入自定义逻辑
3. **Agent 自主探索** - 利用 Claude Code 的 Glob/Grep/Read 工具分析代码
4. **子进程隔离** - 用户自定义 Hook 安全执行，不影响主流程

#### 9.4.2 系统架构

```
┌─────────────────────────────────────────────────────────────────┐
│                     用户输入                                     │
│  - 全局任务定义                                                  │
│  - 目标项目路径                                                  │
│  - 自定义工作流 (可选)                                          │
└──────────────────────────┬──────────────────────────────────────┘
                           │
                           v
┌─────────────────────────────────────────────────────────────────┐
│                  Workflow Engine (Python)                        │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐              │
│  │   Parser    │  │  Executor   │  │   State     │              │
│  │  (YAML)     │→ │  (Steps)    │→ │  Manager    │              │
│  └─────────────┘  └─────────────┘  └─────────────┘              │
└──────────────────────────┬──────────────────────────────────────┘
                           │
           ┌───────────────┼───────────────┐
           v               v               v
┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐
│  Claude Agent   │ │  Python Hook    │ │  Shell Hook     │
│  (代码探索)     │ │  (子进程)       │ │  (子进程)       │
└─────────────────┘ └─────────────────┘ └─────────────────┘
           │               │               │
           └───────────────┼───────────────┘
                           v
┌─────────────────────────────────────────────────────────────────┐
│                    结果存储 (SQLite)                             │
└─────────────────────────────────────────────────────────────────┘
```

#### 9.4.3 工作流定义结构

YAML 工作流定义包含：

| 部分 | 说明 |
|------|------|
| `name` | 工作流名称 |
| `version` | 版本号 |
| `description` | 描述 |
| `inputs` | 输入参数定义 |
| `steps` | 步骤列表 |
| `hooks` | 自定义 Hook 定义 |
| `error_handling` | 错误处理策略 |

#### 9.4.4 步骤类型

| 类型 | 说明 |
|------|------|
| `claude_agent` | 调用 Claude Code Agent 执行任务 |
| `interactive` | 需要用户交互的步骤 |
| `action` | 执行预定义的系统操作 |
| `python` | 执行 Python 脚本 |
| `shell` | 执行 Shell 命令 |

#### 9.4.5 Hook 类型

| 类型 | 执行方式 | 说明 |
|------|----------|------|
| `python` | 子进程 | Python 脚本，通过 HOOK_CONTEXT 环境变量获取上下文 |
| `shell` | 子进程 | Shell 命令，支持环境变量模板 |
| `claude_agent` | Claude CLI | 调用 Claude Agent 执行验证等任务 |

#### 9.4.6 工作流继承

用户自定义工作流可以：
- `extends`: 继承默认工作流
- `override`: 覆盖指定步骤
- `insert_after`: 在指定步骤后插入新步骤

#### 9.4.7 Claude Agent 能力

利用 Claude Code CLI 的非交互模式：

| 命令选项 | 说明 |
|----------|------|
| `-p` | 非交互模式，直接返回结果 |
| `--output-format stream-json` | JSON 输出格式 |
| `--dangerously-skip-permissions` | 跳过权限确认（仅用于容器） |

Agent 可使用的内置工具：
- **Glob**: 文件模式匹配
- **Grep**: 代码内容搜索
- **Read**: 文件读取
- **Bash**: 命令执行

---

## 10. 实现路线图

### 阶段 1: 数据基础

**目标**: 建立数据模型和基础服务

- 在 `database.py` 中添加新表 schema
- 实现数据库迁移逻辑
- 创建 `todo_service.py` 实现 CRUD
- 编写单元测试

### 阶段 2: MCP Server

**目标**: 实现 MCP Server 让 Claude Code 可以调用

- 安装 fastmcp 依赖
- 实现 `mcp/server.py` 主入口
- 实现 7 个核心工具
- 添加 HTTP 传输支持
- 测试与 Claude Code 的集成

### 阶段 3: CLI 工具

**目标**: 提供命令行管理界面

- 实现 `cli/todo_cli.py`
- 实现 task/todo/server 命令组
- 更新 install.sh 安装 CLI

### 阶段 4: Workflow Engine

**目标**: 实现可自定义工作流引擎

- 实现 YAML 解析器
- 实现工作流引擎核心
- 实现 Hook 管理器（子进程隔离）
- 实现 Claude Agent 封装
- 创建默认工作流定义

### 阶段 5: Swift UI 基础

**目标**: 在 Swift App 中展示 Todos 和 Workflows

- 添加数据模型
- 实现 TodoListView
- 实现 WorkflowStatusView
- 在 TaskCenter 添加标签页
- 更新状态栏显示

### 阶段 6: Hook 增强

**目标**: 实现 Session-Todo 自动关联

- 增强 `goal_tracker.py`
- 增强 `snapshot_hook.py`
- 测试自动关联流程

### 阶段 7: 完善和优化

**目标**: 完善功能，优化体验

- 实现 AI 任务分解
- 实现完成总结生成
- 实现 TodoDetailView
- 实现 GlobalTaskView
- 性能优化
- 文档完善

---

## 附录 A: 验收标准

### MVP 验收标准

1. **数据模型**
   - 可以创建、读取、更新、删除全局任务
   - 可以创建、读取、更新、删除 Todos（支持层级）
   - Session 可以关联到 Todo

2. **MCP Server**
   - Claude Code 可以调用 `list_todos` 获取项目 Todos
   - Claude Code 可以调用 `start_todo` 开始执行
   - Claude Code 可以调用 `complete_todo` 完成 Todo
   - Claude Code 可以调用 `split_todo` 拆分 Todo

3. **CLI**
   - 可以通过命令行创建全局任务
   - 可以通过命令行创建/列出/更新 Todos
   - 可以启动/停止 MCP Server

4. **Workflow Engine**
   - 可以解析和执行 YAML 工作流
   - 支持 Python/Shell/Claude Agent 三种 Hook 类型
   - Hook 在子进程中隔离执行

5. **Swift UI**
   - TaskCenter 可以显示 Todos 列表
   - TaskCenter 可以显示工作流状态
   - 可以按项目/状态筛选 Todos

6. **自动关联**
   - Session 开始时可以检测相关 Todos
   - Session 完成时可以更新 Todo 状态

---

## 附录 B: 配置文件路径

| 路径 | 说明 |
|------|------|
| `~/.claude-task-tracker/tasks.db` | SQLite 数据库 |
| `~/.claude-task-tracker/config.json` | 配置文件 |
| `~/.claude-task-tracker/workflows/` | 用户自定义工作流 |
| `~/.claude-task-tracker/cache/` | 缓存目录 |
| `~/.mcp.json` | MCP Server 配置 |

---

## 附录 C: 关键文件清单

| 文件路径 | 操作 | 说明 |
|---------|------|------|
| `python/task_tracker/services/database.py` | 修改 | 添加新表 schema |
| `python/task_tracker/services/todo_service.py` | 新建 | Todo 服务核心 |
| `python/task_tracker/workflow/engine.py` | 新建 | 工作流引擎 |
| `python/task_tracker/workflow/hooks.py` | 新建 | Hook 管理器 |
| `python/task_tracker/workflow/claude_agent.py` | 新建 | Claude Agent 封装 |
| `python/task_tracker/mcp/server.py` | 新建 | MCP Server 主入口 |
| `python/task_tracker/mcp/tools.py` | 新建 | MCP 工具实现 |
| `python/task_tracker/cli/todo_cli.py` | 新建 | CLI 入口 |
| `python/task_tracker/hooks/goal_tracker.py` | 修改 | 增加 Todo 感知 |
| `python/task_tracker/hooks/snapshot_hook.py` | 修改 | 增加完成处理 |
| `swift/Services/DatabaseModels.swift` | 修改 | 新增数据模型 |
| `swift/Services/TodoDatabaseManager.swift` | 新建 | Todo 查询 |
| `swift/UI/Todo/TodoListView.swift` | 新建 | Todo 列表 UI |
| `swift/UI/Workflow/WorkflowStatusView.swift` | 新建 | 工作流状态 UI |
| `install.sh` | 修改 | MCP Server 安装 |
