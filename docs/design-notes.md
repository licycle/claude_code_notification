# Claude Monitor - 设计说明

> 本文档记录设计决策、技术调研结果和未来规划。

---

## 1. 设计目标

### 1.1 核心需求

用户在使用 Claude Code 处理多个并行任务时，需要：

1. **即时通知** - Claude 空闲/等待时主动提醒
2. **窗口恢复** - 点击通知快速切换到对应终端
3. **进度追踪** - 了解任务完成情况
4. **上下文同步** - 快速了解当前任务状态

### 1.2 与 claude-mem 的区别

| 维度 | claude-mem | Claude Monitor |
|------|-----------|----------------|
| **核心目标** | 跨会话记忆持久化 | 多任务实时协作 |
| **关注点** | 记住做过什么 | 知道现在要做什么 |
| **用户场景** | 回忆历史上下文 | 快速切换任务上下文 |
| **数据重点** | 压缩历史观察 | 实时任务状态 |

---

## 2. Claude Code Hooks 机制

### 2.1 支持的 Hook 事件

| Hook 事件 | 触发时机 | 我们的用途 |
|-----------|----------|-----------|
| `SessionStart` | 打开/恢复会话 | (未使用) |
| `UserPromptSubmit` | 用户提交 prompt | 记录原始目标 |
| `PreToolUse` | 工具执行前 | (未使用) |
| `PostToolUse` | 工具执行后 | 追踪 TodoWrite/AskUserQuestion |
| `Notification` | 通知事件 | 检测 idle/permission/elicitation |
| `Stop` | Claude 空闲 | 生成快照 + 发送通知 |
| `SessionEnd` | 会话关闭 | (未使用) |

### 2.2 Hook 输入数据结构

#### UserPromptSubmit

```json
{
  "session_id": "abc123",
  "transcript_path": "/Users/.../.claude/projects/.../uuid.jsonl",
  "cwd": "/Users/...",
  "hook_event_name": "UserPromptSubmit",
  "prompt": "用户提交的 prompt 文本"
}
```

#### PostToolUse

```json
{
  "session_id": "abc123",
  "transcript_path": "/Users/.../.claude/projects/.../uuid.jsonl",
  "hook_event_name": "PostToolUse",
  "tool_name": "TodoWrite|AskUserQuestion|...",
  "tool_input": { /* 工具输入参数 */ },
  "tool_response": { /* 工具执行结果 */ }
}
```

#### Notification

```json
{
  "session_id": "abc123",
  "hook_event_name": "Notification",
  "message": "Claude needs your permission...",
  "notification_type": "permission_prompt|idle_prompt|elicitation_dialog"
}
```

#### Stop

```json
{
  "session_id": "abc123",
  "transcript_path": "/Users/.../.claude/projects/.../uuid.jsonl",
  "hook_event_name": "Stop",
  "stop_hook_active": true
}
```

### 2.3 Hook 输出格式

```json
{
  "continue": true,           // 是否继续执行
  "suppressOutput": true,     // 是否抑制输出
  "systemMessage": "...",     // 注入系统消息 (可选)
  "stopReason": "..."         // 停止原因 (continue=false 时)
}
```

### 2.4 环境变量

| 变量 | 说明 |
|------|------|
| `CLAUDE_PROJECT_DIR` | 项目根目录绝对路径 |
| `CLAUDE_CODE_REMOTE` | 是否远程环境 |

### 2.5 Transcript 文件格式

Transcript 文件为 JSONL 格式，每行一个 JSON 对象：

```jsonl
{"type": "user", "message": {"content": "用户消息内容"}}
{"type": "assistant", "message": {"content": "助手回复内容"}}
{"type": "tool_use", "tool_name": "Read", "tool_input": {...}, "tool_response": {...}}
```

---

## 3. 设计决策

### 3.1 窗口恢复机制

**问题**: 用户点击通知后，需要恢复到正确的终端窗口。

**方案**: 三层窗口识别

1. **CGWindowID** - 最精确，可定位到具体窗口
2. **PID** - 进程级别，可定位到应用
3. **Bundle ID** - 应用级别，作为兜底

**实现**:
- Shell Wrapper 在启动 Claude 前调用 `ClaudeMonitor detect`
- 获取 `bundleID|PID|CGWindowID` 并存入环境变量
- 通知点击时使用 Accessibility API 恢复窗口

### 3.2 Summary Service Provider 选择

**问题**: 生成任务总结需要 AI，但不想强制消耗用户配额。

**方案**: 三种 Provider 可选

| Provider | 优点 | 缺点 |
|----------|------|------|
| `third_party` | 不消耗 Claude 配额 | 需要额外 API Key |
| `claude_session` | 无需配置 | 消耗订阅配额 |
| `extraction_only` | 零成本 | 无 AI 总结能力 |

**支持的第三方 API**:
- DeepSeek: `https://api.deepseek.com/v1`
- OpenRouter: `https://openrouter.ai/api/v1`
- Groq: `https://api.groq.com/openai/v1`
- 本地 Ollama: `http://localhost:11434/v1`

### 3.3 通知分类

**实现**: 使用 `UNNotificationCategory` 支持不同类型的通知

| Category | 场景 | 操作按钮 |
|----------|------|----------|
| `TASK_STATUS` | 任务空闲 | 跳转、稍后处理 |
| `DECISION_NEEDED` | 需要决策 | 跳转、查看详情、稍后处理 |
| `PERMISSION_NEEDED` | 权限确认 | 跳转、稍后处理 |

---

## 4. 未来规划

### 4.1 Menu Bar 任务面板 (P1)

**目标**: 在 Menu Bar 显示任务列表，支持快速切换。

**设计**:

```
┌──────────────────────────────────────────────────────────────────────┐
│                         Menu Bar                                      │
│  [WiFi] [Battery] [🔵 3] [Spotlight] [Control Center]                │
│                      ↑                                                │
│              ClaudeMonitor 图标 (显示活跃任务数)                       │
└────────────────────┬─────────────────────────────────────────────────┘
                     │
                     ▼ 点击展开
┌──────────────────────────────────────────────────────────────────────┐
│                    Popover 任务面板                                   │
│  ┌────────────────────────────────────────────────────────────────┐  │
│  │ 🔴 重构认证模块                              [等待决策] 3/5    │  │
│  │    目标: 重构用户认证模块，支持 OAuth2                         │  │
│  │    ⚠️ 需要决定: 使用哪个 OAuth 库？                            │  │
│  ├────────────────────────────────────────────────────────────────┤  │
│  │ 🟢 修复登录 Bug                              [工作中] 2/4      │  │
│  │    目标: 修复登录页面的内存泄漏                                │  │
│  ├────────────────────────────────────────────────────────────────┤  │
│  │ 🟡 添加头像功能                              [空闲] 5/5 ✓      │  │
│  │    目标: 添加用户头像上传功能                                  │  │
│  └────────────────────────────────────────────────────────────────┘  │
│  [设置 ⚙️]                                      [清理已完成]         │
└───────────────────────────────────────────────────────────────────────┘
```

**状态颜色**:
- 🔴 红色: 等待用户决策/权限
- 🟢 绿色: 工作中
- 🟡 黄色: 空闲
- ⚪ 灰色: 已完成

**实现要点**:
- 使用 `NSStatusItem` 创建 Menu Bar 图标
- 使用 `NSPopover` 显示任务列表
- 监听 SQLite 数据库变化 (FSEvents)
- 点击任务跳转到对应终端

### 4.2 HUD 浮窗 (P2)

**目标**: 全局快捷键触发，快速查看任务状态。

**设计**:
- 屏幕中央显示半透明 HUD
- 显示所有活跃任务
- 几秒后自动消失
- 快捷键: `Cmd + Shift + T`

### 4.3 桌面 Widget (P3)

**目标**: 永久可见的任务状态。

**要求**: macOS 11+

---

## 5. 任务状态模型

### 5.1 状态定义

```
working          → 正在工作
idle             → 空闲等待
waiting_for_user → 等待用户输入/决策
waiting_permission → 等待权限确认
completed        → 已完成
```

### 5.2 状态转换

```
                    ┌─────────────────────────────────────┐
                    │                                     │
                    ▼                                     │
┌─────────┐    ┌─────────┐    ┌─────────────────┐    ┌───┴─────┐
│ working │───▶│  idle   │───▶│ waiting_for_user│───▶│completed│
└────┬────┘    └────┬────┘    └────────┬────────┘    └─────────┘
     │              │                  │
     │              │                  │
     ▼              ▼                  ▼
┌────────────────────────────────────────────────────────────────┐
│                    waiting_permission                           │
└────────────────────────────────────────────────────────────────┘
```

---

## 6. 实现优先级

| 阶段 | 功能 | 状态 |
|------|------|------|
| **P0** | Core 通知 + 窗口恢复 | ✅ 已完成 |
| **P0** | Task Tracker Hooks | ✅ 已完成 |
| **P0** | SQLite 存储 | ✅ 已完成 |
| **P0** | Summary Service | ✅ 已完成 |
| **P1** | Menu Bar 任务面板 | 📋 规划中 |
| **P2** | HUD 浮窗 + 快捷键 | 📋 规划中 |
| **P3** | 桌面 Widget | 📋 规划中 |
| **P3** | 任务时间线分析 | 📋 规划中 |

---

## 7. 参考资源

### 7.1 官方文档

- [Claude Code Hooks](https://docs.anthropic.com/en/docs/claude-code/hooks)

### 7.2 参考项目

- [claude-mem](https://github.com/thedotmack/claude-mem) - Hook 机制和 Worker Service 架构参考

### 7.3 相关技术

- **Accessibility API** - 窗口操作
- **UserNotifications.framework** - macOS 通知
- **SQLite + FTS5** - 全文搜索存储
- **SwiftUI** - UI 开发

---

## 8. 相关文档

- [系统架构](./architecture.md) - 完整架构说明
- [README](../README.md) - 快速入门和使用说明
