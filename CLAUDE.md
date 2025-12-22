# CLAUDE.md

本文件为 Claude Code 提供项目开发指南。

## 项目概述

Claude Monitor 是一个 macOS 原生应用，为 Claude Code 提供桌面通知和会话管理功能。目标是实现**人机协同通知系统**，让用户在 Claude 工作时能够在适当时机收到有意义的通知，以便及时响应。

## 架构设计

### 核心理念

**统一的 Task Tracker 系统**，支持两种运行模式：
- **Raw 模式**（无 AI）：直接显示用户 prompt + AI 需要协助的问题
- **Summary 模式**（有 AI）：使用第三方 API 生成智能总结

### 三层架构

```
┌─────────────────────────────────────────────────┐
│         Claude Code Hook 事件                    │
│  (UserPromptSubmit, PostToolUse, Notification,   │
│   Stop)                                          │
└──────────────────────┬──────────────────────────┘
                       │
                       v
┌─────────────────────────────────────────────────┐
│         Python Task Tracker 系统                 │
│  (hooks/ + services/)                           │
└──────────────────────┬──────────────────────────┘
                       │
                       v
┌─────────────────────────────────────────────────┐
│         Swift 原生应用                           │
│  (通知显示 + 窗口恢复)                           │
└─────────────────────────────────────────────────┘
```

### 目录结构

```
/
├── install.sh                # 主安装脚本
├── uninstall_monitor.sh      # 卸载脚本
├── CLAUDE.md                 # 项目开发指南
├── README.md                 # 用户文档
├── LICENSE
│
├── scripts/                  # 辅助脚本
│   ├── account_wizard.sh     # 账户设置向导
│   └── test_sounds.sh        # 声音测试
│
├── assets/                   # 资源文件
│   ├── app_icon.png          # 应用图标源文件
│   ├── AppIcon.icns          # macOS 图标
│   └── AppIcon.iconset/      # 图标集
│
├── docs/                     # 文档
│   ├── architecture.md
│   ├── design-notes.md
│   └── ui-design-v2.md
│
├── python/
│   └── task_tracker/         # Task Tracker 模块
│       ├── cli/              # CLI 工具
│       │   ├── api_manager.py        # API 配置管理
│       │   └── account_manager.py    # 多账户管理
│       ├── hooks/            # Hook 脚本
│       │   ├── utils.py              # 公共工具函数
│       │   ├── goal_tracker.py       # UserPromptSubmit
│       │   ├── progress_tracker.py   # PostToolUse
│       │   ├── notification_tracker.py # Notification
│       │   └── snapshot_hook.py      # Stop
│       └── services/         # 服务模块
│           ├── database.py           # SQLite 状态存储
│           ├── summary_service.py    # AI 总结服务
│           ├── notification.py       # 通知发送
│           └── notification_formatter.py # 通知格式化
│
└── swift/                    # Swift 原生应用
    ├── Logger.swift
    ├── PermissionManager.swift
    ├── AppDelegate.swift
    ├── SettingsWindow.swift
    └── Main.swift
```

## Hook 事件处理

| 事件 | 处理脚本 | 功能 |
|------|---------|------|
| `UserPromptSubmit` | goal_tracker.py | 捕获用户目标，创建会话 |
| `PostToolUse` | progress_tracker.py | 追踪 TodoWrite/AskUserQuestion |
| `Notification` | notification_tracker.py | 发送桌面通知（idle/permission/elicitation） |
| `Stop` | snapshot_hook.py | 生成快照 + rate limit 检测 |

## 两种运行模式

通过 `~/.claude-task-tracker/config.json` 控制：

### Raw 模式（默认，无 AI）
```json
{
  "summary": {
    "provider": "disabled",
    "disabled": true
  }
}
```
- 通知直接显示用户的原始 prompt
- 显示 AI 需要用户协助的问题
- 无外部 API 依赖

### Summary 模式（有 AI）
```json
{
  "summary": {
    "provider": "third_party",
    "third_party": {
      "enabled": true,
      "base_url": "https://api.openai.com/v1",
      "api_key": "sk-...",
      "model": "gpt-3.5-turbo"
    }
  }
}
```
- 使用第三方 API 生成智能总结
- 通知显示精炼的任务状态
- 需要配置 API

## 构建命令

```bash
# 编译 Swift 应用
swiftc \
  swift/Logger.swift \
  swift/PermissionManager.swift \
  swift/AppDelegate.swift \
  swift/SettingsWindow.swift \
  swift/Main.swift \
  -o ClaudeMonitor \
  -target arm64-apple-macosx12.0

# 完整安装（交互式）
./install.sh

# 卸载
./uninstall_monitor.sh
```

## 测试命令

```bash
# 测试通知
~/Applications/ClaudeMonitor.app/Contents/MacOS/ClaudeMonitor notify "标题" "内容"

# 测试窗口检测
~/Applications/ClaudeMonitor.app/Contents/MacOS/ClaudeMonitor detect

# 打开设置界面
~/Applications/ClaudeMonitor.app/Contents/MacOS/ClaudeMonitor gui

# 查看日志
tail -f ~/.claude-hooks/task_tracker/logs/task-tracker.log
```

## 数据流

```
用户运行别名 (c/cw)
        ↓
Shell 包装器捕获窗口信息（Bundle ID, PID, Window ID）
        ↓
Claude Code 运行
        ↓
Hook 事件触发 Python 脚本
        ↓
Python 调用 ClaudeMonitor 发送通知
        ↓
用户点击通知 → 窗口恢复到前台
```

## 环境变量

由 Shell 包装器设置：
- `CLAUDE_TERM_BUNDLE_ID` - 终端应用 Bundle ID
- `CLAUDE_TERM_PID` - 终端进程 ID
- `CLAUDE_CG_WINDOW_ID` - CoreGraphics 窗口 ID
- `CLAUDE_CONFIG_DIR` - Claude Code 配置目录
- `CLAUDE_ACCOUNT_ALIAS` - 当前账户别名

## 安装路径

- 应用: `~/Applications/ClaudeMonitor.app/`
- 脚本: `~/.claude-hooks/task_tracker/`
- 数据库: `~/.claude-task-tracker/tasks.db`
- 配置: `~/.claude-task-tracker/config.json`

## Swift 文件编译顺序

必须按依赖顺序编译：
1. `Logger.swift` - 无依赖
2. `PermissionManager.swift` - 依赖 Logger
3. `AppDelegate.swift` - 依赖 Logger, PermissionManager
4. `SettingsWindow.swift` - 依赖 Logger, PermissionManager
5. `Main.swift` - 入口点，依赖以上所有

## 代码规范

### Python 代码规范

1. **导入语句**
   - 所有导入必须放在文件顶部
   - 按标准库、第三方库、本地模块顺序分组
   - 禁止在函数内部导入（除非有特殊原因）

2. **路径处理**
   - 统一使用 `pathlib.Path`，不使用 `os.path`
   - 使用 `Path.home()` 而非 `os.path.expanduser("~")`

3. **日志记录**
   - 使用 `hooks/utils.py` 中的统一 `log()` 函数
   - 通过 `log_file` 参数指定不同的日志文件

4. **环境变量**
   - 使用 `hooks/utils.py` 中的 `get_env_info()` 和 `get_account_alias()`
   - 不要在多处重复获取环境变量的逻辑

5. **错误处理**
   - 使用具体的异常类型，避免裸 `except:`
   - 记录错误日志时包含异常信息

### 目录组织规范

1. **根目录**
   - 只保留主要脚本（install.sh, uninstall_monitor.sh）和文档
   - 编译产物（如 ClaudeMonitor 二进制）不提交到 git

2. **资源文件**
   - 图标、图片等资源放在 `assets/` 目录
   - 辅助脚本放在 `scripts/` 目录

3. **Python 模块**
   - CLI 工具放在 `task_tracker/cli/`
   - Hook 脚本放在 `task_tracker/hooks/`
   - 服务模块放在 `task_tracker/services/`
   - 公共工具函数放在 `hooks/utils.py`

### 代码整洁原则

1. **避免代码重复**
   - 相同功能的代码应抽取到公共模块
   - 使用参数化而非复制粘贴

2. **保持文件职责单一**
   - 每个文件应有明确的单一职责
   - 避免在一个文件中混合多种不相关的功能

3. **及时清理**
   - 删除不再使用的代码和文件
   - 更新文档以反映代码变更

