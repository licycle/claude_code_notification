# Claude Monitor

Claude Monitor is a macOS notification and session management system for [Claude Code](https://claude.ai/code). It provides real-time desktop notifications for Claude Code events (idle prompts, permission requests, authentication, etc.) and intelligently restores your terminal window when you click on notifications.

## ✨ Features

- **Smart Notifications**: Get desktop notifications for Claude Code events even when the terminal is in the background
- **Window Restoration**: Click notifications to automatically bring your terminal back to front
- **Multi-Account Support**: Manage multiple Claude Code configurations with simple aliases (`c`, `cw`, etc.)
- **Multi-API Support**: Easily switch between different API providers (Anthropic, Kimi, Qwen, DeepSeek, etc.)
- **Session Insights**: Monitor your Claude Code sessions with detailed logging
- **Lightweight**: Minimal performance overhead, runs natively on macOS

## 🚀 Quick Start

### 1. Installation

```bash
git clone <repository-url>
cd claude-notification
./install.sh
```

The installer will:
- Build and install the ClaudeMonitor app
- Set up command aliases for your Claude Code accounts
- Configure notification hooks in Claude Code settings
- Guide you through API profile setup

### 2. Source Your Shell Configuration

After installation, reload your shell configuration:

```bash
source ~/.zshrc  # or ~/.bashrc
```

### 3. Test It

Run your default Claude Code alias:

```bash
c  # or whatever alias you configured
```

When Claude Code needs your attention (idle prompt, permission request, etc.), you'll receive a desktop notification. Click it to restore your terminal!

## 📖 Usage

### Basic Commands

```bash
# Start Claude Code with default account
c

# Start with a different account
cw  # or any other configured alias

# View all configured accounts
claude-ac list

# Add a new account
claude-ac add
```

### API Management

Claude Monitor supports switching between different API providers:

```bash
# List all configured API profiles
claude-api list

# Add a new API profile (e.g., for Kimi, Qwen, DeepSeek)
claude-api add kimi \
  ANTHROPIC_BASE_URL=https://api.moonshot.cn/v1 \
  ANTHROPIC_API_KEY=your-api-key \
  ANTHROPIC_MODEL=kimi

# Use an API profile
c --api kimi
```

### Settings and Debugging

```bash
# Open settings GUI
~/Applications/ClaudeMonitor.app/Contents/MacOS/ClaudeMonitor gui

# View logs
tail -f ~/.claude-hooks/swift_debug.log
tail -f ~/.claude-hooks/python_debug.log
```

## 🔧 Configuration

### Account Configuration

Your accounts are configured during installation and stored in `~/.claude-hooks/`. Each account has:
- **Alias**: Short command (e.g., `c`, `cw`)
- **Config Path**: Directory containing Claude Code settings

To add or modify accounts, simply run the installer again:

```bash
./install.sh
```

### API Profiles

API profiles are stored in `~/.claude-hooks/api_profiles.json`. Each profile can include:
- `ANTHROPIC_BASE_URL`: API endpoint URL
- `ANTHROPIC_API_KEY`: Your API key
- `ANTHROPIC_MODEL`: Model name
- Custom environment variables as needed

### Notification Settings

Notification hooks are automatically configured in Claude Code's `settings.json`:

```json
{
  "hooks": {
    "Notification": [
      {
        "matcher": "idle_prompt",
        "hooks": [{"type": "command", "command": "~/.claude-hooks/notification_hook.py", "timeout": 10}]
      }
    ],
    "Stop": [...]
  }
}
```

## 🏗️ Project Structure

```
claude-notification/
├── swift/                      # Swift macOS application
│   ├── Main.swift             # Application entry point
│   ├── AppDelegate.swift      # Notification handling & window activation
│   ├── SettingsWindow.swift   # Settings GUI
│   ├── PermissionManager.swift # macOS permissions handling
│   └── Logger.swift           # Logging utilities
├── python/                     # Python management scripts
│   ├── api_manager.py         # API profile management
│   ├── account_manager.py     # Account management
│   ├── hook.py               # Base hook functionality
│   ├── notification_hook.py  # Notification event handler
│   └── stop_hook.py          # Session stop handler
├── install.sh                # Main installation script
├── install_monitor.sh        # Claude Code monitor installer
├── uninstall_monitor.sh      # Cleanup script
└── account_wizard.sh         # Account setup wizard
```

## 🛠️ Development

### Building from Source

```bash
# Build Swift application manually
swiftc \
  swift/Logger.swift \
  swift/PermissionManager.swift \
  swift/AppDelegate.swift \
  swift/SettingsWindow.swift \
  swift/Main.swift \
  -o ClaudeMonitor \
  -target arm64-apple-macosx12.0

# Run directly
./ClaudeMonitor gui
```

### Project Architecture

The system consists of three main components:

1. **Swift Core** (`Main.swift`, `AppDelegate.swift`)
   - Runs in the background as a menu bar app (`LSUIElement`)
   - Detects the frontmost application before Claude Code runs
   - Sends macOS notifications via `UserNotifications.framework`
   - Handles notification clicks and restores windows using Accessibility API

2. **Python Hooks** (`notification_hook.py`, `stop_hook.py`)
   - Triggered by Claude Code's hook system
   - Execute the Swift app with appropriate parameters
   - Handle notifications and session events

3. **Shell Integration** (`config.sh`)
   - Defines aliases that wrap the `claude` command
   - Capture frontmost app info before launching Claude Code
   - Pass window info to hooks for restoration

### Permission Requirements

Claude Monitor requires the following macOS permissions:

- **Notifications**: To display desktop notifications
- **Automation**: To control System Events and restore minimized windows

Grant these in System Preferences > Privacy & Security > Privacy.

## 📋 Troubleshooting

### Notifications Not Appearing

1. Check notification permissions:
   ```bash
   ~/Applications/ClaudeMonitor.app/Contents/MacOS/ClaudeMonitor gui
   ```
   Then grant notification permission in the settings window.

2. Verify hook configuration in `~/.claude/settings.json`

3. Check logs:
   ```bash
   tail -f ~/.claude-hooks/swift_debug.log
   tail -f ~/.claude-hooks/python_debug.log
   ```

### Window Not Restoring on Click

1. Check Automation permission:
   - System Preferences > Privacy & Security > Privacy > Automation
   - Ensure "ClaudeMonitor" is checked for "System Events"

2. Verify the app is not quarantined:
   ```bash
   xattr -dr com.apple.quarantine ~/Applications/ClaudeMonitor.app
   ```

### "App is damaged" Error

If you see "ClaudeMonitor is damaged":

```bash
xattr -cr ~/Applications/ClaudeMonitor.app
```

Or build from source (see Development section).

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🔗 Related Projects

- [Claude Code](https://claude.ai/code) - The official Claude Code CLI tool
- [Claude Code Documentation](https://docs.claude.ai/) - Official documentation

## 🙏 Acknowledgments

This project was built to enhance the Claude Code experience on macOS, providing a seamless notification and window management system that keeps you productive without constantly monitoring your terminal.
