# Claude Monitor

macOS 桌面通知系统，为 [Claude Code](https://claude.ai/code) 提供实时通知和窗口恢复功能。

## 功能

- **桌面通知**：Claude Code 需要响应时（idle、权限请求等）发送通知
- **窗口恢复**：点击通知自动将终端窗口带到前台
- **多账户支持**：通过别名管理多个 Claude Code 配置（`c`, `cw` 等）
- **进度追踪**：通知中显示任务进度条
- **Rate Limit 检测**：API 限流时自动通知

## 安装

```bash
git clone <repository-url>
cd claude-notification
./install.sh
```

安装后重新加载 shell：

```bash
source ~/.zshrc
```

### 快速更新

```bash
./install.sh -p    # 仅更新 Python hooks
./install.sh -a    # 仅重新编译 Swift 应用
```

## 使用

```bash
c                  # 启动 Claude Code
claude-ac list     # 查看账户列表
claude-api list    # 查看 API 配置
```

### 调试

```bash
# 查看日志
tail -f ~/.claude-task-tracker/logs/hooks.log

# 打开设置
~/Applications/ClaudeMonitor.app/Contents/MacOS/ClaudeMonitor gui
```

## 项目结构

```
├── swift/                      # macOS 原生应用
├── python/task_tracker/
│   ├── cli/                    # CLI 工具 (api_manager, account_manager)
│   ├── hooks/                  # Hook 脚本 (goal, progress, notification, snapshot)
│   └── services/               # 服务模块 (database, notification, summary)
├── scripts/                    # 辅助脚本
├── assets/                     # 图标资源
└── docs/                       # 文档
```

## 数据路径

| 类型 | 路径 |
|------|------|
| 应用 | `~/Applications/ClaudeMonitor.app/` |
| 脚本 | `~/.claude-hooks/task_tracker/` |
| 数据库 | `~/.claude-task-tracker/tasks.db` |
| 日志 | `~/.claude-task-tracker/logs/` |
| 配置 | `~/.claude-task-tracker/config.json` |

## 故障排除

**通知不显示**：运行 `ClaudeMonitor gui` 检查通知权限

**窗口不恢复**：检查 系统设置 > 隐私与安全 > 自动化 中的权限

**应用损坏**：运行 `xattr -cr ~/Applications/ClaudeMonitor.app`

## 开发

```bash
# 编译
swiftc swift/Logger.swift swift/PermissionManager.swift \
  swift/AppDelegate.swift swift/SettingsWindow.swift swift/Main.swift \
  -o ClaudeMonitor -target arm64-apple-macosx12.0
```

## License

MIT License
