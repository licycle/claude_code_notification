# Claude Monitor - 系统架构文档

> 本文档描述 Claude Monitor 的完整系统架构，包括核心通知系统和可选的 Task Tracker 模块。

---

## 1. 系统概览

Claude Monitor 是一个 macOS 原生应用，为 Claude Code 提供桌面通知和会话管理功能。

### 1.1 核心功能

| 模块 | 功能 | 状态 |
|------|------|------|
| **Core** | 桌面通知 + 窗口恢复 | 已实现 |
| **Task Tracker** | 任务追踪 + 进度通知 | 已实现 |
| **Menu Bar UI** | 任务面板 + 快速切换 | 规划中 |

### 1.2 系统架构图

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           Claude Code 会话                                   │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │  用户启动 Claude Code (通过 alias: c, cw, etc.)                      │   │
│  │                              │                                       │   │
│  │                              ▼                                       │   │
│  │  ┌─────────────────────────────────────────────────────────────┐   │   │
│  │  │              Shell Wrapper (config.sh)                       │   │   │
│  │  │  1. 调用 ClaudeMonitor detect 获取当前窗口信息                │   │   │
│  │  │  2. 设置环境变量 CLAUDE_MONITOR_*                            │   │   │
│  │  │  3. 启动 claude 命令                                         │   │   │
│  │  └─────────────────────────────────────────────────────────────┘   │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                    │                                        │
│                                    ▼                                        │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                    Claude Code Hooks 系统                            │   │
│  │  ┌───────────────┐  ┌───────────────┐  ┌───────────────┐           │   │
│  │  │UserPromptSubmit│  │ PostToolUse  │  │  Notification │           │   │
│  │  │ (Task Tracker) │  │(Task Tracker)│  │   (Core)      │           │   │
│  │  └───────┬───────┘  └───────┬───────┘  └───────┬───────┘           │   │
│  │          │                  │                  │                    │   │
│  │          │    ┌─────────────┴─────────────┐    │                    │   │
│  │          │    │         Stop Hook         │────┤                    │   │
│  │          │    │   (Core + Task Tracker)   │    │                    │   │
│  │          │    └───────────────────────────┘    │                    │   │
│  └──────────┼──────────────┼─────────────────────┼────────────────────┘   │
└─────────────┼──────────────┼─────────────────────┼────────────────────────┘
              │              │                     │
              ▼              ▼                     ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                          Python Hook 脚本层                                  │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │  Core Hooks                    │  Task Tracker Hooks                │   │
│  │  • notification_hook.py        │  • goal_tracker.py                 │   │
│  │  • stop_hook.py                │  • progress_tracker.py             │   │
│  │                                │  • notification_tracker.py         │   │
│  │                                │  • snapshot_hook.py                │   │
│  └────────────────────────────────┴────────────────────────────────────┘   │
│                                    │                                        │
│                                    ▼                                        │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                    Task Tracker Services                             │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                 │   │
│  │  │  database   │  │  summary    │  │notification │                 │   │
│  │  │  (SQLite)   │  │  service    │  │  service    │                 │   │
│  │  └─────────────┘  └─────────────┘  └─────────────┘                 │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
                                     │
                                     ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                      ClaudeMonitor Swift App                                 │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │  运行模式:                                                           │   │
│  │  • detect  - 检测当前窗口 (输出 bundleID|PID|CGWindowID)            │   │
│  │  • notify  - 发送系统通知                                           │   │
│  │  • gui     - 显示设置窗口                                           │   │
│  │  • default - 后台运行，处理通知点击                                  │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                    │                                        │
│                                    ▼                                        │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                    macOS 系统通知                                    │   │
│  │  • 显示通知 Banner                                                  │   │
│  │  • 用户点击 → 激活目标窗口                                          │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 2. 目录结构

```
claude-notification/
├── swift/                          # Swift macOS 应用
│   ├── Main.swift                  # 应用入口，多模式支持
│   ├── AppDelegate.swift           # 通知处理 + 窗口激活
│   ├── SettingsWindow.swift        # 设置界面
│   ├── PermissionManager.swift     # macOS 权限管理
│   └── Logger.swift                # 日志工具
│
├── python/                         # Python 脚本
│   ├── hook.py                     # Hook 基础功能
│   ├── notification_hook.py        # 基础通知 Hook
│   ├── stop_hook.py                # 停止事件 Hook
│   ├── api_manager.py              # API 配置管理
│   ├── account_manager.py          # 账户管理
│   │
│   └── task_tracker/               # Task Tracker 模块
│       ├── __init__.py
│       ├── hooks.json              # Hook 配置
│       ├── config.template.json    # 配置模板
│       │
│       ├── hooks/                  # Hook 脚本
│       │   ├── utils.py            # 通用工具
│       │   ├── goal_tracker.py     # 目标追踪
│       │   ├── progress_tracker.py # 进度追踪
│       │   ├── notification_tracker.py # 通知追踪
│       │   └── snapshot_hook.py    # 状态快照
│       │
│       └── services/               # 服务模块
│           ├── database.py         # SQLite 数据库
│           ├── notification.py     # 通知服务
│           └── summary_service.py  # AI 总结服务
│
├── docs/                           # 文档
│   ├── architecture.md             # 本文档
│   └── design-notes.md             # 设计说明
│
├── install.sh                      # 安装脚本
├── uninstall_monitor.sh            # 卸载脚本
├── account_wizard.sh               # 账户配置向导
└── README.md                       # 项目说明
```

---

## 3. 核心组件详解

### 3.1 Swift 应用 (ClaudeMonitor)

Swift 应用是系统的核心，负责窗口检测、通知发送和窗口恢复。

| 文件 | 职责 |
|------|------|
| `swift/Main.swift` | 应用入口，支持 detect/notify/gui/default 四种模式 |
| `swift/AppDelegate.swift` | 处理通知点击，使用 Accessibility API 恢复窗口 |
| `swift/SettingsWindow.swift` | SwiftUI 设置界面，权限检查和测试 |
| `swift/PermissionManager.swift` | 检查和请求 macOS 权限 |
| `swift/Logger.swift` | 统一日志输出 |

#### 运行模式

```bash
# 检测当前窗口 (Shell Wrapper 调用)
ClaudeMonitor detect
# 输出: com.apple.Terminal|12345|67890

# 发送通知 (Python Hook 调用)
ClaudeMonitor notify "标题" "内容" "Crystal" "com.apple.Terminal" "12345" "67890"

# 显示设置窗口
ClaudeMonitor gui

# 默认模式 (后台运行)
ClaudeMonitor
```

### 3.2 Python Hook 脚本

#### Core Hooks

| 文件 | Hook 事件 | 功能 |
|------|-----------|------|
| `python/notification_hook.py` | Notification | 基础通知处理 |
| `python/stop_hook.py` | Stop | 检测 Rate Limit |

#### Task Tracker Hooks

| 文件 | Hook 事件 | 功能 |
|------|-----------|------|
| `python/task_tracker/hooks/goal_tracker.py` | UserPromptSubmit | 记录用户原始目标 |
| `python/task_tracker/hooks/progress_tracker.py` | PostToolUse | 追踪 TodoWrite/AskUserQuestion |
| `python/task_tracker/hooks/notification_tracker.py` | Notification | 检测等待状态 |
| `python/task_tracker/hooks/snapshot_hook.py` | Stop | 生成状态快照和总结 |

### 3.3 Task Tracker Services

| 文件 | 职责 |
|------|------|
| `python/task_tracker/services/database.py` | SQLite 数据库操作，存储会话/进度/快照 |
| `python/task_tracker/services/notification.py` | 富通知服务，支持进度条和状态信息 |
| `python/task_tracker/services/summary_service.py` | AI 总结服务，支持多种 Provider |

---

## 4. 数据存储

### 4.1 文件位置

```
~/.claude-hooks/                    # Core 配置
├── config.sh                       # Shell 配置 (aliases)
├── notification_hook.py            # 符号链接
├── stop_hook.py                    # 符号链接
├── swift_debug.log                 # Swift 日志
└── python_debug.log                # Python 日志

~/.claude-task-tracker/             # Task Tracker 数据
├── config.json                     # 配置文件
├── tasks.db                        # SQLite 数据库
├── hooks/                          # Hook 脚本 (符号链接)
├── services/                       # 服务模块 (符号链接)
├── logs/                           # 日志目录
└── state/                          # 状态文件
    └── current-sessions.json       # 当前会话状态
```

### 4.2 数据库 Schema

数据库定义见: `python/task_tracker/services/database.py`

| 表名 | 用途 |
|------|------|
| `sessions` | 任务会话 (session_id, project, original_goal, status) |
| `goal_evolution` | 目标演进历史 |
| `progress` | 进度记录 (todos_json, completed_count, total_count) |
| `pending_decisions` | 待决事项 (question, options, resolved) |
| `snapshots` | 状态快照 (last_user_message, summary_json) |
| `timeline` | 事件时间线 |

### 4.3 配置文件

配置模板见: `python/task_tracker/config.template.json`

```json
{
  "summary": {
    "provider": "auto",           // auto | third_party | claude_session | extraction_only
    "third_party": {
      "enabled": false,
      "base_url": "https://api.deepseek.com/v1",
      "api_key": "",
      "model": "deepseek-chat"
    },
    "claude_session": {
      "model": "haiku"
    },
    "extraction_only": {
      "enabled": false
    }
  },
  "notification": {
    "enabled": true,
    "sound": true
  }
}
```

---

## 5. Hook 配置

### 5.1 Core Hooks

在 Claude Code settings.json 中配置:

```json
{
  "hooks": {
    "Notification": [{
      "matcher": "idle_prompt|permission_prompt|elicitation_dialog",
      "hooks": [{
        "type": "command",
        "command": "~/.claude-hooks/notification_hook.py",
        "timeout": 10
      }]
    }],
    "Stop": [{
      "hooks": [{
        "type": "command",
        "command": "~/.claude-hooks/stop_hook.py",
        "timeout": 10
      }]
    }]
  }
}
```

### 5.2 Task Tracker Hooks

完整配置见: `python/task_tracker/hooks.json`

```json
{
  "hooks": {
    "UserPromptSubmit": [{
      "hooks": [{
        "type": "command",
        "command": "python3 ~/.claude-task-tracker/hooks/goal_tracker.py",
        "timeout": 5
      }]
    }],
    "PostToolUse": [{
      "matcher": "TodoWrite|AskUserQuestion",
      "hooks": [{
        "type": "command",
        "command": "python3 ~/.claude-task-tracker/hooks/progress_tracker.py",
        "timeout": 5
      }]
    }],
    "Notification": [{
      "matcher": "idle_prompt|elicitation_dialog|permission_prompt",
      "hooks": [{
        "type": "command",
        "command": "python3 ~/.claude-task-tracker/hooks/notification_tracker.py",
        "timeout": 5
      }]
    }],
    "Stop": [{
      "hooks": [{
        "type": "command",
        "command": "python3 ~/.claude-task-tracker/hooks/snapshot_hook.py",
        "timeout": 30
      }]
    }]
  }
}
```

---

## 6. 数据流

### 6.1 通知流程

```
Claude Code 触发 Notification Hook
         │
         ▼
Python Hook 读取环境变量
(CLAUDE_MONITOR_BUNDLE, CLAUDE_MONITOR_PID, CLAUDE_MONITOR_WINDOW)
         │
         ▼
调用 ClaudeMonitor notify <title> <message> <sound> <bundle> <pid> <windowID>
         │
         ▼
Swift App 发送 UNNotification
         │
         ▼
用户点击通知
         │
         ▼
AppDelegate.userNotificationCenter(didReceive:)
         │
         ▼
activateAppByPID() → Accessibility API → 恢复窗口
```

### 6.2 Task Tracker 数据流

```
UserPromptSubmit Hook
         │
         ▼
goal_tracker.py → 记录原始目标 → SQLite sessions 表
         │
         ▼
PostToolUse Hook (TodoWrite)
         │
         ▼
progress_tracker.py → 更新进度 → SQLite progress 表
         │
         ▼
Stop Hook
         │
         ▼
snapshot_hook.py → 解析 transcript → 生成总结 → SQLite snapshots 表
         │
         ▼
notification.py → 发送富通知 (含进度信息)
```

---

## 7. 开发指南

### 7.1 构建 Swift 应用

```bash
swiftc \
  swift/Logger.swift \
  swift/PermissionManager.swift \
  swift/AppDelegate.swift \
  swift/SettingsWindow.swift \
  swift/Main.swift \
  -o ClaudeMonitor \
  -target arm64-apple-macosx12.0
```

### 7.2 调试

```bash
# Swift 日志
tail -f ~/.claude-hooks/swift_debug.log

# Python 日志
tail -f ~/.claude-hooks/python_debug.log

# Task Tracker 日志
tail -f ~/.claude-task-tracker/logs/task-tracker.log
```

### 7.3 测试通知

```bash
# 测试基础通知
~/Applications/ClaudeMonitor.app/Contents/MacOS/ClaudeMonitor notify "测试" "这是测试消息"

# 打开设置界面测试
~/Applications/ClaudeMonitor.app/Contents/MacOS/ClaudeMonitor gui
```

---

## 8. 权限要求

| 权限 | 用途 | 设置位置 |
|------|------|----------|
| Notifications | 显示桌面通知 | 系统偏好设置 > 通知 |
| Automation | 控制 System Events | 系统偏好设置 > 隐私与安全 > 自动化 |
| Accessibility | 窗口操作 (可选) | 系统偏好设置 > 隐私与安全 > 辅助功能 |

---

## 9. 相关文档

- [设计说明](./design-notes.md) - 设计决策和未来规划
- [README](../README.md) - 快速入门和使用说明
