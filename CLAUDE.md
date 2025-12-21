# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Claude Monitor is a macOS native application that provides desktop notifications and session management for Claude Code. It consists of a Swift app for notifications/window restoration and Python hooks that integrate with Claude Code's hook system.

## Build Commands

```bash
# Build Swift application
swiftc \
  swift/Logger.swift \
  swift/PermissionManager.swift \
  swift/AppDelegate.swift \
  swift/SettingsWindow.swift \
  swift/Main.swift \
  -o ClaudeMonitor \
  -target arm64-apple-macosx12.0

# Full installation (interactive)
./install.sh

# Uninstall
./uninstall_monitor.sh
```

## Testing

```bash
# Test notification
~/Applications/ClaudeMonitor.app/Contents/MacOS/ClaudeMonitor notify "Title" "Message"

# Test window detection
~/Applications/ClaudeMonitor.app/Contents/MacOS/ClaudeMonitor detect

# Open settings GUI
~/Applications/ClaudeMonitor.app/Contents/MacOS/ClaudeMonitor gui

# View logs
tail -f ~/.claude-hooks/swift_debug.log
tail -f ~/.claude-hooks/python_debug.log
tail -f ~/.claude-hooks/task_tracker/logs/task-tracker.log
```

## Architecture

### Three-Layer System

1. **Swift App** (`swift/`) - macOS native app handling:
   - Window detection via CGWindowID/PID/BundleID
   - System notifications via UserNotifications.framework
   - Window restoration via Accessibility API
   - Four run modes: `detect`, `notify`, `gui`, `default`

2. **Python Hooks** (`python/`) - Claude Code hook handlers:
   - Core: `notification_hook.py`, `stop_hook.py`
   - Task Tracker (optional): `task_tracker/hooks/` for progress tracking, goal capture, session snapshots

3. **Shell Integration** - Generated `~/.claude-hooks/config.sh`:
   - Aliases (`c`, `cw`) wrapping `claude` command
   - Window info capture before Claude launch
   - API profile switching via `--api` flag

### Data Flow

```
User alias (c/cw) → Shell wrapper captures window info → Claude Code runs
                                                              ↓
                                              Hook events trigger Python scripts
                                                              ↓
                                              Python calls ClaudeMonitor notify
                                                              ↓
                                              User clicks notification → Window restored
```

### Key Environment Variables (set by shell wrapper)

- `CLAUDE_TERM_BUNDLE_ID` - Terminal app bundle ID
- `CLAUDE_TERM_PID` - Terminal process ID
- `CLAUDE_CG_WINDOW_ID` - CoreGraphics window ID
- `CLAUDE_CONFIG_DIR` - Claude Code config directory
- `CLAUDE_ACCOUNT_ALIAS` - Current account alias

### Hook Events Used

| Event | Handler | Purpose |
|-------|---------|---------|
| `Notification` | notification_hook.py / notification_tracker.py | Send desktop notifications |
| `Stop` | stop_hook.py / snapshot_hook.py | Rate limit detection, session snapshots |
| `UserPromptSubmit` | goal_tracker.py | Capture user goals (Task Tracker) |
| `PostToolUse` | progress_tracker.py | Track TodoWrite/AskUserQuestion (Task Tracker) |

### Installation Paths

- App: `~/Applications/ClaudeMonitor.app/`
- Scripts: `~/.claude-hooks/`
- Task Tracker data: `~/.claude-hooks/task_tracker/`
- Database: `~/.claude-hooks/task_tracker/tasks.db`

## Swift File Compilation Order

Files must be compiled in dependency order:
1. `Logger.swift` - No dependencies
2. `PermissionManager.swift` - Depends on Logger
3. `AppDelegate.swift` - Depends on Logger, PermissionManager
4. `SettingsWindow.swift` - Depends on Logger, PermissionManager
5. `Main.swift` - Entry point, depends on all above
